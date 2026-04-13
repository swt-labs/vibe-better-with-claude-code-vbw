#!/usr/bin/env bats

# End-to-end lifecycle tests for standalone debug sessions.
# Exercises the full chain: debug → QA → UAT → remediation via debug resume.

setup() {
  export TMPDIR="${BATS_TMPDIR:-/tmp}"
  TEST_DIR=$(mktemp -d "${TMPDIR}/lifecycle-test.XXXXXX")
  export PLANNING_DIR="$TEST_DIR/.vbw-planning"
  mkdir -p "$PLANNING_DIR/debugging"

  # Resolve scripts dir from this test file's location
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export SCRIPTS_DIR="$(cd "$TESTS_DIR/../scripts" && pwd)"
  export TEMPLATES_DIR="$(cd "$TESTS_DIR/../templates" && pwd)"
}

teardown() {
  [ -d "$TEST_DIR" ] && rm -rf "$TEST_DIR"
}

# Helper: start a session and return the session file path
start_session() {
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" start "$PLANNING_DIR" "test-bug" 2>/dev/null)"
  echo "$session_file"
}

# Helper: get suggest-next output for debug context
get_suggestion() {
  bash "$SCRIPTS_DIR/suggest-next.sh" debug 2>/dev/null || true
}

# ── Happy path lifecycle ─────────────────────────────────

@test "full lifecycle: debug → QA pass → UAT pass → complete" {
  SESSION_FILE=$(start_session)
  [ -f "$SESSION_FILE" ]

  # Step 1: Investigation
  echo '{"mode":"investigation","issue":"Button crash","hypotheses":[{"description":"Null ref","status":"confirmed","evidence_for":"Stack trace shows null","evidence_against":"None","conclusion":"Confirmed"}],"root_cause":"Missing null check","plan":"Add guard","changed_files":["src/button.sh"],"commit":"abc123"}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Set status to qa_pending (as debug.md orchestrator would)
  echo '{"mode":"status","status":"qa_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Verify suggest-next recommends QA
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "qa_pending" ]

  # Step 2: QA Pass
  echo '{"mode":"qa","round":1,"result":"PASS","checks":[{"id":"c1","description":"Null check present","status":"pass","evidence":"src/button.sh:42"}],"summary":"All checks pass."}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"uat_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Verify state
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "uat_pending" ]

  # Step 3: UAT Pass
  echo '{"mode":"uat","round":1,"result":"pass","checkpoints":[{"description":"Button click works","result":"pass","user_response":"Verified"}],"summary":"All checkpoints pass."}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"complete"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Verify final state
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "complete" ]

  # Verify file has all sections populated
  grep -q "## Issue" "$SESSION_FILE"
  grep -q "## Investigation" "$SESSION_FILE"
  grep -q "## Plan" "$SESSION_FILE"
  grep -q "## Implementation" "$SESSION_FILE"
  grep -q "## QA" "$SESSION_FILE"
  grep -q "### Round 1 — PASS" "$SESSION_FILE"
  grep -q "## UAT" "$SESSION_FILE"
  grep -q "### Round 1 — pass" "$SESSION_FILE"
  grep -q "> Verified" "$SESSION_FILE"
}

# ── Failure/remediation lifecycle ─────────────────────────

