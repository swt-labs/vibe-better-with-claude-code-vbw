#!/usr/bin/env bats
# Tests for scripts/normalize-plan-filenames.sh brownfield research migration.

SCRIPT="scripts/normalize-plan-filenames.sh"

setup() {
  TEST_DIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TEST_DIR"
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
