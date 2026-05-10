#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/03-test-phase"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  teardown_temp_dir
}

# Helper: create a UAT file with given content
create_uat_file() {
  local content="$1"
  printf '%s\n' "$content" > "$PHASE_DIR/03-UAT.md"
}

assert_output_has_line() {
  local expected="$1"
  grep -Fxq "$expected" <<< "$output"
}

assert_output_lacks_prefix() {
  local prefix="$1"
  local line

  while IFS= read -r line; do
    case "$line" in
      "$prefix"*) return 1 ;;
    esac
  done <<< "$output"

  return 0
}

@test "assert_output_lacks_prefix treats regex metacharacters literally" {
  output='uat_resume_scenario=Literal scenario field'

  assert_output_lacks_prefix 'uat_resume.scenario'
  ! assert_output_lacks_prefix 'uat_resume_scenario'
}

@test "extract-uat-resume: no UAT file returns none" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == "uat_resume=none" ]]
}

@test "extract-uat-resume: nonexistent directory returns none" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$TEST_TEMP_DIR/nonexistent"

  [ "$status" -eq 0 ]
  [[ "$output" == "uat_resume=none" ]]
}

@test "extract-uat-resume: all tests completed returns all_done" {
  create_uat_file '---
phase: 03
status: complete
total_tests: 3
passed: 3
---

## Tests

### P01-T1: First test

- **Plan:** 03-01
- **Scenario:** Check something
- **Expected:** It works
- **Result:** pass

### P01-T2: Second test

- **Plan:** 03-01
- **Scenario:** Check another
- **Expected:** It works
- **Result:** pass

### P02-T1: Third test

- **Plan:** 03-02
- **Scenario:** Check third
- **Expected:** It works
- **Result:** issue

## Summary'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == "uat_resume=all_done uat_completed=3 uat_total=3" ]]
}

@test "extract-uat-resume: partial completion returns resume ID" {
  create_uat_file '---
phase: 03
status: in_progress
total_tests: 4
---

## Tests

### P01-T1: First test

- **Plan:** 03-01
- **Scenario:** Check something
- **Expected:** It works
- **Result:** pass

### P01-T2: Second test

- **Plan:** 03-01
- **Scenario:** Check another
- **Expected:** It works
- **Result:** pass

### P02-T1: Third test

- **Plan:** 03-02
- **Scenario:** Check third
- **Expected:** It works
- **Result:**

### P02-T2: Fourth test

- **Plan:** 03-02
- **Scenario:** Check fourth
- **Expected:** It works
- **Result:**

## Summary'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  assert_output_has_line "uat_resume=P02-T1 uat_completed=2 uat_total=4"
  assert_output_has_line "uat_resume_scenario=Check third"
  assert_output_has_line "uat_resume_expected=It works"
  assert_output_lacks_prefix "uat_resume_title="
  assert_output_lacks_prefix "uat_resume_plan="
}

@test "extract-uat-resume: first test incomplete" {
  create_uat_file '---
phase: 03
status: in_progress
total_tests: 2
---

## Tests

### P01-T1: First test

- **Plan:** 03-01
- **Scenario:** Check something
- **Expected:** It works
- **Result:**

### P01-T2: Second test

- **Plan:** 03-01
- **Scenario:** Check another
- **Expected:** It works
- **Result:**

## Summary'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  assert_output_has_line "uat_resume=P01-T1 uat_completed=0 uat_total=2"
  assert_output_has_line "uat_resume_scenario=Check something"
  assert_output_has_line "uat_resume_expected=It works"
}

@test "extract-uat-resume: discovered issue entry counted" {
  create_uat_file '---
phase: 03
status: in_progress
total_tests: 3
---

## Tests

### P01-T1: First test

- **Plan:** 03-01
- **Scenario:** Check something
- **Expected:** It works
- **Result:** pass

### D1: Discovered issue

- **Plan:** (discovered during P01-T1)
- **Scenario:** User observation
- **Expected:** (not applicable)
- **Result:** issue

### P02-T1: Third test

- **Plan:** 03-02
- **Scenario:** Check third
- **Expected:** It works
- **Result:**

## Summary'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  assert_output_has_line "uat_resume=P02-T1 uat_completed=2 uat_total=3"
  assert_output_has_line "uat_resume_scenario=Check third"
  assert_output_has_line "uat_resume_expected=It works"
}

