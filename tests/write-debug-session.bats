#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  mkdir -p "$VBW_PLANNING_DIR"

  # Create a session to have a valid session file
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$VBW_PLANNING_DIR" "write-test")"
  export SESSION_FILE="$session_file"
}

teardown() {
  teardown_temp_dir
}

# ── investigation mode ───────────────────────────────────

@test "investigation mode writes issue and hypotheses" {
  run bash -c 'echo '"'"'{"mode":"investigation","issue":"Button crashes on click","hypotheses":[{"description":"Null ref","status":"confirmed","evidence_for":"Stack trace","evidence_against":"None","conclusion":"Root cause"}],"root_cause":"Null ref in handler","plan":"Add guard","changed_files":["src/button.sh"],"commit":"abc123"}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode=investigation"* ]]

  # Check session file contents
  grep -q "Button crashes on click" "$SESSION_FILE"
  grep -q "Null ref" "$SESSION_FILE"
  grep -q "Root cause" "$SESSION_FILE"
  grep -q "src/button.sh" "$SESSION_FILE"
}

@test "investigation mode fails without issue field" {
  run bash -c 'echo '"'"'{"mode":"investigation"}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires 'issue'"* ]]
}

# ── qa mode (array format) ───────────────────────────────

@test "qa mode handles checks as array of objects" {
  run bash -c 'echo '"'"'{"mode":"qa","round":1,"result":"PARTIAL","checks":[{"id":"C1","description":"Exit code","status":"PASS","evidence":"exits 0"},{"id":"C2","description":"Output format","status":"FAIL","evidence":"missing header"}]}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"round=1"* ]]
  [[ "$output" == *"result=PARTIAL"* ]]

  # Should have computed 1/2 passed
  grep -q "1/2 passed" "$SESSION_FILE"
  grep -q "1 failed" "$SESSION_FILE"

  # Should have details table with check IDs
  grep -q "C1: Exit code" "$SESSION_FILE"
  grep -q "C2: Output format" "$SESSION_FILE"
  grep -q "PASS" "$SESSION_FILE"
  grep -q "missing header" "$SESSION_FILE"
}

@test "qa mode handles checks as summary object (legacy)" {
  run bash -c 'echo '"'"'{"mode":"qa","round":1,"result":"PASS","checks":{"passed":3,"failed":0,"total":3}}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 0 ]
  grep -q "3/3 passed" "$SESSION_FILE"
}

@test "qa mode fails with invalid result" {
  run bash -c 'echo '"'"'{"mode":"qa","round":1,"result":"INVALID"}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be PASS, FAIL, or PARTIAL"* ]]
}

@test "qa mode updates frontmatter qa_round and qa_last_result" {
  bash -c 'echo '"'"'{"mode":"qa","round":2,"result":"FAIL","checks":[]}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  grep -q "^qa_round: 2$" "$SESSION_FILE"
  grep -q "^qa_last_result: fail$" "$SESSION_FILE"
}

# ── uat mode ─────────────────────────────────────────────

@test "uat mode handles issues as objects with description and severity" {
  run bash -c 'echo '"'"'{"mode":"uat","round":1,"result":"issues_found","checkpoints":[{"description":"Basic flow","result":"pass"}],"issues":[{"description":"Button misaligned","severity":"minor"},{"description":"Crash on empty input","severity":"major"}]}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 0 ]

  grep -q '\[x\] Basic flow' "$SESSION_FILE"
  grep -q '\[minor\] Button misaligned' "$SESSION_FILE"
  grep -q '\[major\] Crash on empty input' "$SESSION_FILE"
}

@test "uat mode handles issues as plain strings" {
  run bash -c 'echo '"'"'{"mode":"uat","round":1,"result":"issues_found","issues":["Simple string issue"]}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 0 ]

  grep -q "Simple string issue" "$SESSION_FILE"
}

@test "uat mode fails with invalid result" {
  run bash -c 'echo '"'"'{"mode":"uat","round":1,"result":"bad"}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be pass or issues_found"* ]]
}

# ── status mode ──────────────────────────────────────────

@test "status mode updates frontmatter status" {
  run bash -c 'echo '"'"'{"mode":"status","status":"qa_pending"}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 0 ]
  grep -q "^status: qa_pending$" "$SESSION_FILE"
}

@test "status mode rejects invalid status values" {
  run bash -c 'echo '"'"'{"mode":"status","status":"invalid_status"}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid status"* ]]
}

# ── error handling ───────────────────────────────────────

@test "fails on invalid JSON input" {
  run bash -c 'echo "not json" | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "fails on missing session file" {
  run bash -c 'echo '"'"'{"mode":"status","status":"investigating"}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "/nonexistent/file.md"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}
