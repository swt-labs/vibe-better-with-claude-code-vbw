#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  export CLAUDE_SESSION_ID="phase-detect-${BATS_TEST_NUMBER:-0}-$$-$RANDOM"
  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"
  touch dummy && git add dummy && git commit -m "init" --quiet
}

teardown() {
  rm -f "/tmp/.vbw-phase-detect-${CLAUDE_SESSION_ID:-default}.txt" 2>/dev/null || true
  rm -rf "/tmp/.vbw-phase-detect-live-${CLAUDE_SESSION_ID:-default}.lock" 2>/dev/null || true
  rm -rf "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}" 2>/dev/null || true
  unset CLAUDE_SESSION_ID
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

@test "detects no planning directory" {
  rm -rf .vbw-planning
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "planning_dir_exists=false"
}

@test "detects planning directory exists" {
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "planning_dir_exists=true"
}

@test "detects no project when PROJECT.md missing" {
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "project_exists=false"
}

@test "detects project exists" {
  echo "# My Project" > .vbw-planning/PROJECT.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "project_exists=true"
}

@test "detects zero phases" {
  mkdir -p .vbw-planning/phases
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "phase_count=0"
}

@test "detects phases needing plan" {
  mkdir -p .vbw-planning/phases/01-test/
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_plan_and_execute"
}

@test "detects phases needing execution" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_execute"
}

@test "detects all phases done" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=all_done"
}

@test "reads config values" {
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "config_effort=balanced"
  echo "$output" | grep -q "config_autonomy=standard"
}

@test "detects unresolved UAT issues as next-phase remediation" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---

## Tests

### P01-T1: sample

- **Result:** issue
- **Issue:** sample
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_slug=01-test"
  echo "$output" | grep -q "uat_issues_phase=01"
  echo "$output" | grep -q "uat_issues_major_or_higher=true"
  echo "$output" | grep -q "uat_file=01-UAT.md"
}

@test "active UAT routing metadata emitted for needs_uat_remediation" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
issues: 1
---

## Tests

### P01-T1: sample test

- **Result:** issue
- **Issue:** sample issue description
  - Description: something is broken
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_issues_count=1"
  echo "$output" | grep -q "uat_file=01-UAT.md"
  ! echo "$output" | grep -q "^---UAT_EXTRACT_START---$"
}

@test "no active UAT marker block when state is not needs_uat_remediation" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "^---UAT_EXTRACT_START---$"
  echo "$output" | grep -q "uat_file=none"
}

@test "active UAT routing metadata uses round-dir relative path" {
  mkdir -p .vbw-planning/phases/01-test/remediation/uat/round-01/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md
  printf '%s\n' 'round=01' 'layout=round-dir' > .vbw-planning/phases/01-test/remediation/uat/.uat-remediation-stage
  cat > .vbw-planning/phases/01-test/remediation/uat/round-01/R01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
issues: 1
---

## Tests

### P01-T1: round-dir test

- **Result:** issue
- **Issue:** round-dir issue
  - Description: round-dir broken
  - Severity: critical
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_file=remediation/uat/round-01/R01-UAT.md"
  echo "$output" | grep -q "uat_issues_count=1"
  ! echo "$output" | grep -q "^---UAT_EXTRACT_START---$"
}

@test "active UAT routing metadata does not depend on parseable issue bodies" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md
  # UAT file with issues_found but no ### P/D test sections
  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
issues: 1
---

## Tests

Some text without parseable test headers.
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  echo "$output" | grep -q "uat_file=01-UAT.md"
  ! echo "$output" | grep -q "^---UAT_EXTRACT_START---$"
}

@test "milestone extraction preserves zero-issue parity with standalone extractor" {
  mkdir -p .vbw-planning/milestones/m01-test/phases/01-alpha/
  mkdir -p .vbw-planning/phases/
  echo '# Shipped' > .vbw-planning/milestones/m01-test/SHIPPED.md
  touch .vbw-planning/milestones/m01-test/phases/01-alpha/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/milestones/m01-test/phases/01-alpha/01-01-SUMMARY.md
  cat > .vbw-planning/milestones/m01-test/phases/01-alpha/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
issues: 0
---

## Tests

### P01-T1: all good

- **Result:** pass
EOF

  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" .vbw-planning/milestones/m01-test/phases/01-alpha
  [ "$status" -eq 0 ]
  expected="$output"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  marker=$(printf '%s\n' "$output" | awk '/^---MILESTONE_UAT_EXTRACT_START---$/{f=1; next} /^---MILESTONE_UAT_EXTRACT_END---$/{exit} f{print}' | awk '/^milestone_phase_dir=/{next} /^---$/{exit} {print}')
  [ "$marker" = "$expected" ]
  echo "$marker" | grep -q 'uat_issues_total=0'
  ! echo "$marker" | grep -q 'uat_extract_error=true'
}

@test "milestone UAT extraction emitted for milestone_uat_issues" {
  # Create a shipped milestone with UAT issues
  mkdir -p .vbw-planning/milestones/m01-test/phases/01-alpha/
  touch .vbw-planning/milestones/m01-test/phases/01-alpha/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/milestones/m01-test/phases/01-alpha/01-01-SUMMARY.md
  cat > .vbw-planning/milestones/m01-test/phases/01-alpha/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
issues: 1
---

## Tests

### P01-T1: milestone test

- **Result:** issue
- **Issue:** milestone issue
  - Description: milestone broken
  - Severity: major
EOF
  # Create an active phases dir that is empty (forces all_done → milestone recovery)
  mkdir -p .vbw-planning/phases/

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^---MILESTONE_UAT_EXTRACT_START---$"
  echo "$output" | grep -q "^---MILESTONE_UAT_EXTRACT_END---$"
  echo "$output" | grep -q "P01-T1|major|milestone broken"
}

@test "inline UAT extraction preserves FAILED_IN_ROUNDS recurrence parity" {
  mkdir -p .vbw-planning/phases/03-feature/
  touch .vbw-planning/phases/03-feature/03-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/03-feature/03-01-SUMMARY.md
  cat > .vbw-planning/phases/03-feature/03-UAT-round-01.md <<'EOF'
---
phase: 03
status: issues_found
---

## Tests

### P03-T2: recurring issue

- **Result:** issue
- **Issue:**
  - Description: still broken
  - Severity: major
EOF
  cat > .vbw-planning/phases/03-feature/03-UAT-round-02.md <<'EOF'
---
phase: 03
status: issues_found
---

## Tests

### P03-T2: recurring issue

- **Result:** issue
- **Issue:**
  - Description: still broken
  - Severity: major
EOF
  cat > .vbw-planning/phases/03-feature/03-UAT.md <<'EOF'
---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P03-T2: recurring issue

- **Result:** issue
- **Issue:**
  - Description: still broken
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  echo "$output" | grep -q "uat_issues_count=1"
  echo "$output" | grep -q "uat_file=03-UAT.md"
  echo "$output" | grep -q "uat_round_count=2"
  ! echo "$output" | grep -q "^---UAT_EXTRACT_START---$"
}

@test "milestone UAT extraction preserves FAILED_IN_ROUNDS recurrence parity" {
  mkdir -p .vbw-planning/milestones/m01-test/phases/03-feature/
  mkdir -p .vbw-planning/phases/
  echo "# Shipped" > .vbw-planning/milestones/m01-test/SHIPPED.md
  touch .vbw-planning/milestones/m01-test/phases/03-feature/03-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/milestones/m01-test/phases/03-feature/03-01-SUMMARY.md
  cat > .vbw-planning/milestones/m01-test/phases/03-feature/03-UAT-round-01.md <<'EOF'
---
phase: 03
status: issues_found
---

## Tests

### P03-T2: recurring issue

- **Result:** issue
- **Issue:**
  - Description: milestone still broken
  - Severity: major
EOF
  cat > .vbw-planning/milestones/m01-test/phases/03-feature/03-UAT-round-02.md <<'EOF'
---
phase: 03
status: issues_found
---

## Tests

### P03-T2: recurring issue

- **Result:** issue
- **Issue:**
  - Description: milestone still broken
  - Severity: major
EOF
  cat > .vbw-planning/milestones/m01-test/phases/03-feature/03-UAT.md <<'EOF'
---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P03-T2: recurring issue

- **Result:** issue
- **Issue:**
  - Description: milestone still broken
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" .vbw-planning/milestones/m01-test/phases/03-feature
  [ "$status" -eq 0 ]
  expected="$output"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  marker=$(printf '%s\n' "$output" | awk '/^---MILESTONE_UAT_EXTRACT_START---$/{f=1; next} /^---MILESTONE_UAT_EXTRACT_END---$/{exit} f{print}' | awk '/^milestone_phase_dir=/{next} /^---$/{exit} {print}')
  [ "$marker" = "$expected" ]
}

@test "milestone extraction uses resolved phase number for non-canonical phase dir" {
  mkdir -p .vbw-planning/milestones/m01-test/phases/setup-api/
  mkdir -p .vbw-planning/phases/
  echo "# Shipped" > .vbw-planning/milestones/m01-test/SHIPPED.md
  touch .vbw-planning/milestones/m01-test/phases/setup-api/03-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/milestones/m01-test/phases/setup-api/03-01-SUMMARY.md
  cat > .vbw-planning/milestones/m01-test/phases/setup-api/03-UAT.md <<'EOF'
---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P03-T1: recovered number

- **Result:** issue
- **Issue:**
  - Description: non-canonical dir still reports phase 03
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "milestone_phase_dir=.vbw-planning/milestones/m01-test/phases/setup-api"
  echo "$output" | grep -q "uat_phase=03 uat_issues_total=1 uat_round=1 uat_file=03-UAT.md"
}

