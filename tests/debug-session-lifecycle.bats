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

# Helper: assert generated markdown does not accumulate repeated blank lines
assert_no_repeated_blank_lines() {
  local file="$1"
  run awk '
    BEGIN { blank_run = 0 }
    /^[[:space:]]*$/ {
      blank_run++
      if (blank_run > 1) {
        printf "repeated blank lines ending at line %d\n", NR
        exit 1
      }
      next
    }
    { blank_run = 0 }
  ' "$file"
  [ "$status" -eq 0 ]
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
  # Use set-status for complete transition (handles move to completed/ and pointer cleanup)
  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$PLANNING_DIR" complete > /dev/null

  # set-status complete moves session from active/ to completed/
  SESSION_FILE="$PLANNING_DIR/debugging/completed/$(basename "$SESSION_FILE")"
  [ -f "$SESSION_FILE" ]
  [[ "$SESSION_FILE" == *"/debugging/completed/"* ]]
  grep -q '^status: complete$' "$SESSION_FILE"

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
  echo '{"mode":"uat","round":1,"result":"issues_found","checkpoints":[{"description":"Mobile layout","result":"issue","user_response":"Broken on iPhone"},{"description":"Desktop layout","result":"pass"},{"description":"Tablet","result":"skip","user_response":"No tablet to test"}],"issues":[{"description":"Mobile flex wraps incorrectly","severity":"major"}]}' \
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

  # Use set-status for complete transition (handles move to completed/ and pointer cleanup)
  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$PLANNING_DIR" complete > /dev/null

  # set-status complete moves session from active/ to completed/
  SESSION_FILE="$PLANNING_DIR/debugging/completed/$(basename "$SESSION_FILE")"
  [ -f "$SESSION_FILE" ]
  [[ "$SESSION_FILE" == *"/debugging/completed/"* ]]
  grep -q '^status: complete$' "$SESSION_FILE"

  # Remediation history should exist
  grep -q "## Remediation History" "$SESSION_FILE"
  grep -q "CSS flex" "$SESSION_FILE"  # archived from round 1
}

@test "write-debug-session normalizes blank lines across repeated lifecycle transitions" {
  SESSION_FILE=$(start_session)
  ROOT_CAUSE_PADDING=$'\n\nRoot cause paragraph one\n\nRoot cause paragraph two\n\n'
  QA_SUMMARY_PADDING=$'\n\nQA summary paragraph one\n\nQA summary paragraph two\n\n'
  UAT_SUMMARY_PADDING=$'\n\nUAT summary paragraph one\n\nUAT summary paragraph two\n\n'

  jq -n \
    --arg root_cause "$ROOT_CAUSE_PADDING" \
    '{mode:"investigation", issue:"Spacing repro", hypotheses:[], root_cause:$root_cause, plan:"Normalize spacing", changed_files:["scripts/write-debug-session.sh"], commit:"aaa111"}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"qa_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  jq -n \
    --arg summary "$QA_SUMMARY_PADDING" \
    '{mode:"qa", round:1, result:"FAIL", checks:[{id:"c1", description:"first qa", status:"fail", evidence:"e1"}], summary:$summary}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"qa_failed"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  echo '{"mode":"status","status":"investigating"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  jq -n \
    --arg root_cause "$ROOT_CAUSE_PADDING" \
    '{mode:"investigation", issue:"Spacing repro remediation", hypotheses:[], root_cause:$root_cause, plan:"Normalize spacing", changed_files:["scripts/write-debug-session.sh"], commit:"bbb222"}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"qa_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  jq -n \
    --arg summary "$QA_SUMMARY_PADDING" \
    '{mode:"qa", round:2, result:"PASS", checks:[{id:"c2", description:"second qa", status:"pass", evidence:"e2"}], summary:$summary}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"uat_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  jq -n \
    --arg summary "$UAT_SUMMARY_PADDING" \
    '{mode:"uat", round:1, result:"issues_found", checkpoints:[{description:"checkpoint 1", result:"issue", user_response:"needs fix"}], issues:[{description:"uat issue", severity:"major"}], summary:$summary}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  grep -q "### Round 2 — PASS" "$SESSION_FILE"
  grep -q "## UAT" "$SESSION_FILE"
  grep -q "## Remediation History" "$SESSION_FILE"
  run awk '
    /^### Root Cause$/ {
      getline
      if ($0 != "") {
        print "expected exactly one blank line after Root Cause heading"
        exit 1
      }
      getline
      if ($0 != "Root cause paragraph one") {
        print "unexpected first root cause paragraph: " $0
        exit 1
      }
      getline
      if ($0 != "") {
        print "expected preserved paragraph break inside root cause"
        exit 1
      }
      getline
      if ($0 != "Root cause paragraph two") {
        print "unexpected second root cause paragraph: " $0
        exit 1
      }
      found = 1
      exit 0
    }
    END {
      if (!found) {
        print "Root Cause heading not found"
        exit 1
      }
    }
  ' "$SESSION_FILE"
  [ "$status" -eq 0 ]
  run awk '
    $0 == "QA summary paragraph one" {
      if (previous != "") {
        print "expected exactly one blank line before QA summary"
        exit 1
      }
      getline
      if ($0 != "") {
        print "expected preserved paragraph break inside QA summary"
        exit 1
      }
      getline
      if ($0 != "QA summary paragraph two") {
        print "unexpected second QA summary paragraph: " $0
        exit 1
      }
      found = 1
      exit 0
    }
    { previous = $0 }
    END {
      if (!found) {
        print "QA summary paragraph not found"
        exit 1
      }
    }
  ' "$SESSION_FILE"
  [ "$status" -eq 0 ]
  assert_no_repeated_blank_lines "$SESSION_FILE"
}

