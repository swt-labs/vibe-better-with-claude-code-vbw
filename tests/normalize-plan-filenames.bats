#!/usr/bin/env bats
# Tests for scripts/normalize-plan-filenames.sh brownfield research migration.

SCRIPT="scripts/normalize-plan-filenames.sh"

setup() {
  TEST_DIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "renames phase-dir PLAN-01.md to 01-PLAN.md" {
  PHASE_DIR="$TEST_DIR/.vbw-planning/phases/01-setup"
  mkdir -p "$PHASE_DIR"
  echo "plan" > "$PHASE_DIR/PLAN-01.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ -f "$PHASE_DIR/01-PLAN.md" ]
  [ ! -f "$PHASE_DIR/PLAN-01.md" ]
  [ ! -f "$PHASE_DIR/R01-PLAN.md" ]
  [[ "$output" == *"renamed: PLAN-01.md -> 01-PLAN.md"* ]]
}

@test "renames QA round-dir PLAN-R01.md to R01-PLAN.md" {
  ROUND_DIR="$TEST_DIR/.vbw-planning/phases/01-setup/remediation/qa/round-01"
  mkdir -p "$ROUND_DIR"
  echo "plan" > "$ROUND_DIR/PLAN-R01.md"

  run bash "$SCRIPT" "$ROUND_DIR"

  [ "$status" -eq 0 ]
  [ -f "$ROUND_DIR/R01-PLAN.md" ]
  [ ! -f "$ROUND_DIR/PLAN-R01.md" ]
  [ ! -f "$ROUND_DIR/01-PLAN.md" ]
  [[ "$output" == *"renamed: PLAN-R01.md -> R01-PLAN.md"* ]]
}

@test "renames QA round-dir PLAN-01.md to R01-PLAN.md" {
  ROUND_DIR="$TEST_DIR/.vbw-planning/phases/01-setup/remediation/qa/round-01"
  mkdir -p "$ROUND_DIR"
  echo "plan" > "$ROUND_DIR/PLAN-01.md"

  run bash "$SCRIPT" "$ROUND_DIR"

  [ "$status" -eq 0 ]
  [ -f "$ROUND_DIR/R01-PLAN.md" ]
  [ ! -f "$ROUND_DIR/PLAN-01.md" ]
  [ ! -f "$ROUND_DIR/01-PLAN.md" ]
  [[ "$output" == *"renamed: PLAN-01.md -> R01-PLAN.md"* ]]
}

@test "renames UAT round-dir PLAN-01.md to R01-PLAN.md" {
  ROUND_DIR="$TEST_DIR/.vbw-planning/phases/01-setup/remediation/uat/round-01"
  mkdir -p "$ROUND_DIR"
  echo "plan" > "$ROUND_DIR/PLAN-01.md"

  run bash "$SCRIPT" "$ROUND_DIR"

  [ "$status" -eq 0 ]
  [ -f "$ROUND_DIR/R01-PLAN.md" ]
  [ ! -f "$ROUND_DIR/PLAN-01.md" ]
  [ ! -f "$ROUND_DIR/01-PLAN.md" ]
  [[ "$output" == *"renamed: PLAN-01.md -> R01-PLAN.md"* ]]
}

@test "renames legacy remediation round-dir PLAN-01.md to R01-PLAN.md" {
  ROUND_DIR="$TEST_DIR/.vbw-planning/phases/01-setup/remediation/round-01"
  mkdir -p "$ROUND_DIR"
  echo "plan" > "$ROUND_DIR/PLAN-01.md"

  run bash "$SCRIPT" "$ROUND_DIR"

  [ "$status" -eq 0 ]
  [ -f "$ROUND_DIR/R01-PLAN.md" ]
  [ ! -f "$ROUND_DIR/PLAN-01.md" ]
  [ ! -f "$ROUND_DIR/01-PLAN.md" ]
  [[ "$output" == *"renamed: PLAN-01.md -> R01-PLAN.md"* ]]
}

@test "renames legacy remediation round-dir PLAN-R01.md to R01-PLAN.md" {
  ROUND_DIR="$TEST_DIR/.vbw-planning/phases/01-setup/remediation/round-01"
  mkdir -p "$ROUND_DIR"
  echo "plan" > "$ROUND_DIR/PLAN-R01.md"

  run bash "$SCRIPT" "$ROUND_DIR"

  [ "$status" -eq 0 ]
  [ -f "$ROUND_DIR/R01-PLAN.md" ]
  [ ! -f "$ROUND_DIR/PLAN-R01.md" ]
  [ ! -f "$ROUND_DIR/01-PLAN.md" ]
  [[ "$output" == *"renamed: PLAN-R01.md -> R01-PLAN.md"* ]]
}

@test "replaces existing round-dir R01-PLAN.md with fresh misnamed plan" {
  ROUND_DIR="$TEST_DIR/.vbw-planning/phases/01-setup/remediation/qa/round-01"
  mkdir -p "$ROUND_DIR"
  echo "stale" > "$ROUND_DIR/R01-PLAN.md"
  echo "fresh" > "$ROUND_DIR/PLAN-01.md"

  run bash "$SCRIPT" "$ROUND_DIR"

  [ "$status" -eq 0 ]
  [ -f "$ROUND_DIR/R01-PLAN.md" ]
  [ ! -f "$ROUND_DIR/PLAN-01.md" ]
  [ ! -f "$ROUND_DIR/01-PLAN.md" ]
  [ "$(cat "$ROUND_DIR/R01-PLAN.md")" = "fresh" ]
  [[ "$output" == *"renamed: PLAN-01.md -> R01-PLAN.md (replaced existing target)"* ]]
}

@test "renames {NN}-01-RESEARCH.md to {NN}-RESEARCH.md when it is the only research file" {
  PHASE_DIR="$TEST_DIR/03-auth"
  mkdir -p "$PHASE_DIR"
  echo "phase-wide research" > "$PHASE_DIR/03-01-RESEARCH.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ -f "$PHASE_DIR/03-RESEARCH.md" ]
  [ ! -f "$PHASE_DIR/03-01-RESEARCH.md" ]
  [[ "$output" == *"renamed: 03-01-RESEARCH.md -> 03-RESEARCH.md"* ]]
}

@test "does not rename when phase-wide {NN}-RESEARCH.md already exists" {
  PHASE_DIR="$TEST_DIR/03-auth"
  mkdir -p "$PHASE_DIR"
  echo "old plan-specific research" > "$PHASE_DIR/03-01-RESEARCH.md"
  echo "existing phase-wide research" > "$PHASE_DIR/03-RESEARCH.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ -f "$PHASE_DIR/03-01-RESEARCH.md" ]
  [ -f "$PHASE_DIR/03-RESEARCH.md" ]
  [[ "$output" != *"03-01-RESEARCH.md -> 03-RESEARCH.md"* ]]
}

@test "does not rename when additional per-plan research exists" {
  PHASE_DIR="$TEST_DIR/03-auth"
  mkdir -p "$PHASE_DIR"
  echo "plan 01 research" > "$PHASE_DIR/03-01-RESEARCH.md"
  echo "plan 02 research" > "$PHASE_DIR/03-02-RESEARCH.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ -f "$PHASE_DIR/03-01-RESEARCH.md" ]
  [ -f "$PHASE_DIR/03-02-RESEARCH.md" ]
  [ ! -f "$PHASE_DIR/03-RESEARCH.md" ]
  [[ "$output" != *"03-01-RESEARCH.md -> 03-RESEARCH.md"* ]]
}

@test "does not rename when a three-digit higher-numbered per-plan research file exists" {
  PHASE_DIR="$TEST_DIR/03-auth"
  mkdir -p "$PHASE_DIR"
  echo "plan 01 research" > "$PHASE_DIR/03-01-RESEARCH.md"
  echo "plan 100 research" > "$PHASE_DIR/03-100-RESEARCH.md"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ -f "$PHASE_DIR/03-01-RESEARCH.md" ]
  [ -f "$PHASE_DIR/03-100-RESEARCH.md" ]
  [ ! -f "$PHASE_DIR/03-RESEARCH.md" ]
  [[ "$output" != *"03-01-RESEARCH.md -> 03-RESEARCH.md"* ]]
}
