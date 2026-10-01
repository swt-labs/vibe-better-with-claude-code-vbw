#!/usr/bin/env bash
# vbw req accept ID | reject ID NOTE: the user's verdict on a [human]
# requirement (docs/proof.md). A rejection opens a fix item carrying the note;
# when that fix is done the requirement returns to the user for acceptance.

cmd_req() {
  local sub="${1:-}" id="${2:-}"
  case "$sub" in
    accept) [ $# -eq 2 ] || vbw_usage_error "usage: vbw req accept ID" ;;
    reject) [ $# -eq 3 ] && [ -n "$3" ] || vbw_usage_error "usage: vbw req reject ID NOTE" ;;
    *) vbw_usage_error "usage: vbw req accept ID | reject ID NOTE" ;;
  esac
  vbw_require_project
  local proof
  proof=$(record_read | jq -r --arg q "$id" '[.requirements[] | select(.id == $q) | .proof][0] // empty')
  [ -n "$proof" ] || vbw_die "unknown requirement $id"
  [ "$proof" = human ] || vbw_die "$id is proved by its checks (vbw prove), not by acceptance"
  if [ "$sub" = accept ]; then
    # The user's word settles it: a fix still open from an earlier rejection closes.
    record_update '(.requirements[] | select(.id == $q)).status = "accepted"
      | (.fixes[] | select(.req == $q and (.status | IN("open", "fixed", "escalated")))).status = "closed"' --arg q "$id"
    printf '%s accepted\n' "$id"
  else
    record_update "$VBW_JQ_DEFS"'(.requirements[] | select(.id == $q)).status = "rejected"
      | .fixes += [{id: (.fixes | next_id("F")), req: $q, attempts: 0, status: "open", note: $note}]' \
      --arg q "$id" --arg note "$3"
    jq -r '.fixes[-1] | "\(.req) rejected: \(.id) opened (\(.note))"' "$VBW_RECORD"
  fi
}
