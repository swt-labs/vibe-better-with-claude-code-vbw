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

  # Session file should exist in active/ subdirectory
  eval "$output"
  [ -f "$session_file" ]
  [[ "$session_file" == *"/debugging/active/"* ]]

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

@test "start-with-source-todo writes Source Todo and keeps session active on success" {
  run bash -lc 'printf %s "$1" | bash "$2" start-with-source-todo "$3" "source-todo-success"' -- \
    '{"mode":"source-todo","text":"Investigate parser crash","raw_line":"- Investigate parser crash (ref:abcd1234)","ref":"abcd1234","detail_status":"ok","related_files":["src/parser.sh"],"detail_context":"Persisted detail"}' \
    "$SCRIPTS_DIR/debug-session-state.sh" \
    "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  eval "$output"
  [ -f "$session_file" ]
  [ -f "$VBW_PLANNING_DIR/debugging/.active-session" ]
  grep -q '^## Source Todo$' "$session_file"
  grep -q 'Investigate parser crash' "$session_file"
  grep -q 'Persisted detail' "$session_file"
}

@test "start-with-source-todo rolls back the new session on writer failure" {
  run bash -lc 'printf %s "$1" | bash "$2" start-with-source-todo "$3" "source-todo-failure"' -- \
    'not-json' \
    "$SCRIPTS_DIR/debug-session-state.sh" \
    "$VBW_PLANNING_DIR"
  [ "$status" -eq 1 ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/.active-session" ]
  run find "$VBW_PLANNING_DIR/debugging/active" -maxdepth 1 -type f -name '*.md'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "start-with-source-todo restores the prior active pointer on writer failure" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "first-bug")"
  local first_session_name
  first_session_name=$(basename "$session_file")

  run bash -lc 'printf %s "$1" | bash "$2" start-with-source-todo "$3" "source-todo-failure"' -- \
    'not-json' \
    "$SCRIPTS_DIR/debug-session-state.sh" \
    "$VBW_PLANNING_DIR"
  [ "$status" -eq 1 ]
  [ -f "$VBW_PLANNING_DIR/debugging/.active-session" ]
  [ "$(cat "$VBW_PLANNING_DIR/debugging/.active-session")" = "$first_session_name" ]
  [ -f "$VBW_PLANNING_DIR/debugging/active/$first_session_name" ]
}

@test "start-with-selected-todo builds Source Todo from selected todo without detail" {
  run bash -lc 'printf %s "$1" | bash "$2" start-with-selected-todo "$3" "selected-todo-no-detail" none' -- \
    '{"command_text":"Investigate parser crash","normalized_text":"Investigate parser crash","line":"- [HIGH] Investigate parser crash (added 2026-04-01) (ref:abcd1234)","ref":"abcd1234"}' \
    "$SCRIPTS_DIR/debug-session-state.sh" \
    "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  eval "$output"
  [ -f "$session_file" ]
  grep -q '\*\*Text:\*\* Investigate parser crash' "$session_file"
  grep -q '\*\*Raw Line:\*\* - \[HIGH\] Investigate parser crash' "$session_file"
  grep -q '\*\*Ref:\*\* abcd1234' "$session_file"
  grep -q '\*\*Detail Status:\*\* none' "$session_file"
  grep -q 'None recorded\.' "$session_file"
  grep -q 'No persisted detail context\.' "$session_file"
}

@test "start-with-selected-todo builds Source Todo from selected todo and detail helper output" {
  run env TODO_DETAIL_RESULT_JSON='{"status":"ok","detail":{"context":"Persisted detail context","files":["src/parser.sh","tests/parser.bats"]}}' \
    bash -lc 'printf %s "$1" | bash "$2" start-with-selected-todo "$3" "selected-todo-with-detail" ok' -- \
    '{"command_text":"Investigate parser crash","line":"- Investigate parser crash (ref:abcd1234)","ref":"abcd1234"}' \
    "$SCRIPTS_DIR/debug-session-state.sh" \
    "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  eval "$output"
  [ -f "$session_file" ]
  grep -q '\*\*Text:\*\* Investigate parser crash' "$session_file"
  grep -q '\*\*Detail Status:\*\* ok' "$session_file"
  grep -q 'src/parser.sh' "$session_file"
  grep -q 'tests/parser.bats' "$session_file"
  grep -q 'Persisted detail context' "$session_file"
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
  printf '%s\n' "$output" | grep -Eq '^session_status=investigating$'
  ! printf '%s\n' "$output" | grep -Eq '^status='
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
  printf '%s\n' "$output" | grep -Eq '^session_status=investigating$'
  ! printf '%s\n' "$output" | grep -Eq '^status='
}

