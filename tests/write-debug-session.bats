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

@test "source-todo mode writes the fixed top-level Source Todo section" {
  run bash -c 'echo '"'"'{"mode":"source-todo","text":"Investigate parser crash","raw_line":"- [HIGH] Investigate parser crash (added 2026-04-01) (ref:abcd1234)","ref":"abcd1234","detail_status":"ok","related_files":["src/parser.sh","tests/parser.bats"],"detail_context":"Parser crash context"}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode=source-todo"* ]]

  grep -q '^## Source Todo$' "$SESSION_FILE"
  grep -q '\*\*Text:\*\* Investigate parser crash' "$SESSION_FILE"
  grep -q '\*\*Raw Line:\*\* - \[HIGH\] Investigate parser crash' "$SESSION_FILE"
  grep -q '\*\*Ref:\*\* abcd1234' "$SESSION_FILE"
  grep -q '\*\*Detail Status:\*\* ok' "$SESSION_FILE"
  grep -q 'src/parser.sh' "$SESSION_FILE"
  grep -q 'tests/parser.bats' "$SESSION_FILE"
  grep -q 'Parser crash context' "$SESSION_FILE"
}

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

@test "investigation mode handles title with sed metacharacters" {
  run bash -c 'echo '"'"'{"mode":"investigation","issue":"Fix crash in src/lib/parser.sh & helpers","hypotheses":[],"root_cause":"test","plan":"test","changed_files":[],"commit":"abc"}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 0 ]

  # Title with / and & should be written correctly
  grep -q "Fix crash in src/lib/parser.sh & helpers" "$SESSION_FILE"
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

@test "uat mode handles skip result and user_response" {
  run bash -c 'echo '"'"'{"mode":"uat","round":1,"result":"pass","checkpoints":[{"description":"Skipped check","result":"skip","user_response":"Not applicable to this flow"},{"description":"Passed check","result":"pass","user_response":"Looks good"}]}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 0 ]

  grep -q '\[-\] Skipped check (\*\*SKIPPED\*\*)' "$SESSION_FILE"
  grep -q '\[x\] Passed check' "$SESSION_FILE"
  grep -q '> Not applicable to this flow' "$SESSION_FILE"
  grep -q '> Looks good' "$SESSION_FILE"
}

@test "uat mode handles issue result on checkpoint" {
  run bash -c 'echo '"'"'{"mode":"uat","round":1,"result":"issues_found","checkpoints":[{"description":"Broken flow","result":"issue","user_response":"Crashes on click"}]}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 0 ]

  grep -q 'Broken flow (\*\*ISSUE\*\*)' "$SESSION_FILE"
  grep -q '> Crashes on click' "$SESSION_FILE"
}

# ── remediation history ──────────────────────────────────

@test "investigation mode archives previous round on remediation" {
  # First investigation
  echo '{"mode":"investigation","issue":"Bug report","hypotheses":[],"root_cause":"Original cause","plan":"Original plan","changed_files":["src/a.sh"],"commit":"abc123"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Simulate QA round (sets qa_round > 0 so archival triggers)
  echo '{"mode":"qa","round":1,"result":"FAIL","checks":[{"id":"c1","description":"test","status":"fail","evidence":"broken"}],"summary":"Failed."}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Second investigation (remediation round)
  run bash -c 'echo '"'"'{"mode":"investigation","issue":"Bug report v2","hypotheses":[],"root_cause":"New cause","plan":"New plan","changed_files":["src/b.sh"],"commit":"def456"}'"'"' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"'
  [ "$status" -eq 0 ]

  # Current sections should have new content
  grep -q "New cause" "$SESSION_FILE"
  grep -q "New plan" "$SESSION_FILE"
  grep -q "src/b.sh" "$SESSION_FILE"

  # Remediation History should have archived old content
  grep -q "## Remediation History" "$SESSION_FILE"
  grep -q "### Round 1" "$SESSION_FILE"
  grep -q "Original cause" "$SESSION_FILE"
  grep -q "Original plan" "$SESSION_FILE"
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
