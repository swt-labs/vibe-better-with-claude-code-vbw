#!/usr/bin/env bash
# vbw show roadmap | phase ID | req ID | plan ID [--json] | fix ID [--json] |
# contract | evidence: views rendered from the record and git trailers. Nothing
# is stored in rendered form. plan and fix are the context a builder works from.

cmd_show() {
  local view="${1:-}" record
  [ $# -gt 0 ] && shift
  case "$view" in roadmap|phase|req|plan|fix|contract|evidence) ;; *) vbw_usage_error "usage: vbw show roadmap | phase ID | req ID | plan ID [--json] | fix ID [--json] | contract | evidence" ;; esac
  vbw_require_project
  record=$(record_read)
  case "$view" in
    roadmap)
      printf '%s' "$record" | jq -r '
        "\(.milestone.id) \(.milestone.title) [\(.milestone.status)]",
        (.phases[] as $ph
          | "  \($ph.id) \($ph.title) [\($ph.status)]",
            (.plans[] | select(.phase == $ph.id)
              | "    \(.id) \(.title) [\(.status)]\(if (.after | length) > 0 then " after \(.after | join(", "))" else "" end)"))'
      ;;
    phase)
      [ $# -eq 1 ] || vbw_usage_error "usage: vbw show phase ID"
      printf '%s' "$record" | jq -e --arg p "$1" 'any(.phases[]; .id == $p)' > /dev/null || vbw_die "unknown phase $1"
      printf '%s' "$record" | jq -r --arg p "$1" '
        . as $r | (.phases[] | select(.id == $p)) as $ph
        | "\($ph.id) \($ph.title) [\($ph.status)]",
          "requirements:",
          ($ph.reqs[] as $q | $r.requirements[] | select(.id == $q) | "  \(.id) [\(.proof), \(.status)] \(.text)"),
          "plans:",
          ($r.plans[] | select(.phase == $p) | "  \(.id) \(.title) [\(.status)]: \(.files | join(", "))")'
      ;;
    req)
      [ $# -eq 1 ] || vbw_usage_error "usage: vbw show req ID"
      printf '%s' "$record" | jq -e --arg q "$1" 'any(.requirements[]; .id == $q)' > /dev/null || vbw_die "unknown requirement $1"
      printf '%s' "$record" | jq -r --arg q "$1" "$SHOW_JQ_DEFS"'
        . as $r | (.requirements[] | select(.id == $q)) as $req
        | "\($req.id) [\($req.proof), \($req.status)] \($req.text)",
          "checks:", ($r.checks[] | select(.req == $q) | "  \(.id) " + check_line),
          "plans:", ($r.plans[] | select(any(.reqs[]; . == $q)) | "  \(.id) \(.title) [\(.status)]")'
      printf 'commits:\n'
      show_commits_for_req "$1"
      ;;
    plan|fix)
      [ $# -ge 1 ] && [ $# -le 2 ] && { [ $# -eq 1 ] || [ "$2" = --json ]; } || vbw_usage_error "usage: vbw show $view ID [--json]"
      show_work "$record" "$view" "$1" "${2:-}"
      ;;
    contract)
      local hash state="NOT APPROVED"
      hash=$(contract_hash "$record")
      contract_approved "$hash" && state="approved"
      printf 'contract %s (%s)\n' "${hash:0:12}" "$state"
      printf '%s' "$record" | jq -r "$SHOW_JQ_DEFS"'
        . as $r
        | "requirements:",
          (.requirements[] | . as $q | "  \(.id) [\(.proof)] \(.text)",
            ($r.checks[] | select(.req == $q.id) | "    \(.id) " + check_line)),
          "plans:",
          (.plans[] | "  \(.id) \(.title): \(.files | join(", "))\(if (.after | length) > 0 then " (after \(.after | join(", ")))" else "" end)"),
          "project commands:",
          (.commands | to_entries[] | "  \(.key): \(.value | argv_line)")'
      ;;
    evidence)
      printf '%s' "$record" | jq -r '
        if .evidence == null then "no proof run yet (vbw prove)" else .evidence
        | "proof run \(.at): \(if .passed then "passed" else "FAILED" end) (contract \(.contract[0:12]))",
          ((.checks + .commands) | to_entries[]
            | "  \(.key) \(.value.status)\(if .value.exit != null then " exit \(.value.exit)" else "" end) \(.value.seconds)s",
              (.value.tail | select(length > 0) | split("\n")[] | "    | " + .)),
          (.scope[] | "  scope: " + .)
        end'
      ;;
  esac
}

