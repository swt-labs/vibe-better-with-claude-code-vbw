#!/usr/bin/env bats
# R16: autonomous mode is per session; one session turning it on or off never
# changes another's.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

status_of() { run "$VBW" auto status "$1" < /dev/null; }

@test "turning autonomy on in B leaves A on, in either order" {
  "$VBW" auto on sessA > /dev/null
  "$VBW" auto on sessB > /dev/null
  status_of sessA
  [[ "$output" == armed* ]]
  status_of sessB
  [[ "$output" == armed* ]]
  "$VBW" auto off sessA > /dev/null
  "$VBW" auto off sessB > /dev/null
  "$VBW" auto on sessB > /dev/null
  "$VBW" auto on sessA > /dev/null
  status_of sessA
  [[ "$output" == armed* ]]
  status_of sessB
  [[ "$output" == armed* ]]
}

@test "concurrent turn-on calls from two sessions both persist" {
  local i
  for i in 1 2 3 4 5 6; do
    "$VBW" auto off "sA$i" > /dev/null 2>&1 || true
    "$VBW" auto on "sA$i" > /dev/null &
    "$VBW" auto on "sB$i" > /dev/null &
  done
  wait
  for i in 1 2 3 4 5 6; do
    status_of "sA$i"; [[ "$output" == armed* ]]
    status_of "sB$i"; [[ "$output" == armed* ]]
  done
}

@test "turning it off in one session leaves the other on" {
  "$VBW" auto on sessA > /dev/null
  "$VBW" auto on sessB > /dev/null
  "$VBW" auto off sessA > /dev/null
  status_of sessA
  [ "$output" = off ]
  status_of sessB
  [[ "$output" == armed* ]]
}

@test "the gate follows each session's own state" {
  "$VBW" auto on sessA > /dev/null
  "$VBW" auto on sessB > /dev/null
  run bash -c 'jq -nc "{hook_event_name: \"Stop\", session_id: \"sessB\", stop_hook_active: false}" | "$1" auto gate' _ "$VBW"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block" or has("systemMessage")'
  status_of sessA
  [[ "$output" == armed* ]]
}
