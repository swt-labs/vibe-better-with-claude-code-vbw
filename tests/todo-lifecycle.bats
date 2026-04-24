#!/usr/bin/env bats

load test_helper

snapshot_path_for_session_id() {
  local raw_session_id="${1:-${CLAUDE_SESSION_ID:-default}}"
  local session_key

  session_key=$(printf '%s' "$raw_session_id" | tr -c 'A-Za-z0-9_.-' '_')
  session_key="${session_key:-default}"
  printf '/tmp/.vbw-last-list-view-%s.json\n' "$session_key"
}

fixed_todo_now_epoch() {
  date -j -f "%Y-%m-%d %H:%M:%S" "2026-04-23 12:00:00" +%s 2>/dev/null || \
    date -d "2026-04-23 12:00:00" +%s 2>/dev/null
}

setup() {
  setup_temp_dir
  create_test_config
  if [ "${VBW_TODO_NOW_EPOCH+x}" = "x" ]; then
    export _ORIG_VBW_TODO_NOW_EPOCH_WAS_SET=1
    export _ORIG_VBW_TODO_NOW_EPOCH="$VBW_TODO_NOW_EPOCH"
  else
    export _ORIG_VBW_TODO_NOW_EPOCH_WAS_SET=0
    unset _ORIG_VBW_TODO_NOW_EPOCH 2>/dev/null || true
  fi
  export VBW_TODO_NOW_EPOCH="$(fixed_todo_now_epoch)"
  export CLAUDE_SESSION_ID="todo-lifecycle-test"
  export VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  SCRIPT="$SCRIPTS_DIR/todo-lifecycle.sh"
  LIST_SCRIPT="$SCRIPTS_DIR/list-todos.sh"
  RESOLVE_SCRIPT="$SCRIPTS_DIR/resolve-todo-item.sh"
  TRACK_SCRIPT="$SCRIPTS_DIR/track-known-issues.sh"
  DETAILS_SCRIPT="$SCRIPTS_DIR/todo-details.sh"
  export TEST_SNAPSHOT_PATH="$(snapshot_path_for_session_id "$CLAUDE_SESSION_ID")"
  rm -f "$TEST_SNAPSHOT_PATH"
  mkdir -p "$VBW_PLANNING_DIR/phases/03-test-phase"
}

teardown() {
  rm -f "$TEST_SNAPSHOT_PATH" "$(snapshot_path_for_session_id)" 2>/dev/null || true
  if [ "${_ORIG_VBW_TODO_NOW_EPOCH_WAS_SET:-0}" = "1" ]; then
    export VBW_TODO_NOW_EPOCH="${_ORIG_VBW_TODO_NOW_EPOCH-}"
  else
    unset VBW_TODO_NOW_EPOCH 2>/dev/null || true
  fi
  unset TEST_SNAPSHOT_PATH _ORIG_VBW_TODO_NOW_EPOCH _ORIG_VBW_TODO_NOW_EPOCH_WAS_SET
  teardown_temp_dir
}

write_state_with_recent_activity() {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Fix parser bug (added 2026-04-01)
- [HIGH] Refactor auth module (added 2026-04-02)
- [low] Update docs (added 2026-04-03)

## Recent Activity
- 2026-04-01: Existing note
EOF
}

write_state_without_activity() {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Only todo item (added 2026-04-01)

## Blockers
None.
EOF
}

write_state_with_no_todos() {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
None.

## Blockers
None.
EOF
}

write_legacy_state() {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos

### Pending Todos
- [KNOWN-ISSUE] TestCrash (CrashTests.swift): signal trap (phase 03, seen 1x) (added 2026-04-01) (ref:abc12345)
- Follow-up todo (added 2026-04-02)

### Completed Todos
- Already completed item

## Activity Log
- 2026-04-01: Existing note
EOF
}

save_snapshot() {
  local filter="${1:-}"
  if [ -n "$filter" ]; then
    run bash "$LIST_SCRIPT" "$filter"
  else
    run bash "$LIST_SCRIPT"
  fi
  [ "$status" -eq 0 ]
  printf '%s' "$output" | bash "$SCRIPT" snapshot-save >/dev/null
}

