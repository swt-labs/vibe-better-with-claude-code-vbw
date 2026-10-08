#!/usr/bin/env bash
# vbw triage [--json]: the facts for sorting a new idea (R121), from one read of
# the record: the active milestone, its requirements neither proven nor
# accepted, the open run, and the open backlog in `vbw todo list` order.
# It starts nothing and writes nothing.

# shellcheck source=/dev/null
. "$VBW_LIB/cmd-todo.sh"

cmd_triage() {
  local json=0
  case "${1:-}" in
    "") ;;
    --json) json=1; shift ;;
  esac
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw triage [--json]"
  vbw_require_project
  local facts
  facts=$(record_read | jq "$VBW_JQ_DEFS"'.milestone as $m
    | {milestone: (if $m == null then null else {id: $m.id, title: $m.title, status: $m.status} end),
       open: (if $m == null or $m.status == "shipped" then []
              else [.requirements[] | select(.milestone == $m.id and .status != "proven" and .status != "accepted")
                    | {id, text, proof, status}] end),
       run: (if .lease == null then null else .lease | {run, kind, session, started_at} end),
       todos: ('"$TODO_OPEN_JQ"' | map(del(.status)))}') || vbw_die "internal error: triage failed"
  if [ "$json" = 1 ]; then
    printf '%s\n' "$facts"
    return 0
  fi
  printf '%s\n' "$facts" | jq -r '
    (if .milestone then "\(.milestone.id) \(.milestone.title) (\(.milestone.status))" else "no milestone" end),
    (if (.open | length) == 0 then "no open requirements" else "open requirements:", (.open[] | "  \(.id) [\(.proof)] \(.text)") end),
    (if .run then "run open: \(.run.kind) \(.run.run)" else "no run open" end),
    (if (.todos | length) == 0 then "no open todos" else "backlog:", (.todos[] | if has("sort") then "  \(.id) [\(.sort), \(.size)] \(.text)" else "  \(.id) \(.text)" end) end)'
}
