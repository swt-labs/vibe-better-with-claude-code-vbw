#!/usr/bin/env bats

load test_helper

snapshot_path_for_session_id() {
  local raw_session_id="${1:-${CLAUDE_SESSION_ID:-default}}"
  local session_key

  session_key=$(printf '%s' "$raw_session_id" | tr -c 'A-Za-z0-9_.-' '_')
  session_key="${session_key:-default}"
  printf '/tmp/.vbw-last-list-view-%s.json\n' "$session_key"
}

setup() {
  setup_temp_dir
  create_test_config
  export VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  export CLAUDE_SESSION_ID="debug-start-selected-${BATS_TEST_NUMBER:-0}-$$-$RANDOM"
  SCRIPT="$SCRIPTS_DIR/debug-start-selected-todo.sh"
  LIFECYCLE_SCRIPT="$SCRIPTS_DIR/todo-lifecycle.sh"
  DETAILS_SCRIPT="$SCRIPTS_DIR/todo-details.sh"
  export TEST_SNAPSHOT_PATH="$(snapshot_path_for_session_id "$CLAUDE_SESSION_ID")"
  rm -f "$TEST_SNAPSHOT_PATH"
}

teardown() {
  rm -f "$TEST_SNAPSHOT_PATH" 2>/dev/null || true
  teardown_temp_dir
}

write_state() {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Fix parser bug (added 2026-04-01)
- Investigate detail-backed crash (added 2026-04-02) (ref:deadbeef)
- Empty detail item (added 2026-04-03) (ref:feedcafe)
- Missing detail item (added 2026-04-04) (ref:f78562c0)

## Recent Activity
- 2026-04-01: Existing note
EOF
}

save_snapshot() {
  (cd "$TEST_TEMP_DIR" && VBW_PLANNING_DIR="$VBW_PLANNING_DIR" bash "$LIFECYCLE_SCRIPT" list-with-snapshot) >/dev/null
}

session_file_from_output() {
  printf '%s' "$1" | jq -r '.session.file'
}

active_session_count() {
  find "$VBW_PLANNING_DIR/debugging/active" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '
}

completed_session_count() {
  find "$VBW_PLANNING_DIR/debugging/completed" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '
}

pending_todos_contains() {
  local needle="$1"
  awk '/^## Todos$/{found=1; next} found && /^## /{exit} found {print}' "$VBW_PLANNING_DIR/STATE.md" | grep -qF "$needle"
}

@test "debug-start-selected-todo: no-ref happy path creates session and removes root todo" {
  write_state
  save_snapshot

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 1
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "ok" ]
  [ "$(printf '%s' "$output" | jq -r '.bug_desc')" = "Fix parser bug" ]
  [ "$(printf '%s' "$output" | jq -r '.detail_status')" = "none" ]
  [ "$(printf '%s' "$output" | jq -r '.pickup.status')" = "ok" ]
  [ "$(printf '%s' "$output" | jq -r '.pickup.auto_note')" = "Selected todo was already picked up automatically." ]
  ! printf '%s\n' "$output" | grep -q '^status='

  session_file=$(session_file_from_output "$output")
  [ -f "$session_file" ]
  grep -q '^## Source Todo$' "$session_file"
  grep -q '\*\*Text:\*\* Fix parser bug' "$session_file"
  ! grep -q '^- Fix parser bug' "$VBW_PLANNING_DIR/STATE.md"
  grep -q 'Picked up todo via /vbw:debug: Fix parser bug' "$VBW_PLANNING_DIR/STATE.md"

  run bash "$LIFECYCLE_SCRIPT" list-with-snapshot
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.items[]?.command_text' | grep -c '^Fix parser bug$' | tr -d ' ')" = "0" ]
}