select_snapshot_item() {
  local selection="$1"
  bash "$RESOLVE_SCRIPT" "$selection" --session-snapshot
}

write_raw_snapshot() {
  printf '%s' "$1" > "$(snapshot_path_for_session_id)"
}

assert_snapshot_invalid_everywhere() {
  local selection="${1:-1}"

  run bash "$SCRIPT" snapshot-show
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "error" ]
  [ "$(echo "$output" | jq -r '.code')" = "snapshot_invalid" ]

  run bash "$SCRIPT" snapshot-select "$selection"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "error" ]
  [ "$(echo "$output" | jq -r '.code')" = "snapshot_invalid" ]

  run bash "$RESOLVE_SCRIPT" "$selection" --session-snapshot --require-unfiltered --validate-live
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "error" ]
  [ "$(echo "$output" | jq -r '.code')" = "snapshot_invalid" ]
}

@test "todo-lifecycle: snapshot-show fails closed when missing" {
  run bash "$SCRIPT" snapshot-show
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'snapshot_missing'* ]]
}

@test "todo-lifecycle: snapshot-save preserves list error payloads without masking them" {
  ERROR_JSON='{"status":"error","message":"STATE.md not found at .vbw-planning/STATE.md. Run /vbw:init to set up your project."}'

  run bash -lc 'printf "%s" "$1" | bash "$2" snapshot-save' -- "$ERROR_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]

  run bash "$SCRIPT" snapshot-show
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "error" ]
  [[ "$output" == *'STATE.md not found'* ]]
}

@test "todo-lifecycle: snapshot path sanitizes CLAUDE_SESSION_ID" {
  write_state_with_recent_activity
  export CLAUDE_SESSION_ID='../unsafe session id'

  run bash "$LIST_SCRIPT"
  [ "$status" -eq 0 ]
  run bash -lc 'printf "%s" "$1" | bash "$2" snapshot-save' -- "$output" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [[ "$(echo "$output" | jq -r '.path')" == /tmp/.vbw-last-list-view-* ]]
  [[ "$(echo "$output" | jq -r '.path')" != *'../'* ]]

  run bash "$SCRIPT" snapshot-show
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
}

@test "todo-lifecycle: list-with-snapshot returns full metadata and writes the exact snapshot" {
  write_state_with_recent_activity

  run bash "$LIST_SCRIPT" high
  [ "$status" -eq 0 ]
  EXPECTED_JSON="$output"

  run bash "$SCRIPT" list-with-snapshot high
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -cS '.')" = "$(printf '%s' "$EXPECTED_JSON" | jq -cS '.')" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].age')" = "21d ago" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].command_text')" = "Refactor auth module" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].section_index')" = "2" ]

  run bash "$SCRIPT" snapshot-show
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -cS '.')" = "$(printf '%s' "$EXPECTED_JSON" | jq -cS '.')" ]
}

@test "todo-lifecycle: validate-item returns status ok for a matching live selection" {
  write_state_with_recent_activity
  save_snapshot
  ITEM_JSON=$(select_snapshot_item 1)

  run bash -lc 'printf "%s" "$1" | bash "$2" validate-item' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [ "$(echo "$output" | jq -r '.normalized_text')" = "Fix parser bug" ]
}

@test "todo-lifecycle: snapshot-show accepts valid empty snapshot payloads" {
  write_raw_snapshot '{"status":"empty","state_path":".vbw-planning/STATE.md","section":null,"count":0,"filter":null,"display":"No pending todos.","items":[]}'

  run bash "$SCRIPT" snapshot-show
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "empty" ]
}