@test "extract-uat-resume: summary-deviation checkpoint emits deviation metadata only" {
  create_uat_file '---
phase: 03
status: in_progress
total_tests: 3
---

## Tests

### D01: Review summary deviation

- **Source:** Summary deviation review
- **Deviation Signature:** abc123
- **Source Plan:** 03-02
- **Source Summary:** remediation/uat/round-06/R06-SUMMARY.md
- **Deviation:** Summary documented a different refresh path than the plan.
- **Scenario:** Generic scenario that must be suppressed for summary-deviation prompts
- **Expected:** Generic expected value that must be suppressed for summary-deviation prompts
- **Result:**

### PR03-T01: Verify LCID behavior

- **Plan:** R03
- **Result:**

### P03-T02: Verify regression

- **Plan:** R03
- **Result:**'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  assert_output_has_line "uat_resume=D01 uat_completed=0 uat_total=3"
  assert_output_has_line "uat_resume_deviation=Summary documented a different refresh path than the plan."
  assert_output_has_line "uat_resume_source_plan=03-02"
  assert_output_has_line "uat_resume_source_summary=remediation/uat/round-06/R06-SUMMARY.md"
  assert_output_has_line "uat_resume_deviation_signature=abc123"
  assert_output_lacks_prefix "uat_resume_scenario="
  assert_output_lacks_prefix "uat_resume_expected="
}

@test "extract-uat-resume: D-prefixed checkpoint without deviation metadata is not summary-deviation" {
  create_uat_file '---
phase: 03
status: in_progress
total_tests: 1
---

## Tests

### D02: Discovered issue follow-up

- **Plan:** (discovered during P01-T1)
- **Scenario:** User observation needs human review
- **Expected:** The discovered issue is no longer visible
- **Result:**

## Summary'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  assert_output_has_line "uat_resume=D02 uat_completed=0 uat_total=1"
  assert_output_has_line "uat_resume_scenario=User observation needs human review"
  assert_output_has_line "uat_resume_expected=The discovered issue is no longer visible"
  assert_output_lacks_prefix "uat_resume_deviation="
  assert_output_lacks_prefix "uat_resume_source_plan="
  assert_output_lacks_prefix "uat_resume_source_summary="
  assert_output_lacks_prefix "uat_resume_deviation_signature="
}

@test "extract-uat-resume: PR-prefixed checkpoint is parsed after accepted deviation" {
  create_uat_file '---
phase: 03
status: in_progress
total_tests: 2
---

## Tests

### D01: Review summary deviation

- **Source:** Summary deviation review
- **Result:** pass
- **Disposition:** accepted-process-exception

### PR03-T01: Verify LCID behavior

- **Plan:** R03
- **Scenario:** Open LCID after remediation
- **Expected:** LCID remains visible as an active wheel
- **Result:**'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  assert_output_has_line "uat_resume=PR03-T01 uat_completed=1 uat_total=2"
  assert_output_has_line "uat_resume_scenario=Open LCID after remediation"
  assert_output_has_line "uat_resume_expected=LCID remains visible as an active wheel"
}

@test "extract-uat-resume: excludes SOURCE-UAT.md" {
  # Create a SOURCE-UAT.md (incomplete) and a real UAT (all done)
  create_uat_file '---
phase: 03
status: complete
total_tests: 1
---

## Tests

### P01-T1: Test

- **Result:** pass

## Summary'

  cat > "$PHASE_DIR/03-SOURCE-UAT.md" <<'EOF'
---
phase: 03
status: in_progress
---

### P01-T1: Test

- **Result:**
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Should use the real UAT (all done), not the SOURCE-UAT
  [[ "$output" == "uat_resume=all_done uat_completed=1 uat_total=1" ]]
}

@test "extract-uat-resume: last test missing result (no trailing section)" {
  create_uat_file '---
phase: 03
status: in_progress
total_tests: 2
---

## Tests

### P01-T1: First test

- **Result:** pass

### P01-T2: Last test

- **Result:**'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == "uat_resume=P01-T2 uat_completed=1 uat_total=2" ]]
}

@test "extract-uat-resume: round-dir current round UAT missing returns none (not stale previous round)" {
  # Round 02 has no UAT yet; round 01 has a completed UAT.
  # The script must return none (not stale all_done from round 01).
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  mkdir -p "$PHASE_DIR/remediation/uat/round-02"
  printf 'stage=verify\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"

  cat > "$PHASE_DIR/remediation/uat/round-01/R01-UAT.md" <<'EOF'
---
phase: 03
status: complete
total_tests: 2
passed: 2
---

## Tests

### P01-T1: First test

- **Result:** pass

### P01-T2: Second test

- **Result:** pass

## Summary
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == "uat_resume=none" ]]
}

@test "extract-uat-resume: round-dir current round UAT exists returns current round data" {
  # Both round 01 (all_done) and round 02 (partial) exist.
  # The script must return resume data from round 02, not round 01.
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  mkdir -p "$PHASE_DIR/remediation/uat/round-02"
  printf 'stage=verify\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"

  cat > "$PHASE_DIR/remediation/uat/round-01/R01-UAT.md" <<'EOF'
---
phase: 03
status: complete
total_tests: 2
passed: 2
---

## Tests

### P01-T1: Old test

- **Result:** pass

### P01-T2: Old test 2

- **Result:** pass

## Summary
EOF

  cat > "$PHASE_DIR/remediation/uat/round-02/R02-UAT.md" <<'EOF'
---
phase: 03
status: in_progress
total_tests: 3
---

## Tests

### P01-T1: New test

- **Result:** pass

### P01-T2: New test 2

- **Result:**

### P02-T1: New test 3

- **Result:**

## Summary
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == "uat_resume=P01-T2 uat_completed=1 uat_total=3" ]]
}