@test "milestone extraction resolves phase number from round-dir UAT in non-canonical phase dir" {
  mkdir -p .vbw-planning/milestones/m01-test/phases/setup-api/remediation/uat/round-01/
  mkdir -p .vbw-planning/milestones/m01-test/phases/setup-api/remediation/uat/round-02/
  mkdir -p .vbw-planning/phases/
  echo "# Shipped" > .vbw-planning/milestones/m01-test/SHIPPED.md
  # Legacy brownfield root artifacts without numeric prefixes
  printf '%s\n' '---' 'phase: 03' 'plan: legacy' 'title: Setup' '---' > .vbw-planning/milestones/m01-test/phases/setup-api/PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/milestones/m01-test/phases/setup-api/SUMMARY.md
  printf 'stage=verify\nround=02\nlayout=round-dir\n' > .vbw-planning/milestones/m01-test/phases/setup-api/remediation/uat/.uat-remediation-stage
  cat > .vbw-planning/milestones/m01-test/phases/setup-api/remediation/uat/round-01/R01-UAT.md <<'EOF'
---
phase: 03
status: issues_found
---

## Tests

### P03-T2: recurring issue

- **Result:** issue
- **Issue:**
  - Description: broke before
  - Severity: major
EOF
  cat > .vbw-planning/milestones/m01-test/phases/setup-api/remediation/uat/round-02/R02-UAT.md <<'EOF'
---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P03-T2: recurring issue

- **Result:** issue
- **Issue:**
  - Description: broke again
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "milestone_phase_dir=.vbw-planning/milestones/m01-test/phases/setup-api"
  echo "$output" | grep -q "uat_phase=03 uat_issues_total=1 uat_round=2 uat_file=R02-UAT.md"
  echo "$output" | grep -q "P03-T2|major|broke again|1,2"
}

@test "milestone extraction preserves round-01 parity for non-canonical round-dir current UAT" {
  mkdir -p .vbw-planning/milestones/m01-test/phases/setup-api/remediation/uat/round-01/
  mkdir -p .vbw-planning/phases/
  echo "# Shipped" > .vbw-planning/milestones/m01-test/SHIPPED.md
  printf '%s\n' '---' 'phase: 03' 'plan: legacy' 'title: Setup' '---' > .vbw-planning/milestones/m01-test/phases/setup-api/PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/milestones/m01-test/phases/setup-api/SUMMARY.md
  printf 'stage=verify\nround=01\nlayout=round-dir\n' > .vbw-planning/milestones/m01-test/phases/setup-api/remediation/uat/.uat-remediation-stage
  cat > .vbw-planning/milestones/m01-test/phases/setup-api/remediation/uat/round-01/R01-UAT.md <<'EOF'
---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P03-T2: recurring issue

- **Result:** issue
- **Issue:**
  - Description: broke first time
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "uat_phase=03 uat_issues_total=1 uat_round=1 uat_file=R01-UAT.md"
  echo "$output" | grep -q "P03-T2|major|broke first time|1"
}

@test "minor-only UAT issues set major-or-higher flag false" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---

## Tests

### P01-T1: sample

- **Result:** issue
- **Issue:** sample
  - Severity: minor
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  echo "$output" | grep -q "uat_issues_major_or_higher=false"
}

@test "detects bold-markdown severity format as major" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---

## Tests

### P01-T1: sample

- **Result:** issue
- **Issue:** sample
  - **Severity:** major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  echo "$output" | grep -q "uat_issues_major_or_higher=true"
}

@test "terminal UAT with missing QA verification reroutes to needs_verification" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md

  # UAT was re-run after fixes; now passes
  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: complete
---

All tests passed.
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_issues_phase=none"
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_state=needs_verification"
}

@test "orphan UAT without PLAN or SUMMARY is ignored" {
  mkdir -p .vbw-planning/phases/01-test/
  # No PLAN or SUMMARY — just an orphan UAT file
  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
  - Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_issues_phase=none"
  # Should route to needs_plan_and_execute, not needs_uat_remediation
  echo "$output" | grep -q "next_phase_state=needs_plan_and_execute"
}

@test "mid-execution phase with UAT is not routed to remediation" {
  mkdir -p .vbw-planning/phases/01-partial/
  # 2 plans, only 1 summary — still mid-execution
  touch .vbw-planning/phases/01-partial/01-01-PLAN.md
  touch .vbw-planning/phases/01-partial/01-02-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-partial/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-partial/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_issues_phase=none"
  echo "$output" | grep -q "next_phase_state=needs_execute"
  echo "$output" | grep -q "next_phase_plans=2"
  echo "$output" | grep -q "next_phase_summaries=1"
}

@test "non-canonical PLAN files are not counted as plan artifacts" {
  mkdir -p .vbw-planning/phases/01-test/
  # Canonical PLAN file
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  # Non-canonical — should NOT count
  touch .vbw-planning/phases/01-test/not-a-PLAN.md

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Only 1 canonical plan, 0 summaries → needs_execute (not needs_plan_and_execute)
  echo "$output" | grep -q "next_phase_state=needs_execute"
  echo "$output" | grep -q "next_phase_plans=1"
}

@test "legacy PLAN.md and SUMMARY.md support UAT remediation detection" {
  mkdir -p .vbw-planning/phases/01-legacy/
  touch .vbw-planning/phases/01-legacy/PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-legacy/SUMMARY.md
  cat > .vbw-planning/phases/01-legacy/01-UAT.md <<'EOF'
phase: 01
status: issues_found
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "uat_issues_phase=01"
}

@test "phase-detect: legacy key-value remediation state routes to needs_reverification" {
  mkdir -p .vbw-planning/phases/01-legacy/remediation
  touch .vbw-planning/phases/01-legacy/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-legacy/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-legacy/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
EOF
  printf 'stage=done\nround=01\nlayout=legacy\n' > .vbw-planning/phases/01-legacy/.uat-remediation-stage

  run bash "$SCRIPTS_DIR/phase-detect.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=needs_reverification"* ]]
}

@test "phase-detect: stale execute auto-advance writes back to legacy remediation state file" {
  mkdir -p .vbw-planning/phases/01-legacy/remediation
  touch .vbw-planning/phases/01-legacy/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-legacy/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-legacy/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
EOF
  printf 'stage=execute\nround=01\nlayout=legacy\n' > .vbw-planning/phases/01-legacy/remediation/.uat-remediation-stage

  run bash "$SCRIPTS_DIR/phase-detect.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=needs_reverification"* ]]
  grep -q '^stage=done$' .vbw-planning/phases/01-legacy/remediation/.uat-remediation-stage
}

@test "phase-detect does not auto-advance UAT remediation past finite cap on rerun" {
  cat > .vbw-planning/config.json <<'EOF'
{
  "effort": "balanced",
  "max_uat_remediation_rounds": 1
}
EOF
  mkdir -p .vbw-planning/phases/01-feature/remediation/uat/round-01
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md
  printf 'stage=done\nround=01\nlayout=round-dir\n' > .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  cat > .vbw-planning/phases/01-feature/remediation/uat/round-01/R01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"

  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_reverification"
  grep -q '^stage=done$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  grep -q '^round=01$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  [ ! -d .vbw-planning/phases/01-feature/remediation/uat/round-02 ]
}

@test "phase-detect auto-advances UAT remediation when cap is explicitly false" {
  cat > .vbw-planning/config.json <<'EOF'
{
  "effort": "balanced",
  "max_uat_remediation_rounds": false
}
EOF
  mkdir -p .vbw-planning/phases/01-feature/remediation/uat/round-01
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md
  printf 'stage=done\nround=01\nlayout=round-dir\n' > .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  cat > .vbw-planning/phases/01-feature/remediation/uat/round-01/R01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"

  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  grep -q '^stage=research$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  grep -q '^round=02$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  [ -d .vbw-planning/phases/01-feature/remediation/uat/round-02 ]
}

@test "phase-detect auto-advances UAT remediation when cap is explicitly zero" {
  cat > .vbw-planning/config.json <<'EOF'
{
  "effort": "balanced",
  "max_uat_remediation_rounds": 0
}
EOF
  mkdir -p .vbw-planning/phases/01-feature/remediation/uat/round-01
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md
  printf 'stage=done\nround=01\nlayout=round-dir\n' > .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  cat > .vbw-planning/phases/01-feature/remediation/uat/round-01/R01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"

  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  grep -q '^stage=research$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  grep -q '^round=02$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  [ -d .vbw-planning/phases/01-feature/remediation/uat/round-02 ]
}

@test "phase-detect does not auto-advance UAT remediation when cap helper exits nonzero" {
  mkdir -p .vbw-planning/phases/01-feature/remediation/uat/round-01
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md
  printf 'stage=done\nround=01\nlayout=round-dir\n' > .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  cat > .vbw-planning/phases/01-feature/remediation/uat/round-01/R01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  local shim_dir="$TEST_TEMP_DIR/scripts-phase-detect-helper-fail"
  cp -R "$SCRIPTS_DIR" "$shim_dir"
  cat > "$shim_dir/resolve-uat-remediation-round-limit.sh" <<'EOF'
#!/usr/bin/env bash
exit 23
EOF
  chmod +x "$shim_dir/resolve-uat-remediation-round-limit.sh"

  run bash "$shim_dir/phase-detect.sh"

  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_reverification"
  grep -q '^stage=done$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  grep -q '^round=01$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  [ ! -d .vbw-planning/phases/01-feature/remediation/uat/round-02 ]
}