@test "get-or-latest metadata eval succeeds when status shell variable is readonly" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "readonly-fallback")"
  rm -f "$VBW_PLANNING_DIR/debugging/.active-session"

  run bash -lc '
    readonly status=0
    helper_output=$(bash "$1" get-or-latest "$2")
    printf "%s\n" "$helper_output" | grep -Eq "^session_status=investigating$"
    ! printf "%s\n" "$helper_output" | grep -Eq "^status="
    eval "$helper_output"
    printf "active_session=%s\nsession_status=%s\nsession_file=%s\n" "${active_session:-}" "${session_status:-}" "${session_file:-}"
  ' -- "$SCRIPTS_DIR/debug-session-state.sh" "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=fallback"* ]]
  [[ "$output" == *"session_status=investigating"* ]]
  [[ "$output" == *"session_file=$VBW_PLANNING_DIR/debugging/active/"* ]]
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
  printf '%s\n' "$output" | grep -Eq '^session_status=investigating$'
  ! printf '%s\n' "$output" | grep -Eq '^status='
  [ -f "$VBW_PLANNING_DIR/debugging/.active-session" ]
}

@test "resume metadata eval succeeds when status shell variable is readonly" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "readonly-resume")"
  local sid="$session_id"
  bash "$SCRIPTS_DIR/debug-session-state.sh" clear-active "$VBW_PLANNING_DIR" > /dev/null

  run bash -lc '
    readonly status=0
    helper_output=$(bash "$1" resume "$2" "$3")
    printf "%s\n" "$helper_output" | grep -Eq "^session_status=investigating$"
    ! printf "%s\n" "$helper_output" | grep -Eq "^status="
    eval "$helper_output"
    printf "active_session=%s\nsession_status=%s\nsession_id=%s\n" "${active_session:-}" "${session_status:-}" "${session_id:-}"
  ' -- "$SCRIPTS_DIR/debug-session-state.sh" "$VBW_PLANNING_DIR" "$sid"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=true"* ]]
  [[ "$output" == *"session_status=investigating"* ]]
  [[ "$output" == *"session_id=$sid"* ]]
}

@test "resume fails for nonexistent session" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" resume "$VBW_PLANNING_DIR" "20990101-000000-no-such-session.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "resume rejects malformed session names" {
  # Path traversal
  run bash "$SCRIPTS_DIR/debug-session-state.sh" resume "$VBW_PLANNING_DIR" "../etc/passwd"
  [ "$status" -eq 1 ]

  # No timestamp prefix
  run bash "$SCRIPTS_DIR/debug-session-state.sh" resume "$VBW_PLANNING_DIR" "nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"YYYYMMDD-HHMMSS-slug"* ]]

  # Wrong extension
  run bash "$SCRIPTS_DIR/debug-session-state.sh" resume "$VBW_PLANNING_DIR" "20990101-000000-foo.txt"
  [ "$status" -eq 1 ]
}

# ── set-status ───────────────────────────────────────────

@test "set-status transitions through valid states" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "status-test")"

  # Test non-complete statuses in loop (complete moves file and clears pointer)
  for s in fix_applied qa_pending qa_failed uat_pending uat_failed; do
    run bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" "$s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"status=$s"* ]]
  done

  # Test complete separately — it moves to completed/ and clears pointer
  run bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" complete
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=complete"* ]]
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