# jq helpers for rendering checks. An argv is shown shell-quoted where needed.
# shellcheck disable=SC2016 # jq text, not shell
SHOW_JQ_DEFS='
def argv_line: map(if test("^[A-Za-z0-9_./:=@%+-]+$") then . else @sh end) | join(" ");
def check_line: (.run | argv_line)
  + (if (.exit // 0) != 0 then " (exit \(.exit))" else "" end)
  + (if .output then " (output ~ /\(.output)/)" else "" end)
  + (if .files then " [protects \(.files | join(", "))]" else "" end);
'

# Commits whose VBW-Req trailer lists REQ as an exact token (not a substring:
# R1 must not match R12).
show_commits_for_req() {
  local req="$1" line subject reqs r
  while IFS= read -r line; do
    subject=${line%%$'\x1f'*}
    reqs=${line#*$'\x1f'}
    for r in $(printf '%s' "$reqs" | tr ',' ' '); do
      [ "$r" = "$req" ] && { printf '  %s\n' "$subject"; break; }
    done
  done < <(git -C "$VBW_ROOT" log --format='%h %s%x1f%(trailers:key=VBW-Req,valueonly,separator=%x2C)' 2>/dev/null)
}

# show_work RECORD plan|fix ID [--json]: what a builder needs, and nothing else.
show_work() {
  local json
  json=$(printf '%s' "$1" | jq -c --arg kind "$2" --arg id "$3" '
    . as $r
    | def checks_for($reqs): [$r.checks[] | select(.req as $q | any($reqs[]; . == $q))
        | . + {last: ($r.evidence.checks[.id] // null)}];
      if $kind == "plan" then
        [.plans[] | select(.id == $id)][0] as $p
        | if $p == null then null else
          {plan: $p,
           requirements: [$p.reqs[] as $q | $r.requirements[] | select(.id == $q) | {id, text, proof}],
           checks: checks_for($p.reqs), commands: $r.commands} end
      else
        [.fixes[] | select(.id == $id)][0] as $f
        | if $f == null then null else
          {fix: $f,
           requirement: (if $f.req then [$r.requirements[] | select(.id == $f.req) | {id, text, proof}][0] else null end),
           checks: (if $f.req then checks_for([$f.req]) else [] end),
           command: (if $f.command then {name: $f.command, argv: $r.commands[$f.command],
                                          last: ($r.evidence.commands[$f.command] // null)} else null end),
           plans: [$r.plans[] | select($f.req != null and any(.reqs[]; . == $f.req)) | {id, title, files}]} end
      end')
  [ "$json" != null ] || vbw_die "unknown $2 $3"
  if [ "${4:-}" = --json ]; then
    printf '%s\n' "$json"
    return 0
  fi
  printf '%s' "$json" | jq -r "$SHOW_JQ_DEFS"'
    def check_lines: .checks[] | "  \(.id) (\(.req)) " + check_line
      + (if .last then " — last: \(.last.status)" else "" end);
    if .plan then
      "\(.plan.id) \(.plan.title) [\(.plan.status)]\(if .plan.note then ": " + .plan.note else "" end)",
      "files: \(.plan.files | join(", "))",
      (if (.plan.after | length) > 0 then "after: \(.plan.after | join(", "))" else empty end),
      "requirements:", (.requirements[] | "  \(.id) [\(.proof)] \(.text)"),
      "checks:", check_lines
    else
      "\(.fix.id) [\(.fix.status), attempts \(.fix.attempts)]: \(.fix.note)",
      (if .requirement then "requirement: \(.requirement.id) \(.requirement.text)" else empty end),
      (if .command then "command \(.command.name): \(.command.argv | argv_line)\(if .command.last then " — last: \(.command.last.status)" else "" end)",
         (.command.last.tail // "" | select(length > 0) | split("\n")[] | "    | " + .) else empty end),
      (if (.checks | length) > 0 then "checks:", check_lines else empty end),
      (.checks[] | select(.last and .last.status != "pass") | .last.tail | select(length > 0) | split("\n")[] | "    | " + .),
      (if (.plans | length) > 0 then "files (plans serving the requirement):", (.plans[] | "  \(.id): \(.files | join(", "))") else empty end)
    end'
}
