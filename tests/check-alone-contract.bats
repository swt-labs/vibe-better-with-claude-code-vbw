#!/usr/bin/env bats
# R45: the alone marker of a check is part of the contract (docs/proof.md):
# apply accepts it, refuses a non-boolean naming the check, the contract hash
# and the approval screen carry it.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'grep -qx sent src/receipt.txt\n' > tests/receipt.sh
  PLAN='{"phases": [{"id": "P1", "title": "Checkout", "reqs": ["R1", "R2"], "tier": "standard"}],
         "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]},
                   {"id": "P1.2", "phase": "P1", "title": "Receipt", "reqs": ["R2"], "files": ["src/receipt.txt"], "after": ["P1.1"]}],
         "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]},
                    {"id": "C2", "req": "R2", "run": ["sh", "tests/receipt.sh"], "files": ["tests/receipt.sh"]}]}'
  ALONE=$(printf '%s' "$PLAN" | jq '.checks[0].alone = true')
}

teardown() { vbw_teardown; }

apply_doc() { printf '%s' "$1" | "$VBW" apply; }

@test "apply accepts alone: true, keeps it in the record and shows it in the contract" {
  run apply_doc "$ALONE"
  [ "$status" -eq 0 ]
  jq -e '(.checks[] | select(.id == "C1") | .alone) == true and (.checks[] | select(.id == "C2") | has("alone") | not)' .vbw/record.json
  vbw_run show contract
  [ "$status" -eq 0 ]
  [[ "$output" == *"C1"*"alone"* ]]
  [ "$(printf '%s\n' "$output" | grep -c 'alone')" -eq 1 ]
}

@test "apply accepts alone: false" {
  run apply_doc "$(printf '%s' "$PLAN" | jq '.checks[0].alone = false')"
  [ "$status" -eq 0 ]
  jq -e '(.checks[] | select(.id == "C1") | .alone) == false' .vbw/record.json
}

@test "a non-boolean alone is refused, naming the check, and changes nothing" {
  cp .vbw/record.json "$TEST_ROOT/before.json"
  local v
  for v in '"yes"' 1 null '[]'; do
    run apply_doc "$(printf '%s' "$PLAN" | jq ".checks[1].alone = $v")"
    [ "$status" -eq 1 ]
    [[ "$output" == *"C2"*"alone"*"boolean"* ]]
    cmp .vbw/record.json "$TEST_ROOT/before.json"
  done
}

@test "the alone marker is part of the contract hash" {
  apply_doc "$PLAN" > /dev/null
  plain=$(vbw_contract_hash)
  apply_doc "$ALONE" > /dev/null
  marked=$(vbw_contract_hash)
  [ -n "$plain" ] && [ -n "$marked" ] && [ "$plain" != "$marked" ]
  apply_doc "$PLAN" > /dev/null
  [ "$(vbw_contract_hash)" = "$plain" ]
}

@test "adding the marker to an approved contract needs approving again" {
  apply_doc "$PLAN" > /dev/null
  "$VBW" approve > /dev/null
  vbw_run check C1
  [[ "$output" != *"not approved"* ]]
  apply_doc "$ALONE" > /dev/null
  vbw_run check C1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not approved"* ]]
  vbw_run next --json
  echo "$output" | jq -e '.action == "approve"'
}

@test "removing the marker from an approved contract needs approving again" {
  apply_doc "$ALONE" > /dev/null
  "$VBW" approve > /dev/null
  apply_doc "$PLAN" > /dev/null
  vbw_run check C1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not approved"* ]]
}

@test "the approval screen shows an added or removed marker" {
  apply_doc "$PLAN" > /dev/null
  "$VBW" approve > /dev/null
  apply_doc "$ALONE" > /dev/null
  vbw_run show contract --changes
  [ "$status" -eq 0 ]
  [[ "$output" == *"C1"*"alone"* ]]
  "$VBW" approve > /dev/null
  apply_doc "$PLAN" > /dev/null
  vbw_run show contract --changes
  [[ "$output" == *"C1"*"alone"* ]]
}

@test "a record whose checks use alone is schema 2, so an older VBW asks for an update instead of calling it corrupt" {
  run apply_doc "$ALONE"
  [ "$status" -eq 0 ]
  jq -e '.schema == 2' .vbw/record.json
  vbw_run status
  [ "$status" -eq 0 ]
  run apply_doc "$PLAN"
  [ "$status" -eq 0 ]
  jq -e '.schema == 1 and all(.checks[]; has("alone") | not)' .vbw/record.json
}

@test "a schema-1 record with an alone check, or a schema-2 record without one, is refused as corrupt" {
  run apply_doc "$PLAN"
  [ "$status" -eq 0 ]
  jq '.schema = 2' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
  jq '.schema = 1 | .checks[0].alone = true' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
}

@test "a record newer than schema 2 still says it needs a newer VBW" {
  jq '.schema = 3' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 4 ]
  [[ "$output" == *"newer VBW"* ]]
}