@test "list shows sessions with status and location" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "list-test")"

  run bash "$SCRIPTS_DIR/debug-session-state.sh" list "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"session="* ]]
  [[ "$output" == *"investigating"* ]]
  [[ "$output" == *"|active"* ]]
  [[ "$output" == *"session_count=1"* ]]
}

# ── active/completed directory layout ────────────────────

@test "set-status complete moves session to completed directory" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "complete-move")"
  local fname
  fname=$(basename "$session_file")

  # Session starts in active/
  [ -f "$VBW_PLANNING_DIR/debugging/active/$fname" ]

  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" complete > /dev/null

  # Session moved to completed/
  [ ! -f "$VBW_PLANNING_DIR/debugging/active/$fname" ]
  [ -f "$VBW_PLANNING_DIR/debugging/completed/$fname" ]
  grep -q '^status: complete$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
  grep -q '^qa_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
  grep -q '^uat_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
}

@test "set-status complete preserves existing verified results" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "complete-preserve")"
  local fname
  fname=$(basename "$session_file")

  echo '{"mode":"qa","round":1,"result":"PASS","checks":[{"id":"c1","description":"QA check","status":"PASS","evidence":"ok"}]}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$session_file" > /dev/null
  echo '{"mode":"uat","round":1,"result":"pass","checkpoints":[{"description":"UAT check","result":"pass","user_response":"verified"}]}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$session_file" > /dev/null

  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" complete > /dev/null

  [ -f "$VBW_PLANNING_DIR/debugging/completed/$fname" ]
  grep -q '^qa_round: 1$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
  grep -q '^qa_last_result: pass$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
  grep -q '^uat_round: 1$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
  grep -q '^uat_last_result: pass$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
}

@test "set-status complete clears active pointer" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "pointer-clear")"
  [ -f "$VBW_PLANNING_DIR/debugging/.active-session" ]

  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" complete > /dev/null

  [ ! -f "$VBW_PLANNING_DIR/debugging/.active-session" ]
}

@test "legacy flat-path session migrated on get-or-latest" {
  # Manually create a session in the legacy flat location
  mkdir -p "$VBW_PLANNING_DIR/debugging"
  local session_id="20250101-120000-legacy-bug"
  local legacy_file="$VBW_PLANNING_DIR/debugging/${session_id}.md"
  printf '%s\n' '---' "session_id: ${session_id}" 'title: legacy-bug' 'status: investigating' 'created: 2025-01-01 12:00:00' 'updated: 2025-01-01 12:00:00' 'qa_round: 0' 'qa_last_result: pending' 'uat_round: 0' 'uat_last_result: pending' '---' '' '# Debug Session: legacy-bug' > "$legacy_file"
  echo "${session_id}.md" > "$VBW_PLANNING_DIR/debugging/.active-session"

  run bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=true"* ]]

  # Legacy file should be migrated to active/
  [ ! -f "$legacy_file" ]
  [ -f "$VBW_PLANNING_DIR/debugging/active/${session_id}.md" ]
}

@test "get-or-latest discovers unmigrated legacy session on migration collision" {
  mkdir -p "$VBW_PLANNING_DIR/debugging/active"
  local session_id="20250101-120000-collision-bug"
  local legacy_file="$VBW_PLANNING_DIR/debugging/${session_id}.md"
  # Create a legacy flat-path session (investigating = unresolved)
  printf '%s\n' '---' "session_id: ${session_id}" 'title: collision-bug' 'status: investigating' 'created: 2025-01-01 12:00:00' 'updated: 2025-01-01 12:00:00' 'qa_round: 0' 'qa_last_result: pending' 'uat_round: 0' 'uat_last_result: pending' '---' '' '# Debug Session: collision-bug' > "$legacy_file"
  # Pre-create a collision file in active/ to make migration fail
  printf '%s\n' '---' "session_id: ${session_id}" 'title: collision-existing' 'status: complete' '---' > "$VBW_PLANNING_DIR/debugging/active/${session_id}.md"

  run bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  # The session should still be discoverable
  [[ "$output" == *"session_id=${session_id}"* ]]
  # Collision resolution: complete file moved to completed/, legacy migrated to active/
  [ -f "$VBW_PLANNING_DIR/debugging/active/${session_id}.md" ]
  [ -f "$VBW_PLANNING_DIR/debugging/completed/${session_id}.md" ]
  # Legacy file should no longer exist (successfully migrated after collision resolution)
  [ ! -f "$legacy_file" ]
}

