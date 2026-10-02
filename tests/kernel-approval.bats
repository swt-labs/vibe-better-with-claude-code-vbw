#!/usr/bin/env bats
# Approval survives blocking and resetting a plan (R10): a plan's status and
# note are run state, not contract content.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf '{"phases": [{"id": "P1", "title": "Checkout", "reqs": ["R1"]}],
   "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]}],
   "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

approved_hash() { vbw_run show contract; printf '%s' "$output" | grep -c "NOT APPROVED" || true; }

next_action() { vbw_run next --json; echo "$output" | jq -r '.action'; }

@test "blocking an approved plan keeps the approval and proceeds without re-approval" {
  [ "$(next_action)" != "approve" ]
  vbw_run plan block P1.1 "the payment API key is missing"
  [ "$status" -eq 0 ]
  [ "$(approved_hash)" = "0" ]
  [ "$(next_action)" != "approve" ]
  vbw_run next --json
  echo "$output" | jq -e '.contract.approved == true or .approved == true or (.action != "approve")'
}

@test "resetting a blocked plan keeps the approval and the approved hash" {
  vbw_run plan block P1.1 "waiting"
  [ "$status" -eq 0 ]
  blocked=$(vbw_contract_hash)
  vbw_run plan reset P1.1
  [ "$status" -eq 0 ]
  [ "$(vbw_contract_hash)" = "$blocked" ]
  [ "$(approved_hash)" = "0" ]
  [ "$(next_action)" != "approve" ]
}

@test "a plan's note does not change the contract hash" {
  before=$(vbw_contract_hash)
  vbw_run plan block P1.1 "a note"
  [ "$(vbw_contract_hash)" = "$before" ]
  vbw_run doctor
  [[ "$output" == *"the contract is approved"* ]]
}

@test "changing a plan definition still withdraws the approval" {
  jq '.plans[0].title = "Pay twice"' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  [ "$(next_action)" = "approve" ]
}

@test "changing a check or a requirement still withdraws the approval" {
  jq '.checks[0].run = ["sh", "tests/other.sh"]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  [ "$(next_action)" = "approve" ]
  jq '.checks[0].run = ["sh", "tests/pay.sh"] | .requirements[0].text = "changed"' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  [ "$(next_action)" = "approve" ]
}
