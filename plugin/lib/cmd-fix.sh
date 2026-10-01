#!/usr/bin/env bash
# vbw fix done ID: the fix's work is committed and awaits proof (docs/proof.md).
# The next vbw prove closes it, or counts a failed attempt.

cmd_fix() {
  [ $# -eq 2 ] && [ "$1" = "done" ] || vbw_usage_error "usage: vbw fix done ID"
  local id="$2"
  vbw_require_project
  record_read | jq -e --arg f "$id" 'any(.fixes[]; .id == $f)' > /dev/null || vbw_die "unknown fix $id"
  record_read | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .status == "open")' > /dev/null \
    || vbw_die "$id is not open"
  record_update '(.fixes[] | select(.id == $f)).status = "fixed"' --arg f "$id"
  printf '%s fixed: vbw prove decides\n' "$id"
}