@test "get-or-latest discovers legacy session via fallback when collision is non-complete" {
  mkdir -p "$VBW_PLANNING_DIR/debugging/active"
  local session_id="20250101-130000-noncomp-collision"
  local legacy_file="$VBW_PLANNING_DIR/debugging/${session_id}.md"
  # Create a legacy flat-path session (investigating = unresolved)
  printf '%s\n' '---' "session_id: ${session_id}" 'title: noncomp-collision' 'status: investigating' 'created: 2025-01-01 13:00:00' 'updated: 2025-01-01 13:00:00' 'qa_round: 0' 'qa_last_result: pending' 'uat_round: 0' 'uat_last_result: pending' '---' '' '# Debug Session: noncomp-collision' > "$legacy_file"
  # Place a symlink in active/ with the colliding name.  The symlink blocks
  # migration (destination exists) AND is skipped by the active/ candidate scan
  # (which filters symlinks with [ ! -L ]).  This proves the ONLY way the
  # session can be discovered is via the fallback $DEBUG_DIR/*.md scan.
  ln -s /dev/null "$VBW_PLANNING_DIR/debugging/active/${session_id}.md"

  # Capture stderr for warning assertion
  local stderr_file="$VBW_PLANNING_DIR/stderr.tmp"
  run bash -c "bash '$SCRIPTS_DIR/debug-session-state.sh' get-or-latest '$VBW_PLANNING_DIR' 2>'$stderr_file'"
  [ "$status" -eq 0 ]
  # Session is discoverable via fallback scan of DEBUG_DIR/*.md
  [[ "$output" == *"session_id=${session_id}"* ]]
  # Legacy file remains (migration permanently failed due to symlink collision)
  [ -f "$legacy_file" ]
  # Warning was emitted to stderr
  [[ "$(cat "$stderr_file")" == *"Warning: could not migrate legacy session"* ]]
}

@test "legacy complete session migrated to completed on list" {
  # Manually create a complete session in the legacy flat location
  mkdir -p "$VBW_PLANNING_DIR/debugging"
  local session_id="20250101-120000-legacy-done"
  local legacy_file="$VBW_PLANNING_DIR/debugging/${session_id}.md"
  printf '%s\n' '---' "session_id: ${session_id}" 'title: legacy-done' 'status: complete' 'created: 2025-01-01 12:00:00' 'updated: 2025-01-01 12:00:00' 'qa_round: 1' 'qa_last_result: pass' 'uat_round: 1' 'uat_last_result: pass' '---' '' '# Debug Session: legacy-done' > "$legacy_file"

  run bash "$SCRIPTS_DIR/debug-session-state.sh" list "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"|completed"* ]]

  # Legacy file should be migrated to completed/
  [ ! -f "$legacy_file" ]
  [ -f "$VBW_PLANNING_DIR/debugging/completed/${session_id}.md" ]
  grep -q '^qa_last_result: pass$' "$VBW_PLANNING_DIR/debugging/completed/${session_id}.md"
  grep -q '^uat_last_result: pass$' "$VBW_PLANNING_DIR/debugging/completed/${session_id}.md"
}

