#!/usr/bin/env bats
# R111 (docs/proof.md): QA verdicts and shipping are accepted only after a full
# proof (vbw prove --full): vbw qa record and vbw ship refuse a proof that is
# not full without changing the record, vbw next asks for a full proof before
# QA or shipping, and QA agents are given the full proof's test result. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  # Each command prints which one ran, so the result a QA agent is given can be told apart.
  printf 'echo "$1 ok"\n' > tests/cmd.sh
  git add tests/cmd.sh && git commit -q -m "chore: project command"
  printf '%s' '{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt && "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  "$VBW" plan "done" P1.1 > /dev/null
  "$VBW" prove > /dev/null
}

teardown() { vbw_teardown; }

set_full() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# partial: the proof ran only part of the work (the record names it, as vbw prove does).
partial() { set_full '.evidence.full = false'; }

@test "R111: vbw qa record refuses a proof that is not full, changes nothing, and says to run vbw prove --full" {
  partial
  local before
  before=$(shasum .vbw/record.json)
  vbw_run qa record P1 pass standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"the last proof was partial: run vbw prove --full, then record the verdict again"* ]] || { echo "$output"; false; }
  [ "$(shasum .vbw/record.json)" = "$before" ]
}

@test "R111: the refusal for code that changed since the proof still applies first" {
  partial
  printf 'paid\nmore\n' > src/pay.txt
  git add src/pay.txt && git commit -q -m "fix(pay): more"
  vbw_run qa record P1 pass standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"the code changed since the last proof"* ]] || { echo "$output"; false; }
}

@test "R111: vbw ship refuses a proof that is not full, changes nothing, and says to run vbw prove --full" {
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ]
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" = ship ]
  partial
  local before
  before=$(shasum .vbw/record.json)
  vbw_run ship
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw prove --full"* ]] || { echo "$output"; false; }
  [ "$(shasum .vbw/record.json)" = "$before" ]
}

@test "R111: before QA, vbw next asks for a full proof when the latest proof is not full, and --json marks it" {
  partial
  vbw_run next --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "prove" and .detail.full == true and (.instruction | contains("Run vbw prove --full") and contains("a proof that ran every check"))' \
    || { echo "$output"; false; }
  vbw_run next
  [[ "$output" == *"Run vbw prove --full"* ]]
}

@test "R111: before shipping, vbw next asks for a full proof when the latest proof is not full" {
  vbw_run qa record P1 pass standard
  partial
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "prove" and .detail.full == true and (.instruction | contains("vbw prove --full"))' \
    || { echo "$output"; false; }
}

@test "R111: with a full proof, vbw next goes on to QA and does not mark the detail as full" {
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "qa" and (.detail.full // false) == false' || { echo "$output"; false; }
}

@test "R111: a refused verdict, then vbw prove --full, then the verdict is recorded" {
  "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null
  "$VBW" prove > /dev/null
  jq -e '.evidence.full == false' .vbw/record.json
  vbw_run qa record P1 pass standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw prove --full"* ]]
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.phases[0].qa.result == "pass"' .vbw/record.json
}

@test "R111: a proof recorded before the full flag existed counts as full" {
  set_full 'del(.evidence.full)'
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R111: the test-command result QA agents are given comes from the full proof, never from the quick command" {
  jq '.commands = {test: ["sh","tests/cmd.sh","full-suite"], quick: ["sh","tests/cmd.sh","quick-suite"]}' .vbw/record.json > "$TEST_ROOT/edit.json" \
    && cp "$TEST_ROOT/edit.json" .vbw/record.json
  "$VBW" approve > /dev/null
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "qa" and (.round.suite.tail | contains("full-suite")) and (.round.suite.tail | contains("quick-suite") | not)' \
    || { echo "$output"; false; }
}