# ── suggest-next lifecycle chain ─────────────────────────

@test "suggest-next follows full lifecycle state transitions" {
  export VBW_PLANNING_DIR="$PLANNING_DIR"
  SESSION_FILE=$(start_session)

  # During investigation, suggest-next for debug recommends nothing special (investigating)
  eval "$(bash "$SCRIPTS_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null)"
  [ "$status" = "investigating" ]

  # After fix → qa_pending: suggest-next for debug should recommend inline QA via resume
  echo '{"mode":"status","status":"qa_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  run bash "$SCRIPTS_DIR/suggest-next.sh" debug
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:debug --resume"* ]]
  [[ "$output" == *"Continue to QA verification"* ]]

  # After QA pass → uat_pending: suggest-next for qa pass should recommend inline UAT via resume
  echo '{"mode":"status","status":"uat_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:debug --resume"* ]]
  [[ "$output" == *"Continue to UAT verification"* ]]

  # After QA fail → qa_failed: suggest-next for qa fail should recommend debug resume
  echo '{"mode":"status","status":"qa_failed"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  run bash "$SCRIPTS_DIR/suggest-next.sh" qa fail
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:debug --resume"* ]]

  # After UAT fail → uat_failed: suggest-next for verify should recommend debug resume
  echo '{"mode":"status","status":"uat_failed"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  run bash "$SCRIPTS_DIR/suggest-next.sh" verify fail
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:debug --resume"* ]]

  # Complete — use set-status for proper move to completed/
  bash "$SCRIPTS_DIR/debug-session-state.sh" set-status "$PLANNING_DIR" complete > /dev/null
  # Verify session moved to completed/
  [ -f "$PLANNING_DIR/debugging/completed/$(basename "$SESSION_FILE")" ]
}

# ── compile-debug-session-context produces usable output ──

@test "compile-debug-session-context extracts QA failure context for resume handoff" {
  SESSION_FILE=$(start_session)

  # Populate investigation + QA failure
  echo '{"mode":"investigation","issue":"Crash on save","hypotheses":[{"description":"Race condition","status":"confirmed","evidence_for":"Thread dump","evidence_against":"","conclusion":"Confirmed"}],"root_cause":"Missing lock","plan":"Add mutex","changed_files":["src/save.sh"],"commit":"fff000"}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"qa_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"qa","round":1,"result":"FAIL","checks":[{"id":"c1","description":"Lock acquired before write","status":"fail","evidence":"No lock call in save path"}],"summary":"Missing lock acquisition."}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"qa_failed"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Compile QA context
  run bash "$SCRIPTS_DIR/compile-debug-session-context.sh" "$SESSION_FILE" qa
  [ "$status" -eq 0 ]
  [[ "$output" == *"Debug Session QA Context"* ]]
  [[ "$output" == *"Crash on save"* ]]
  [[ "$output" == *"Missing lock"* ]]
  [[ "$output" == *"Prior QA Rounds"* ]]
  [[ "$output" == *"FAIL"* ]]
}

@test "compile-debug-session-context extracts UAT failure context for resume handoff" {
  SESSION_FILE=$(start_session)

  # Populate through QA pass + UAT failure
  echo '{"mode":"investigation","issue":"UI misalignment","hypotheses":[],"root_cause":"Wrong margin","plan":"Fix CSS","changed_files":["style.css"],"commit":"eee111"}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"qa_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"qa","round":1,"result":"PASS","checks":[{"id":"c1","description":"Margin correct","status":"pass","evidence":"OK"}],"summary":"Pass."}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"uat_pending"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"uat","round":1,"result":"issues_found","checkpoints":[{"description":"Header alignment","result":"issue","user_response":"Still off by 2px"}],"issues":[{"description":"Header offset","severity":"major"}]}' \
    | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"
  echo '{"mode":"status","status":"uat_failed"}' | bash "$SCRIPTS_DIR/write-debug-session.sh" "$SESSION_FILE"

  # Compile UAT context
  run bash "$SCRIPTS_DIR/compile-debug-session-context.sh" "$SESSION_FILE" uat
  [ "$status" -eq 0 ]
  [[ "$output" == *"Debug Session UAT Context"* ]]
  [[ "$output" == *"UI misalignment"* ]]
  [[ "$output" == *"Prior UAT Rounds"* ]]
  [[ "$output" == *"issues_found"* ]]
}