@test "list emits warning to stderr when legacy migration fails" {
  mkdir -p "$VBW_PLANNING_DIR/debugging/active"
  local session_id="20250101-140000-list-warn"
  local legacy_file="$VBW_PLANNING_DIR/debugging/${session_id}.md"
  # Create a legacy flat-path session
  printf '%s\n' '---' "session_id: ${session_id}" 'title: list-warn' 'status: investigating' 'created: 2025-01-01 14:00:00' 'updated: 2025-01-01 14:00:00' 'qa_round: 0' 'qa_last_result: pending' 'uat_round: 0' 'uat_last_result: pending' '---' '' '# Debug Session: list-warn' > "$legacy_file"
  # Collision file in active/ with non-complete status — cannot be resolved
  printf '%s\n' '---' "session_id: ${session_id}" 'title: active-blocker' 'status: investigating' '---' > "$VBW_PLANNING_DIR/debugging/active/${session_id}.md"

  # Capture stderr for warning assertion
  local stderr_file="$VBW_PLANNING_DIR/stderr-list.tmp"
  run bash -c "bash '$SCRIPTS_DIR/debug-session-state.sh' list '$VBW_PLANNING_DIR' 2>'$stderr_file'"
  [ "$status" -eq 0 ]
  [[ "$(cat "$stderr_file")" == *"Warning: could not migrate legacy session"* ]]
}

@test "list shows sessions from both active and completed" {
  # Create an active session
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "active-bug")"
  local active_file="$session_file"

  # Create another session and complete it
  sleep 1
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "done-bug")"
  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" complete > /dev/null

  # Resume the first session to make it active again
  local active_name
  active_name=$(basename "$active_file")
  bash "$SCRIPTS_DIR/debug-session-state.sh" resume "$VBW_PLANNING_DIR" "$active_name" > /dev/null

  run bash "$SCRIPTS_DIR/debug-session-state.sh" list "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"|active"* ]]
  [[ "$output" == *"|completed"* ]]
  [[ "$output" == *"session_count=2"* ]]
}

@test "resume returns completed session metadata without reactivating it" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "resume-done")"
  local fname
  fname=$(basename "$session_file")

  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" complete > /dev/null
  [ -f "$VBW_PLANNING_DIR/debugging/completed/$fname" ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/.active-session" ]

  run bash "$SCRIPTS_DIR/debug-session-state.sh" resume "$VBW_PLANNING_DIR" "$fname"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=true"* ]]
  printf '%s\n' "$output" | grep -Eq '^session_status=complete$'
  ! printf '%s\n' "$output" | grep -Eq '^status='
  [ ! -f "$VBW_PLANNING_DIR/debugging/active/$fname" ]
  [ -f "$VBW_PLANNING_DIR/debugging/completed/$fname" ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/.active-session" ]

  run bash "$SCRIPTS_DIR/debug-session-state.sh" get "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=none"* ]]
}

@test "resume migrates legacy completed session without reactivating it" {
  mkdir -p "$VBW_PLANNING_DIR/debugging"
  local session_name="20240101-120000-legacy-resume-done.md"
  cat > "$VBW_PLANNING_DIR/debugging/$session_name" << 'EOF'
---
session_id: 20240101-120000-legacy-resume-done
title: legacy-resume-done
status: complete
created: 2024-01-01 12:00:00
updated: 2024-01-01 12:00:00
qa_round: 1
qa_last_result: pass
uat_round: 1
uat_last_result: pass
---
# Legacy completed session
EOF

  run bash "$SCRIPTS_DIR/debug-session-state.sh" resume "$VBW_PLANNING_DIR" "$session_name"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=true"* ]]
  printf '%s\n' "$output" | grep -Eq '^session_status=complete$'
  [ ! -f "$VBW_PLANNING_DIR/debugging/$session_name" ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/active/$session_name" ]
  [ -f "$VBW_PLANNING_DIR/debugging/completed/$session_name" ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/.active-session" ]
}

@test "resume canonicalizes completed session stranded in active without reactivating it" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "resume-stranded-done")"
  local fname
  fname=$(basename "$session_file")

  awk 'BEGIN{in_fm=0} /^---$/{in_fm=!in_fm} in_fm && /^status:/{print "status: complete";next} {print}' \
    "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

  [ -f "$VBW_PLANNING_DIR/debugging/active/$fname" ]
  [ -f "$VBW_PLANNING_DIR/debugging/.active-session" ]

  run bash "$SCRIPTS_DIR/debug-session-state.sh" resume "$VBW_PLANNING_DIR" "$fname"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=true"* ]]
  printf '%s\n' "$output" | grep -Eq '^session_status=complete$'
  [ ! -f "$VBW_PLANNING_DIR/debugging/active/$fname" ]
  [ -f "$VBW_PLANNING_DIR/debugging/completed/$fname" ]
  grep -q '^qa_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
  grep -q '^uat_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
  [ ! -f "$VBW_PLANNING_DIR/debugging/.active-session" ]
}

