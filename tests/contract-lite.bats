#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/03-test-phase"

  # Create a sample PLAN.md
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/03-test-phase/03-01-PLAN.md" <<'EOF'
---
phase: 3
plan: 1
title: "Test Plan"
wave: 1
depends_on: []
must_haves:
  - "Feature A implemented"
  - "Feature B tested"
---

# Plan 03-01: Test Plan

## Tasks

### Task 1: Implement feature A
- **Files:** `scripts/feature-a.sh`, `config/settings.json`
- **Action:** Create feature A.

### Task 2: Test feature B
- **Files:** `tests/feature-b.bats`
- **Action:** Add tests.
EOF
}

teardown() {
  teardown_temp_dir
}

@test "generate-contract.sh exits 0 when v3_contract_lite=false" {
  # OBSOLETE: v3_contract_lite graduated (always on)
  # Test retained but now expects contracts to be generated
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/03-test-phase/03-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ -f ".vbw-planning/.contracts/3-1.json" ]
}

@test "generate-contract.sh creates contract JSON when flag=true" {
  # v3_contract_lite graduated (always on) — no need to set flag
  cd "$TEST_TEMP_DIR"

  run bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/03-test-phase/03-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ -f ".vbw-planning/.contracts/3-1.json" ]
}

@test "generate-contract.sh contract has correct must_haves" {
  cd "$TEST_TEMP_DIR"

  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/03-test-phase/03-01-PLAN.md"

  run jq -r '.must_haves | length' ".vbw-planning/.contracts/3-1.json"
  [ "$output" = "2" ]

  run jq -r '.must_haves[0]' ".vbw-planning/.contracts/3-1.json"
  [ "$output" = "Feature A implemented" ]
}

@test "generate-contract.sh contract has allowed_paths from task Files" {
  cd "$TEST_TEMP_DIR"

  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/03-test-phase/03-01-PLAN.md"

  # Should include files from both tasks
  run jq -r '.allowed_paths | length' ".vbw-planning/.contracts/3-1.json"
  [ "$output" -ge 3 ]

  run jq -r '.allowed_paths[]' ".vbw-planning/.contracts/3-1.json"
  echo "$output" | grep -q "scripts/feature-a.sh"
  echo "$output" | grep -q "config/settings.json"
  echo "$output" | grep -q "tests/feature-b.bats"
}

@test "generate-contract.sh contract has correct task_count" {
  cd "$TEST_TEMP_DIR"

  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/03-test-phase/03-01-PLAN.md"

  run jq -r '.task_count' ".vbw-planning/.contracts/3-1.json"
  [ "$output" = "2" ]
}

@test "generate-contract.sh preserves normalized dependency references" {
  cd "$TEST_TEMP_DIR"

  cat > ".vbw-planning/phases/03-test-phase/03-02-PLAN.md" <<'EOF'
---
phase: 3
plan: 2
title: "Dependency Parser Test"
wave: 2
depends_on:
  - 1
  - "03-01"
  - custom-id
---

# Plan 03-02: Dependency Parser Test

## Tasks

### Task 1: Implement dependent work
- **Files:** `scripts/dependent.sh`
- **Action:** Create dependent work.
EOF

  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/03-test-phase/03-02-PLAN.md"

  run jq -c '.depends_on' ".vbw-planning/.contracts/3-2.json"
  [ "$output" = '["03-01","03-01","custom-id"]' ]
}

@test "validate-contract.sh start mode passes for valid task" {
  cd "$TEST_TEMP_DIR"

  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/03-test-phase/03-01-PLAN.md"

  run bash "$SCRIPTS_DIR/validate-contract.sh" start ".vbw-planning/.contracts/3-1.json" 1
  [ "$status" -eq 0 ]
}

@test "validate-contract.sh start mode logs violation for out-of-range task" {
  cd "$TEST_TEMP_DIR"

  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/03-test-phase/03-01-PLAN.md"

  run bash "$SCRIPTS_DIR/validate-contract.sh" start ".vbw-planning/.contracts/3-1.json" 99
  # Hard contracts graduated — violations are hard stops (exit 2)
  [ "$status" -eq 2 ]

  # Should have logged a scope_violation metric
  [ -f ".vbw-planning/.metrics/run-metrics.jsonl" ]
  grep -q "scope_violation" ".vbw-planning/.metrics/run-metrics.jsonl"
}

@test "validate-contract.sh end mode passes for in-scope files" {
  cd "$TEST_TEMP_DIR"

  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/03-test-phase/03-01-PLAN.md"

  run bash "$SCRIPTS_DIR/validate-contract.sh" end ".vbw-planning/.contracts/3-1.json" 1 "scripts/feature-a.sh"
  [ "$status" -eq 0 ]
}

@test "validate-contract.sh end mode logs violation for out-of-scope files" {
  cd "$TEST_TEMP_DIR"

  bash "$SCRIPTS_DIR/generate-contract.sh" ".vbw-planning/phases/03-test-phase/03-01-PLAN.md"

  run bash "$SCRIPTS_DIR/validate-contract.sh" end ".vbw-planning/.contracts/3-1.json" 1 "some/random/file.txt"
  # Hard contracts graduated — out-of-scope is a hard stop (exit 2)
  [ "$status" -eq 2 ]

  # Should have logged a scope_violation metric
  [ -f ".vbw-planning/.metrics/run-metrics.jsonl" ]
  grep -q "scope_violation" ".vbw-planning/.metrics/run-metrics.jsonl"
  grep -q "out_of_scope" ".vbw-planning/.metrics/run-metrics.jsonl"
}
