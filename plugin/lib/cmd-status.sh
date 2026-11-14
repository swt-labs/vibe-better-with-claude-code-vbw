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
  local slim interview step road out
  # One pass over the record (next_prepare): its slim form holds all that status shows,
  # and the road is worked out with vbw next's answer in the one run that judges it.
  next_prepare || exit $?
  slim=$NP_SLIM
  interview=$(interview_effective "$slim")
  step=$(step_status "$(printf '%s' "$slim" | jq -r '.lease.run // ""')")
  road=$(printf '%s' "$step" | jq -c 'select(type == "object") | .road | select(type == "object")' 2> /dev/null) || road=
  if [ -z "$road" ]; then
    # shellcheck disable=SC2034  # read by next_decide
    [ "$step" = null ] || NP_NOTE=$step
    # shellcheck disable=SC2034
    NP_WANT_ROAD=1
    out=$(next_decide) || exit $?
    road=$(printf '%s' "$out" | jq -c '.road // null' 2> /dev/null) || road=null
  fi
  if [ "${1:-}" = "--json" ]; then
    printf '%s\n' "$slim" | jq --argjson iv "$interview" --argjson step "$step" --argjson road "${road:-null}" '.milestone.id as $m | [.requirements[] | select(.milestone == $m)] as $cur | {
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
  printf '%s\n' "$slim" | jq -r --argjson iv "$interview" --argjson step "$step" --argjson road "${road:-null}" "$VBW_STEP_DEFS"'.milestone.id as $m | [.requirements[] | select(.milestone == $m)] as $cur |
    "\(.project.name) · \(.milestone.id) \(.milestone.title) (\(.milestone.status))",
    "requirements: \([$cur[] | select(.status == "proven" or .status == "accepted")] | length)/\($cur | length) proven",
    ([.requirements[] | select(.queued) | .id] | if length > 0 then "queued: \(length) requirement\(if length == 1 then "" else "s" end) (\(join(", ")))" else empty end),
    "phases: \([.phases[] | select(.milestone == $m)] | length) · open fixes: \([.fixes[] | select(.status == "open")] | length) · open todos: \([.todos[] | select(.status == "open" or .status == "in_progress")] | length)",
    # A built plan whose awaited check has no passing result yet (R250), derived here, never stored.
    (. as $r | .plans[] | select(.status == "done") | . as $p
      | [(.awaits // [])[] | select(($r.evidence.checks[.].status // "") != "pass")] | select(length > 0)
      | "\($p.id) built, awaiting \(join(", "))"),
    (if $step != null then "now: \(step_sentence($step; vbw_now | floor))" else empty end),
    (if $road != null then $road.say else empty end),
    (if (.shipped | length) > 0 then "shipped: \([.shipped[] | "\(.id) \(.title)"] | join(", "))" else empty end),
    (if ((.parked // []) | length) > 0 then "parked: \([.parked[] | "\(.id) (\(.reason))"] | join(", "))" else empty end),
    (if $iv.interviewed then "interview (kept \($iv.kept)): level \($iv.level) · depth \($iv.depth) · involvement \($iv.involvement)" else "interview: the interview has not been done" end),
    (.recommendation as $r | if $r == null then "what\u0027s next: none yet (ask /vbw:vibe what\u0027s next)"
      elif $r.empty then "what\u0027s next: the backlog is empty (written \($r.at[0:10]))"
      else "what\u0027s next: \($r.top.text) (\($r.top.size))", "  \($r.top.reason)",
        ($r.runners[] | "  then: \(.text) (\(.size))"), "  written \($r.at[0:10])" end)'
}
