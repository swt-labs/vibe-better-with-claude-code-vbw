#!/usr/bin/env bash
# vbw status [--json]: where the project stands, rendered from the record (zero
# tokens). Progress counts the current milestone's requirements; earlier
# milestones are listed as shipped.

# shellcheck source=interview.sh
. "$VBW_LIB/interview.sh"

cmd_status() {
  vbw_require_project
  local record interview
  record=$(record_read)
  interview=$(interview_effective)
  if [ "${1:-}" = "--json" ]; then
    printf '%s\n' "$record" | jq --argjson iv "$interview" '.milestone.id as $m | [.requirements[] | select(.milestone == $m)] as $cur | {
      milestone: .milestone,
      shipped: [.shipped[].id],
      requirements: {total: ($cur | length),
                     proven: ([$cur[] | select(.status == "proven" or .status == "accepted")] | length)},
      phases: ([.phases[] | select(.milestone == $m)] | length),
      open_fixes: ([.fixes[] | select(.status == "open")] | length),
      open_todos: ([.todos[] | select(.status == "open" or .status == "in_progress")] | length),
      interview: $iv
    }'
    return 0
  fi
  printf '%s\n' "$record" | jq -r --argjson iv "$interview" '.milestone.id as $m | [.requirements[] | select(.milestone == $m)] as $cur |
    "\(.project.name) · \(.milestone.id) \(.milestone.title) (\(.milestone.status))",
    "requirements: \([$cur[] | select(.status == "proven" or .status == "accepted")] | length)/\($cur | length) proven",
    "phases: \([.phases[] | select(.milestone == $m)] | length) · open fixes: \([.fixes[] | select(.status == "open")] | length) · open todos: \([.todos[] | select(.status == "open" or .status == "in_progress")] | length)",
    (if (.shipped | length) > 0 then "shipped: \([.shipped[] | "\(.id) \(.title)"] | join(", "))" else empty end),
    (if $iv.interviewed then "interview (kept \($iv.kept)): level \($iv.level) · depth \($iv.depth) · involvement \($iv.involvement)" else "interview: the interview has not been done" end)'
}
