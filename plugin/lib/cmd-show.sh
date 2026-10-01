#!/usr/bin/env bash
# vbw show roadmap | phase ID | req ID | plan ID [--json] | fix ID [--json] |
# contract | evidence | decisions | requirements: views rendered from the record
# and git trailers. Nothing is stored in rendered form. plan and fix are the
# context a Dev works from.

cmd_show() {
  local view="${1:-}" record
  [ $# -gt 0 ] && shift
  case "$view" in roadmap|phase|req|plan|fix|contract|evidence|decisions|requirements) ;; *) vbw_usage_error "usage: vbw show roadmap | phase ID | req ID | plan ID [--json] | fix ID [--json] | contract [--changes] | evidence | decisions | requirements" ;; esac
  vbw_require_project
  record=$(record_read)
  case "$view" in
    roadmap)
      printf '%s' "$record" | jq -r "$SHOW_JQ_DEFS"'
        . as $r
        | (.shipped[] | "\(.id) \(.title) [shipped \(.at[0:10])]"),
          (if .milestone.status == "shipped" then empty else
             "\(.milestone.id) \(.milestone.title) [\(.milestone.status)]",
             ((.phases[] | select(.milestone == $r.milestone.id)) as $ph
               | "  \($ph.id) \($ph.title) [\($ph | phase_status($r))]",
                 ($r.plans[] | select(.phase == $ph.id)
                   | "    \(.id) \(.title) [\(.status)]\(if (.after | length) > 0 then " after \(.after | join(", "))" else "" end)"))
           end)'
      ;;
    phase)
      [ $# -eq 1 ] || vbw_usage_error "usage: vbw show phase ID"
      printf '%s' "$record" | jq -e --arg p "$1" 'any(.phases[]; .id == $p)' > /dev/null || vbw_die "unknown phase $1"
      printf '%s' "$record" | jq -r --arg p "$1" "$SHOW_JQ_DEFS"'
        . as $r | (.phases[] | select(.id == $p)) as $ph
        | "\($ph.id) \($ph.title) [\($ph | phase_status($r))]",
          (if $ph.goal then "goal: \($ph.goal)" else empty end),
          (if $ph.criteria then "criteria:", ($ph.criteria[] | "  - " + .) else empty end),
          (if $ph.qa then "qa: \($ph.qa.result) (\($ph.qa.tier), \($ph.qa.at))\(if $ph.qa.note then ": " + $ph.qa.note else "" end)"
             + (if $ph.qa.tree != ($r.evidence.tree // "") then " [on older code]" else "" end) else empty end),
          "requirements:",
          ($ph.reqs[] as $q | $r.requirements[] | select(.id == $q) | "  \(.id) [\(.proof), \(.status)] \(.text)"),
          "plans:",
          ($r.plans[] | select(.phase == $p) | "  \(.id) \(.title) [\(.status)\(if .role == "docs" then ", docs" else "" end)]: \(.files | join(", "))",
            ((.tasks // [])[] | "    - " + .))'
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
      if [ "${1:-}" = --changes ]; then
        show_contract_changes "$record"
        return 0
      fi
      [ $# -eq 0 ] || vbw_usage_error "usage: vbw show contract [--changes]"
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
    requirements)
      # Every requirement with its proof, status and milestone, and whether the
      # work for it is built (every plan serving it is done).
      printf '%s' "$record" | jq -r '. as $r | .requirements[]
        | . as $q | [$r.plans[] | select(any(.reqs[]; . == $q.id))] as $ps
        | "\(.id) [\(.proof), \(.status)] \(.text) (\(.milestone)\(if ($ps | length) > 0 and all($ps[]; .status == "done") then ", built" else "" end))"'
      ;;
    decisions)
      printf '%s' "$record" | jq -r 'if (.decisions | length) == 0 then "no decisions recorded yet (vbw decide TEXT [WHY])"
        else .decisions[] | "\(.id) \(.text)\(if .why then " (why: \(.why))" else "" end)" end'
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

# What changed in the contract since the last approval in this clone.
show_contract_changes() {
  local before="$VBW_RUNTIME/approved-contract.json"
  if [ ! -f "$before" ]; then
    printf 'no earlier approval in this clone: the whole contract is new (vbw show contract)\n'
    return 0
  fi
  contract_doc "$1" | jq -r --slurpfile old "$before" "$SHOW_JQ_DEFS"'
    . as $new | $old[0] as $old
    | [ ($new.requirements | to_entries[] | select($old.requirements[.key] == null)
          | "added requirement \(.key) [\(.value.proof)] \(.value.text)"),
        ($old.requirements | to_entries[] | select($new.requirements[.key] == null)
          | "removed requirement \(.key): \(.value.text)"),
        ($new.requirements | to_entries[] | select($old.requirements[.key] != null and $old.requirements[.key] != .value)
          | "changed requirement \(.key): [\($old.requirements[.key].proof)] \($old.requirements[.key].text) -> [\(.value.proof)] \(.value.text)"),
        ($new.checks | to_entries[] | select($old.checks[.key] == null)
          | "added check \(.key) (\(.value.req)): " + (.value | check_line)),
        ($old.checks | to_entries[] | select($new.checks[.key] == null)
          | "removed check \(.key) (\(.value.req))"),
        ($new.checks | to_entries[] | select($old.checks[.key] != null and $old.checks[.key] != .value)
          | "changed check \(.key) (\(.value.req)): " + (.value | check_line)),
        ($new.files | to_entries[] | select($old.files[.key] != null and $old.files[.key] != .value)
          | "changed test file \(.key)"),
        ($new.plans | to_entries[] | select($old.plans[.key] == null)
          | "added plan \(.key) \(.value.title): \(.value.files | join(", "))"),
        ($old.plans | to_entries[] | select($new.plans[.key] == null)
          | "removed plan \(.key) \(.value.title)"),
        ($new.plans | to_entries[] | select($old.plans[.key] != null and $old.plans[.key] != .value)
          | "changed plan \(.key) \(.value.title): \(.value.files | join(", "))\(if (.value.after | length) > 0 then " (after \(.value.after | join(", ")))" else "" end)") ]
    | if length == 0 then "no changes since the last approval" else "changes since the last approval:", (.[] | "  " + .) end'
}

# jq helpers for rendering checks. An argv is shown shell-quoted where needed.
# shellcheck disable=SC2016 # jq text, not shell
SHOW_JQ_DEFS='
# The status of a phase is derived from its plans, never stored.
def phase_status($r): .id as $id | [$r.plans[] | select(.phase == $id) | .status] as $s
  | if ($s | length) > 0 and all($s[]; . == "done") then "built"
    elif any($s[]; . != "planned") then "building" else "planned" end;
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

# show_work RECORD plan|fix ID [--json]: what a Dev needs, and nothing else.
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
           requirements: [$p.reqs[] as $q | $r.requirements[] | select(.id == $q) | {id, text, proof,
             other_open_plans: [$r.plans[] | select(.id != $p.id and .status != "done" and any(.reqs[]; . == $q)) | .id]}],
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
      (if .plan.tasks then "tasks:", (.plan.tasks | to_entries[] | "  \(.key + 1). \(.value)") else empty end),
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