@test "extract-uat-resume: active round 06 emits product checkpoint scenario and expected" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-06"
  printf 'stage=verify\nround=06\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"

  cat > "$PHASE_DIR/remediation/uat/round-06/R06-UAT.md" <<'EOF'
---
phase: 03
status: in_progress
total_tests: 3
---

## Tests

### PR06-T01: First remediation checkpoint

- **Result:** pass

### PR06-T02: Second remediation checkpoint

- **Scenario:** In the Robinhood Roth IRA account after the same clear/full-resync and two refreshes, navigate to Wheels and open/review LCID.
- **Expected:** LCID remains visible as one active/open wheel after repeated refresh.
- **Result:**

### PR06-T03: Third remediation checkpoint

- **Scenario:** Reopen TSLA after completing the LCID check.
- **Expected:** TSLA remains available for review.
- **Result:**

## Summary
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  assert_output_has_line "uat_resume=PR06-T02 uat_completed=1 uat_total=3"
  assert_output_has_line "uat_resume_scenario=In the Robinhood Roth IRA account after the same clear/full-resync and two refreshes, navigate to Wheels and open/review LCID."
  assert_output_has_line "uat_resume_expected=LCID remains visible as one active/open wheel after repeated refresh."
  assert_output_lacks_prefix "uat_resume_title="
  assert_output_lacks_prefix "uat_resume_plan="
}

@test "extract-uat-resume: refreshed default output advances to next checkpoint context" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-06"
  printf 'stage=verify\nround=06\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"

  cat > "$PHASE_DIR/remediation/uat/round-06/R06-UAT.md" <<'EOF'
---
phase: 03
status: in_progress
total_tests: 3
---

## Tests

### PR06-T01: First remediation checkpoint

- **Result:** pass

### PR06-T02: Second remediation checkpoint

- **Scenario:** Review LCID after the second refresh.
- **Expected:** LCID remains visible as one active/open wheel.
- **Result:** pass

### PR06-T03: Third remediation checkpoint

- **Scenario:** Reopen TSLA after completing the LCID check.
- **Expected:** TSLA remains available for review.
- **Result:**

## Summary
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  assert_output_has_line "uat_resume=PR06-T03 uat_completed=2 uat_total=3"
  assert_output_has_line "uat_resume_scenario=Reopen TSLA after completing the LCID check."
  assert_output_has_line "uat_resume_expected=TSLA remains available for review."
}

@test "extract-uat-resume: round-dir current round UAT all_done returns correct counts" {
  # Round 02 UAT has all tests completed.
  mkdir -p "$PHASE_DIR/remediation/uat/round-02"
  printf 'stage=verify\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"

  cat > "$PHASE_DIR/remediation/uat/round-02/R02-UAT.md" <<'EOF'
---
phase: 03
status: complete
total_tests: 2
passed: 1
issues: 1
---

## Tests

### P01-T1: Check fix

- **Result:** pass

### P01-T2: Check other fix

- **Result:** issue

## Summary
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == "uat_resume=all_done uat_completed=2 uat_total=2" ]]
}

@test "extract-uat-resume: legacy current round UAT missing returns none" {
  mkdir -p "$PHASE_DIR/remediation/round-01" "$PHASE_DIR/remediation/round-02"
  printf 'stage=verify\nround=02\nlayout=legacy\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  cat > "$PHASE_DIR/remediation/round-01/R01-UAT.md" <<'EOF'
---
phase: 03
status: complete
total_tests: 1
passed: 1
---

## Tests

### P01-T1: Old legacy test

- **Result:** pass

## Summary
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == "uat_resume=none" ]]
}

@test "extract-uat-resume: legacy current round UAT exists returns current round data" {
  mkdir -p "$PHASE_DIR/remediation/round-01" "$PHASE_DIR/remediation/round-02"
  printf 'stage=verify\nround=02\nlayout=legacy\n' > "$PHASE_DIR/.uat-remediation-stage"

  cat > "$PHASE_DIR/remediation/round-01/R01-UAT.md" <<'EOF'
---
phase: 03
status: complete
total_tests: 1
passed: 1
---

## Tests

### P01-T1: Old legacy test

- **Result:** pass

## Summary
EOF

  cat > "$PHASE_DIR/remediation/round-02/R02-UAT.md" <<'EOF'
---
phase: 03
status: in_progress
total_tests: 2
---

## Tests

### P01-T1: New legacy test

- **Result:** pass

### P01-T2: New legacy test 2

- **Result:**

## Summary
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == "uat_resume=P01-T2 uat_completed=1 uat_total=2" ]]
}