@test "phase-detect does not auto-advance UAT remediation when cap helper output is malformed" {
  mkdir -p .vbw-planning/phases/01-feature/remediation/uat/round-01
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md
  printf 'stage=done\nround=01\nlayout=round-dir\n' > .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  cat > .vbw-planning/phases/01-feature/remediation/uat/round-01/R01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  local shim_dir="$TEST_TEMP_DIR/scripts-phase-detect-helper-malformed"
  cp -R "$SCRIPTS_DIR" "$shim_dir"
  cat > "$shim_dir/resolve-uat-remediation-round-limit.sh" <<'EOF'
#!/usr/bin/env bash
printf 'current_round=01\nnext_round=02\n'
EOF
  chmod +x "$shim_dir/resolve-uat-remediation-round-limit.sh"

  run bash "$shim_dir/phase-detect.sh"

  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_reverification"
  grep -q '^stage=done$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  grep -q '^round=01$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  [ ! -d .vbw-planning/phases/01-feature/remediation/uat/round-02 ]
}

@test "corrupt QA remediation stage does not route as active remediation" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md
  printf 'stage=garbage\nround=01\n' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "next_phase_state=needs_qa_remediation"
  echo "$output" | grep -q "qa_status=pending"
}

@test "dotfile PLAN files are not counted as plan artifacts" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md
  # Dotfile — should NOT count (ls glob ignores dotfiles)
  touch ".vbw-planning/phases/01-test/.01-02-PLAN.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # 1 plan, 1 summary → all_done (dotfile plan not counted)
  echo "$output" | grep -q "next_phase_state=all_done"
}

@test "outputs has_shipped_milestones=true when shipped milestone exists" {
  mkdir -p .vbw-planning/phases
  mkdir -p .vbw-planning/milestones/foundation
  echo "# Shipped" > .vbw-planning/milestones/foundation/SHIPPED.md

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "has_shipped_milestones=true"
}

@test "outputs has_shipped_milestones=false when no shipped milestones" {
  mkdir -p .vbw-planning/phases

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "has_shipped_milestones=false"
}

@test "auto-renames milestones/default during phase-detect" {
  mkdir -p .vbw-planning/milestones/default
  mkdir -p .vbw-planning/milestones/default/phases/01-legacy-phase

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "needs_milestone_rename=false"
  [ ! -d .vbw-planning/milestones/default ]
}

@test "outputs needs_milestone_rename=false when no milestones/default/" {
  mkdir -p .vbw-planning/phases

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "needs_milestone_rename=false"
}

@test "does not output active_milestone (removed)" {
  mkdir -p .vbw-planning/phases

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "active_milestone="
}

@test "ignores ACTIVE file (always uses root phases)" {
  mkdir -p .vbw-planning/phases/01-root-phase/
  mkdir -p .vbw-planning/milestones/old/phases/01-milestone-phase/
  echo "old" > .vbw-planning/ACTIVE

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "phase_count=1"
  echo "$output" | grep -q "phases_dir=.vbw-planning/phases"
}

@test "phase directories sort numerically not lexicographically" {
  mkdir -p .vbw-planning/phases/11-eleven/
  mkdir -p .vbw-planning/phases/100-hundred/
  for p in 11 100; do
    case "$p" in
      11) dir=".vbw-planning/phases/11-eleven/" ;;
      100) dir=".vbw-planning/phases/100-hundred/" ;;
    esac
    touch "${dir}${p}-01-PLAN.md"
    printf '%s\n' '---' 'status: complete' '---' 'Done.' > "${dir}${p}-01-SUMMARY.md"
    cat > "${dir}${p}-UAT.md" <<EOF
---
phase: $p
status: issues_found
---
- Severity: major
EOF
  done

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Phase 11 should be selected first (numeric), not 100 (lexicographic)
  echo "$output" | grep -q "uat_issues_phase=11"
  echo "$output" | grep -q "next_phase=11"
}

# --- require_phase_discussion tests ---

@test "outputs config_require_phase_discussion=false by default" {
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "config_require_phase_discussion=false"
}

@test "outputs config_require_phase_discussion=true when set in config" {
  local tmp
  tmp=$(mktemp)
  jq '.require_phase_discussion = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "config_require_phase_discussion=true"
}

@test "needs_discussion state when require_phase_discussion=true and phase lacks CONTEXT.md" {
  local tmp
  tmp=$(mktemp)
  jq '.require_phase_discussion = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  mkdir -p .vbw-planning/phases/01-test/

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_discussion"
  echo "$output" | grep -q "next_phase=01"
}

@test "needs_plan_and_execute when require_phase_discussion=true but CONTEXT.md exists" {
  local tmp
  tmp=$(mktemp)
  jq '.require_phase_discussion = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-CONTEXT.md

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_plan_and_execute"
}

@test "needs_plan_and_execute when require_phase_discussion=false even without CONTEXT.md" {
  mkdir -p .vbw-planning/phases/01-test/

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_plan_and_execute"
}

@test "needs_discussion only applies to unplanned phases" {
  local tmp
  tmp=$(mktemp)
  jq '.require_phase_discussion = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  mkdir -p .vbw-planning/phases/01-test/
  # Phase has a plan already — discussion should not be required
  touch .vbw-planning/phases/01-test/01-01-PLAN.md

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_execute"
}

@test "needs_discussion targets first undiscussed phase in multi-phase project" {
  local tmp
  tmp=$(mktemp)
  jq '.require_phase_discussion = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  mkdir -p .vbw-planning/phases/01-first/
  mkdir -p .vbw-planning/phases/02-second/
  # Phase 1 is fully done
  touch .vbw-planning/phases/01-first/01-CONTEXT.md
  touch .vbw-planning/phases/01-first/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-first/01-01-SUMMARY.md
  # Phase 2 has no context

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_discussion"
  echo "$output" | grep -q "next_phase=02"
  echo "$output" | grep -q "next_phase_slug=02-second"
}

@test "milestone UAT recovery takes priority over needs_discussion when all active phases done" {
  local tmp
  tmp=$(mktemp)
  jq '.require_phase_discussion = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  # All active phases complete
  mkdir -p .vbw-planning/phases/01-done/
  touch .vbw-planning/phases/01-done/01-CONTEXT.md
  touch .vbw-planning/phases/01-done/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-done/01-01-SUMMARY.md
  # Shipped milestone with UAT issues
  mkdir -p .vbw-planning/milestones/v1/phases/01-shipped/
  echo "# Shipped" > .vbw-planning/milestones/v1/SHIPPED.md
  touch .vbw-planning/milestones/v1/phases/01-shipped/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/milestones/v1/phases/01-shipped/01-01-SUMMARY.md
  cat > .vbw-planning/milestones/v1/phases/01-shipped/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Active phases all_done (not needs_discussion — all are planned)
  echo "$output" | grep -q "next_phase_state=all_done"
  # Milestone UAT recovery detected
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "milestone_uat_slug=v1"
}

# --- non-canonical directory handling ---

@test "non-canonical phase dir without numeric prefix is skipped" {
  mkdir -p .vbw-planning/phases/misc-notes/
  mkdir -p .vbw-planning/phases/01-real/

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "phase_count=1"
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_slug=01-real"
  echo "$output" | grep -q "next_phase_state=needs_plan_and_execute"
}

@test "non-canonical CONTEXT.md does not satisfy discussion requirement" {
  local tmp
  tmp=$(mktemp)
  jq '.require_phase_discussion = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  mkdir -p .vbw-planning/phases/01-test/
  # Non-canonical — should NOT satisfy the CONTEXT.md check
  touch .vbw-planning/phases/01-test/NOTES-CONTEXT.md

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_discussion"
}

@test "canonical CONTEXT.md satisfies discussion requirement" {
  local tmp
  tmp=$(mktemp)
  jq '.require_phase_discussion = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  mkdir -p .vbw-planning/phases/01-test/
  # Canonical phase-prefixed CONTEXT.md
  touch .vbw-planning/phases/01-test/01-CONTEXT.md

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_plan_and_execute"
}

# --- SOURCE-UAT exclusion tests ---

@test "SOURCE-UAT.md is not treated as a UAT report in active phase scan" {
  mkdir -p .vbw-planning/phases/01-remediate-test/
  touch .vbw-planning/phases/01-remediate-test/01-CONTEXT.md
  touch .vbw-planning/phases/01-remediate-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-remediate-test/01-01-SUMMARY.md
  # SOURCE-UAT is a reference copy — should NOT trigger remediation
  cat > .vbw-planning/phases/01-remediate-test/01-SOURCE-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_issues_phase=none"
  echo "$output" | grep -q "next_phase_state=all_done"
}

@test "SOURCE-UAT.md ignored while real UAT.md in later phase is detected" {
  # Phase 01: completed remediation with SOURCE-UAT (should be ignored)
  mkdir -p .vbw-planning/phases/01-remediate-first/
  touch .vbw-planning/phases/01-remediate-first/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-remediate-first/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-remediate-first/01-SOURCE-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  # Phase 02: has real UAT issues
  mkdir -p .vbw-planning/phases/02-executed/
  touch .vbw-planning/phases/02-executed/02-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/02-executed/02-01-SUMMARY.md
  cat > .vbw-planning/phases/02-executed/02-UAT.md <<'EOF'
---
phase: 02
status: issues_found
---
- Severity: critical
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_issues_phase=02"
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
}

