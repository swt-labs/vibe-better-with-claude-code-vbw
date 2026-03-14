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
  [[ "$output" == "uat_resume=P02-T1 uat_completed=2 uat_total=4" ]]
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
  [[ "$output" == "uat_resume=P01-T1 uat_completed=0 uat_total=2" ]]
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
  [[ "$output" == "uat_resume=P02-T1 uat_completed=2 uat_total=3" ]]
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
  mkdir -p "$PHASE_DIR/remediation/round-01"
  mkdir -p "$PHASE_DIR/remediation/round-02"
  printf 'stage=verify\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  cat > "$PHASE_DIR/remediation/round-01/R01-UAT.md" <<'EOF'
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
  mkdir -p "$PHASE_DIR/remediation/round-01"
  mkdir -p "$PHASE_DIR/remediation/round-02"
  printf 'stage=verify\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  cat > "$PHASE_DIR/remediation/round-01/R01-UAT.md" <<'EOF'
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

  cat > "$PHASE_DIR/remediation/round-02/R02-UAT.md" <<'EOF'
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

@test "extract-uat-resume: round-dir current round UAT all_done returns correct counts" {
  # Round 02 UAT has all tests completed.
  mkdir -p "$PHASE_DIR/remediation/round-02"
  printf 'stage=verify\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  cat > "$PHASE_DIR/remediation/round-02/R02-UAT.md" <<'EOF'
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
