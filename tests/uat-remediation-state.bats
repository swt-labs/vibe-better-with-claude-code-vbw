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

@test "get returns none when no state file exists" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "init major creates discuss stage" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major"
  [ "$status" -eq 0 ]
  [ "$output" = "discuss" ]
  [ -f "$PHASE_DIR/.uat-remediation-stage" ]
  [ "$(cat "$PHASE_DIR/.uat-remediation-stage")" = "discuss" ]
}

@test "init minor creates fix stage" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "minor"
  [ "$status" -eq 0 ]
  [ "$output" = "fix" ]
  [ "$(cat "$PHASE_DIR/.uat-remediation-stage")" = "fix" ]
}

@test "init unknown severity defaults to discuss" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "unknown"
  [ "$status" -eq 0 ]
  [ "$output" = "discuss" ]
}

@test "advance major chain: discuss -> plan -> execute -> done" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "plan" ]

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "execute" ]

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "done" ]
}

@test "advance minor chain: fix -> done" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "minor" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "done" ]
}

@test "advance from done stays done" {
  echo "done" > "$PHASE_DIR/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR"
  [ "$output" = "done" ]
}

@test "get returns persisted stage after advance" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$PHASE_DIR" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get "$PHASE_DIR"
  [ "$output" = "plan" ]
}

@test "reset removes state file" {
  bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR" "major" >/dev/null

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" reset "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
  [ ! -f "$PHASE_DIR/.uat-remediation-stage" ]
}

@test "missing arguments exits with error" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh"
  [ "$status" -eq 1 ]

  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get
  [ "$status" -eq 1 ]
}

@test "init without severity exits with error" {
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$PHASE_DIR"
  [ "$status" -eq 1 ]
}