@test "completed remediation phases with SOURCE-UAT do not block unplanned phase" {
  # Phase 01: unplanned (needs work)
  mkdir -p .vbw-planning/phases/01-remediate-unresolved/
  touch .vbw-planning/phases/01-remediate-unresolved/01-CONTEXT.md
  cat > .vbw-planning/phases/01-remediate-unresolved/01-SOURCE-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: critical
EOF

  # Phase 02: completed remediation with SOURCE-UAT only
  mkdir -p .vbw-planning/phases/02-remediate-done/
  touch .vbw-planning/phases/02-remediate-done/02-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/02-remediate-done/02-01-SUMMARY.md
  cat > .vbw-planning/phases/02-remediate-done/02-SOURCE-UAT.md <<'EOF'
---
phase: 02
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Phase 02 SOURCE-UAT should NOT trigger remediation
  echo "$output" | grep -q "uat_issues_phase=none"
  # Phase 01 has no plans — should route to needs_plan_and_execute
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_state=needs_plan_and_execute"
}

@test "SOURCE-UAT.md in milestone phases is excluded from milestone UAT scan" {
  mkdir -p .vbw-planning/phases/01-done/
  touch .vbw-planning/phases/01-done/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-done/01-01-SUMMARY.md

  mkdir -p .vbw-planning/milestones/v1/phases/01-shipped/
  echo "# Shipped" > .vbw-planning/milestones/v1/SHIPPED.md
  touch .vbw-planning/milestones/v1/phases/01-shipped/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/milestones/v1/phases/01-shipped/01-01-SUMMARY.md
  # Only SOURCE-UAT — should NOT trigger milestone recovery
  cat > .vbw-planning/milestones/v1/phases/01-shipped/01-SOURCE-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=false"
}

# --- Brownfield milestone cross-reference tests ---

@test "milestone UAT skipped when active remediation phase references it" {
  # Active remediation phase with CONTEXT referencing the milestone phase
  mkdir -p .vbw-planning/phases/01-remediate-v1-setup/
  touch .vbw-planning/phases/01-remediate-v1-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-remediate-v1-setup/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-remediate-v1-setup/01-CONTEXT.md <<'EOF'
---
phase: 01
source_milestone: v1
source_phase: 01-setup
pre_seeded: true
---
EOF

  # Shipped milestone with UAT issues
  mkdir -p .vbw-planning/milestones/v1/phases/01-setup/
  echo "# Shipped" > .vbw-planning/milestones/v1/SHIPPED.md
  touch .vbw-planning/milestones/v1/phases/01-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/milestones/v1/phases/01-setup/01-01-SUMMARY.md
  cat > .vbw-planning/milestones/v1/phases/01-setup/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=all_done"
  echo "$output" | grep -q "milestone_uat_issues=false"
}

@test "milestone UAT detected when no active remediation references it" {
  # Active phase complete but NOT a remediation (no source_milestone in CONTEXT)
  mkdir -p .vbw-planning/phases/01-feature/
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md

  # Shipped milestone with UAT issues — no active remediation covers it
  mkdir -p .vbw-planning/milestones/v1/phases/01-setup/
  echo "# Shipped" > .vbw-planning/milestones/v1/SHIPPED.md
  touch .vbw-planning/milestones/v1/phases/01-setup/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/milestones/v1/phases/01-setup/01-01-SUMMARY.md
  cat > .vbw-planning/milestones/v1/phases/01-setup/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "milestone_uat_issues=true"
  echo "$output" | grep -q "milestone_uat_slug=v1"
}

@test "multiple phases with UAT issues are all reported in uat_issues_phases" {
  mkdir -p .vbw-planning/phases/01-first/
  touch .vbw-planning/phases/01-first/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-first/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-first/01-UAT.md <<'EOF'
---
status: complete
---
All tests passed.
EOF

  mkdir -p .vbw-planning/phases/02-second/
  touch .vbw-planning/phases/02-second/02-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/02-second/02-01-SUMMARY.md
  cat > .vbw-planning/phases/02-second/02-UAT.md <<'EOF'
---
status: issues_found
---
- Severity: major
EOF

  mkdir -p .vbw-planning/phases/03-third/
  touch .vbw-planning/phases/03-third/03-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/03-third/03-01-SUMMARY.md
  cat > .vbw-planning/phases/03-third/03-UAT.md <<'EOF'
---
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # First phase with issues is the routing target
  echo "$output" | grep -q "uat_issues_phase=02"
  echo "$output" | grep -q "next_phase=02"
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  # All phases with issues are listed
  echo "$output" | grep -q "uat_issues_phases=02,03"
  echo "$output" | grep -q "uat_issues_count=2"
}

@test "single phase with UAT issues reports count=1 and phases list" {
  mkdir -p .vbw-planning/phases/01-only/
  touch .vbw-planning/phases/01-only/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-only/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-only/01-UAT.md <<'EOF'
---
status: issues_found
---
- Severity: minor
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_issues_phase=01"
  echo "$output" | grep -q "uat_issues_phases=01"
  echo "$output" | grep -q "uat_issues_count=1"
}

@test "no UAT issues reports empty phases list and count=0" {
  mkdir -p .vbw-planning/phases/01-clean/
  touch .vbw-planning/phases/01-clean/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-clean/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-clean/01-UAT.md <<'EOF'
---
status: complete
---
All tests passed.
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_issues_phase=none"
  echo "$output" | grep -q "uat_issues_phases=$"
  echo "$output" | grep -q "uat_issues_count=0"
}

# --- Mid-remediation priority tests (issue #145) ---

@test "mid-remediation phase takes priority over later phase UAT issues" {
  # Phase 02: mid-remediation — original plan done, remediation plan created but not executed
  mkdir -p .vbw-planning/phases/02-feature/
  touch .vbw-planning/phases/02-feature/02-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/02-feature/02-01-SUMMARY.md
  touch .vbw-planning/phases/02-feature/02-02-PLAN.md
  # No 02-02-SUMMARY.md — remediation plan not yet executed
  echo "execute" > .vbw-planning/phases/02-feature/.uat-remediation-stage
  cat > .vbw-planning/phases/02-feature/02-UAT.md <<'EOF'
---
phase: 02
status: issues_found
---
- Severity: major
EOF

  # Phase 03: fully complete but has UAT issues
  mkdir -p .vbw-planning/phases/03-polish/
  touch .vbw-planning/phases/03-polish/03-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/03-polish/03-01-SUMMARY.md
  cat > .vbw-planning/phases/03-polish/03-UAT.md <<'EOF'
---
phase: 03
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Phase 02 mid-remediation should take priority over Phase 03 UAT
  echo "$output" | grep -q "next_phase=02"
  echo "$output" | grep -q "next_phase_state=needs_execute"
  echo "$output" | grep -q "next_phase_plans=2"
  echo "$output" | grep -q "next_phase_summaries=1"
}

@test "earlier unplanned phase takes priority over later phase UAT issues" {
  # Phase 01: no plans at all — needs planning
  mkdir -p .vbw-planning/phases/01-setup/

  # Phase 02: fully complete with UAT issues
  mkdir -p .vbw-planning/phases/02-feature/
  touch .vbw-planning/phases/02-feature/02-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/02-feature/02-01-SUMMARY.md
  cat > .vbw-planning/phases/02-feature/02-UAT.md <<'EOF'
---
phase: 02
status: issues_found
---
- Severity: critical
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Phase 01 unplanned should take priority over Phase 02 UAT
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_state=needs_plan_and_execute"
}

@test "mid-execution phase without remediation marker takes priority over later UAT" {
  # Phase 02: mid-execution (no .uat-remediation-stage, just incomplete plans)
  mkdir -p .vbw-planning/phases/02-feature/
  touch .vbw-planning/phases/02-feature/02-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/02-feature/02-01-SUMMARY.md
  touch .vbw-planning/phases/02-feature/02-02-PLAN.md
  # No 02-02-SUMMARY.md — task 2 not yet executed

  # Phase 03: fully complete with UAT issues
  mkdir -p .vbw-planning/phases/03-polish/
  touch .vbw-planning/phases/03-polish/03-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/03-polish/03-01-SUMMARY.md
  cat > .vbw-planning/phases/03-polish/03-UAT.md <<'EOF'
---
phase: 03
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Phase 02 mid-execution should take priority over Phase 03 UAT
  echo "$output" | grep -q "next_phase=02"
  echo "$output" | grep -q "next_phase_state=needs_execute"
  echo "$output" | grep -q "next_phase_plans=2"
  echo "$output" | grep -q "next_phase_summaries=1"
}

@test "earlier undiscussed phase with require_phase_discussion routes to needs_discussion over later UAT" {
  # Enable discussion requirement
  echo '{"require_phase_discussion": true}' > .vbw-planning/config.json

  # Phase 01: no plans, no CONTEXT — needs discussion first
  mkdir -p .vbw-planning/phases/01-setup/

  # Phase 02: fully complete with UAT issues
  mkdir -p .vbw-planning/phases/02-feature/
  touch .vbw-planning/phases/02-feature/02-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/02-feature/02-01-SUMMARY.md
  cat > .vbw-planning/phases/02-feature/02-UAT.md <<'EOF'
---
phase: 02
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Phase 01 should route to needs_discussion, not needs_plan_and_execute
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_state=needs_discussion"
}

@test "earlier discussed phase (CONTEXT exists, no PLAN) routes to needs_plan_and_execute over later UAT" {
  # Enable discussion requirement
  echo '{"require_phase_discussion": true}' > .vbw-planning/config.json

  # Phase 01: has CONTEXT (discussed) but no PLAN — needs planning
  mkdir -p .vbw-planning/phases/01-setup/
  touch .vbw-planning/phases/01-setup/01-CONTEXT.md

  # Phase 02: fully complete with UAT issues
  mkdir -p .vbw-planning/phases/02-feature/
  touch .vbw-planning/phases/02-feature/02-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/02-feature/02-01-SUMMARY.md
  cat > .vbw-planning/phases/02-feature/02-UAT.md <<'EOF'
---
phase: 02
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Discussion done (CONTEXT exists) — should route to needs_plan_and_execute
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_state=needs_plan_and_execute"
}

