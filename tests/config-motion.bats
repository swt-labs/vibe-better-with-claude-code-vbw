#!/usr/bin/env bats
# Motion setting (mods_4_vbw.md §3.7): vbw config set motion full|calm|off
# stores record.settings.motion, default removes it (the panel then picks by
# the interview level), vbw config shows it, any other value is refused and
# changes nothing.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

@test "motion accepts full, calm and off and stores each in the record's settings" {
  local v
  for v in full calm off; do
    vbw_run config set motion "$v"
    [ "$status" -eq 0 ]
    [ "$output" = "motion = $v" ]
    jq -e --arg v "$v" '.settings.motion == $v' .vbw/record.json
  done
}

@test "motion default removes the setting" {
  vbw_run config set motion off
  [ "$status" -eq 0 ]
  vbw_run config set motion default
  [ "$status" -eq 0 ]
  jq -e '.settings | has("motion") | not' .vbw/record.json
}

@test "an unknown motion value is refused with the allowed values and changes nothing" {
  cp .vbw/record.json "$TEST_ROOT/before.json"
  local v
  for v in fast FULL none ""; do
    vbw_run config set motion "$v"
    [ "$status" -ne 0 ] || { echo "'$v' accepted"; false; }
    [[ "$output" == *"motion must be full, calm or off (or default)"* ]]
  done
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}

@test "vbw config shows motion: default when unset, the value when set" {
  vbw_run config
  [ "$status" -eq 0 ]
  [[ "$output" == *"motion: default"* ]]
  "$VBW" config set motion calm > /dev/null
  vbw_run config
  [[ "$output" == *"motion: calm"* ]]
}
