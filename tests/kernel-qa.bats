#!/usr/bin/env bats
# vbw qa: the QA agent's goal-backward verification of built phases (VBW 1's
# QA mandate; docs/proof.md).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt && "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove --full > /dev/null
}

teardown() { vbw_teardown; }

@test "after the proof, QA is next; a pass on the proven code lets the milestone ship" {
  vbw_run next --json
  echo "$output" | jq -e '.action == "qa" and .detail.phases == ["P1"]'
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ]
  jq -e '.phases[0].qa.result == "pass" and (.phases[0].qa.tree | test("^[0-9a-f]{64}$"))' .vbw/record.json
  vbw_run next --json
  echo "$output" | jq -e '.action == "ship"'
}

@test "a failed verdict needs findings; findings become fixes only QA closes, and a pass closes them" {
  vbw_run qa record P1 fail standard
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs its findings first"* ]]
  "$VBW" qa finding R1 "the plan said a receipt is printed; none is" > /dev/null
  vbw_run qa record P1 fail standard "1 deviation"
  [ "$status" -eq 0 ]
  jq -e '.fixes[0] | .source == "qa" and .status == "open" and .req == "R1"' .vbw/record.json
  vbw_run next --json
  echo "$output" | jq -e '.action == "fix" and .detail.fixes == ["F1"]'
  # The checks pass, but a proof never closes QA's finding.
  "$VBW" fix done F1 > /dev/null
  "$VBW" prove --full > /dev/null
  jq -e '.fixes[0].status == "fixed"' .vbw/record.json
  vbw_run qa record P1 pass standard
  jq -e '.fixes[0].status == "closed" and .phases[0].qa.result == "pass"' .vbw/record.json
}

@test "code that changes after QA needs QA again; three failed rounds escalate" {
  "$VBW" qa record P1 pass standard > /dev/null
  printf 'paid\nmore\n' > src/pay.txt
  git add src/pay.txt && git commit -q -m "fix(pay): more"
  "$VBW" prove --full > /dev/null
  vbw_run next --json
  echo "$output" | jq -e '.action == "qa"'
  local round
  for round in 1 2 3; do
    "$VBW" qa finding R1 "still deviates ($round)" > /dev/null
    "$VBW" qa record P1 fail standard > /dev/null
  done
  jq -e '.phases[0].qa.rounds == 3 and ([.fixes[] | select(.status == "escalated")] | length) == 3' .vbw/record.json
  vbw_run next --json
  echo "$output" | jq -e '.action == "escalate"'
}

@test "show phase gives QA the goal, criteria, tasks and verdict; show plan gives a Dev its tasks" {
  printf '%s' '{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"], "goal": "A customer can pay", "criteria": ["a paid order says paid"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"], "tasks": ["write paid", "check it"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" qa record P1 pass deep "18/18 checks" > /dev/null
  vbw_run show phase P1
  [[ "$output" == *"goal: A customer can pay"* ]]
  [[ "$output" == *"  - a paid order says paid"* ]]
  [[ "$output" == *"qa: pass (deep, "*"): 18/18 checks"* ]]
  [[ "$output" == *"    - write paid"* ]]
  vbw_run show plan P1.1
  [[ "$output" == *"tasks:"*"  1. write paid"*"  2. check it"* ]]
}
