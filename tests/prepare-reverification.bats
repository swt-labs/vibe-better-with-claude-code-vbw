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

# Helper: create a UAT file with issues_found status at the phase root
create_issues_uat() {
  cat > "$PHASE_DIR/03-UAT.md" <<'EOF'
---
phase: "03"
status: issues_found
total_tests: 3
passed: 2
failed: 1
---
# UAT — Phase 03

## Test 1
- **Result:** pass

## Test 2
- **Result:** issue — broken layout
EOF
}

@test "round-dir layout: archives UAT and advances to verify without changing round" {
  create_issues_uat

  # Create round-dir remediation state with stage=done
  mkdir -p "$PHASE_DIR/remediation/round-01"
  printf 'stage=done\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  touch "$PHASE_DIR/remediation/round-01/R01-PLAN.md"
  touch "$PHASE_DIR/remediation/round-01/R01-SUMMARY.md"

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]

  # UAT was archived
  [ ! -f "$PHASE_DIR/03-UAT.md" ]
  archived_file=$(find "$PHASE_DIR" -maxdepth 1 -name '03-UAT-round-*.md' | head -1)
  [ -n "$archived_file" ]

  # Stage is verify — NOT advanced to research/round-02
  grep -q "^stage=verify$" "$PHASE_DIR/remediation/.uat-remediation-stage"

  # Round is still 01
  grep -q "^round=01$" "$PHASE_DIR/remediation/.uat-remediation-stage"

  # Output includes layout=round-dir
  [[ "$output" == *"layout=round-dir"* ]]
}

@test "flat layout: archives UAT and advances to next round" {
  create_issues_uat

  # Create flat/legacy remediation state (in new location but without layout)
  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]

  # UAT was archived
  [ ! -f "$PHASE_DIR/03-UAT.md" ]

  # Flat layout calls needs-round — stage should be research, round incremented
  grep -q "^stage=research$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^round=02$" "$PHASE_DIR/remediation/.uat-remediation-stage"

  # Output includes layout=flat
  [[ "$output" == *"layout=flat"* ]]
}

@test "round-dir layout: phase-root UAT absent exits 0 with skip marker" {
  # No UAT file exists (already archived)
  mkdir -p "$PHASE_DIR/remediation/round-01"
  printf 'stage=done\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped=already_archived"* ]]
}

@test "refuses to archive when UAT status is not issues_found" {
  # Create a passing UAT
  cat > "$PHASE_DIR/03-UAT.md" <<'EOF'
---
phase: "03"
status: complete
total_tests: 3
passed: 3
failed: 0
---
# UAT — Phase 03
EOF

  mkdir -p "$PHASE_DIR/remediation"
  printf 'stage=done\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$PHASE_DIR"

  [ "$status" -eq 1 ]
  [[ "$output" == *"not 'issues_found'"* ]]
}

@test "round-dir layout: round-dir UAT found via current_uat skips mv" {
  mkdir -p "$PHASE_DIR/remediation/round-01"
  printf 'stage=done\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  cat > "$PHASE_DIR/remediation/round-01/R01-UAT.md" <<'EOF'
---
phase: "03"
status: issues_found
total_tests: 3
passed: 2
failed: 1
---
# UAT — Remediation Round 01
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]

  # R01-UAT.md still exists (NOT mv'd)
  [ -f "$PHASE_DIR/remediation/round-01/R01-UAT.md" ]

  # Output indicates in-round-dir archival
  [[ "$output" == *"archived=in-round-dir"* ]]

  # State advanced to next round
  grep -q "^stage=research$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^round=02$" "$PHASE_DIR/remediation/.uat-remediation-stage"
}

@test "round-dir layout: previous round UAT skipped when current round has no UAT" {
  # Round 02 is current, stage=done, but only R01-UAT.md exists (from round 01).
  # No R02-UAT.md yet — prepare-reverification should NOT archive or advance rounds.
  mkdir -p "$PHASE_DIR/remediation/round-01" "$PHASE_DIR/remediation/round-02"
  printf 'stage=done\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  touch "$PHASE_DIR/remediation/round-01/R01-PLAN.md"
  touch "$PHASE_DIR/remediation/round-01/R01-SUMMARY.md"
  touch "$PHASE_DIR/remediation/round-02/R02-PLAN.md"
  touch "$PHASE_DIR/remediation/round-02/R02-SUMMARY.md"
  cat > "$PHASE_DIR/remediation/round-01/R01-UAT.md" <<'EOF'
---
phase: "03"
status: issues_found
total_tests: 3
passed: 2
failed: 1
---
# UAT — Remediation Round 01
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]

  # Output should indicate skipped (ready for verify), NOT archived
  [[ "$output" == *"skipped=ready_for_verify"* ]]
  [[ "$output" != *"archived=in-round-dir"* ]]

  # State should be verify (advanced from done), NOT research/round=03
  grep -q "^stage=verify$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  # Round stays at 02 — NOT bumped to 03
  grep -q "^round=02$" "$PHASE_DIR/remediation/.uat-remediation-stage"

  # R01-UAT.md still exists untouched
  [ -f "$PHASE_DIR/remediation/round-01/R01-UAT.md" ]
}

@test "round-dir layout: stage=verify accepted when current round UAT has issues" {
  # Round 01, stage=verify, R01-UAT.md with issues — should archive and advance to round 02
  mkdir -p "$PHASE_DIR/remediation/round-01"
  printf 'stage=verify\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/.uat-remediation-stage"
  cat > "$PHASE_DIR/remediation/round-01/R01-UAT.md" <<'EOF'
---
phase: "03"
status: issues_found
total_tests: 3
passed: 2
failed: 1
---
# UAT — Remediation Round 01
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]

  # Output indicates in-round-dir archival
  [[ "$output" == *"archived=in-round-dir"* ]]

  # State advanced to next round (round-02, stage=research)
  grep -q "^stage=research$" "$PHASE_DIR/remediation/.uat-remediation-stage"
  grep -q "^round=02$" "$PHASE_DIR/remediation/.uat-remediation-stage"
}
