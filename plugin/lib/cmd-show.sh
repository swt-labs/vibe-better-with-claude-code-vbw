#!/usr/bin/env bash
# vbw show roadmap|phase ID|req ID|evidence: views rendered from the record
# and git trailers. Nothing is stored in rendered form.

cmd_show() {
  local view="${1:-}" record
  [ $# -gt 0 ] && shift
  case "$view" in roadmap|phase|req|evidence) ;; *) vbw_usage_error "usage: vbw show roadmap|phase ID|req ID|evidence" ;; esac
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
      printf '%s' "$record" | jq -r --arg q "$1" '
        . as $r | (.requirements[] | select(.id == $q)) as $req
        | "\($req.id) [\($req.proof), \($req.status)] \($req.text)",
          "checks:", ($r.checks[] | select(.req == $q) | "  \(.id) \(.kind) \(.path)"),
          "plans:", ($r.plans[] | select(any(.reqs[]; . == $q)) | "  \(.id) \(.title) [\(.status)]")'
      printf 'commits:\n'
      show_commits_for_req "$1"
      ;;
    evidence)
      printf '%s' "$record" | jq -r 'if .evidence == null then "no proof run yet (vbw prove)" else .evidence | tojson end'
      ;;
  esac
}

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
