#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  teardown_temp_dir
}

# --- get command ---

@test "get returns none when no state file exists" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "get returns persisted stage" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
}

@test "get emits metadata when stage is active" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=execute\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^round=02$"
  echo "$output" | grep -q "^round_dir=.*remediation/qa/round-02$"
}

# --- init command ---

@test "init creates state file and round-01 dir" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]
  grep -q "^stage=plan$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  grep -q "^round=01$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  [ -d "$PHASE_DIR/remediation/qa/round-01" ]
}

@test "init emits plan metadata" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^round=01$"
  echo "$output" | grep -q "^round_dir=.*remediation/qa/round-01$"
  echo "$output" | grep -q "^plan_path=.*R01-PLAN.md$"
}

# --- get-or-init command ---

@test "get-or-init initializes when no state exists" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get-or-init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]
  [ -d "$PHASE_DIR/remediation/qa/round-01" ]
}

@test "get-or-init returns existing stage without reinitializing" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=execute\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get-or-init "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "execute" ]
  # Round preserved, not reset to 01
  echo "$output" | grep -q "^round=02$"
  grep -q "^stage=execute$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  grep -q "^round=02$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

# --- advance command ---

@test "advance chain: plan -> execute -> verify -> done" {
  bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR" >/dev/null

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$(echo "$output" | head -1)" = "execute" ]
  grep -q "^stage=execute$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$(echo "$output" | head -1)" = "verify" ]
  grep -q "^stage=verify$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$(echo "$output" | head -1)" = "done" ]
  grep -q "^stage=done$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "advance from done stays at done" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "done" ]
  grep -q "^stage=done$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "advance preserves round number" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=plan\nround=03\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$(echo "$output" | head -1)" = "execute" ]
  grep -q "^round=03$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "advance with no active state errors" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" advance "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

# --- needs-round command ---

@test "needs-round starts round-02 from done state" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  echo "$output" | grep -q "^round=02$"
  [ -d "$PHASE_DIR/remediation/qa/round-02" ]
  grep -q "^stage=plan$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  grep -q "^round=02$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "needs-round increments to round-03" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-02"
  printf 'stage=done\nround=02\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^round=03$"
  [ -d "$PHASE_DIR/remediation/qa/round-03" ]
}

@test "needs-round from verify stage succeeds" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1)" = "plan" ]
  echo "$output" | grep -q "^round=02$"
}

@test "needs-round from plan stage errors" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

@test "needs-round from execute stage errors" {
  mkdir -p "$PHASE_DIR/remediation/qa"
  printf 'stage=execute\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" needs-round "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

# --- reset command ---

@test "reset removes state file" {
  bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$PHASE_DIR" >/dev/null

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" reset "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
  [ ! -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]
}

# --- error handling ---

@test "missing arguments exits with error" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh"
  [ "$status" -eq 1 ]

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" get
  [ "$status" -eq 1 ]
}

@test "unknown command exits with error" {
  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" bogus "$PHASE_DIR"
  [ "$status" -eq 1 ]
}

@test "archived milestone path is rejected" {
  ARCHIVED_DIR="$TEST_TEMP_DIR/.vbw-planning/milestones/v1/phases/01-test"
  mkdir -p "$ARCHIVED_DIR"

  run bash "$SCRIPTS_DIR/qa-remediation-state.sh" init "$ARCHIVED_DIR"
  [ "$status" -eq 1 ]
}