# --- UAT round count tracking tests ---

@test "uat_round_count=0 when no round files exist" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_round_count=0"
}

@test "uat_round_count=5 when five round files exist" {
  mkdir -p .vbw-planning/phases/03-feature/
  touch .vbw-planning/phases/03-feature/03-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/03-feature/03-01-SUMMARY.md

  # Create 5 archived round files
  for i in 01 02 03 04 05; do
    printf 'round %s\n' "$i" > ".vbw-planning/phases/03-feature/03-UAT-round-${i}.md"
  done

  # Active UAT with issues
  cat > .vbw-planning/phases/03-feature/03-UAT.md <<'EOF'
---
phase: 03
status: issues_found
---
- Severity: major
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_round_count=5"
}

@test "uat_round_count=0 when no planning directory" {
  rm -rf .vbw-planning
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uat_round_count=0"
}

@test "uat_round_count=0 when UAT issues resolved (no routing target)" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-test/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: complete
---
All tests passed.
EOF
  # Round files exist from previous remediation cycles
  printf 'round 1\n' > .vbw-planning/phases/01-test/01-UAT-round-01.md

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # No active UAT issues → round count stays 0 (no routing target)
  echo "$output" | grep -q "uat_round_count=0"
}

@test "auto-advance scoped to current round: previous-round summary does not trigger advance" {
  # Round 02, stage=execute. Round 01 has plan+summary, round 02 has plan only.
  # Auto-advance should NOT trigger because the current round (02) has no summary.
  # Phase-root plan+summary required so the UAT scan picks up this phase.
  mkdir -p .vbw-planning/phases/01-feature/remediation/uat/round-01
  mkdir -p .vbw-planning/phases/01-feature/remediation/uat/round-02
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md
  printf 'stage=execute\nround=02\nlayout=round-dir\n' > .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  touch .vbw-planning/phases/01-feature/remediation/uat/round-01/R01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/remediation/uat/round-01/R01-SUMMARY.md
  touch .vbw-planning/phases/01-feature/remediation/uat/round-02/R02-PLAN.md
  # No R02-SUMMARY.md — execution not complete for round 02

  # Round 01 UAT with issues (needed to route into UAT remediation path)
  cat > .vbw-planning/phases/01-feature/remediation/uat/round-01/R01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  create_test_config
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]

  # Stage must NOT advance to done — should remain needs_uat_remediation (execute)
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  # Confirm the state file was NOT rewritten to done
  grep -q "^stage=execute$" .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
}

# --- UAT status normalization in phase-detect ---

@test "phase with all_pass UAT is treated as verified but still needs QA when verification is missing" {
  mkdir -p .vbw-planning/phases/01-feature
  touch .vbw-planning/phases/01-feature/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-SUMMARY.md
  cat > .vbw-planning/phases/01-feature/01-UAT.md <<'EOF'
---
phase: 01
status: all_pass
total_tests: 3
passed: 3
issues: 0
---
All tests passed.
EOF

  # Enable auto_uat to trigger the unverified phases scan
  cat > .vbw-planning/config.json <<'CONF'
{
  "effort": "balanced",
  "auto_uat": true,
  "auto_commit": true,
  "planning_tracking": "manual",
  "auto_push": "never"
}
CONF

  echo "# My Project" > .vbw-planning/PROJECT.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]

  # all_pass should be normalized to complete → phase is verified for UAT,
  # but terminal UAT with no QA artifact must still reroute to needs_verification.
  echo "$output" | grep -q "has_unverified_phases=false"
  echo "$output" | grep -q "next_phase_state=needs_verification"
}

@test "phase with passed UAT is treated as verified (not unverified)" {
  mkdir -p .vbw-planning/phases/01-feature
  touch .vbw-planning/phases/01-feature/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-SUMMARY.md
  cat > .vbw-planning/phases/01-feature/01-UAT.md <<'EOF'
---
phase: 01
status: passed
---
All tests passed.
EOF

  cat > .vbw-planning/config.json <<'CONF'
{
  "effort": "balanced",
  "auto_uat": true,
  "auto_commit": true,
  "planning_tracking": "manual",
  "auto_push": "never"
}
CONF

  echo "# My Project" > .vbw-planning/PROJECT.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]

  echo "$output" | grep -q "has_unverified_phases=false"
}

# --- QA status detection tests ---

@test "qa_status defaults to none when no phases" {
  mkdir -p .vbw-planning/phases
  echo "# My Project" > .vbw-planning/PROJECT.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=none"
  echo "$output" | grep -q "qa_round=00"
}

@test "qa_status is pending when SUMMARY.md exists but no VERIFICATION.md" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=pending"
}

@test "qa_status is passed when VERIFICATION.md has PASS result" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  current_commit="$(git rev-parse HEAD)"
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - 01' "verified_at_commit: ${current_commit}" '---' '# Verification' 'All passed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=passed"
}

@test "qa_status is failed when PASS verification still has unresolved known issues" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  current_commit="$(git rev-parse HEAD)"
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - 01' "verified_at_commit: ${current_commit}" '---' '# Verification' 'All passed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  cat > .vbw-planning/phases/01-test/known-issues.json <<'EOF'
{
  "schema_version": 1,
  "phase": "01",
  "issues": [
    {
      "test": "FIGIRegistryServiceTests",
      "file": "Tests/FIGIRegistryServiceTests.swift",
      "error": "compositeFigi missing",
      "first_seen_in": "01-01-SUMMARY.md",
      "last_seen_in": "01-VERIFICATION.md",
      "first_seen_round": 0,
      "last_seen_round": 0,
      "times_seen": 2
    }
  ]
}
EOF
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=failed"
}

@test "phase-detect restores missing known-issues registry from existing verification before computing qa_status" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  current_commit="$(git rev-parse HEAD)"
  cat > .vbw-planning/phases/01-test/01-VERIFICATION.md <<'EOF'
---
result: FAIL
writer: write-verification.sh
plans_verified:
  - 01
EOF
  printf '%s\n' "verified_at_commit: ${current_commit}" >> .vbw-planning/phases/01-test/01-VERIFICATION.md
  cat >> .vbw-planning/phases/01-test/01-VERIFICATION.md <<'EOF'
---

## Pre-existing Issues

| Test | File | Error |
|------|------|-------|
| FIGIRegistryServiceTests | Tests/FIGIRegistryServiceTests.swift | compositeFigi missing |
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"

  [ "$status" -eq 0 ]
  [ -f .vbw-planning/phases/01-test/known-issues.json ]
  echo "$output" | grep -q "qa_status=failed"
}

@test "qa_status is passed when brownfield plain VERIFICATION.md has PASS result" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  current_commit="$(git rev-parse HEAD)"
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - 01' "verified_at_commit: ${current_commit}" '---' '# Verification' 'All passed.' > .vbw-planning/phases/01-test/VERIFICATION.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=passed"
}

@test "qa_status is passed when latest wave verification has PASS result" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  current_commit="$(git rev-parse HEAD)"
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Wave 1 failed.' > .vbw-planning/phases/01-test/01-VERIFICATION-wave1.md
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - 01' "verified_at_commit: ${current_commit}" '---' '# Verification' 'Wave 2 passed.' > .vbw-planning/phases/01-test/01-VERIFICATION-wave2.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=passed"
}

@test "qa_status is failed when VERIFICATION.md has FAIL result" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Failed checks.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=failed"
}

@test "qa_status is remediating when qa-remediation-stage is active" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Failed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  printf '%s\n%s\n' 'stage=execute' 'round=01' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  echo "# My Project" > .vbw-planning/PROJECT.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=remediating"
  echo "$output" | grep -q "qa_round=01"
}

@test "qa_status is remediating for plan stage" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Failed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  printf '%s\n%s\n' 'stage=plan' 'round=02' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  echo "# My Project" > .vbw-planning/PROJECT.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=remediating"
}

@test "qa_status is remediating for verify stage" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Failed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  printf '%s\n%s\n' 'stage=verify' 'round=01' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  echo "# My Project" > .vbw-planning/PROJECT.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=remediating"
}

@test "qa_status is remediated when qa-remediation done and PASS" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa/round-01
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  cat > .vbw-planning/phases/01-test/01-VERIFICATION.md <<'EOF'
---
result: FAIL
writer: write-verification.sh
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Original failure | FAIL | Missing |
EOF
  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-PLAN.md <<'EOF'
---
round: 01
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Fixture documents a structurally valid remediated round"}
---
EOF
  round_anchor_commit="$(git rev-parse HEAD)"
  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-SUMMARY.md <<'EOF'
---
plan: R01
status: complete
files_modified:
  - README.md
  - .vbw-planning/phases/01-test/remediation/qa/round-01/R01-SUMMARY.md
deviations: []
---
EOF
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Documented historical process exception.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "remediation notes" > README.md
  git add README.md .vbw-planning/phases/01-test/01-SUMMARY.md
  git commit -m "document remediation summary" --quiet
  current_commit="$(git rev-parse HEAD)"
  printf '%s\n%s\n%s\n' 'stage=done' 'round=01' "round_started_at_commit=${round_anchor_commit}" > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - R01' "verified_at_commit: ${current_commit}" '---' '# Verification' 'Passed after remediation.' > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-VERIFICATION.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=remediated"
}

