#!/usr/bin/env bats
# R97 (L1): choosing Approve approves the contract the question names, whatever
# text, spaces or line breaks follow the fingerprint. A different fingerprint
# approves nothing and says the contract changed; a malformed one approves
# nothing and the kernel says what a fingerprint is.

load helper
load approve-choice-helper

setup() {
  vbw_setup
  approve_choice_project
  FP=$(fingerprint)
}
teardown() { vbw_teardown; }

say() { printf '%s' "$output" | jq -r '.systemMessage // empty'; }

@test "R97: a line break right after the fingerprint's question mark still approves" {
  run answer_hook "Approve contract $FP?"$'\n'"It builds two small scripts." "Approve"
  [ "$status" -eq 0 ]
  [ "$(contract_state)" = "approved" ] || { echo "$output"; false; }
  [ "$(approved_count)" = "1" ]
}

@test "R97: extra spaces and several line breaks after the fingerprint still approve" {
  run answer_hook "Approve contract $FP?   "$'\n\n'"  Summary:"$'\n'"- a script"$'\n' "Approve"
  [ "$status" -eq 0 ]
  [ "$(contract_state)" = "approved" ] || { echo "$output"; false; }
  [ "$(approved_count)" = "1" ]
}

@test "R97: carriage returns, tabs and only trailing whitespace after the fingerprint still approve" {
  run answer_hook "Approve contract $FP?"$'\r\n'$'\t'"Details" "Approve"
  [ "$(contract_state)" = "approved" ] || { echo "$output"; false; }
  [ "$(approved_count)" = "1" ]
}

@test "R97: trailing whitespace alone after the question mark approves" {
  run answer_hook "Approve contract $FP?"$'\n' "Approve"
  [ "$(contract_state)" = "approved" ] || { echo "$output"; false; }
}

@test "R97: a different 12-digit fingerprint approves nothing and the user is told the contract changed" {
  local other=ffffffffffff
  [ "$other" != "$FP" ]
  run answer_hook "Approve contract $other?"$'\n'"Summary" "Approve"
  [ "$status" -eq 0 ]
  [ "$(contract_state)" = "NOT APPROVED" ]
  [ "$(approved_count)" = "0" ]
  [[ "$(say)" == *changed* ]] || { echo "$output"; false; }
}

@test "R97: a malformed fingerprint approves nothing, in the hook and in the kernel, and the kernel says what a fingerprint is" {
  run answer_hook "Approve contract ${FP:0:8}?"$'\n'"Summary" "Approve"
  [ "$(contract_state)" = "NOT APPROVED" ]
  run "$VBW" approve --hash zzzzzzzzzzzz < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *12* ]]
  [ "$(contract_state)" = "NOT APPROVED" ]
  [ "$(approved_count)" = "0" ]
}

@test "R97: the user's own words after a multi-line question still approve nothing" {
  run answer_hook "Approve contract $FP?"$'\n'"Summary" "Approve, but change R1"
  [ "$(contract_state)" = "NOT APPROVED" ]
  [ "$(approved_count)" = "0" ]
}