@test "todo-lifecycle: list-with-snapshot preserves valid filtered empty snapshots" {
  write_state_with_no_todos

  run bash "$SCRIPT" list-with-snapshot high
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "empty" ]
  [ "$(echo "$output" | jq -r '.section')" = "null" ]
  [ "$(echo "$output" | jq -r '.count')" = "0" ]
  [ "$(echo "$output" | jq -r '.filter')" = "high" ]
  [ "$(echo "$output" | jq -r '.display')" = "No pending todos." ]
  [ "$(echo "$output" | jq -r '.items | length')" = "0" ]

  EXPECTED_JSON="$output"

  run bash "$SCRIPT" snapshot-show
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -cS '.')" = "$(printf '%s' "$EXPECTED_JSON" | jq -cS '.')" ]
}

@test "todo-lifecycle: snapshot-show accepts valid no-match snapshot payloads" {
  write_raw_snapshot '{"status":"no-match","state_path":".vbw-planning/STATE.md","section":"## Todos","count":0,"filter":"high","display":"No high-priority todos found.","items":[]}'

  run bash "$SCRIPT" snapshot-show
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "no-match" ]
}

@test "todo-lifecycle: snapshot schema rejects bogus top-level status" {
  write_raw_snapshot '{"status":"bogus","state_path":".vbw-planning/STATE.md","section":"## Todos","count":1,"filter":null,"items":[{"num":1,"section_index":1,"line":"- Test todo","normalized_text":"Test todo","state_path":".vbw-planning/STATE.md","section":"## Todos","line_no":12,"identity_occurrence":1,"identity_total":1,"ref":null,"known_issue_signature":null}]}'

  assert_snapshot_invalid_everywhere
}

@test "todo-lifecycle: snapshot schema rejects ok snapshots missing filter" {
  write_raw_snapshot '{"status":"ok","state_path":".vbw-planning/STATE.md","section":"## Todos","count":1,"items":[{"num":1,"section_index":1,"line":"- Test todo","normalized_text":"Test todo","state_path":".vbw-planning/STATE.md","section":"## Todos","line_no":12,"identity_occurrence":1,"identity_total":1,"ref":null,"known_issue_signature":null}]}'

  assert_snapshot_invalid_everywhere
}

@test "todo-lifecycle: snapshot schema rejects no-match snapshots with null filter" {
  write_raw_snapshot '{"status":"no-match","state_path":".vbw-planning/STATE.md","section":"## Todos","count":0,"filter":null,"display":"No matching todos.","items":[]}'

  assert_snapshot_invalid_everywhere
}

@test "todo-lifecycle: snapshot schema rejects invalid item ref metadata" {
  write_raw_snapshot '{"status":"ok","state_path":".vbw-planning/STATE.md","section":"## Todos","count":1,"filter":null,"items":[{"num":1,"section_index":1,"line":"- Test todo","normalized_text":"Test todo","state_path":".vbw-planning/STATE.md","section":"## Todos","line_no":12,"identity_occurrence":1,"identity_total":1,"ref":"not-a-ref","known_issue_signature":null}]}'

  assert_snapshot_invalid_everywhere
}

@test "resolve-todo-item: validate-live returns status ok for a matching selection" {
  write_state_with_recent_activity

  run bash "$SCRIPT" list-with-snapshot
  [ "$status" -eq 0 ]

  run bash "$RESOLVE_SCRIPT" 1 --session-snapshot --validate-live
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [ "$(echo "$output" | jq -r '.selection_source')" = "snapshot" ]
}

@test "todo-lifecycle: snapshot-select preserves filtered numbering and section index" {
  write_state_with_recent_activity
  save_snapshot high

  run bash "$SCRIPT" snapshot-select 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [ "$(echo "$output" | jq -r '.priority')" = "high" ]
  [ "$(echo "$output" | jq -r '.num')" = "1" ]
  [ "$(echo "$output" | jq -r '.section_index')" = "2" ]
  [ "$(echo "$output" | jq -r '.normalized_text')" = "Refactor auth module" ]
}

@test "todo-lifecycle: validate-item fails closed when duplicate occurrence count changes" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Duplicate task (added 2026-04-01)
- Duplicate task (added 2026-04-01)

## Activity Log
- 2026-04-01: Existing note
EOF

  save_snapshot
  ITEM_JSON=$(select_snapshot_item 2)

  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Duplicate task (added 2026-04-01)