@test "qa_status stays failed when remediation PASS still has unresolved known issues" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa/round-01
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  current_commit="$(git rev-parse HEAD)"
  cat > .vbw-planning/phases/01-test/01-VERIFICATION.md <<'EOF'
---
result: FAIL
writer: write-verification.sh
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Original failure | FAIL | Missing |
EOF
  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-PLAN.md <<'EOF'
---
round: 01
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Need a fix"}
---
EOF
  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-SUMMARY.md <<'EOF'
---
plan: R01
status: complete
files_modified:
  - README.md
deviations: []
---
EOF
  printf '%s\n%s\n%s\n' 'stage=done' 'round=01' "round_started_at_commit=${current_commit}" > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - R01' "verified_at_commit: ${current_commit}" '---' '# Verification' 'Passed after remediation.' > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-VERIFICATION.md
  cat > .vbw-planning/phases/01-test/known-issues.json <<'EOF'
{
  "schema_version": 1,
  "phase": "01",
  "issues": [
    {
      "test": "TransferMatchingServiceTests",
      "file": "Tests/TransferMatchingServiceTests.swift",
      "error": "debugTestConfiguration missing",
      "first_seen_in": "01-01-SUMMARY.md",
      "last_seen_in": "remediation/qa/round-01/R01-VERIFICATION.md",
      "first_seen_round": 0,
      "last_seen_round": 1,
      "times_seen": 3
    }
  ]
}
EOF
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=failed"
}

@test "qa_status is failed when qa-remediation done but FAIL in VERIFICATION" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa/round-01
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Original failure.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  printf '%s\n%s\n' 'stage=done' 'round=01' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  echo "# My Project" > .vbw-planning/PROJECT.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Still failing after remediation.' > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-VERIFICATION.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=failed"
}

@test "qa_status is pending when qa-remediation done but VERIFICATION is missing" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  printf '%s\n%s\n' 'stage=done' 'round=01' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  echo "# My Project" > .vbw-planning/PROJECT.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=pending"
}

@test "qa_status remediated reads round VERIFICATION.md when stage=done" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa/round-01
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  # Phase-level stays as original FAIL
  cat > .vbw-planning/phases/01-test/01-VERIFICATION.md <<'EOF'
---
result: FAIL
writer: write-verification.sh
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Original failure | FAIL | Missing |
EOF
  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-PLAN.md <<'EOF'
---
round: 01
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Fixture documents a structurally valid remediated round"}
---
EOF
  # Round VERIFICATION.md has PASS
  round_anchor_commit="$(git rev-parse HEAD)"
  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-SUMMARY.md <<'EOF'
---
plan: R01
status: complete
files_modified:
  - README.md
  - .vbw-planning/phases/01-test/remediation/qa/round-01/R01-SUMMARY.md
deviations: []
---
EOF
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Round 01 documented the historical process exception.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "round pass docs" > README.md
  git add README.md .vbw-planning/phases/01-test/01-SUMMARY.md
  git commit -m "round pass summary evidence" --quiet
  current_commit="$(git rev-parse HEAD)"
  printf '%s\n%s\n%s\n' 'stage=done' 'round=01' "round_started_at_commit=${round_anchor_commit}" > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - R01' "verified_at_commit: ${current_commit}" '---' '# Verification' 'Passed after fix.' > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-VERIFICATION.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=remediated"
}

@test "qa_status failed reads round VERIFICATION.md FAIL when stage=done" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa/round-01
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  printf '%s\n%s\n' 'stage=done' 'round=01' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  echo "# My Project" > .vbw-planning/PROJECT.md
  # Phase-level original FAIL
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Original failure.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  # Round VERIFICATION.md also FAIL
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Still failing.' > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-VERIFICATION.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=failed"
}

@test "qa_status is pending when round VERIFICATION.md absent and stage=done" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  printf '%s\n%s\n' 'stage=done' 'round=01' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  echo "# My Project" > .vbw-planning/PROJECT.md
  # Phase-level PASS stays frozen, but missing round verification must fail closed.
  current_commit="$(git rev-parse HEAD)"
  printf '%s\n' '---' 'result: PASS' "verified_at_commit: ${current_commit}" '---' '# Verification' 'Passed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  # No round VERIFICATION.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=pending"
}

@test "qa_status remediated reads round-02 VERIFICATION.md when stage=done" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa/round-01
  mkdir -p .vbw-planning/phases/01-test/remediation/qa/round-02
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  # Phase-level stays as original FAIL
  cat > .vbw-planning/phases/01-test/01-VERIFICATION.md <<'EOF'
---
result: FAIL
writer: write-verification.sh
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Original failure | FAIL | Missing |
EOF
  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-VERIFICATION.md <<'EOF'
---
result: PASS
writer: write-verification.sh
plans_verified:
  - R01
---
## Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| MH-01 | must_have | Structural bookkeeping passed | PASS | Done |
EOF
  cat > .vbw-planning/phases/01-test/remediation/qa/round-02/R02-PLAN.md <<'EOF'
---
round: 02
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Fixture documents a structurally valid remediated round"}
---
EOF
  cat > .vbw-planning/phases/01-test/remediation/qa/round-02/R02-SUMMARY.md <<'EOF'
---
plan: R02
status: complete
files_modified:
  - README.md
  - .vbw-planning/phases/01-test/remediation/qa/round-02/R02-SUMMARY.md
deviations: []
---
EOF
  # Round-02 VERIFICATION.md has PASS
  round_anchor_commit="$(git rev-parse HEAD)"
  cat > .vbw-planning/phases/01-test/remediation/qa/round-02/R02-SUMMARY.md <<'EOF'
---
plan: R02
status: complete
files_modified:
  - README.md
  - .vbw-planning/phases/01-test/remediation/qa/round-02/R02-SUMMARY.md
deviations: []
---
EOF
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Round 02 documented the historical process exception.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "round two docs" > README.md
  git add README.md .vbw-planning/phases/01-test/01-SUMMARY.md
  git commit -m "round two summary evidence" --quiet
  current_commit="$(git rev-parse HEAD)"
  printf '%s\n%s\n%s\n' 'stage=done' 'round=02' "round_started_at_commit=${round_anchor_commit}" > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - R02' "verified_at_commit: ${current_commit}" '---' '# Verification' 'Passed after round 2.' > .vbw-planning/phases/01-test/remediation/qa/round-02/R02-VERIFICATION.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=remediated"
}

@test "stage-done resume does not resurrect stale phase-level known issues after cleared round verification" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa/round-01
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  round_anchor_commit="$(git rev-parse HEAD)"
  cat > .vbw-planning/phases/01-test/01-VERIFICATION.md <<'EOF'
---
result: PASS
writer: write-verification.sh
plans_verified:
  - 01
EOF
  printf '%s\n' "verified_at_commit: ${round_anchor_commit}" >> .vbw-planning/phases/01-test/01-VERIFICATION.md
  cat >> .vbw-planning/phases/01-test/01-VERIFICATION.md <<'EOF'
---

## Pre-existing Issues

| Test | File | Error |
|------|------|-------|
| FIGIRegistryServiceTests | Tests/FIGIRegistryServiceTests.swift | stale phase-level issue |
EOF
  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-PLAN.md <<'EOF'
---
round: 01
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Need a real fix"}
---
EOF
  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-SUMMARY.md <<'EOF'
---
plan: R01
status: complete
files_modified:
  - src/Fix.swift
  - README.md
  - .vbw-planning/phases/01-test/01-SUMMARY.md
deviations: []
---
EOF
  mkdir -p src
  echo "real code fix" > src/Fix.swift
  echo "round pass docs" > README.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Round 01 documented the remediation outcome.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  git add src/Fix.swift README.md .vbw-planning/phases/01-test/01-SUMMARY.md
  git commit -m "round pass summary evidence" --quiet
  current_commit="$(git rev-parse HEAD)"
  printf '%s\n%s\n%s\n' 'stage=done' 'round=01' "round_started_at_commit=${round_anchor_commit}" > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - R01' "verified_at_commit: ${current_commit}" '---' '# Verification' 'Passed after remediation.' > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-VERIFICATION.md

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [ ! -f .vbw-planning/phases/01-test/known-issues.json ]
  ! echo "$output" | grep -q "next_phase_state=needs_qa_remediation"
}

@test "qa_status degrades gracefully with corrupt round in state file" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  printf '%s\n%s\n' 'stage=done' 'round=abc' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  echo "# My Project" > .vbw-planning/PROJECT.md
  # Phase-level with PASS (brownfield fallback target)
  current_commit="$(git rev-parse HEAD)"
  printf '%s\n' '---' 'result: PASS' "verified_at_commit: ${current_commit}" '---' '# Verification' 'Passed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  # Must not crash — exits 0
  [ "$status" -eq 0 ]
}

@test "needs_qa_remediation blocks needs_verification" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Failed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  printf '%s\n%s\n' 'stage=plan' 'round=01' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  echo "# My Project" > .vbw-planning/PROJECT.md
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_qa_remediation"
}

@test "later active QA remediation takes priority over earlier unverified phase" {
  echo "# My Project" > .vbw-planning/PROJECT.md

  # Phase 01: fully built, no UAT yet → unverified
  mkdir -p .vbw-planning/phases/01-unverified
  echo "# Plan" > .vbw-planning/phases/01-unverified/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-unverified/01-SUMMARY.md

  # Phase 02: fully built with active QA remediation
  mkdir -p .vbw-planning/phases/02-remediating/remediation/qa
  echo "# Plan" > .vbw-planning/phases/02-remediating/02-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/02-remediating/02-SUMMARY.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Failed.' > .vbw-planning/phases/02-remediating/02-VERIFICATION.md
  printf '%s\n%s\n' 'stage=execute' 'round=01' > .vbw-planning/phases/02-remediating/remediation/qa/.qa-remediation-stage

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_qa_remediation"
  echo "$output" | grep -q "next_phase=02"
  echo "$output" | grep -q "next_phase_slug=02-remediating"
  echo "$output" | grep -q "qa_status=remediating"
}