@test "debug-start-selected-todo: ref detail success persists detail signal and safely removes sidecar" {
  write_state
  bash "$DETAILS_SCRIPT" add deadbeef '{"summary":"Investigate detail-backed crash","context":"Crash detail context","files":["src/parser.sh","tests/parser.bats"],"added":"2026-04-02","source":"session"}' "$VBW_PLANNING_DIR/todo-details.json" >/dev/null
  save_snapshot

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 2
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "ok" ]
  [ "$(printf '%s' "$output" | jq -r '.detail_status')" = "ok" ]
  [ "$(printf '%s' "$output" | jq -r '.detail_has_signal')" = "true" ]
  [ "$(printf '%s' "$output" | jq -r '.detail.files[0]')" = "src/parser.sh" ]

  session_file=$(session_file_from_output "$output")
  grep -q 'Crash detail context' "$session_file"
  grep -q 'src/parser.sh' "$session_file"
  ! grep -q 'Investigate detail-backed crash' "$VBW_PLANNING_DIR/STATE.md"

  run bash "$DETAILS_SCRIPT" get deadbeef "$VBW_PLANNING_DIR/todo-details.json"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "not_found" ]
}

@test "debug-start-selected-todo: structurally empty ok detail remains sparse but still cleans root todo" {
  write_state
  bash "$DETAILS_SCRIPT" add feedcafe '{"summary":"Empty detail item","context":"","files":[],"added":"2026-04-03","source":"session"}' "$VBW_PLANNING_DIR/todo-details.json" >/dev/null
  save_snapshot

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 3
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "ok" ]
  [ "$(printf '%s' "$output" | jq -r '.detail_status')" = "ok" ]
  [ "$(printf '%s' "$output" | jq -r '.detail_has_signal')" = "false" ]
  ! pending_todos_contains 'Empty detail item'
}

@test "debug-start-selected-todo: missing detail warns, creates session, and removes root todo" {
  write_state
  save_snapshot

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 4
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "ok" ]
  [ "$(printf '%s' "$output" | jq -r '.detail_status')" = "not_found" ]
  [ "$(printf '%s' "$output" | jq -r '.pickup.status')" = "partial" ]
  [[ "$(printf '%s' "$output" | jq -r '.pickup.warning')" == *'sidecar registry was left untouched'* ]]
  ! grep -q 'Missing detail item' "$VBW_PLANNING_DIR/STATE.md"
  grep -q 'Detail for ref f78562c0 could not be loaded' "$VBW_PLANNING_DIR/STATE.md"
}

@test "debug-start-selected-todo: completed-session stale-state repair removes root todo without duplicate active session" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Already completed bug (added 2026-04-04) (ref:f78562c0)

## Activity Log
- 2026-04-01: Existing note
EOF
  source_json=$(jq -cn --arg mode source-todo --arg text 'Already completed bug' --arg raw_line '- Already completed bug (added 2026-04-04) (ref:f78562c0)' --arg ref f78562c0 --arg detail_status not_found '{mode:$mode,text:$text,raw_line:$raw_line,ref:$ref,detail_status:$detail_status,related_files:[],detail_context:""}')
  eval "$(printf '%s' "$source_json" | bash "$SCRIPTS_DIR/debug-session-state.sh" start-with-source-todo "$VBW_PLANNING_DIR" already-completed-bug)"
  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" complete >/dev/null
  [ "$(completed_session_count)" = "1" ]
  save_snapshot

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 1
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "already_complete" ]
  [ "$(printf '%s' "$output" | jq -r '.session.status')" = "complete" ]
  [ "$(active_session_count)" = "0" ]
  [ "$(completed_session_count)" = "1" ]
  ! pending_todos_contains 'Already completed bug'
}

@test "debug-start-selected-todo: legacy flat completed session repairs stale root todo" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Legacy completed bug (added 2026-04-04) (ref:deadbeef)

