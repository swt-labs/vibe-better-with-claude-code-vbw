#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# --- finalize-uat-status.sh tests ---

create_uat_file() {
  local path="$1"
  cat > "$path"
}

@test "finalize-uat-status: all pass results → status=complete" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-23
completed:
total_tests: 2
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:** pass
- **Issue:**

### P01-T2: Test two

- **Result:** pass
- **Issue:**
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=complete"* ]]
  [[ "$output" == *"passed=2"* ]]
  [[ "$output" == *"issues=0"* ]]
  # Verify frontmatter was updated
  grep -q "^status: complete" "$uat"
  grep -q "^passed: 2" "$uat"
}

@test "finalize-uat-status: issue result → status=issues_found" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-23
completed:
total_tests: 2
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:** pass
- **Issue:**

### P02-T1: Test two

- **Result:** issue
- **Issue:** Something is broken
  - Description: Something is broken
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=issues_found"* ]]
  [[ "$output" == *"passed=1"* ]]
  [[ "$output" == *"issues=1"* ]]
  grep -q "^status: issues_found" "$uat"
}

@test "finalize-uat-status: FAIL result → status=issues_found" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-23
completed:
total_tests: 2
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:** pass
- **Issue:**

### P02-T1: Test two

- **Result:** FAIL
- **Issue:** Post-auth redirect hangs
  - Description: Post-auth redirect hangs
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=issues_found"* ]]
  [[ "$output" == *"issues=1"* ]]
  grep -q "^status: issues_found" "$uat"
}

@test "finalize-uat-status: PARTIAL result → status=issues_found" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-23
completed:
total_tests: 1
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:** PARTIAL — dismissal works, completion blocked
- **Issue:** Could not verify completion
  - Description: Could not verify completion
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=issues_found"* ]]
  [[ "$output" == *"issues=1"* ]]
  grep -q "^status: issues_found" "$uat"
}

@test "finalize-uat-status: empty results → status=in_progress" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-23
completed:
total_tests: 2
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:**
- **Issue:**

### P01-T2: Test two

- **Result:**
- **Issue:**
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=in_progress"* ]]
  grep -q "^status: in_progress" "$uat"
  # F-01/F-06: completed date must NOT be set for in_progress
  ! grep -q "^completed: 20" "$uat"
}

@test "finalize-uat-status: zero test entries → status=in_progress" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-23
completed:
total_tests: 0
passed: 0
skipped: 0
issues: 0
---

## Tests
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=in_progress"* ]]
  [[ "$output" == *"total=0"* ]]
  grep -q "^status: in_progress" "$uat"
  # completed must NOT be set
  ! grep -q "^completed: 20" "$uat"
}

@test "finalize-uat-status: PASS (uppercase) result → status=complete" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-23
completed:
total_tests: 1
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:** PASS
- **Issue:**
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=complete"* ]]
  [[ "$output" == *"passed=1"* ]]
  grep -q "^status: complete" "$uat"
}

@test "finalize-uat-status: mixed pass and skip → status=complete" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-23
completed:
total_tests: 2
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:** pass
- **Issue:**

### P01-T2: Test two

- **Result:** skip
- **Issue:**
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=complete"* ]]
  [[ "$output" == *"passed=1"* ]]
  [[ "$output" == *"skipped=1"* ]]
  grep -q "^status: complete" "$uat"
}

@test "finalize-uat-status: updates completed date" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-23
completed:
total_tests: 1
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:** pass
- **Issue:**
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  # Completed date should be today's date
  local today
  today=$(date +%Y-%m-%d)
  grep -q "^completed: $today" "$uat"
}

@test "finalize-uat-status: missing file errors" {
  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "/nonexistent/file.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error"* ]]
}

# --- finalize-uat-status.sh robustness: edge-case Result values ---

@test "finalize-uat-status: Result with leading whitespace → pass" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-27
total_tests: 1
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:**  pass
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"passed=1"* ]]
  [[ "$output" == *"status=complete"* ]]
}

@test "finalize-uat-status: Result 'passed!' with trailing punctuation → pass" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-27
total_tests: 1
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:** passed!
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"passed=1"* ]]
  [[ "$output" == *"status=complete"* ]]
}

@test "finalize-uat-status: Result with checkmark decorator → pass" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-27
total_tests: 1
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:** ✓ pass
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"passed=1"* ]]
  [[ "$output" == *"status=complete"* ]]
}

@test "finalize-uat-status: Result 'Pass' mixed case → pass" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-27
total_tests: 2
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:** Pass

### P01-T2: Test two

- **Result:** PASSED
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"passed=2"* ]]
  [[ "$output" == *"status=complete"* ]]
}

@test "finalize-uat-status: unrecognized Result value fails closed without rewriting frontmatter" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-27
completed:
total_tests: 2
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Broken token