@test "earlier UAT remediation keeps priority over later active QA remediation" {
  echo "# My Project" > .vbw-planning/PROJECT.md

  # Phase 01: unresolved UAT issues
  mkdir -p .vbw-planning/phases/01-uat-issues
  echo "# Plan" > .vbw-planning/phases/01-uat-issues/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-uat-issues/01-SUMMARY.md
  cat > .vbw-planning/phases/01-uat-issues/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
---
- Severity: major
EOF

  # Phase 02: active QA remediation
  mkdir -p .vbw-planning/phases/02-remediating/remediation/qa
  echo "# Plan" > .vbw-planning/phases/02-remediating/02-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/02-remediating/02-SUMMARY.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Failed.' > .vbw-planning/phases/02-remediating/02-VERIFICATION.md
  printf '%s\n%s\n' 'stage=execute' 'round=01' > .vbw-planning/phases/02-remediating/remediation/qa/.qa-remediation-stage

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  echo "$output" | grep -q "next_phase=01"
}

@test "later active QA remediation backed by known issues outranks earlier unplanned phase" {
  echo "# My Project" > .vbw-planning/PROJECT.md

  mkdir -p .vbw-planning/phases/01-unplanned

  mkdir -p .vbw-planning/phases/02-remediating/remediation/qa
  echo "# Plan" > .vbw-planning/phases/02-remediating/02-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/02-remediating/02-SUMMARY.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Failed.' > .vbw-planning/phases/02-remediating/02-VERIFICATION.md
  printf '%s\n%s\n' 'stage=execute' 'round=01' > .vbw-planning/phases/02-remediating/remediation/qa/.qa-remediation-stage
  cat > .vbw-planning/phases/02-remediating/known-issues.json <<'EOF'
{
  "schema_version": 1,
  "phase": "02",
  "issues": [
    {
      "test": "FIGIRegistryServiceTests",
      "file": "Tests/FIGIRegistryServiceTests.swift",
      "error": "compositeFigi missing",
      "first_seen_in": "02-01-SUMMARY.md",
      "last_seen_in": "02-VERIFICATION.md",
      "first_seen_round": 0,
      "last_seen_round": 0,
      "times_seen": 2
    }
  ]
}
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_qa_remediation"
  echo "$output" | grep -q "next_phase=02"
}

@test "earlier unfinished work still emits failed QA-attention for later stage-less known-issues backlog" {
  echo "# My Project" > .vbw-planning/PROJECT.md

  mkdir -p .vbw-planning/phases/01-unplanned

  mkdir -p .vbw-planning/phases/02-known-issues
  echo "# Plan" > .vbw-planning/phases/02-known-issues/02-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/02-known-issues/02-SUMMARY.md
  current_commit="$(git rev-parse HEAD)"
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - 02' "verified_at_commit: ${current_commit}" '---' '# Verification' 'Passed.' > .vbw-planning/phases/02-known-issues/02-VERIFICATION.md
  cat > .vbw-planning/phases/02-known-issues/known-issues.json <<'EOF'
{
  "schema_version": 1,
  "phase": "02",
  "issues": [
    {
      "test": "FIGIRegistryServiceTests",
      "file": "Tests/FIGIRegistryServiceTests.swift",
      "error": "compositeFigi missing",
      "first_seen_in": "02-01-SUMMARY.md",
      "last_seen_in": "02-VERIFICATION.md",
      "first_seen_round": 0,
      "last_seen_round": 0,
      "times_seen": 2
    }
  ]
}
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_state=needs_plan_and_execute"
  echo "$output" | grep -q "first_qa_attention_phase=02"
  echo "$output" | grep -q "first_qa_attention_slug=02-known-issues"
  echo "$output" | grep -q "qa_attention_status=failed"
}

@test "later active QA remediation outranks earlier mid-execution phase" {
  echo "# My Project" > .vbw-planning/PROJECT.md

  mkdir -p .vbw-planning/phases/01-executing
  echo "# Plan" > .vbw-planning/phases/01-executing/01-01-PLAN.md

  mkdir -p .vbw-planning/phases/02-remediating/remediation/qa
  echo "# Plan" > .vbw-planning/phases/02-remediating/02-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/02-remediating/02-SUMMARY.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Failed.' > .vbw-planning/phases/02-remediating/02-VERIFICATION.md
  printf '%s\n%s\n' 'stage=execute' 'round=01' > .vbw-planning/phases/02-remediating/remediation/qa/.qa-remediation-stage

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_qa_remediation"
  echo "$output" | grep -q "next_phase=02"
}

@test "qa_status is pending when PASS verification is stale for current code" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md

  echo "print(\"old\")" > app.py
  git add app.py
  git commit -m "old app" --quiet
  verified_commit="$(git rev-parse HEAD)"

  printf '%s\n' \
    '---' \
    'result: PASS' \
    "verified_at_commit: ${verified_commit}" \
    '---' \
    '# Verification' \
    'Passed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md

  echo "print(\"new\")" > app.py
  git add app.py
  git commit -m "new app" --quiet

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=pending" || {
    echo "# DIAG: full phase-detect.sh output follows" >&3
    echo "$output" >&3
    false
  }
}

@test "qa_status is pending for brownfield PASS verification after later commit" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md

  echo "print(\"before\")" > app.py
  git add app.py
  git commit -m "before qa" --quiet

  printf '%s\n' '---' 'result: PASS' '---' '# Verification' 'Passed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  echo "print(\"after\")" > app.py
  git add app.py
  git commit -m "after qa" --quiet

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=pending" || {
    echo "# DIAG: full phase-detect.sh output follows" >&3
    echo "$output" >&3
    false
  }
}

@test "qa_status is pending when PASS verification has uncommitted product changes" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md

  echo "print(\"clean\")" > app.py
  git add app.py
  git commit -m "clean app" --quiet
  verified_commit="$(git rev-parse HEAD)"

  printf '%s\n' \
    '---' \
    'result: PASS' \
    "verified_at_commit: ${verified_commit}" \
    '---' \
    '# Verification' \
    'Passed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md

  echo "print(\"dirty\")" > app.py

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=pending" || {
    echo "# DIAG: full phase-detect.sh output follows" >&3
    echo "$output" >&3
    false
  }
}

@test "qa_status is pending when structured phase PASS fails qa-result-gate" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  cat > .vbw-planning/phases/01-test/01-SUMMARY.md <<'EOF'
---
status: complete
deviations:
  - Changed API approach
---
EOF
  echo "# My Project" > .vbw-planning/PROJECT.md

  printf '%s\n' \
    '---' \
    'result: PASS' \
    'writer: ' \
    '---' \
    '# Verification' \
    'Passed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=pending"
}

@test "qa_status is pending for brownfield remediated verification after later commit" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md

  echo "print(\"before\")" > app.py
  git add app.py
  git commit -m "before remediated qa" --quiet

  printf '%s\n' '---' 'result: PASS' '---' '# Verification' 'Passed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  printf '%s\n%s\n' 'stage=done' 'round=01' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage
  echo "print(\"after\")" > app.py
  git add app.py
  git commit -m "after remediated qa" --quiet

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qa_status=pending"
}

@test "first_qa_attention targets stale QA even when terminal UAT exists" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md

  echo "print(\"before\")" > app.py
  git add app.py
  git commit -m "before stale qa with uat" --quiet
  verified_commit="$(git rev-parse HEAD)"

  printf '%s\n' \
    '---' \
    'result: PASS' \
    "verified_at_commit: ${verified_commit}" \
    '---' \
    '# Verification' \
    'Passed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md

  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: complete
---
All tests passed.
EOF

  echo "print(\"after\")" > app.py
  git add app.py
  git commit -m "after stale qa with uat" --quiet

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_slug=01-test"
  echo "$output" | grep -q "next_phase_state=needs_verification"
  echo "$output" | grep -q "first_qa_attention_phase=01"
  echo "$output" | grep -q "first_qa_attention_slug=01-test"
  echo "$output" | grep -q "qa_attention_status=pending"
}

@test "all_done routes to QA remediation when authoritative QA failed despite terminal UAT" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md

  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Failed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md

  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: complete
---
All tests passed.
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_state=needs_qa_remediation"
  echo "$output" | grep -q "first_qa_attention_phase=01"
  echo "$output" | grep -q "qa_attention_status=failed"
}

@test "terminal UAT QA-attention restore rebuilds missing registry before routing" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md
  current_commit="$(git rev-parse HEAD)"
  cat > .vbw-planning/phases/01-test/01-VERIFICATION.md <<'EOF'
---
result: PASS
writer: write-verification.sh
plans_verified:
  - 01
EOF
  printf '%s\n' "verified_at_commit: ${current_commit}" >> .vbw-planning/phases/01-test/01-VERIFICATION.md
  cat >> .vbw-planning/phases/01-test/01-VERIFICATION.md <<'EOF'
---

## Pre-existing Issues

| Test | File | Error |
|------|------|-------|
| FIGIRegistryServiceTests | Tests/FIGIRegistryServiceTests.swift | compositeFigi missing |
EOF
  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: complete
