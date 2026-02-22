#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.contracts"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.metrics"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
}

teardown() {
  teardown_temp_dir
}

create_valid_contract() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/.contracts/1-1.json" << 'CONTRACT'
{
  "phase_id": "phase-1",
  "plan_id": "phase-1-plan-1",
  "phase": 1,
  "plan": 1,
  "objective": "Test Plan",
  "task_ids": ["1-1-T1", "1-1-T2"],
  "task_count": 2,
  "allowed_paths": ["src/a.js", "src/b.js"],
  "forbidden_paths": [".env", "secrets"],
  "depends_on": [],
  "must_haves": ["Feature A works"],
  "verification_checks": ["true"],
  "max_token_budget": 50000,
  "timeout_seconds": 600
}
CONTRACT
  # Compute and add hash
  cd "$TEST_TEMP_DIR"
  local hash
  hash=$(jq 'del(.contract_hash)' ".vbw-planning/.contracts/1-1.json" | shasum -a 256 | cut -d' ' -f1)
  jq --arg h "$hash" '.contract_hash = $h' ".vbw-planning/.contracts/1-1.json" > ".vbw-planning/.contracts/1-1.json.tmp" \
    && mv ".vbw-planning/.contracts/1-1.json.tmp" ".vbw-planning/.contracts/1-1.json"
}

create_tampered_contract() {
  create_valid_contract
  cd "$TEST_TEMP_DIR"
  jq '.task_count = 99' ".vbw-planning/.contracts/1-1.json" > ".vbw-planning/.contracts/1-1.json.tmp" \
    && mv ".vbw-planning/.contracts/1-1.json.tmp" ".vbw-planning/.contracts/1-1.json"
}

# --- hard-gate.sh tests ---

@test "gate: contract_compliance passes with valid contract" {
  create_valid_contract
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/hard-gate.sh" contract_compliance 1 1 1 ".vbw-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "gate: contract_compliance fails on tampered contract" {
  create_tampered_contract
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/hard-gate.sh" contract_compliance 1 1 1 ".vbw-planning/.contracts/1-1.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
}

@test "gate: contract_compliance fails on task out of range" {
  create_valid_contract
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/hard-gate.sh" contract_compliance 1 1 99 ".vbw-planning/.contracts/1-1.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
  [[ "$output" == *"outside range"* ]]
}

@test "gate: contract_compliance fails on missing contract" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/hard-gate.sh" contract_compliance 1 1 1 ".vbw-planning/.contracts/nonexistent.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
}

@test "gate: required_checks passes when checks succeed" {
  create_valid_contract
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/hard-gate.sh" required_checks 1 1 1 ".vbw-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "gate: required_checks fails when check command fails" {
  create_valid_contract
  cd "$TEST_TEMP_DIR"
  # Set verification_checks to a failing command
  jq '.verification_checks = ["false"]' ".vbw-planning/.contracts/1-1.json" > ".vbw-planning/.contracts/1-1.json.tmp" \
    && mv ".vbw-planning/.contracts/1-1.json.tmp" ".vbw-planning/.contracts/1-1.json"
  # Recompute hash
  local hash
  hash=$(jq 'del(.contract_hash)' ".vbw-planning/.contracts/1-1.json" | shasum -a 256 | cut -d' ' -f1)
  jq --arg h "$hash" '.contract_hash = $h' ".vbw-planning/.contracts/1-1.json" > ".vbw-planning/.contracts/1-1.json.tmp" \
    && mv ".vbw-planning/.contracts/1-1.json.tmp" ".vbw-planning/.contracts/1-1.json"

  run bash "$SCRIPTS_DIR/hard-gate.sh" required_checks 1 1 1 ".vbw-planning/.contracts/1-1.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
}

@test "gate: commit_hygiene passes valid commit format" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.name "test" && git config user.email "test@test.com"
  echo "test" > file.txt
  git add file.txt && git commit -q -m "feat(test): valid commit"
  create_valid_contract
  run bash "$SCRIPTS_DIR/hard-gate.sh" commit_hygiene 1 1 1 ".vbw-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "gate: commit_hygiene fails invalid commit format" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.name "test" && git config user.email "test@test.com"
  echo "test" > file.txt
  git add file.txt && git commit -q -m "bad commit message"
  create_valid_contract
  run bash "$SCRIPTS_DIR/hard-gate.sh" commit_hygiene 1 1 1 ".vbw-planning/.contracts/1-1.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
}