## Activity Log
- 2026-04-01: Existing note
EOF
  source_json=$(jq -cn --arg mode source-todo --arg text 'Legacy completed bug' --arg raw_line '- Legacy completed bug (added 2026-04-04) (ref:deadbeef)' --arg ref deadbeef --arg detail_status not_found '{mode:$mode,text:$text,raw_line:$raw_line,ref:$ref,detail_status:$detail_status,related_files:[],detail_context:""}')
  eval "$(printf '%s' "$source_json" | bash "$SCRIPTS_DIR/debug-session-state.sh" start-with-source-todo "$VBW_PLANNING_DIR" legacy-completed-bug)"
  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" complete >/dev/null
  legacy_file="$VBW_PLANNING_DIR/debugging/${session_id}.md"
  mv "$VBW_PLANNING_DIR/debugging/completed/${session_id}.md" "$legacy_file"
  rmdir "$VBW_PLANNING_DIR/debugging/completed"
  [ -f "$legacy_file" ]
  save_snapshot

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 1
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "already_complete" ]
  [ "$(printf '%s' "$output" | jq -r '.session.status')" = "complete" ]
  [ "$(active_session_count)" = "0" ]
  [ "$(completed_session_count)" = "1" ]
  [ ! -f "$legacy_file" ]
  ! pending_todos_contains 'Legacy completed bug'
}

@test "debug-start-selected-todo: ref-less duplicate raw lines do not use completed proof" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Duplicate bug (added 2026-04-01)
- Duplicate bug (added 2026-04-01)

## Activity Log
- 2026-04-01: Existing note
EOF
  source_json=$(jq -cn --arg mode source-todo --arg text 'Duplicate bug' --arg raw_line '- Duplicate bug (added 2026-04-01)' --arg ref none --arg detail_status none '{mode:$mode,text:$text,raw_line:$raw_line,ref:$ref,detail_status:$detail_status,related_files:[],detail_context:""}')
  eval "$(printf '%s' "$source_json" | bash "$SCRIPTS_DIR/debug-session-state.sh" start-with-source-todo "$VBW_PLANNING_DIR" duplicate-bug)"
  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$VBW_PLANNING_DIR" complete >/dev/null
  save_snapshot

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 1
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "ok" ]
  [ "$(active_session_count)" = "1" ]
  [ "$(completed_session_count)" = "1" ]
}

@test "debug-start-selected-todo: pickup failure after session creation returns partial lifecycle state" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Pickup failure bug (added 2026-04-01)

## Activity Log
- 2026-04-01: Existing note
EOF
  save_snapshot
  mkdir -p "$VBW_PLANNING_DIR/debugging/active"
  chmod u-w "$VBW_PLANNING_DIR"

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 1
  chmod u+w "$VBW_PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "error" ]
  [ "$(printf '%s' "$output" | jq -r '.code')" = "pickup_failed_after_session" ]
  [ "$(printf '%s' "$output" | jq -r '.session.id | length > 0')" = "true" ]
  session_file=$(session_file_from_output "$output")
  [ -f "$session_file" ]
  [ "$(printf '%s' "$output" | jq -r '.session.status')" = "investigating" ]
  [ "$(active_session_count)" = "1" ]
  [ "$(printf '%s' "$output" | jq -r '.pickup.status')" = "error" ]
  [ "$(printf '%s' "$output" | jq -r '((.pickup.message // .message // "") | length > 0)')" = "true" ]
  pending_todos_contains 'Pickup failure bug'
}

@test "debug-start-selected-todo: resolver errors do not create sessions or mutate state" {
  write_state
  save_snapshot

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 99
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "error" ]
  [ "$(printf '%s' "$output" | jq -r '.code')" = "invalid_selection" ]
  [ ! -d "$VBW_PLANNING_DIR/debugging/active" ]
  grep -q 'Fix parser bug' "$VBW_PLANNING_DIR/STATE.md"
}

@test "debug-start-selected-todo: archived milestone state is rejected before mutation" {
  rm -f "$VBW_PLANNING_DIR/STATE.md"
  mkdir -p "$VBW_PLANNING_DIR/milestones/old"
  cat > "$VBW_PLANNING_DIR/milestones/old/STATE.md" <<'EOF'
# Project State

## Todos
- Archived bug (added 2026-04-01)
EOF
  save_snapshot

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 1
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "error" ]
  [ "$(printf '%s' "$output" | jq -r '.code')" = "archived_state" ]
  [ ! -d "$VBW_PLANNING_DIR/debugging/active" ]
  grep -q 'Archived bug' "$VBW_PLANNING_DIR/milestones/old/STATE.md"
}

