#!/usr/bin/env bash
# vbw fix done ID | retry ID: the fix's work is committed (docs/proof.md). For a
# requirement proved by checks, or a project command, it awaits proof: the next
# vbw prove closes it or counts a failed attempt. For a [human] requirement no
# check can decide, so the fix closes and the requirement returns to the user
# for acceptance. `retry` reopens an escalated fix for one more attempt (the
# user's decision at the cap; a further failure escalates again).

cmd_fix() {
  [ $# -eq 2 ] && { [ "$1" = "done" ] || [ "$1" = retry ]; } || vbw_usage_error "usage: vbw fix done ID | fix retry ID"
  local id="$2" human
  vbw_require_project
  record_read | jq -e --arg f "$id" 'any(.fixes[]; .id == $f)' > /dev/null || vbw_die "unknown fix $id"
  if [ "$1" = retry ]; then
    # The user decides to try again after the cap: one more attempt.
    record_read | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .status == "escalated")' > /dev/null \
      || vbw_die "$id is not escalated"
    record_update '(.fixes[] | select(.id == $f)).status = "open"' --arg f "$id"
    printf '%s reopened for one more attempt\n' "$id"
    return 0
  fi
  record_read | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .status == "open")' > /dev/null \
    || vbw_die "$id is not open"
  human=$(record_read | jq -r --arg f "$id" '. as $r | [.fixes[] | select(.id == $f)][0] as $x
    | any($r.requirements[]; .id == $x.req and .proof == "human")')
  if [ "$human" = true ]; then
    record_update '[.fixes[] | select(.id == $f)][0].req as $q
      | (.fixes[] | select(.id == $f)).status = "closed"
      | (.requirements[] | select(.id == $q)).status = "open"' --arg f "$id"
    printf '%s closed: its requirement goes back to the user for acceptance\n' "$id"
  else
    record_update '(.fixes[] | select(.id == $f)).status = "fixed"' --arg f "$id"
    printf '%s fixed: vbw prove decides\n' "$id"
  fi
}
