#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  echo '# Project' > "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

# Helper: create a debug session with a given status
create_debug_session() {
  local status_val="$1"
  local slug="${2:-test-bug}"
  local subdir="active"
  if [ "$status_val" = "complete" ]; then
    subdir="completed"
  fi
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/debugging/$subdir"
  local session_id="20250101-120000-${slug}"
  local session_file="$TEST_TEMP_DIR/.vbw-planning/debugging/$subdir/${session_id}.md"

  cat > "$session_file" <<EOF
---
session_id: ${session_id}
title: ${slug}
status: ${status_val}
created: 2025-01-01 12:00:00
updated: 2025-01-01 12:01:00
qa_round: 0
qa_last_result: pending
uat_round: 0
uat_last_result: pending
---

# Debug Session: ${slug}

## Issue

Test issue.

## Investigation

## Plan

## Implementation

### Changed Files

### Commit

## QA

## UAT
EOF

  # Only set active pointer for non-complete sessions (set-status complete clears it)
  if [ "$status_val" != "complete" ]; then
    echo "${session_id}.md" > "$TEST_TEMP_DIR/.vbw-planning/debugging/.active-session"
  fi
}

@test "suggest-next debug with investigating session suggests resume" {
  create_debug_session "investigating"
  run bash "$SCRIPTS_DIR/suggest-next.sh" debug pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"--resume"* ]]
  [[ "$output" == *"Continue investigation"* ]]
}

@test "suggest-next debug with qa_pending session suggests qa" {
  create_debug_session "qa_pending"
  run bash "$SCRIPTS_DIR/suggest-next.sh" debug pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:qa"* ]]
}

@test "suggest-next debug with qa_failed session suggests resume" {
  create_debug_session "qa_failed"
  run bash "$SCRIPTS_DIR/suggest-next.sh" debug pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"--resume"* ]]
  [[ "$output" == *"QA failures"* ]]
}

@test "suggest-next debug with uat_pending session suggests verify" {
  create_debug_session "uat_pending"
  run bash "$SCRIPTS_DIR/suggest-next.sh" debug pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:verify"* ]]
}

@test "suggest-next debug with uat_failed session suggests resume" {
  create_debug_session "uat_failed"
  run bash "$SCRIPTS_DIR/suggest-next.sh" debug pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"--resume"* ]]
  [[ "$output" == *"UAT issues"* ]]
}

@test "suggest-next debug with complete session suggests fix" {
  # Complete sessions live in completed/ with no active pointer —
  # suggest-next sees no active session and suggests starting new work
  create_debug_session "complete"
  run bash "$SCRIPTS_DIR/suggest-next.sh" debug pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:fix"* ]]
}

@test "suggest-next debug with no session suggests fix" {
  run bash "$SCRIPTS_DIR/suggest-next.sh" debug pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:fix"* ]]
}

# --- qa context with active debug sessions ---

@test "suggest-next qa pass with uat_pending debug session suggests verify" {
  create_debug_session "uat_pending"
  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:verify"* ]]
}

@test "suggest-next qa pass with qa_pending debug session suggests verify" {
  create_debug_session "qa_pending"
  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:verify"* ]]
}

@test "suggest-next qa fail with active debug session suggests resume" {
  create_debug_session "qa_pending"
  run bash "$SCRIPTS_DIR/suggest-next.sh" qa fail
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:debug --resume"* ]]
}

@test "suggest-next qa pass with debug session and phases exist defers to phase logic" {
  create_debug_session "uat_pending"
  # Create a phase directory so phase_count > 0
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  echo '# Plan' > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-PLAN.md"
  echo '# Summary' > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-SUMMARY.md"
  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass
  [ "$status" -eq 0 ]
  # When phases exist, debug-session handler is skipped to avoid hijacking phase QA suggestions.
  # qa.md itself handles inline next-step text for debug-session QA.
  # The suggestion should NOT contain debug-session-specific routing.
  [[ "$output" != *"Run UAT on the debug fix"* ]]
}

@test "suggest-next qa pass with complete debug session ignores session" {
  create_debug_session "complete"
  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass
  [ "$status" -eq 0 ]
  # complete session should not trigger debug-session suggestions
  [[ "$output" != *"Run UAT on the debug fix"* ]]
  [[ "$output" != *"--resume"* ]]
}

# --- fix context with active debug sessions ---

@test "suggest-next fix with qa_pending debug session suggests resume" {
  create_debug_session "qa_pending"
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"--resume"* ]]
  [[ "$output" == *"remaining issues"* ]]
}

@test "suggest-next fix with qa_failed debug session suggests resume" {
  create_debug_session "qa_failed"
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"--resume"* ]]
  [[ "$output" == *"QA failures"* ]]
}

@test "suggest-next fix with fix_applied debug session suggests resume" {
  create_debug_session "fix_applied"
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"--resume"* ]]
}

@test "suggest-next fix with uat_pending debug session suggests verify" {
  create_debug_session "uat_pending"
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:verify"* ]]
  [[ "$output" == *"UAT"* ]]
}

@test "suggest-next fix with uat_failed debug session suggests resume" {
  create_debug_session "uat_failed"
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"--resume"* ]]
  [[ "$output" == *"UAT issues"* ]]
}

@test "suggest-next fix with investigating debug session suggests resume" {
  create_debug_session "investigating"
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"--resume"* ]]
  [[ "$output" == *"Continue investigation"* ]]
}

@test "suggest-next fix with no debug session suggests qa" {
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:qa"* ]]
}

@test "suggest-next fix with complete debug session suggests qa" {
  create_debug_session "complete"
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:qa"* ]]
  [[ "$output" != *"--resume"* ]]
}

@test "suggest-next fix with debug session and phases exist defers to default" {
  create_debug_session "qa_pending"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  echo '# Plan' > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-PLAN.md"
  echo '# Summary' > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-SUMMARY.md"
  run bash "$SCRIPTS_DIR/suggest-next.sh" fix pass
  [ "$status" -eq 0 ]
  # When phases exist, debug-session handler is skipped
  [[ "$output" != *"--resume"* ]]
  [[ "$output" == *"/vbw:qa"* ]]
}