- Duplicate task (added 2026-04-01)
- Duplicate task (added 2026-04-01)

## Activity Log
- 2026-04-01: Existing note
EOF

  run bash -lc 'printf "%s" "$1" | bash "$2" validate-item' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "error" ]
  [ "$(echo "$output" | jq -r '.code')" = "selection_stale" ]
}

@test "todo-lifecycle: validate-item fails closed when raw displayed line changes" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- [HIGH] Change me (added 2026-04-01)

## Activity Log
- 2026-04-01: Existing note
EOF

  save_snapshot
  ITEM_JSON=$(select_snapshot_item 1)

  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Change me (added 2026-04-01)

## Activity Log
- 2026-04-01: Existing note
EOF

  run bash -lc 'printf "%s" "$1" | bash "$2" validate-item' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "error" ]
  [ "$(echo "$output" | jq -r '.code')" = "selection_stale" ]
}

@test "todo-lifecycle: remove uses filtered snapshot metadata and preserves Recent Activity heading" {
  write_state_with_recent_activity
  save_snapshot high
  ITEM_JSON=$(select_snapshot_item 1)

  run bash -lc 'printf "%s" "$1" | bash "$2" remove none safe' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  grep -q '^## Recent Activity$' "$VBW_PLANNING_DIR/STATE.md"
  ! grep -q 'Refactor auth module' "$VBW_PLANNING_DIR/STATE.md"
  grep -q 'Fix parser bug' "$VBW_PLANNING_DIR/STATE.md"
  grep -q 'Removed todo via /vbw:list-todos: \[HIGH\] Refactor auth module' "$VBW_PLANNING_DIR/STATE.md"
}

@test "todo-lifecycle: pickup restores None and creates Activity Log when missing" {
  write_state_without_activity
  ITEM_JSON=$(bash "$LIST_SCRIPT" | jq -c '.items[0]')

  run bash -lc 'printf "%s" "$1" | bash "$2" pickup /vbw:fix none keep' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  grep -q '^## Activity Log$' "$VBW_PLANNING_DIR/STATE.md"
  grep -q '^None\.$' "$VBW_PLANNING_DIR/STATE.md"
  grep -q 'Picked up todo via /vbw:fix: Only todo item' "$VBW_PLANNING_DIR/STATE.md"
}

@test "todo-lifecycle: remove rejects archived milestone fallback state" {
  mkdir -p "$VBW_PLANNING_DIR/milestones/old-milestone"
  cat > "$VBW_PLANNING_DIR/milestones/old-milestone/STATE.md" <<'EOF'
# Project State

## Todos
- Archived todo (added 2026-04-01)
EOF

  ITEM_JSON=$(bash "$LIST_SCRIPT" | jq -c '.items[0]')
  run bash -lc 'printf "%s" "$1" | bash "$2" remove none keep' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "error" ]
  [ "$(echo "$output" | jq -r '.code')" = "archived_state" ]
  grep -q 'Archived todo' "$VBW_PLANNING_DIR/milestones/old-milestone/STATE.md"
}

@test "todo-lifecycle: remove leaves legacy Completed Todos untouched" {
  write_legacy_state
  ITEM_JSON=$(bash "$LIST_SCRIPT" | jq -c '.items[0]')

  run bash -lc 'printf "%s" "$1" | bash "$2" remove none keep' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '^### Completed Todos$' "$VBW_PLANNING_DIR/STATE.md"
  grep -q 'Already completed item' "$VBW_PLANNING_DIR/STATE.md"
  ! grep -q 'TestCrash (CrashTests.swift): signal trap' "$VBW_PLANNING_DIR/STATE.md"
  grep -q 'Follow-up todo' "$VBW_PLANNING_DIR/STATE.md"
}

@test "todo-lifecycle: remove reports partial cleanup when detail is missing" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Remove me (added 2026-04-01) (ref:deadbeef)