@test "get-or-latest recovers pointer to unresolved session stranded in completed directory" {
  local session_name="20240101-120000-stranded-qa.md"
  mkdir -p "$VBW_PLANNING_DIR/debugging/completed"
  cat > "$VBW_PLANNING_DIR/debugging/completed/$session_name" << 'EOF'
---
session_id: 20240101-120000-stranded-qa
title: stranded-qa
status: qa_failed
created: 2024-01-01 12:00:00
updated: 2024-01-01 12:10:00
qa_round: 1
qa_last_result: fail
uat_round: 0
uat_last_result: pending
---
# Stranded session
EOF
  echo "$session_name" > "$VBW_PLANNING_DIR/debugging/.active-session"

  run bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=true"* ]]
  printf '%s\n' "$output" | grep -Eq '^session_status=qa_failed$'
  [ -f "$VBW_PLANNING_DIR/debugging/active/$session_name" ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/completed/$session_name" ]
  [ "$(cat "$VBW_PLANNING_DIR/debugging/.active-session")" = "$session_name" ]
}

@test "get-or-latest fallback recovers unresolved session stranded in completed directory" {
  local session_name="20240101-120000-stranded-uat.md"
  mkdir -p "$VBW_PLANNING_DIR/debugging/completed"
  cat > "$VBW_PLANNING_DIR/debugging/completed/$session_name" << 'EOF'
---
session_id: 20240101-120000-stranded-uat
title: stranded-uat
status: uat_pending
created: 2024-01-01 12:00:00
updated: 2024-01-01 12:10:00
qa_round: 1
qa_last_result: pass
uat_round: 0
uat_last_result: pending
---
# Stranded session
EOF

  run bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=fallback"* ]]
  printf '%s\n' "$output" | grep -Eq '^session_status=uat_pending$'
  [ -f "$VBW_PLANNING_DIR/debugging/active/$session_name" ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/completed/$session_name" ]
  [ "$(cat "$VBW_PLANNING_DIR/debugging/.active-session")" = "$session_name" ]
}

@test "resume preserves unresolved status for session stranded in completed directory" {
  local session_name="20240101-120000-stranded-resume.md"
  mkdir -p "$VBW_PLANNING_DIR/debugging/completed"
  cat > "$VBW_PLANNING_DIR/debugging/completed/$session_name" << 'EOF'
---
session_id: 20240101-120000-stranded-resume
title: stranded-resume
status: qa_failed
created: 2024-01-01 12:00:00
updated: 2024-01-01 12:10:00
qa_round: 2
qa_last_result: fail
uat_round: 0
uat_last_result: pending
---
# Stranded session
EOF

  run bash "$SCRIPTS_DIR/debug-session-state.sh" resume "$VBW_PLANNING_DIR" "$session_name"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=true"* ]]
  printf '%s\n' "$output" | grep -Eq '^session_status=qa_failed$'
  [ -f "$VBW_PLANNING_DIR/debugging/active/$session_name" ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/completed/$session_name" ]
}

@test "list self-heals unresolved sessions stranded in completed directory" {
  local session_name="20240101-120000-list-stranded.md"
  mkdir -p "$VBW_PLANNING_DIR/debugging/completed"
  cat > "$VBW_PLANNING_DIR/debugging/completed/$session_name" << 'EOF'
---
session_id: 20240101-120000-list-stranded
title: list-stranded
status: investigating
created: 2024-01-01 12:00:00
updated: 2024-01-01 12:10:00
qa_round: 0
qa_last_result: pending
uat_round: 0
uat_last_result: pending
---
# Stranded session
EOF

  run bash "$SCRIPTS_DIR/debug-session-state.sh" list "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"session=20240101-120000-list-stranded|investigating|list-stranded|active"* ]]
  [ -f "$VBW_PLANNING_DIR/debugging/active/$session_name" ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/completed/$session_name" ]
}

@test "list self-heals complete sessions stranded in active directory" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "stranded-done")"
  local fname
  fname=$(basename "$session_file")

  # Simulate write-debug-session.sh setting complete without set-status (frontmatter only)
  awk 'BEGIN{in_fm=0} /^---$/{in_fm=!in_fm} in_fm && /^status:/{print "status: complete";next} {print}' \
    "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

  # File should still be in active/ (no set-status was called)
  [ -f "$VBW_PLANNING_DIR/debugging/active/$fname" ]

  # list should self-heal: detect complete in active/ and move to completed/
  run bash "$SCRIPTS_DIR/debug-session-state.sh" list "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"|completed"* ]]

  # File should be physically moved
  [ ! -f "$VBW_PLANNING_DIR/debugging/active/$fname" ]
  [ -f "$VBW_PLANNING_DIR/debugging/completed/$fname" ]
  grep -q '^qa_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
  grep -q '^uat_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
}

@test "get returns none after self-heal of completed session in active" {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "selfheal-get")"
  local fname
  fname=$(basename "$session_file")

  # Simulate write-debug-session.sh setting complete without set-status
  awk 'BEGIN{in_fm=0} /^---$/{in_fm=!in_fm} in_fm && /^status:/{print "status: complete";next} {print}' \
    "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

  # get should self-heal and return none (completed session is not active)
  run bash "$SCRIPTS_DIR/debug-session-state.sh" get "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=none"* ]]
  # File moved to completed/, pointer cleared
  [ -f "$VBW_PLANNING_DIR/debugging/completed/$fname" ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/active/$fname" ]
  grep -q '^qa_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
  grep -q '^uat_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$fname"
  [ ! -f "$VBW_PLANNING_DIR/debugging/.active-session" ]
}

