#!/usr/bin/env bats
# R12: vbw qa record refuses a verdict on a proof older than the current code
# and names vbw prove as the next step; the QA agent and workflow recover.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt && "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove > /dev/null
}

teardown() { vbw_teardown; }

@test "R12: after a code change since the last proof, qa record refuses, names vbw prove, writes nothing" {
  printf 'more\n' > src/extra.txt
  local before; before=$(git rev-parse HEAD)
  local sum; sum=$(shasum .vbw/record.json)
  vbw_run qa record P1 pass standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw prove"* ]]
  [ "$(shasum .vbw/record.json)" = "$sum" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  jq -e '.phases[0].qa == null' .vbw/record.json
}

@test "R12: after vbw prove, the same qa record succeeds" {
  printf 'more\n' > src/extra.txt
  run "$VBW" qa record P1 pass standard
  [ "$status" -ne 0 ]
  "$VBW" prove > /dev/null
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ]
  jq -e '.phases[0].qa.result == "pass"' .vbw/record.json
}

@test "R12: the QA agent and the verifying workflow run prove and retry when qa record refuses" {
  grep -q 'refus' "$PLUGIN_ROOT/agents/qa.md"
  grep -A3 'refus' "$PLUGIN_ROOT/agents/qa.md" | grep -q 'vbw prove'
  grep -A3 'refus' "$PLUGIN_ROOT/agents/qa.md" | grep -qi 'retry\|again'
  grep -q 'vbw prove' "$PLUGIN_ROOT/workflows/verifying.js"
  grep -q 'refus' "$PLUGIN_ROOT/workflows/verifying.js"
}
