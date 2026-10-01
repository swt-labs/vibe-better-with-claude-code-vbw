#!/usr/bin/env bash
# vbw decide TEXT [WHY]: record a decision the user made, and why, in the plan
# of record (the Q&A's memory: planners and builders read it).

cmd_decide() {
  [ $# -ge 1 ] && [ $# -le 2 ] && [ -n "$1" ] && { [ $# -eq 1 ] || [ -n "$2" ]; } \
    || vbw_usage_error "usage: vbw decide TEXT [WHY]"
  vbw_require_project
  if [ $# -eq 2 ]; then
    record_update "$VBW_JQ_DEFS"'.decisions += [{id: (.decisions | next_id("D")), text: $t, why: $w, at: $at}]' \
      --arg t "$1" --arg w "$2" --arg at "$(vbw_now)"
  else
    record_update "$VBW_JQ_DEFS"'.decisions += [{id: (.decisions | next_id("D")), text: $t, at: $at}]' \
      --arg t "$1" --arg at "$(vbw_now)"
  fi
  jq -r '.decisions[-1] | "recorded \(.id): \(.text)"' "$VBW_RECORD"
}
