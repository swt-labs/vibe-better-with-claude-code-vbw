#!/usr/bin/env bats
# R81 (docs/proof.md): an approval whose commit fails stops and says why
# (git's own reason), instead of only warning; the record does not show it as
# approved and no consent is kept, so the next try starts clean. An approval
# whose commit works is as before. L1: a git hook makes the commit fail.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"planned"}]
    | del(.requirements[]?.rules)' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  HOOK="$(git rev-parse --git-path hooks)/pre-commit"
  mkdir -p "$(dirname "$HOOK")"
  printf '#!/bin/sh\necho "refused by the project hook: lint failed" >&2\nexit 1\n' > "$HOOK"
  chmod +x "$HOOK"
}

teardown() { vbw_teardown; }

approved_decisions() { jq '[.decisions[] | select(.text | startswith("Contract approved"))] | length' .vbw/record.json; }

@test "R81: an approval whose commit fails stops with an error that says why" {
  vbw_run approve
  [ "$status" -ne 0 ]
  [[ "$output" == *"lint failed"* ]] || { echo "$output"; false; }
  [[ "$output" == *"not approved"* ]] || { echo "$output"; false; }
}

@test "R81: a failed approval leaves no approval: not in the record, not in the consent" {
  local before
  before=$(approved_decisions)
  vbw_run approve
  [ "$status" -ne 0 ]
  [ "$(approved_decisions)" = "$before" ]
  vbw_run show contract
  [[ "$output" == *"NOT APPROVED"* ]]
  vbw_run next --json
  echo "$output" | jq -e '.action == "approve"'
}

@test "R81: once the commit can work, the same approval goes through" {
  vbw_run approve
  [ "$status" -ne 0 ]
  rm -f "$HOOK"
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run show contract
  [[ "$output" == *"(approved)"* ]]
  [ "$(approved_decisions)" -ge 1 ]
}
