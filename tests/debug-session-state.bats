#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  mkdir -p "$VBW_PLANNING_DIR"
}

teardown() {
  teardown_temp_dir
}

# ── start ────────────────────────────────────────────────

@test "start creates session file and active pointer" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "test-bug"
  [ "$status" -eq 0 ]

  # Should output session_id and session_file
  [[ "$output" == *"session_id="* ]]
  [[ "$output" == *"session_file="* ]]

  # Active pointer should exist
  [ -f "$VBW_PLANNING_DIR/debugging/.active-session" ]

  # Session file should exist
  eval "$output"
  [ -f "$session_file" ]

  # Session file should have correct frontmatter
  grep -q '^status: investigating$' "$session_file"
  grep -q '^qa_round: 0$' "$session_file"
  grep -q '^uat_round: 0$' "$session_file"
}

@test "start sanitizes slug" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "My Bug Has Spaces & Symbols!"
  [ "$status" -eq 0 ]
  eval "$output"
  # Slug should be sanitized — no uppercase, spaces, or special chars
  [[ "$session_id" == *"-my-bug-has-spaces-symbols"* ]]
}

@test "start fails without slug" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR"
  [ "$status" -eq 1 ]
}

# ── get ──────────────────────────────────────────────────

@test "get returns none when no active session" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" get "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=none"* ]]
}

@test "get returns session metadata when active" {
  # Create a session first
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "get-test")"

  run bash "$SCRIPTS_DIR/debug-session-state.sh" get "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=true"* ]]
  [[ "$output" == *"status=investigating"* ]]
  [[ "$output" == *"qa_round=0"* ]]
}

# ── get-or-latest ────────────────────────────────────────

@test "get-or-latest returns none when no sessions exist" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=none"* ]]
}

@test "get-or-latest falls back to latest unresolved" {
  # Create a session and then remove the active pointer
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "fallback-test")"
  rm -f "$VBW_PLANNING_DIR/debugging/.active-session"

  run bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=fallback"* ]]
  [[ "$output" == *"status=investigating"* ]]
}

@test "get-or-latest skips completed sessions in fallback" {
  # Create two sessions, complete the first
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "old-bug")"
  local old_file="$session_file"
  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" complete > /dev/null

  # Wait 1 second to ensure different timestamp
  sleep 1

  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "new-bug")"
  local new_file="$session_file"
  rm -f "$VBW_PLANNING_DIR/debugging/.active-session"

  run bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=fallback"* ]]
  [[ "$output" == *"new-bug"* ]]
}

# ── resume ───────────────────────────────────────────────

@test "resume sets active pointer to specified session" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "resume-test")"
  local sid="$session_id"
  bash "$SCRIPTS_DIR/debug-session-state.sh" clear-active "$VBW_PLANNING_DIR" > /dev/null

  run bash "$SCRIPTS_DIR/debug-session-state.sh" resume "$VBW_PLANNING_DIR" "$sid"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=true"* ]]
  [ -f "$VBW_PLANNING_DIR/debugging/.active-session" ]
}

@test "resume fails for nonexistent session" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" resume "$VBW_PLANNING_DIR" "nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

# ── set-status ───────────────────────────────────────────

@test "set-status transitions through valid states" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "status-test")"

  for s in fix_applied qa_pending qa_failed uat_pending uat_failed complete; do
    run bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" "$s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"status=$s"* ]]
  done
}

@test "set-status rejects invalid status" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "invalid-test")"
  run bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" "bogus"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid status"* ]]
}

@test "set-status fails without active session" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" qa_pending
  [ "$status" -eq 1 ]
  [[ "$output" == *"no active"* ]]
}

@test "set-status updates the updated timestamp" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "ts-test")"
  local before_ts
  before_ts=$(grep '^updated:' "$session_file" | head -1)

  sleep 1
  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" fix_applied > /dev/null

  local after_ts
  after_ts=$(grep '^updated:' "$session_file" | head -1)
  [ "$before_ts" != "$after_ts" ]
}

# ── increment-qa / increment-uat ────────────────────────

@test "increment-qa bumps round counter" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "qa-inc")"

  run bash "$SCRIPTS_DIR/debug-session-state.sh" increment-qa "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_round=1"* ]]

  run bash "$SCRIPTS_DIR/debug-session-state.sh" increment-qa "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_round=2"* ]]
}

@test "increment-uat bumps round counter" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "uat-inc")"

  run bash "$SCRIPTS_DIR/debug-session-state.sh" increment-uat "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_round=1"* ]]

  run bash "$SCRIPTS_DIR/debug-session-state.sh" increment-uat "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_round=2"* ]]
}

@test "increment-qa resets qa_last_result to pending" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "reset-test")"

  bash "$SCRIPTS_DIR/debug-session-state.sh" increment-qa "$VBW_PLANNING_DIR" > /dev/null
  grep -q '^qa_last_result: pending$' "$session_file"
}

@test "increment-qa fails without active session" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" increment-qa "$VBW_PLANNING_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no active"* ]]
}

# ── clear-active ─────────────────────────────────────────

@test "clear-active removes the pointer" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "clear-test")"
  [ -f "$VBW_PLANNING_DIR/debugging/.active-session" ]

  run bash "$SCRIPTS_DIR/debug-session-state.sh" clear-active "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/.active-session" ]
}

# ── list ─────────────────────────────────────────────────

@test "list shows no sessions when directory is empty" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" list "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no_sessions=true"* ]]
}

@test "list shows sessions with status" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "list-test")"

  run bash "$SCRIPTS_DIR/debug-session-state.sh" list "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"session="* ]]
  [[ "$output" == *"investigating"* ]]
  [[ "$output" == *"session_count=1"* ]]
}

# ── unknown command ──────────────────────────────────────

@test "unknown command fails with error" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" bogus "$VBW_PLANNING_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]]
}