@test "get-or-latest falls back after self-heal of completed session" {
  # Create session A (will be completed)
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "fallback-a")"
  local fname_a session_file_a
  fname_a=$(basename "$session_file")
  session_file_a="$session_file"

  # Create session B (remains active)
  sleep 1  # ensure different timestamp
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "fallback-b")"
  local fname_b
  fname_b=$(basename "$session_file")

  # Set pointer back to A, then make A complete
  echo "$fname_a" > "$VBW_PLANNING_DIR/debugging/.active-session"
  awk 'BEGIN{in_fm=0} /^---$/{in_fm=!in_fm} in_fm && /^status:/{print "status: complete";next} {print}' \
    "$session_file_a" > "${session_file_a}.tmp" && mv "${session_file_a}.tmp" "$session_file_a"

  # get-or-latest should self-heal A, then fall back to B
  run bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=fallback"* ]]
  [[ "$output" == *"fallback-b"* ]]
  grep -q '^qa_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$fname_a"
  grep -q '^uat_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$fname_a"
}

@test "get returns none after legacy migration of completed session" {
  # Create a legacy flat-path session with complete status
  local session_name="20240101-120000-legacy-done.md"
  mkdir -p "$VBW_PLANNING_DIR/debugging"
  cat > "$VBW_PLANNING_DIR/debugging/$session_name" << 'EOF'
---
session_id: 20240101-120000-legacy-done
title: legacy-done
status: complete
created: 2024-01-01 12:00:00
updated: 2024-01-01 12:00:00
qa_round: 0
qa_last_result: pending
uat_round: 0
uat_last_result: pending
---
# Legacy session
EOF
  echo "$session_name" > "$VBW_PLANNING_DIR/debugging/.active-session"

  # get should migrate to completed/ and return none
  run bash "$SCRIPTS_DIR/debug-session-state.sh" get "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=none"* ]]
  [ -f "$VBW_PLANNING_DIR/debugging/completed/$session_name" ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/$session_name" ]
  grep -q '^qa_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$session_name"
  grep -q '^uat_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$session_name"
}