@test "debug-start-selected-todo: absolute planning-dir isolation works from another cwd" {
  local target_root="$TEST_TEMP_DIR/target"
  local other_root="$TEST_TEMP_DIR/other"
  local target_planning="$target_root/.vbw-planning"
  local other_planning="$other_root/.vbw-planning"

  mkdir -p "$target_planning" "$other_planning"
  cat > "$target_planning/STATE.md" <<'EOF'
# Project State

## Todos
- Target-only bug (added 2026-04-01) (ref:deadbeef)

## Activity Log
- 2026-04-01: Target note
EOF
  cat > "$other_planning/STATE.md" <<'EOF'
# Project State

## Todos
- Other repo bug (added 2026-04-01) (ref:deadbeef)

## Activity Log
- 2026-04-01: Other note
EOF
  bash "$DETAILS_SCRIPT" add deadbeef '{"summary":"Target-only bug","context":"target context","files":["target.sh"],"added":"2026-04-01","source":"session"}' "$target_planning/todo-details.json" >/dev/null
  (cd "$target_root" && VBW_PLANNING_DIR="$target_planning" bash "$LIFECYCLE_SCRIPT" list-with-snapshot) >/dev/null

  run bash -c 'cd "$1" && bash "$2" "$3" 1' -- "$other_root" "$SCRIPT" "$target_planning"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "ok" ]
  ! grep -q 'Target-only bug' "$target_planning/STATE.md"
  grep -q 'Other repo bug' "$other_planning/STATE.md"
  [ "$(printf '%s' "$output" | jq -r '.detail.context')" = "target context" ]
}

@test "debug-start-selected-todo: routing flags are preserved" {
  write_state
  save_snapshot

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 1 --parallel --serial
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.routing_flags | join(",")')" = "--parallel,--serial" ]
}

@test "debug-start-selected-todo: accepted-exception marker extraction covers selected and detail metadata" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- [KNOWN-ISSUE] Marker bug (added 2026-04-01) (ref:decafbad)

## Activity Log
- 2026-04-01: Existing note
EOF
  bash "$DETAILS_SCRIPT" add decafbad '{"summary":"Marker bug","context":"Accepted UAT summary deviation","files":[],"added":"2026-04-01","source":"uat-deviation","uat_deviation":{"id":"D1"},"known_issue_signature":{"disposition":"accepted-process-exception"}}' "$VBW_PLANNING_DIR/todo-details.json" >/dev/null
  save_snapshot

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 1
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.accepted_exception_markers | index("[KNOWN-ISSUE]") != null')" = "true" ]
  [ "$(printf '%s' "$output" | jq -r '.accepted_exception_markers | index("known_issue_signature.disposition") != null')" = "true" ]
  [ "$(printf '%s' "$output" | jq -r '.accepted_exception_markers | index("source: \"uat-deviation\"") != null')" = "true" ]
  [ "$(printf '%s' "$output" | jq -r '.accepted_exception_markers | index("uat_deviation") != null')" = "true" ]
  [ "$(printf '%s' "$output" | jq -r '.accepted_exception_markers | index("Accepted UAT summary deviation") != null')" = "true" ]
}

@test "debug-start-selected-todo: usage errors are compact parseable JSON" {
  run bash "$SCRIPT" "$VBW_PLANNING_DIR"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "error" ]
  [ "$(printf '%s' "$output" | jq -r '.code')" = "usage" ]

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" not-a-number
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "error" ]
  [ "$(printf '%s' "$output" | jq -r '.code')" = "usage" ]

  run bash "$SCRIPT" "$VBW_PLANNING_DIR" 1 --unknown
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.status')" = "error" ]
  [ "$(printf '%s' "$output" | jq -r '.code')" = "usage" ]
}
