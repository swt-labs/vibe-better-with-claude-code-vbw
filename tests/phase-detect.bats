#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"
  touch dummy && git add dummy && git commit -m "init" --quiet
}

teardown() {
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
  touch .vbw-planning/phases/01-test/01-01-SUMMARY.md
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
  touch .vbw-planning/phases/01-test/01-01-SUMMARY.md
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
  echo "$output" | grep -q "uat_issues_phase=01"
  echo "$output" | grep -q "uat_issues_major_or_higher=true"
}

@test "minor-only UAT issues set major-or-higher flag false" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  touch .vbw-planning/phases/01-test/01-01-SUMMARY.md
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
  touch .vbw-planning/phases/01-test/01-01-SUMMARY.md
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

@test "re-verified UAT with status complete clears remediation state" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  touch .vbw-planning/phases/01-test/01-01-SUMMARY.md

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
  echo "$output" | grep -q "next_phase_state=all_done"
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
  touch .vbw-planning/phases/01-partial/01-01-SUMMARY.md
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

@test "dotfile PLAN files are not counted as plan artifacts" {
  mkdir -p .vbw-planning/phases/01-test/
  touch .vbw-planning/phases/01-test/01-01-PLAN.md
  touch .vbw-planning/phases/01-test/01-01-SUMMARY.md
  # Dotfile — should NOT count (ls glob ignores dotfiles)
  touch ".vbw-planning/phases/01-test/.01-02-PLAN.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # 1 plan, 1 summary → all_done (dotfile plan not counted)
  echo "$output" | grep -q "next_phase_state=all_done"
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
    touch "${dir}${p}-01-SUMMARY.md"
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
