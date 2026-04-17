#!/usr/bin/env bats

# Tests for caveman language mode integration
# Verifies resolve-caveman-level.sh, config injection in session-start.sh,
# compile-context.sh, and compaction-instructions.sh

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase"
}

teardown() {
  teardown_temp_dir
}

# ---------------------------------------------------------------------------
# resolve-caveman-level.sh — passthrough for non-auto values
# ---------------------------------------------------------------------------

@test "resolve-caveman-level: non-auto value passes through unchanged (full)" {
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "full" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "full" ]
}

@test "resolve-caveman-level: non-auto value passes through unchanged (none)" {
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "none" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "none" ]
}

@test "resolve-caveman-level: non-auto value passes through unchanged (lite)" {
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "lite" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "lite" ]
}

@test "resolve-caveman-level: non-auto value passes through unchanged (ultra)" {
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "ultra" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "ultra" ]
}

# ---------------------------------------------------------------------------
# resolve-caveman-level.sh — auto mode with .context-usage
# ---------------------------------------------------------------------------

@test "resolve-caveman-level: auto with missing .context-usage defaults to none" {
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "none" ]
}

@test "resolve-caveman-level: auto at 40% context usage resolves to none" {
  echo "test-session|40|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "none" ]
}

@test "resolve-caveman-level: auto at 50% context usage resolves to lite" {
  echo "test-session|50|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "lite" ]
}

@test "resolve-caveman-level: auto at 60% context usage resolves to lite" {
  echo "test-session|60|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "lite" ]
}

@test "resolve-caveman-level: auto at 70% context usage resolves to full" {
  echo "test-session|70|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "full" ]
}

@test "resolve-caveman-level: auto at 75% context usage resolves to full" {
  echo "test-session|75|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "full" ]
}

@test "resolve-caveman-level: auto at 85% context usage resolves to ultra" {
  echo "test-session|85|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "ultra" ]
}

@test "resolve-caveman-level: auto at 90% context usage resolves to ultra" {
  echo "test-session|90|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "ultra" ]
}

@test "resolve-caveman-level: auto at 49% context usage resolves to none" {
  echo "test-session|49|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "none" ]
}

@test "resolve-caveman-level: auto at 69% context usage resolves to lite" {
  echo "test-session|69|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "lite" ]
}

@test "resolve-caveman-level: auto at 84% context usage resolves to full" {
  echo "test-session|84|1000000" > "$TEST_TEMP_DIR/.vbw-planning/.context-usage"
  . "$SCRIPTS_DIR/lib/resolve-caveman-level.sh"
  resolve_caveman_level "auto" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$RESOLVED_CAVEMAN_LEVEL" = "full" ]
}
