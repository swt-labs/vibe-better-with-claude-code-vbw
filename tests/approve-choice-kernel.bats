#!/usr/bin/env bats
# R61 (kernel part, L1): the contract view carries the approval question with
# the contract's short fingerprint, and `vbw approve --hash FINGERPRINT`
# approves exactly that contract: the same record entry as plain `vbw approve`,
# nothing when the contract is no longer the one named, and once per approval.
# A plan changed after this milestone's plan was approved is offered again with
# detail.changed, so VBW says it changed instead of calling it a new plan.

load helper
load approve-choice-helper
load fixture-helper

choice_project() {
  vbw_setup
  approve_choice_project
}

setup_file() { fixture_build choice choice_project; }
setup() { fixture_copy choice; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

@test "R61: the contract view ends with the approval question naming the fingerprint, and the options Approve first, Not yet second" {
  vbw_run show contract
  [ "$status" -eq 0 ]
  local fp
  fp=$(fingerprint)
  # The counts of R251 may follow the question; the question itself is unchanged.
  [[ "$output" == *$'\n'"approval question: Approve contract $fp?"* ]]
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

@test "R61: a plan changed after its approval is offered again as changed (detail.changed); a first approval is not" {
  "$VBW" next --json | jq -e '.action == "approve" and (.detail | has("changed") | not)' > /dev/null || { "$VBW" next --json; false; }
  "$VBW" approve > /dev/null
  jq '.plans[0].title = "Pay by card"' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" next --json | jq -e '.action == "approve" and .detail.changed == true' > /dev/null || { "$VBW" next --json; false; }
  # An approval that held none of this milestone's requirements (the last milestone's) is not this plan's.
  jq '.requirements = {}' .vbw/runtime/approved-contract.json > "$TEST_ROOT/a.json" && cp "$TEST_ROOT/a.json" .vbw/runtime/approved-contract.json
  "$VBW" next --json | jq -e '.action == "approve" and (.detail | has("changed") | not)' > /dev/null || { "$VBW" next --json; false; }
}