## Activity Log
- 2026-04-01: Existing note
EOF

  ITEM_JSON=$(bash "$LIST_SCRIPT" | jq -c '.items[0]')
  run bash -lc 'printf "%s" "$1" | bash "$2" remove not_found safe' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "partial" ]
  [[ "$(echo "$output" | jq -r '.warning')" == *'sidecar registry was left untouched'* ]]
  grep -q '^None\.$' "$VBW_PLANNING_DIR/STATE.md"
}

@test "todo-lifecycle: remove with detail_status ok and safe cleanup removes sidecar entry" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Remove me safely (added 2026-04-01) (ref:deadbeef)

## Activity Log
- 2026-04-01: Existing note
EOF
  bash "$DETAILS_SCRIPT" add deadbeef '{"summary":"Remove me safely","context":"extra detail","files":["a.sh"],"added":"2026-04-01","source":"session"}' "$VBW_PLANNING_DIR/todo-details.json" >/dev/null

  ITEM_JSON=$(bash "$LIST_SCRIPT" | jq -c '.items[0]')
  run bash -lc 'printf "%s" "$1" | bash "$2" remove ok safe' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  run bash "$DETAILS_SCRIPT" get deadbeef "$VBW_PLANNING_DIR/todo-details.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "not_found" ]
}

@test "todo-lifecycle: remove with detail_status ok and keep preserves sidecar entry" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Keep my detail (added 2026-04-01) (ref:deadbeef)

## Activity Log
- 2026-04-01: Existing note
EOF
  bash "$DETAILS_SCRIPT" add deadbeef '{"summary":"Keep my detail","context":"extra detail","files":["a.sh"],"added":"2026-04-01","source":"session"}' "$VBW_PLANNING_DIR/todo-details.json" >/dev/null

  ITEM_JSON=$(bash "$LIST_SCRIPT" | jq -c '.items[0]')
  run bash -lc 'printf "%s" "$1" | bash "$2" remove ok keep' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  run bash "$DETAILS_SCRIPT" get deadbeef "$VBW_PLANNING_DIR/todo-details.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
}

@test "todo-lifecycle: remove reports partial cleanup when detail load errored" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Error detail item (added 2026-04-01) (ref:deadbeef)

## Activity Log
- 2026-04-01: Existing note
EOF
  bash "$DETAILS_SCRIPT" add deadbeef '{"summary":"Error detail item","context":"extra detail","files":["a.sh"],"added":"2026-04-01","source":"session"}' "$VBW_PLANNING_DIR/todo-details.json" >/dev/null

  ITEM_JSON=$(bash "$LIST_SCRIPT" | jq -c '.items[0]')
  run bash -lc 'printf "%s" "$1" | bash "$2" remove error safe' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "partial" ]
  [[ "$(echo "$output" | jq -r '.warning')" == *'sidecar registry was left untouched'* ]]
  run bash "$DETAILS_SCRIPT" get deadbeef "$VBW_PLANNING_DIR/todo-details.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
}

