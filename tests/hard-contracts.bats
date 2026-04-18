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

setup_unrelated_git_repo() {
  local repo_dir="$1"

  mkdir -p "$repo_dir"
  cd "$repo_dir" || return 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"
  echo "initial" > unrelated.txt
  git add unrelated.txt
  git commit -qm "init"
}

create_plan_file() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-PLAN.md" << 'PLAN'
---
phase: 1
plan: 1
title: Test Plan
wave: 1
depends_on: []
must_haves:
  - "Feature A works"
  - "Feature B passes tests"
forbidden_paths:
  - ".env"
  - "secrets/"
verification_checks:
  - "true"
---

# Plan 01-01: Test Plan

### Task 1: Implement feature A
**Files:** `src/a.js`

### Task 2: Implement feature B
**Files:** `src/b.js`, `tests/b.test.js`
PLAN
}

# --- generate-contract.sh tests ---

@test "generate-contract: v2 hard emits all 11 fields + hash" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  CONTRACT=".vbw-planning/.contracts/1-1.json"
  [ -f "$CONTRACT" ]
  # Check all fields present
  [ "$(jq -r '.phase_id' "$CONTRACT")" = "phase-1" ]
  [ "$(jq -r '.plan_id' "$CONTRACT")" = "phase-1-plan-1" ]
  [ "$(jq -r '.objective' "$CONTRACT")" = "Test Plan" ]
  [ "$(jq '.task_count' "$CONTRACT")" = "2" ]
  [ "$(jq '.task_ids | length' "$CONTRACT")" = "2" ]
  [ "$(jq '.allowed_paths | length' "$CONTRACT")" -ge 1 ]
  [ "$(jq '.forbidden_paths | length' "$CONTRACT")" = "2" ]
  [ "$(jq '.must_haves | length' "$CONTRACT")" = "2" ]
  [ "$(jq '.verification_checks | length' "$CONTRACT")" = "1" ]
  [ "$(jq '.max_token_budget' "$CONTRACT")" -gt 0 ]
  [ "$(jq '.timeout_seconds' "$CONTRACT")" -gt 0 ]
  # Hash present and non-empty
  HASH=$(jq -r '.contract_hash' "$CONTRACT")
  [ -n "$HASH" ]
  [ "$HASH" != "null" ]
}

@test "generate-contract: always emits full contract (v3 lite graduated)" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  CONTRACT=".vbw-planning/.contracts/1-1.json"
  [ -f "$CONTRACT" ]
  # v3_contract_lite graduated — always full contracts with all fields + hash
  [ "$(jq -r '.phase_id' "$CONTRACT")" = "phase-1" ]
  [ "$(jq -r '.plan_id' "$CONTRACT")" = "phase-1-plan-1" ]
  [ "$(jq '.task_count' "$CONTRACT")" = "2" ]
  HASH=$(jq -r '.contract_hash' "$CONTRACT")
  [ -n "$HASH" ]
  [ "$HASH" != "null" ]
}

@test "generate-contract: contract hash is deterministic" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  HASH1=$(jq -r '.contract_hash' ".vbw-planning/.contracts/1-1.json")
  # Regenerate
  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  HASH2=$(jq -r '.contract_hash' ".vbw-planning/.contracts/1-1.json")
  [ "$HASH1" = "$HASH2" ]
}

@test "generate-contract: off-root absolute plan path writes contract to target planning dir" {
  local unrelated_repo="$TEST_TEMP_DIR/unrelated-git"
  local canonical_root
  local target_contract

  create_plan_file
  setup_unrelated_git_repo "$unrelated_repo"
  canonical_root=$(cd "$TEST_TEMP_DIR" && pwd -P)
  target_contract="$canonical_root/.vbw-planning/.contracts/1-1.json"
  cd "$unrelated_repo" || return 1

  run bash "$SCRIPTS_DIR/generate-contract.sh" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$target_contract" ]
  [ -f "$target_contract" ]
  [ ! -e "$unrelated_repo/.vbw-planning/.contracts/1-1.json" ]
}

# --- validate-contract.sh tests ---

@test "validate-contract: hash mismatch hard stop" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".vbw-planning/.contracts/1-1.json"
  # Tamper with contract (change task_count)
  jq '.task_count = 99' "$CONTRACT" > "${CONTRACT}.tmp" && mv "${CONTRACT}.tmp" "$CONTRACT"
  run bash "$SCRIPTS_DIR/validate-contract.sh" start "$CONTRACT" 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"hash_mismatch"* ]] || [[ "$output" == *"hash mismatch"* ]]
}

@test "validate-contract: valid hash passes" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".vbw-planning/.contracts/1-1.json"
  run bash "$SCRIPTS_DIR/validate-contract.sh" start "$CONTRACT" 1
  [ "$status" -eq 0 ]
}

@test "validate-contract: forbidden path hard stop" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".vbw-planning/.contracts/1-1.json"
  run bash "$SCRIPTS_DIR/validate-contract.sh" end "$CONTRACT" 1 ".env"
  [ "$status" -eq 2 ]
  [[ "$output" == *"forbidden_path"* ]] || [[ "$output" == *"forbidden path"* ]]
}

@test "validate-contract: forbidden path subdir hard stop" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".vbw-planning/.contracts/1-1.json"
  run bash "$SCRIPTS_DIR/validate-contract.sh" end "$CONTRACT" 1 "secrets/api-key.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"forbidden_path"* ]] || [[ "$output" == *"forbidden path"* ]]
}

@test "validate-contract: out of scope file hard stop" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".vbw-planning/.contracts/1-1.json"
  run bash "$SCRIPTS_DIR/validate-contract.sh" end "$CONTRACT" 1 "unrelated/file.js"
  [ "$status" -eq 2 ]
  [[ "$output" == *"out_of_scope"* ]]
}

@test "validate-contract: hard contracts graduated (always hard stop)" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".vbw-planning/.contracts/1-1.json"
  # Out of scope file — always hard stop (v3 lite graduated to full)
  run bash "$SCRIPTS_DIR/validate-contract.sh" end "$CONTRACT" 1 "unrelated/file.js"
  [ "$status" -eq 2 ]
  [[ "$output" == *"out_of_scope"* ]]
}

# --- contract-revision.sh tests ---

@test "contract-revision: detects scope change and archives old" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".vbw-planning/.contracts/1-1.json"
  OLD_HASH=$(jq -r '.contract_hash' "$CONTRACT")

  # Modify plan (add a task)
  cat >> ".vbw-planning/phases/01-test/01-01-PLAN.md" << 'EXTRA'

### Task 3: Extra task
**Files:** `src/c.js`
EXTRA

  run bash "$SCRIPTS_DIR/contract-revision.sh" "$CONTRACT" ".vbw-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"revised:"* ]]
  # Old contract archived
  [ -f ".vbw-planning/.contracts/1-1.rev1.json" ]
  # New contract has different hash
  NEW_HASH=$(jq -r '.contract_hash' "$CONTRACT")
  [ "$OLD_HASH" != "$NEW_HASH" ]
}

@test "contract-revision: no change returns no_change" {
  create_plan_file
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/01-test/01-01-PLAN.md" >/dev/null
  CONTRACT=".vbw-planning/.contracts/1-1.json"
  run bash "$SCRIPTS_DIR/contract-revision.sh" "$CONTRACT" ".vbw-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no_change"* ]]
}