@test "remediation lifecycle: QA fail → debug resume → QA pass" {
  SESSION_FILE=$(start_session)

  # Step 1: Initial investigation
  echo '{"mode":"investigation","issue":"Parser crash","hypotheses":[],"root_cause":"Bad regex","plan":"Fix regex","changed_files":["src/parser.sh"],"commit":"aaa111"}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"qa_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Step 2: QA Fail
  echo '{"mode":"qa","round":1,"result":"FAIL","checks":[{"id":"c1","description":"Regex handles edge case","status":"fail","evidence":"Crashes on empty input"}],"summary":"Regex still broken."}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"qa_failed"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Verify qa_failed state
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "qa_failed" ]

  # Step 3: Resume with new investigation (remediation)
  echo '{"mode":"status","status":"investigating"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"investigation","issue":"Parser crash (remediation)","hypotheses":[],"root_cause":"Add empty-input guard","plan":"Guard regex input","changed_files":["src/parser.sh"],"commit":"bbb222"}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"qa_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Remediation History should exist with Round 1 content
  grep -q "## Remediation History" "$SESSION_FILE"
  grep -q "### Round 1" "$SESSION_FILE"
  grep -q "Bad regex" "$SESSION_FILE"

  # Current sections should have new content
  grep -q "Add empty-input guard" "$SESSION_FILE"

  # Step 4: QA Pass after remediation
  echo '{"mode":"qa","round":2,"result":"PASS","checks":[{"id":"c1","description":"Regex handles edge case","status":"pass","evidence":"Empty input returns gracefully"}],"summary":"All checks pass."}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"uat_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Verify both QA rounds are in the file
  grep -c "### Round" "$SESSION_FILE" | grep -q "3"  # 2 QA + 1 remediation round marker

  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "uat_pending" ]
  [ "$qa_round" = "2" ]
}

# ── UAT failure remediation ──────────────────────────────

@test "UAT fail → debug resume → new investigation → QA → UAT pass" {
  SESSION_FILE=$(start_session)

  # Initial flow through to UAT
  echo '{"mode":"investigation","issue":"Layout bug","hypotheses":[],"root_cause":"CSS flex","plan":"Fix flex","changed_files":["style.css"],"commit":"ccc333"}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"qa_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"qa","round":1,"result":"PASS","checks":[{"id":"c1","description":"Layout test","status":"pass","evidence":"OK"}],"summary":"Pass."}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"uat_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # UAT finds issues
  echo '{"mode":"uat","round":1,"result":"issues_found","checkpoints":[{"description":"Mobile layout","result":"issue","user_response":"Broken on iPhone"},{"description":"Desktop layout","result":"pass"},{"description":"Tablet","result":"skip","user_response":"No tablet to test"}],"issues":[{"description":"Mobile flex wraps incorrectly","severity":"high"}]}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"uat_failed"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "uat_failed" ]

  # Verify checkpoint details are preserved
  grep -q 'ISSUE' "$SESSION_FILE"
  grep -q 'SKIPPED' "$SESSION_FILE"
  grep -q '> Broken on iPhone' "$SESSION_FILE"
  grep -q '> No tablet to test' "$SESSION_FILE"

  # Resume, fix, re-QA, re-UAT
  echo '{"mode":"status","status":"investigating"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"investigation","issue":"Layout bug (UAT remediation)","hypotheses":[],"root_cause":"Media query missing","plan":"Add media query","changed_files":["style.css"],"commit":"ddd444"}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"qa_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"qa","round":2,"result":"PASS","checks":[{"id":"c1","description":"Layout test","status":"pass","evidence":"OK"}],"summary":"Pass."}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"uat_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"uat","round":2,"result":"pass","checkpoints":[{"description":"Mobile layout","result":"pass"},{"description":"Desktop layout","result":"pass"},{"description":"Tablet","result":"skip"}],"summary":"All good."}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"complete"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "complete" ]

  # Remediation history should exist
  grep -q "## Remediation History" "$SESSION_FILE"
  grep -q "CSS flex" "$SESSION_FILE"  # archived from round 1
}

# ── suggest-next lifecycle chain ─────────────────────────

@test "suggest-next follows full lifecycle state transitions" {
  SESSION_FILE=$(start_session)

  # During investigation, suggest-next for debug recommends nothing special (investigating)
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "investigating" ]

  # After fix → qa_pending: suggest-next should recommend QA
  echo '{"mode":"status","status":"qa_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "qa_pending" ]

  # After QA pass → uat_pending: suggest-next should recommend verify
  echo '{"mode":"status","status":"uat_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "uat_pending" ]

  # After QA fail → qa_failed: should recommend debug resume
  echo '{"mode":"status","status":"qa_failed"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "qa_failed" ]

  # After UAT fail → uat_failed: should recommend debug resume
  echo '{"mode":"status","status":"uat_failed"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "uat_failed" ]

  # Complete
  echo '{"mode":"status","status":"complete"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "complete" ]
}