@test "todo-lifecycle: pickup suppresses known-issue re-promotion" {
  local phase_dir="$VBW_PLANNING_DIR/phases/03-test-phase"
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- [KNOWN-ISSUE] TestCrash (CrashTests.swift): signal trap (phase 03, seen 1x) (added 2026-04-01) (ref:feedcafe)

## Activity Log
- 2026-04-01: Existing note
EOF

  cat > "$phase_dir/known-issues.json" <<'EOF'
{"schema_version":1,"phase":"03","issues":[{"test":"TestCrash","file":"CrashTests.swift","error":"signal trap","first_seen_in":"03-VERIFICATION.md","last_seen_in":"03-VERIFICATION.md","first_seen_round":0,"last_seen_round":0,"times_seen":1,"source_kind":"registry"}]}
EOF

  SIGNATURE=$(jq -cn --arg phase "03" --arg phase_dir "$phase_dir" --arg test "TestCrash" --arg file "CrashTests.swift" --arg error "signal trap" --arg source_kind "registry" --arg disposition "unresolved" --arg source_path "03-VERIFICATION.md" '{phase:$phase, phase_dir:$phase_dir, test:$test, file:$file, error:$error, source_kind:$source_kind, disposition:$disposition, source_path:$source_path}')
  DETAIL_JSON=$(jq -cn --arg summary 'TestCrash (CrashTests.swift): signal trap' --arg context 'Known issue detail' --arg added '2026-04-01' --argjson signature "$SIGNATURE" '{summary:$summary, context:$context, files:["CrashTests.swift"], added:$added, source:"known-issue", known_issue_signature:$signature}')
  bash "$DETAILS_SCRIPT" add feedcafe "$DETAIL_JSON" "$VBW_PLANNING_DIR/todo-details.json" >/dev/null

  ITEM_JSON=$(bash "$LIST_SCRIPT" | jq -c '.items[0]')
  run bash -lc 'printf "%s" "$1" | bash "$2" pickup /vbw:debug ok keep' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [ -f "$phase_dir/known-issue-suppressions.json" ]

  run bash "$TRACK_SCRIPT" promote-todos "$phase_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *'promoted_count=0'* ]]
  run bash -c 'awk "/^## Todos?$/{f=1;next} f&&/^##/{exit} f" "$1" | grep -q "\[KNOWN-ISSUE\].*TestCrash (CrashTests.swift): signal trap"' -- "$VBW_PLANNING_DIR/STATE.md"
  [ "$status" -ne 0 ]
}

@test "todo-lifecycle: remove suppresses legacy ref-less known-issue todos via structured lookup" {
  local phase_dir="$VBW_PLANNING_DIR/phases/03-test-phase"
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- [KNOWN-ISSUE] TestCrash (CrashTests.swift): signal trap (phase 03, seen 1x) (added 2026-04-01)

## Activity Log
- 2026-04-01: Existing note
EOF

  cat > "$phase_dir/known-issues.json" <<'EOF'
{"schema_version":1,"phase":"03","issues":[{"test":"TestCrash","file":"CrashTests.swift","error":"signal trap","first_seen_in":"03-VERIFICATION.md","last_seen_in":"03-VERIFICATION.md","first_seen_round":0,"last_seen_round":0,"times_seen":1,"source_kind":"registry"}]}
EOF

  ITEM_JSON=$(bash "$LIST_SCRIPT" | jq -c '.items[0]')
  [ "$(echo "$ITEM_JSON" | jq -r '.ref')" = "null" ]
  [ "$(echo "$ITEM_JSON" | jq -r '.known_issue_signature')" = "null" ]

  run bash -lc 'printf "%s" "$1" | bash "$2" remove none keep' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [ -f "$phase_dir/known-issue-suppressions.json" ]

  run bash "$TRACK_SCRIPT" promote-todos "$phase_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *'promoted_count=0'* ]]
  run bash -c 'awk "/^## Todos?$/{f=1;next} f&&/^##/{exit} f" "$1" | grep -q "\[KNOWN-ISSUE\].*TestCrash (CrashTests.swift): signal trap"' -- "$VBW_PLANNING_DIR/STATE.md"
  [ "$status" -ne 0 ]
}

@test "todo-lifecycle: pickup returns partial warning when detail load errored and cleanup is keep" {
  cat > "$VBW_PLANNING_DIR/STATE.md" <<'EOF'
# Project State

## Todos
- Broken detail item (added 2026-04-01) (ref:deadbeef)

## Activity Log
- 2026-04-01: Existing note
EOF
  bash "$DETAILS_SCRIPT" add deadbeef '{"summary":"Broken detail item","context":"extra detail","files":["a.sh"],"added":"2026-04-01","source":"session"}' "$VBW_PLANNING_DIR/todo-details.json" >/dev/null

  ITEM_JSON=$(bash "$LIST_SCRIPT" | jq -c '.items[0]')
  run bash -lc 'printf "%s" "$1" | bash "$2" pickup /vbw:fix error keep' -- "$ITEM_JSON" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "partial" ]
  [[ "$(echo "$output" | jq -r '.warning')" == *'sidecar registry was left untouched'* ]]
  run bash "$DETAILS_SCRIPT" get deadbeef "$VBW_PLANNING_DIR/todo-details.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
}
