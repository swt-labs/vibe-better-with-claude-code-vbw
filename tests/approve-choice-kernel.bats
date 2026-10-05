#!/usr/bin/env bats
# R61 (kernel part, L1): the contract view carries the approval question with
# the contract's short fingerprint, and `vbw approve --hash FINGERPRINT`
# approves exactly that contract: the same record entry as plain `vbw approve`,
# nothing when the contract is no longer the one named, and once per approval.

load helper
load approve-choice-helper

setup() {
  vbw_setup
  approve_choice_project
}
teardown() { vbw_teardown; }

@test "R61: the contract view ends with the approval question naming the fingerprint, and the options Approve first, Not yet second" {
  vbw_run show contract
  [ "$status" -eq 0 ]
  local fp
  fp=$(fingerprint)
  [[ "$output" == *$'\n'"approval question: Approve contract $fp?"$'\n'* ]] || [[ "$output" == *$'\n'"approval question: Approve contract $fp?" ]]
  echo "$output" | grep -qx 'approval options: Approve, Not yet'
  [ "$(contract_state)" = "NOT APPROVED" ]
}

@test "R61: an approved contract shows no approval question" {
  "$VBW" approve > /dev/null
  vbw_run show contract
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q '^approval question:'
}

@test "R61: approve --hash with the current fingerprint approves it, like plain approve, and writes the decision once" {
  local fp
  fp=$(fingerprint)
  vbw_run approve --hash "$fp"
  [ "$status" -eq 0 ]
  [ "$(contract_state)" = "approved" ]
  [ "$(approved_count)" = "1" ]
  jq -e --arg fp "$fp" '.decisions[-1].text | test("^Contract approved: 1 requirements, 1 checks, 1 plans \\(" + $fp + "\\)")' .vbw/record.json
  vbw_run approve
  [ "$status" -eq 0 ]
  vbw_run approve --hash "$fp"
  [ "$status" -eq 0 ]
  [ "$(approved_count)" = "1" ]
}

@test "R61: approve --hash with a fingerprint that is no longer current approves nothing and says the contract changed" {
  local old
  old=$(fingerprint)
  printf 'grep -qx paid src/pay.txt && true\n' > tests/pay.sh
  [ "$(fingerprint)" != "$old" ]
  local before
  before=$(jq -S . .vbw/record.json)
  vbw_run approve --hash "$old"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'changed'
  [ "$(contract_state)" = "NOT APPROVED" ]
  [ "$(jq -S . .vbw/record.json)" = "$before" ]
}

@test "R61: approve --hash refuses a malformed fingerprint and a contract that is not ready, changing nothing" {
  vbw_run approve --hash nonsense
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'fingerprint'
  [ "$(contract_state)" = "NOT APPROVED" ]
  vbw_run approve --hash
  [ "$status" -ne 0 ]
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] Another thing\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  vbw_run approve --hash "$(fingerprint)"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'not ready for approval'
  [ "$(approved_count)" = "0" ]
}