---
All tests passed.
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [ -f .vbw-planning/phases/01-test/known-issues.json ]
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_state=needs_qa_remediation"
  echo "$output" | grep -q "qa_attention_status=failed"
}

@test "all_done without UAT routes to QA remediation when known issues already failed QA" {
  mkdir -p .vbw-planning/phases/01-test
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md

  current_commit="$(git rev-parse HEAD)"
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - 01' "verified_at_commit: ${current_commit}" '---' '# Verification' 'Passed.' > .vbw-planning/phases/01-test/01-VERIFICATION.md
  cat > .vbw-planning/phases/01-test/known-issues.json <<'EOF'
{
  "schema_version": 1,
  "phase": "01",
  "issues": [
    {
      "test": "FIGIRegistryServiceTests",
      "file": "Tests/FIGIRegistryServiceTests.swift",
      "error": "compositeFigi missing",
      "first_seen_in": "01-01-SUMMARY.md",
      "last_seen_in": "01-VERIFICATION.md",
      "first_seen_round": 0,
      "last_seen_round": 0,
      "times_seen": 2
    }
  ]
}
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_slug=01-test"
  echo "$output" | grep -q "next_phase_state=needs_qa_remediation"
  echo "$output" | grep -q "first_qa_attention_phase=01"
  echo "$output" | grep -q "qa_attention_status=failed"
  echo "$output" | grep -q "qa_status=failed"
}

@test "all_done routes to QA remediation when round-scoped PASS fails deterministic gate" {
  mkdir -p .vbw-planning/phases/01-test/remediation/qa/round-01
  echo "# Plan" > .vbw-planning/phases/01-test/01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/01-test/01-SUMMARY.md
  echo "# My Project" > .vbw-planning/PROJECT.md

  cat > .vbw-planning/phases/01-test/01-VERIFICATION.md <<'EOF'
---
result: FAIL
writer: write-verification.sh
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Original failure still needs remediation | FAIL | Missing |
EOF

  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-PLAN.md <<'EOF'
---
round: 01
fail_classifications:
  - {id: "FAIL-01", type: "code-fix", rationale: "Code still needs to change"}
---
EOF
  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-SUMMARY.md <<'EOF'
---
plan: R01
status: complete
files_modified:
  - README.md
deviations: []
---
EOF
  cat > .vbw-planning/phases/01-test/remediation/qa/round-01/R01-VERIFICATION.md <<'EOF'
---
result: PASS
writer: write-verification.sh
plans_verified:
  - R01
---
## Summary
Result: PASS
EOF
  printf 'stage=done\nround=01\n' > .vbw-planning/phases/01-test/remediation/qa/.qa-remediation-stage

  cat > .vbw-planning/phases/01-test/01-UAT.md <<'EOF'
---
phase: 01
status: complete
---
All tests passed.
EOF

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase=01"
  echo "$output" | grep -q "next_phase_state=needs_qa_remediation"
  echo "$output" | grep -q "qa_attention_status=failed"
}

@test "verify-stage QA remediation outranks earlier unfinished work" {
  echo "# My Project" > .vbw-planning/PROJECT.md

  mkdir -p .vbw-planning/phases/01-unplanned

  mkdir -p .vbw-planning/phases/02-remediating/remediation/qa/round-01
  echo "# Plan" > .vbw-planning/phases/02-remediating/02-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' '# Summary' 'Done.' > .vbw-planning/phases/02-remediating/02-SUMMARY.md
  printf '%s\n' '---' 'result: FAIL' '---' '# Verification' 'Failed.' > .vbw-planning/phases/02-remediating/02-VERIFICATION.md
  printf '%s\n%s\n' 'stage=verify' 'round=01' > .vbw-planning/phases/02-remediating/remediation/qa/.qa-remediation-stage

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase=02"
  echo "$output" | grep -q "next_phase_state=needs_qa_remediation"
  echo "$output" | grep -q "first_qa_attention_phase=02"
  echo "$output" | grep -q "first_qa_attention_slug=02-remediating"
  echo "$output" | grep -q "qa_attention_status=verify"
}

# ---------- #369: cross-session reverification routing ----------

@test "phase-detect: stage=done + round UAT with issues_found routes to needs_uat_remediation" {
  # Scenario: UAT remediation round 02 completed, re-verification found issues,
  # but the session ended before auto-continuing to round 03. The next session
  # should recognise the round UAT and route to remediation, not re-verify.
  mkdir -p .vbw-planning/phases/01-feature/remediation/uat/round-01
  mkdir -p .vbw-planning/phases/01-feature/remediation/uat/round-02
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-feature/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
issues: 1
---
## Tests
### P01-T1: sample test
- **Result:** issue
EOF
  # Round 01 UAT (prior round, already remediated)
  cat > .vbw-planning/phases/01-feature/remediation/uat/round-01/R01-UAT.md <<'EOF'
---
phase: 01
round: 01
status: issues_found
issues: 1
---
## Tests
### P01-T1: sample test
- **Result:** issue
EOF
  # Round 02 UAT — re-verification happened, still has issues
  cat > .vbw-planning/phases/01-feature/remediation/uat/round-02/R02-UAT.md <<'EOF'
---
phase: 01
round: 02
status: issues_found
issues: 1
---
## Tests
### P01-T1: sample test
- **Result:** issue
- **Issue:** fix did not resolve
  - Description: test still fails
  - Severity: major
EOF
  # Remediation state: round 02 done
  printf 'stage=done\nround=02\nlayout=round-dir\n' > .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  # State file should be auto-advanced to round 03, stage=research
  grep -q '^stage=research$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  grep -q '^round=03$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  # Round 03 directory should be created
  [ -d .vbw-planning/phases/01-feature/remediation/uat/round-03 ]
}

@test "phase-detect: stage=done + no round UAT routes to needs_reverification" {
  # Scenario: UAT remediation round 02 completed execution, but re-verification
  # has NOT happened yet. Should route to needs_reverification so it can run.
  mkdir -p .vbw-planning/phases/01-feature/remediation/uat/round-02
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-feature/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
issues: 1
---
## Tests
### P01-T1: sample test
- **Result:** issue
EOF
  touch .vbw-planning/phases/01-feature/remediation/uat/round-02/R02-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/remediation/uat/round-02/R02-SUMMARY.md
  # Remediation state: round 02 done, but NO R02-UAT.md
  printf 'stage=done\nround=02\nlayout=round-dir\n' > .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_reverification"
  # State file should NOT be modified
  grep -q '^stage=done$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  grep -q '^round=02$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
}

@test "phase-detect: stage=done + round UAT with complete status does NOT trigger remediation" {
  # Scenario: UAT remediation round 01 completed, re-verification passed.
  # Phase-detect sees no active UAT issues since round UAT is complete,
  # so it exits the remediation routing block. Must NOT start another round.
  mkdir -p .vbw-planning/phases/01-feature/remediation/uat/round-01
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-feature/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
issues: 1
---
## Tests
### P01-T1: sample test
- **Result:** issue
EOF
  # Round 01 UAT — re-verification passed (all tests passed)
  cat > .vbw-planning/phases/01-feature/remediation/uat/round-01/R01-UAT.md <<'EOF'
---
phase: 01
round: 01
status: complete
issues: 0
---
## Tests
### P01-T1: sample test
- **Result:** pass
EOF
  # Remediation state: round 01 done
  printf 'stage=done\nround=01\nlayout=round-dir\n' > .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # When round UAT is complete (tests passed), must NOT trigger another remediation round
  ! echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  # Phase exits remediation routing entirely — routes to standard verification
  echo "$output" | grep -q "next_phase_state=needs_verification"
  # State file should NOT be modified — no round advancement
  grep -q '^stage=done$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
  grep -q '^round=01$' .vbw-planning/phases/01-feature/remediation/uat/.uat-remediation-stage
}

@test "phase-detect: stage=done + legacy layout routes to needs_uat_remediation with correct paths" {
  # Scenario: Legacy brownfield project uses .uat-remediation-stage at phase root
  # and stores round UATs under remediation/round-NN/ (no /uat/ prefix).
  # The auto-advance must create remediation/round-02 (legacy), NOT remediation/uat/round-02.
  mkdir -p .vbw-planning/phases/01-feature/remediation/round-01
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md
  cat > .vbw-planning/phases/01-feature/01-UAT.md <<'EOF'
---
phase: 01
status: issues_found
issues: 1
---
## Tests
### P01-T1: sample test
- **Result:** issue
EOF
  # Round 01 UAT at legacy path — re-verification found issues
  cat > .vbw-planning/phases/01-feature/remediation/round-01/R01-UAT.md <<'EOF'
---
phase: 01
round: 01
status: issues_found
issues: 1
---
## Tests
### P01-T1: sample test
- **Result:** issue
EOF
  # Legacy state file at phase root (no /uat/ prefix)
  printf 'stage=done\nround=01\n' > .vbw-planning/phases/01-feature/.uat-remediation-stage

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_uat_remediation"
  # State file should advance to round 02, stage=research, layout=legacy
  grep -q '^stage=research$' .vbw-planning/phases/01-feature/.uat-remediation-stage
  grep -q '^round=02$' .vbw-planning/phases/01-feature/.uat-remediation-stage
  grep -q '^layout=legacy$' .vbw-planning/phases/01-feature/.uat-remediation-stage
  # Legacy layout: create remediation/round-02 (NOT remediation/uat/round-02)
  [ -d .vbw-planning/phases/01-feature/remediation/round-02 ]
  [ ! -d .vbw-planning/phases/01-feature/remediation/uat/round-02 ]
}