- **Result:** `a``

### P01-T2: Empty-ish token

- **Result:** ````
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unrecognized Result value"* ]]
  grep -q '^status: in_progress' "$uat"
  grep -q '^passed: 0' "$uat"
  grep -q '^skipped: 0' "$uat"
  grep -q '^issues: 0' "$uat"
}

@test "finalize-uat-status: missing Result line in a test block fails closed without rewriting frontmatter" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-27
completed:
total_tests: 2
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Missing result

- **Expected:** Something should happen

### P01-T2: Valid result

- **Result:** pass
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing Result line"* ]]
  grep -q '^status: in_progress' "$uat"
  grep -q '^passed: 0' "$uat"
  grep -q '^skipped: 0' "$uat"
  grep -q '^issues: 0' "$uat"
}

@test "finalize-uat-status: injects completed date when field missing from frontmatter" {
  local uat="$TEST_TEMP_DIR/01-UAT.md"
  create_uat_file "$uat" <<'EOF'
---
phase: 01
plan_count: 1
status: in_progress
started: 2026-03-27
total_tests: 1
passed: 0
skipped: 0
issues: 0
---

## Tests

### P01-T1: Test one

- **Result:** pass
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$uat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=complete"* ]]
  local today
  today=$(date +%Y-%m-%d)
  grep -q "^completed: $today" "$uat"
}

# --- extract-uat-issues.sh lenient parsing tests ---

create_uat_phase() {
  local phase_dir="$1"
  local uat_file="$2"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/$uat_file"
}

@test "extract-uat-issues: parses Result: FAIL as an issue" {
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  create_uat_phase "$dir" "01-UAT.md" <<'EOF'
---
phase: 01
plan_count: 1
status: issues_found
started: 2026-03-23
completed: 2026-03-23
total_tests: 2
passed: 1
skipped: 0
issues: 1
---

## Tests

### P01-T1: App launches correctly

- **Result:** pass
- **Issue:**

### P02-T1: Portal loads

- **Result:** FAIL
- **Issue:** Post-auth spinner hangs
  - Description: Post-auth spinner hangs after credential entry
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_issues_total=1"* ]]
  [[ "$output" == *"P02-T1|major|"* ]]
}

@test "extract-uat-issues: parses Result: PARTIAL as an issue" {
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  create_uat_phase "$dir" "01-UAT.md" <<'EOF'
---
phase: 01
plan_count: 1
status: issues_found
started: 2026-03-23
completed: 2026-03-23
total_tests: 1
passed: 0
skipped: 0
issues: 1
---

## Tests

### P02-T2: Connection flow

- **Result:** PARTIAL — dismissal works, completion blocked
- **Issue:** Connection completion blocked by T1
  - Description: Connection completion blocked by T1
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_issues_total=1"* ]]
  [[ "$output" == *"P02-T2|major|"* ]]
}

@test "extract-uat-issues: parses Result: issue (backward compat)" {
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  create_uat_phase "$dir" "01-UAT.md" <<'EOF'
---
phase: 01
plan_count: 1
status: issues_found
started: 2026-03-23
completed: 2026-03-23
total_tests: 1
passed: 0
skipped: 0
issues: 1
---

## Tests

### P01-T1: Test one

- **Result:** issue
- **Issue:**
  - Description: Something is broken
  - Severity: critical
EOF

  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_issues_total=1"* ]]
  [[ "$output" == *"P01-T1|critical|Something is broken"* ]]
}

@test "extract-uat-issues: extracts inline Issue text as fallback description" {
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  create_uat_phase "$dir" "01-UAT.md" <<'EOF'
---
phase: 01
plan_count: 1
status: issues_found
started: 2026-03-23
completed: 2026-03-23
total_tests: 1
passed: 0
skipped: 0
issues: 1
---

## Tests

### P02-T1: Portal loads

- **Result:** FAIL
- **Issue:** Post-auth spinner hangs after credential entry
EOF

  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_issues_total=1"* ]]
  [[ "$output" == *"P02-T1|major|Post-auth spinner hangs after credential entry"* ]]
}

@test "extract-uat-issues: infers severity from keywords when missing" {
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  create_uat_phase "$dir" "01-UAT.md" <<'EOF'
---
phase: 01
plan_count: 1
status: issues_found
started: 2026-03-23
completed: 2026-03-23
total_tests: 1
passed: 0
skipped: 0
issues: 1
---

## Tests

### P01-T1: Test crash

- **Result:** issue
- **Issue:** The app crashes on launch
EOF

  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"P01-T1|critical|The app crashes on launch"* ]]
}

@test "extract-uat-issues: handles real-world UAT format from session 91fb3274" {
  # Replicates the exact format that caused the original failure
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-snap"
  create_uat_phase "$dir" "01-UAT.md" <<'EOF'
---
phase: 01
plan_count: 2
status: issues_found
started: 2026-03-23
completed: 2026-03-23
total_tests: 3
passed: 1
skipped: 0
issues: 2
---

# Phase 01: SnapTrade WebView Migration — UAT

## Tests

### P01-T1: App launches with existing data intact

- **Plan:** 01 — Extract ConnectionResult
- **Scenario:** Launch the app
- **Expected:** All accounts appear
- **Result:** PASS
- **Issue:**

### P02-T1: SnapTrade connection portal loads and is interactive

- **Plan:** 02 — Rewrite SnapTradeWebView
- **Scenario:** Navigate to connection flow
- **Expected:** SnapTrade portal loads
- **Result:** FAIL
- **Issue:** After selecting Coinbase and entering credentials, the portal shows a spinning wheel that never resolves.

### P02-T2: Connection flow handles completion events correctly

- **Plan:** 02 — Rewrite SnapTradeWebView
- **Scenario:** Test connection completion
- **Expected:** Completing a connection shows account selection
- **Result:** PARTIAL — dismissal works, completion blocked
- **Issue:** Dismissing the sheet works. However, completing a connection could not be tested — blocked by P02-T1 spinner issue.
EOF

  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_issues_total=2"* ]]
  # Both FAIL and PARTIAL should be extracted
  [[ "$output" == *"P02-T1|"* ]]
  [[ "$output" == *"P02-T2|"* ]]
}

@test "extract-uat-issues: pipe chars in description are sanitized" {
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  create_uat_phase "$dir" "01-UAT.md" <<'EOF'
---
phase: 01
plan_count: 1
status: issues_found
started: 2026-03-23
completed: 2026-03-23
total_tests: 1
passed: 0
skipped: 0
issues: 1
---

## Tests

### P01-T1: Portal error

- **Result:** issue
- **Issue:** Portal shows A | B error code
  - Description: Portal shows A | B error code
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_issues_total=1"* ]]
  # Description should have pipes replaced with dashes
  [[ "$output" == *"P01-T1|major|Portal shows A - B error code"* ]]
}

# --- F-04/F-05: stale completed date is cleared for in_progress ---

@test "finalize-uat-status: clears stale completed date when status becomes in_progress" {
  local dir="$BATS_TEST_TMPDIR/f04"
  mkdir -p "$dir"
  cat > "$dir/01-UAT.md" << 'EOF'
---
status: issues_found
completed: 2026-01-15
passed: 2
skipped: 0
issues: 1
total_tests: 3
---

## Tests

### P01-T1: Feature A

- **Result:** pass

### P01-T2: Feature B

- **Result:**

### P01-T3: Feature C

- **Result:** pass
EOF

  run bash "$SCRIPTS_DIR/finalize-uat-status.sh" "$dir/01-UAT.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=in_progress"* ]]

  # Completed date must be cleared, not preserved from previous state
  run grep '^completed:' "$dir/01-UAT.md"
  [ "$status" -eq 0 ]
  [[ "$output" == "completed:" ]]
}

# --- F-06: verified state preserves current_uat() discoverability ---

@test "current_uat discovers round-dir UAT when stage=verified" {
  local dir="$BATS_TEST_TMPDIR/f06/01-feature"
  mkdir -p "$dir/remediation/uat/round-02"

  # Write a state file with stage=verified (post-successful re-verification)
  printf 'stage=verified\nround=02\nlayout=round-dir\n' > "$dir/remediation/uat/.uat-remediation-stage"

  # Write the passing round-dir UAT
  cat > "$dir/remediation/uat/round-02/R02-UAT.md" << 'EOF'
---
status: complete
completed: 2026-03-21
passed: 3
skipped: 0
issues: 0
total_tests: 3
---
EOF

  # current_uat should find the round-dir UAT via the state file
  source "$SCRIPTS_DIR/uat-utils.sh"
  result=$(current_uat "$dir")
  [ -n "$result" ]
  [[ "$result" == *"R02-UAT.md" ]]
}

# --- F-03: extract_round_issue_ids matches FAIL/PARTIAL/failed ---

@test "extract_round_issue_ids matches FAIL, PARTIAL, and failed Result values" {
  local uat="$BATS_TEST_TMPDIR/f03-uat.md"
  cat > "$uat" << 'EOF'
---
status: issues_found
---

## Tests

### P01-T1: Feature A

- **Result:** FAIL

### P01-T2: Feature B

- **Result:** PARTIAL (needs rework)

### P01-T3: Feature C

- **Result:** failed

### P01-T4: Feature D

- **Result:** pass
EOF

  source "$SCRIPTS_DIR/uat-utils.sh"
  result=$(extract_round_issue_ids "$uat")
  # Should match all three non-pass entries
  [[ "$result" == *"P01-T1"* ]]
  [[ "$result" == *"P01-T2"* ]]
  [[ "$result" == *"P01-T3"* ]]
  # Should NOT match the passing entry
  [[ "$result" != *"P01-T4"* ]]
}