@test "get-or-latest normalizes canonical completed session with pending no-verification results" {
  local session_name="20240101-120000-canonical-done.md"
  mkdir -p "$VBW_PLANNING_DIR/debugging/completed"
  cat > "$VBW_PLANNING_DIR/debugging/completed/$session_name" << 'EOF'
---
session_id: 20240101-120000-canonical-done
title: canonical-done
status: complete
created: 2024-01-01 12:00:00
updated: 2024-01-01 12:00:00
qa_round: 0
qa_last_result: pending
uat_round: 0
uat_last_result: pending
---
# Canonical completed session
EOF

  run bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=none"* ]]
  grep -q '^qa_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$session_name"
  grep -q '^uat_last_result: skipped_no_fix_required$' "$VBW_PLANNING_DIR/debugging/completed/$session_name"
}

@test "get-or-latest preserves verified results for canonical completed session" {
  local session_name="20240101-120000-canonical-verified.md"
  mkdir -p "$VBW_PLANNING_DIR/debugging/completed"
  cat > "$VBW_PLANNING_DIR/debugging/completed/$session_name" << 'EOF'
---
session_id: 20240101-120000-canonical-verified
title: canonical-verified
status: complete
created: 2024-01-01 12:00:00
updated: 2024-01-01 12:00:00
qa_round: 1
qa_last_result: pass
uat_round: 1
uat_last_result: pass
---
# Canonical completed verified session
EOF

  run bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=none"* ]]
  grep -q '^qa_round: 1$' "$VBW_PLANNING_DIR/debugging/completed/$session_name"
  grep -q '^qa_last_result: pass$' "$VBW_PLANNING_DIR/debugging/completed/$session_name"
  grep -q '^uat_round: 1$' "$VBW_PLANNING_DIR/debugging/completed/$session_name"
  grep -q '^uat_last_result: pass$' "$VBW_PLANNING_DIR/debugging/completed/$session_name"
}

@test "get returns none for stale pointer to completed session" {
  # Create a session via normal flow, then complete it
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "stale-ptr")"
  local fname
  fname=$(basename "$session_file")
  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" complete > /dev/null
  [ -f "$VBW_PLANNING_DIR/debugging/completed/$fname" ]
  [ ! -f "$VBW_PLANNING_DIR/debugging/.active-session" ]

  # Simulate stale pointer (e.g., from earlier buggy run or race condition)
  echo "$fname" > "$VBW_PLANNING_DIR/debugging/.active-session"

  # get should detect pointer targets completed/ and return none
  run bash "$SCRIPTS_DIR/debug-session-state.sh" get "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active_session=none"* ]]
  # Stale pointer should be cleaned up
  [ ! -f "$VBW_PLANNING_DIR/debugging/.active-session" ]
}

@test "list does not double-count self-healed sessions" {
  # Place one session with complete status in active/ (will be self-healed)
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "double-a")"
  local fname_a
  fname_a=$(basename "$session_file")
  awk 'BEGIN{in_fm=0} /^---$/{in_fm=!in_fm} in_fm && /^status:/{print "status: complete";next} {print}' \
    "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

  # Place one session already in completed/
  mkdir -p "$VBW_PLANNING_DIR/debugging/completed"
  local session_name_b="20240101-120000-double-b.md"
  cat > "$VBW_PLANNING_DIR/debugging/completed/$session_name_b" << 'EOF'
---
session_id: 20240101-120000-double-b
title: double-b
status: complete
created: 2024-01-01 12:00:00
updated: 2024-01-01 12:00:00
qa_round: 0
qa_last_result: pending
uat_round: 0
uat_last_result: pending
---
# Already completed
EOF

  run bash "$SCRIPTS_DIR/debug-session-state.sh" list "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  # Exactly 2 sessions, not 3
  [[ "$output" == *"session_count=2"* ]]
  # Each session appears exactly once
  local count
  count=$(echo "$output" | grep -c "^session=")
  [ "$count" -eq 2 ]
}

# ── unknown command ──────────────────────────────────────

@test "unknown command fails with error" {
  run bash "$SCRIPTS_DIR/debug-session-state.sh" bogus "$VBW_PLANNING_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]]
}
