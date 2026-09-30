#!/usr/bin/env bash
# vbw status: where the project stands, rendered from the record (zero tokens).

cmd_status() {
  vbw_require_project
  local record
  record=$(record_read)
  if [ "${1:-}" = "--json" ]; then
    printf '%s\n' "$record" | jq '{
      milestone: .milestone,
      requirements: {total: (.requirements | length),
                     proven: ([.requirements[] | select(.status == "proven" or .status == "accepted")] | length)},
      phases: (.phases | length),
      open_fixes: ([.fixes[] | select(.status == "open")] | length),
      open_todos: ([.todos[] | select(.status == "open" or .status == "in_progress")] | length)
    }'
    return 0
  fi
  printf '%s\n' "$record" | jq -r '
    "\(.project.name) · \(.milestone.id) \(.milestone.title) (\(.milestone.status))",
    "requirements: \([.requirements[] | select(.status == "proven" or .status == "accepted")] | length)/\(.requirements | length) proven",
    "phases: \(.phases | length) · open fixes: \([.fixes[] | select(.status == "open")] | length) · open todos: \([.todos[] | select(.status == "open" or .status == "in_progress")] | length)"'
}
