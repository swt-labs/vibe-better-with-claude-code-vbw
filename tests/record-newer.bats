#!/usr/bin/env bats
# R33 (docs/record.md): a VBW that opens a project record written by a newer VBW
# says the project needs a newer VBW and how to update, instead of calling the
# record corrupt, never touches it, and every VBW still reads older records.

load helper

FIXTURES="$BATS_TEST_DIRNAME/fixtures/records"

setup() {
  vbw_setup
  vbw_git_project
  mkdir -p .vbw
}

teardown() { vbw_teardown; }

use_record() { cp "$FIXTURES/$1" .vbw/record.json; }

@test "R33: a record with a newer schema exits non-zero and says the project needs a newer VBW" {
  use_record future.json
  local cmd
  for cmd in "status" "next" "show roadmap" "show requirements" "decide a-decision" "prove" "approve" "doctor"; do
    # shellcheck disable=SC2086 # the command words split on purpose
    vbw_run $cmd
    [ "$status" -ne 0 ]
    [[ "$output" == *"needs a newer VBW"* ]]
    [[ "$output" == *"update"* ]]
  done
}

@test "R33: the message never calls a newer record corrupt" {
  use_record future.json
  local cmd
  for cmd in "status" "next" "show roadmap" "decide a-decision" "doctor"; do
    # shellcheck disable=SC2086
    vbw_run $cmd
    [ "$status" -ne 0 ]
    ! printf '%s' "$output" | grep -qi corrupt
  done
}

@test "R33: a newer record is not modified, rewritten or locked by the older VBW" {
  use_record future.json
  local before cmd
  before=$(cksum < .vbw/record.json)
  for cmd in "decide a-decision" "todo add x" "spec sync" "ship" "tier raise P2 deep why" "qa finding R3 x" "config set profile quality"; do
    # shellcheck disable=SC2086
    vbw_run $cmd
    [ "$status" -ne 0 ]
  done
  [ "$(cksum < .vbw/record.json)" = "$before" ]
  [ -z "$(find .vbw/runtime -maxdepth 1 \( -name 'record.*' -o -name lock \) 2> /dev/null)" ]
  cmp .vbw/record.json "$FIXTURES/future.json"
}

@test "R33: a record that is damaged, not newer, is still reported as corrupt" {
  use_record v1.json
  jq '.schema = "two"' .vbw/record.json > .vbw/record.tmp && mv .vbw/record.tmp .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
  [[ "$output" == *"corrupt"* ]]
  printf '{ not json' > .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
  [[ "$output" == *"corrupt"* ]]
}

@test "R33: the record of every earlier schema version still loads and shows correctly" {
  local f n=0
  for f in "$FIXTURES"/v*.json; do
    n=$((n + 1))
    cp "$f" .vbw/record.json
    vbw_run show roadmap
    [ "$status" -eq 0 ]
    [[ "$output" == *"M2 Refunds [active]"* ]]
    [[ "$output" == *"P2 Refunds [planned]"* ]]
    vbw_run show requirements
    [ "$status" -eq 0 ]
    [[ "$output" == *"R3 [auto, open] Refund a payment"* ]]
    vbw_run status
    [ "$status" -eq 0 ]
    vbw_run decide "still works"
    [ "$status" -eq 0 ]
    jq -e '.decisions[-1].text == "still works"' .vbw/record.json
  done
  [ "$n" -ge 1 ]
}