@test "gate: verification_threshold prefers final verification over wave file (final FAIL)" {
  cd "$TEST_TEMP_DIR"
  cat > ".vbw-planning/phases/01-test/01-VERIFICATION-wave1.md" << 'EOF'
## Summary
Result: PASS
EOF
  cat > ".vbw-planning/phases/01-test/01-VERIFICATION.md" << 'EOF'
## Summary
Result: FAIL
EOF

  run bash "$SCRIPTS_DIR/hard-gate.sh" verification_threshold 01 1 1 ".vbw-planning/.contracts/nonexistent.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
  [[ "$output" == *"verification failed"* ]]
}

@test "gate: verification_threshold prefers final verification over wave file (final PASS)" {
  cd "$TEST_TEMP_DIR"
  cat > ".vbw-planning/phases/01-test/01-VERIFICATION-wave1.md" << 'EOF'
## Summary
Result: FAIL
EOF
  cat > ".vbw-planning/phases/01-test/01-VERIFICATION.md" << 'EOF'
## Summary
Result: PASS
EOF

  run bash "$SCRIPTS_DIR/hard-gate.sh" verification_threshold 01 1 1 ".vbw-planning/.contracts/nonexistent.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
  [[ "$output" == *"verification passed"* ]]
}


@test "gate: JSON output format correct" {
  create_valid_contract
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/hard-gate.sh" contract_compliance 1 1 1 ".vbw-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  # Verify all JSON fields present
  echo "$output" | jq -e '.gate == "contract_compliance"'
  echo "$output" | jq -e '.result'
  echo "$output" | jq -e '.evidence'
  echo "$output" | jq -e '.ts'
}

@test "gate: logs gate_passed event" {
  create_valid_contract
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/hard-gate.sh" contract_compliance 1 1 1 ".vbw-planning/.contracts/1-1.json" >/dev/null 2>&1
  [ -f ".vbw-planning/.events/event-log.jsonl" ]
  EVENT=$(tail -1 ".vbw-planning/.events/event-log.jsonl")
  echo "$EVENT" | jq -e '.event == "gate_passed"'
}

# --- auto-repair.sh tests ---

@test "auto-repair: non-repairable gate escalates immediately" {
  create_valid_contract
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/auto-repair.sh" protected_file 1 1 1 ".vbw-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.repaired == false'
  echo "$output" | jq -e '.attempts == 0'
  [[ "$output" == *"not repairable"* ]]
}

@test "auto-repair: repairable gate attempts max 2 retries" {
  create_tampered_contract
  cd "$TEST_TEMP_DIR"
  # Create the plan file so regeneration can work
  mkdir -p ".vbw-planning/phases/01-test"
  cat > ".vbw-planning/phases/01-test/01-01-PLAN.md" << 'PLAN'
---
phase: 1
plan: 1
title: Test Plan
wave: 1
depends_on: []
must_haves:
  - "Feature A"
---

# Plan

### Task 1: Do something
**Files:** `src/a.js`
PLAN
  run bash "$SCRIPTS_DIR/auto-repair.sh" contract_compliance 1 1 1 ".vbw-planning/.contracts/1-1.json"
  [ "$status" -eq 0 ]
  # Should attempt repair (regenerate contract)
  ATTEMPTS=$(echo "$output" | jq -r '.attempts')
  [ "$ATTEMPTS" -le 2 ]
}


@test "auto-repair: blocker event logged on final failure" {
  create_tampered_contract
  cd "$TEST_TEMP_DIR"
  # No plan file -> repair can't regenerate -> should escalate
  bash "$SCRIPTS_DIR/auto-repair.sh" contract_compliance 1 1 1 ".vbw-planning/.contracts/1-1.json" >/dev/null 2>&1
  [ -f ".vbw-planning/.events/event-log.jsonl" ]
  # Check for task_blocked event
  BLOCKED=$(grep 'task_blocked' ".vbw-planning/.events/event-log.jsonl" | tail -1)
  [ -n "$BLOCKED" ]
  echo "$BLOCKED" | jq -e '.data.owner == "lead"'
}
