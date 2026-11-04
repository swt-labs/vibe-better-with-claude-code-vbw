#!/usr/bin/env bash
# vbw status [--json]: where the project stands, rendered from the record (zero
# tokens). Progress counts the current milestone's requirements; earlier
# milestones are listed as shipped or parked.

# shellcheck source=interview.sh
. "$VBW_LIB/interview.sh"
# shellcheck source=steps.sh
. "$VBW_LIB/steps.sh"
# shellcheck source=cmd-next.sh
. "$VBW_LIB/cmd-next.sh"

cmd_status() {
  vbw_require_project
  local record interview step road
  # One pass over the record (next_prepare): its working record holds all that status shows,
  # and the road's answer of vbw next is judged from the same pass.
  next_prepare || exit $?
  record=$NP_WORK
  interview=$(interview_effective "$record")
  step=$(step_status "$(printf '%s' "$record" | jq -r '.lease.run // ""')")
  road=$(step_road_status "$record" "$step" next_road_input)
  if [ "${1:-}" = "--json" ]; then
    printf '%s\n' "$record" | jq --argjson iv "$interview" --argjson step "$step" --argjson road "${road:-null}" '.milestone.id as $m | [.requirements[] | select(.milestone == $m)] as $cur | {
      milestone: .milestone,
      shipped: [.shipped[].id],
      parked: [(.parked // [])[].id],
      requirements: {total: ($cur | length),
                     proven: ([$cur[] | select(.status == "proven" or .status == "accepted")] | length)},
      phases: ([.phases[] | select(.milestone == $m)] | length),
      open_fixes: ([.fixes[] | select(.status == "open")] | length),
      open_todos: ([.todos[] | select(.status == "open" or .status == "in_progress")] | length),
      interview: $iv,
      recommendation: (.recommendation // null),
      step: $step,
      road: $road
    }'
    return 0
  fi
  printf '%s\n' "$record" | jq -r --argjson iv "$interview" --argjson step "$step" --argjson road "${road:-null}" "$VBW_STEP_DEFS"'.milestone.id as $m | [.requirements[] | select(.milestone == $m)] as $cur |
    "\(.project.name) · \(.milestone.id) \(.milestone.title) (\(.milestone.status))",
    "requirements: \([$cur[] | select(.status == "proven" or .status == "accepted")] | length)/\($cur | length) proven",
    "phases: \([.phases[] | select(.milestone == $m)] | length) · open fixes: \([.fixes[] | select(.status == "open")] | length) · open todos: \([.todos[] | select(.status == "open" or .status == "in_progress")] | length)",
    (if $step != null then "now: \(step_sentence($step; now | floor))" else empty end),
    (if $road != null then $road.say else empty end),
    (if (.shipped | length) > 0 then "shipped: \([.shipped[] | "\(.id) \(.title)"] | join(", "))" else empty end),
    (if ((.parked // []) | length) > 0 then "parked: \([.parked[] | "\(.id) (\(.reason))"] | join(", "))" else empty end),
    (if $iv.interviewed then "interview (kept \($iv.kept)): level \($iv.level) · depth \($iv.depth) · involvement \($iv.involvement)" else "interview: the interview has not been done" end),
    (.recommendation as $r | if $r == null then "what\u0027s next: none yet (ask /vbw:vibe what\u0027s next)"
      elif $r.empty then "what\u0027s next: the backlog is empty (written \($r.at[0:10]))"
      else "what\u0027s next: \($r.top.text) (\($r.top.size))", "  \($r.top.reason)",
        ($r.runners[] | "  then: \(.text) (\(.size))"), "  written \($r.at[0:10])" end)'
}
