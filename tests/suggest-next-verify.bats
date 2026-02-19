#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

create_phase_with_uat() {
  local phase="$1"
  local slug="$2"
  local severity="${3:-major}"
  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/${phase}-${slug}"
  local uat_file="$phase_dir/${phase}-UAT.md"

  mkdir -p "$phase_dir"

  cat > "$phase_dir/${phase}-01-PLAN.md" <<EOF
---
phase: $phase
plan: ${phase}-01
title: Sample plan
---
EOF

  cat > "$phase_dir/${phase}-01-SUMMARY.md" <<EOF
---
status: complete
deviations: 0
---
Done.
EOF

  cat > "$uat_file" <<EOF
---
phase: $phase
status: issues_found
---

## Tests

### P01-T1: sample

- **Result:** issue
- **Issue:** sample issue
EOF

  if [ "$severity" != "none" ]; then
    cat >> "$uat_file" <<EOF
  - Severity: $severity
EOF
  fi
}

@test "suggest-next verify issues_found escalates major issues to plain vibe remediation" {
  cd "$TEST_TEMP_DIR"
  create_phase_with_uat "08" "cost-basis-integrity-warnings" "major"

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 08

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:vibe -- Continue UAT remediation for Phase 8"* ]]
  [[ "$output" == *"/vbw:verify --resume -- Continue testing after changes"* ]]
  [[ "$output" != *"/vbw:fix -- Fix the issues found during UAT"* ]]
}

@test "suggest-next verify issues_found keeps quick-fix path for minor-only issues" {
  cd "$TEST_TEMP_DIR"
  create_phase_with_uat "03" "ui-polish" "minor"

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 03

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:fix -- Fix the issues found during UAT"* ]]
  [[ "$output" == *"/vbw:verify --resume -- Continue testing after fix"* ]]
  [[ "$output" != *"/vbw:vibe -- Continue UAT remediation for Phase 3"* ]]
}

@test "suggest-next verify issues_found defaults to escalation when severity is absent" {
  cd "$TEST_TEMP_DIR"
  create_phase_with_uat "05" "legacy-format" "none"

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 05

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:vibe -- Continue UAT remediation for Phase 5"* ]]
}

@test "suggest-next verify issues_found detects bold-markdown severity format" {
  cd "$TEST_TEMP_DIR"
  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/06-bold-fmt"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/06-01-PLAN.md" <<'EOF'
---
phase: 06
plan: 06-01
title: Sample plan
---
EOF
  cat > "$phase_dir/06-01-SUMMARY.md" <<'EOF'
---
status: complete
deviations: 0
---
Done.
EOF
  cat > "$phase_dir/06-UAT.md" <<'EOF'
---
phase: 06
status: issues_found
---

## Tests

### P01-T1: sample

- **Result:** issue
- **Issue:** sample issue
  - **Severity:** critical
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 06

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:vibe -- Continue UAT remediation for Phase 6"* ]]
  [[ "$output" != *"/vbw:fix"* ]]
}

@test "suggest-next verify issues_found detects bare-text minor severity" {
  cd "$TEST_TEMP_DIR"
  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/07-bare-fmt"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/07-01-PLAN.md" <<'EOF'
---
phase: 07
plan: 07-01
title: Sample plan
---
EOF
  cat > "$phase_dir/07-01-SUMMARY.md" <<'EOF'
---
status: complete
deviations: 0
---
Done.
EOF
  cat > "$phase_dir/07-UAT.md" <<'EOF'
---
phase: 07
status: issues_found
---

## Tests

### P01-T1: sample

- **Result:** issue
- **Issue:** typo in label
Severity: minor
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 07

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:fix -- Fix the issues found during UAT"* ]]
  [[ "$output" != *"/vbw:vibe -- Continue UAT remediation"* ]]
}

@test "suggest-next verify issues_found handles unpadded phase number" {
  cd "$TEST_TEMP_DIR"
  create_phase_with_uat "03" "ui-polish" "minor"

  # Pass unpadded "3" instead of "03"
  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 3

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:fix -- Fix the issues found during UAT"* ]]
  [[ "$output" != *"/vbw:vibe -- Continue UAT remediation"* ]]
}

@test "suggest-next verify issues_found unpadded phase escalates major correctly" {
  cd "$TEST_TEMP_DIR"
  create_phase_with_uat "08" "api-layer" "major"

  # Pass unpadded "8" instead of "08"
  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 8

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:vibe -- Continue UAT remediation"* ]]
  [[ "$output" != *"/vbw:fix"* ]]
}

@test "suggest-next verify issues_found no-arg targets first UAT phase numerically" {
  cd "$TEST_TEMP_DIR"
  # Create two phases with UAT issues — 11 and 100
  create_phase_with_uat "11" "eleven" "major"
  create_phase_with_uat "100" "hundred" "major"

  # No phase arg — should target 11 (first numerically), not 100 (first lexicographically)
  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:vibe -- Continue UAT remediation for Phase 11"* ]]
}

@test "suggest-next verify issues_found no-arg with all-complete UATs shows fix not remediation" {
  cd "$TEST_TEMP_DIR"
  # Two phases fully executed with UATs that passed (status: complete)
  for p in 03 04; do
    case $p in 03) s=ui;; 04) s=api;; esac
    local dir="$TEST_TEMP_DIR/.vbw-planning/phases/${p}-${s}"
    mkdir -p "$dir"
    printf -- '---\nphase: %s\nplan: %s-01\n---\n' "$p" "$p" > "${dir}/${p}-01-PLAN.md"
    printf -- '---\nstatus: complete\ndeviations: 0\n---\n' > "${dir}/${p}-01-SUMMARY.md"
    printf -- '---\nphase: %s\nstatus: complete\n---\nAll passed.\n' "$p" > "${dir}/${p}-UAT.md"
  done

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:fix"* ]]
  [[ "$output" != *"remediation"* ]]
}

@test "suggest-next verify issues_found no-arg with no UAT files shows fix not remediation" {
  cd "$TEST_TEMP_DIR"
  # Single phase fully executed, no UAT file
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/03-ui"
  mkdir -p "$dir"
  printf -- '---\nphase: 03\nplan: 03-01\n---\n' > "${dir}/03-01-PLAN.md"
  printf -- '---\nstatus: complete\ndeviations: 0\n---\n' > "${dir}/03-01-SUMMARY.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:fix"* ]]
  [[ "$output" != *"remediation"* ]]
}

@test "suggest-next verify issues_found no-arg ignores non-canonical PLAN files in execution guard" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/03-ui"
  mkdir -p "$dir"
  # Non-canonical PLAN file — should NOT satisfy the execution guard
  touch "${dir}/not-a-PLAN.md"
  printf -- '---\nstatus: complete\ndeviations: 0\n---\n' > "${dir}/not-a-SUMMARY.md"
  printf -- '---\nphase: 03\nstatus: issues_found\n---\nSeverity: major\n' > "${dir}/03-UAT.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found

  [ "$status" -eq 0 ]
  # Execution guard should reject this phase (0 canonical plans)
  [[ "$output" != *"remediation"* ]]
  [[ "$output" == *"/vbw:fix"* ]]
}

@test "suggest-next verify issues_found no-arg ignores dotfile PLAN artifacts" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/03-ui"
  mkdir -p "$dir"
  # Only canonical artifacts
  printf -- '---\nphase: 03\nplan: 03-01\n---\n' > "${dir}/03-01-PLAN.md"
  printf -- '---\nstatus: complete\ndeviations: 0\n---\n' > "${dir}/03-01-SUMMARY.md"
  # Dotfile — must NOT count (matching ls behavior in phase-detect.sh)
  touch "${dir}/.03-02-PLAN.md"
  printf -- '---\nphase: 03\nstatus: issues_found\n---\nSeverity: major\n' > "${dir}/03-UAT.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found

  [ "$status" -eq 0 ]
  # 1 canonical plan, 1 summary → execution guard passes → remediation triggered
  [[ "$output" == *"/vbw:vibe -- Continue UAT remediation for Phase 3"* ]]
}

@test "suggest-next verify issues_found no-arg skips orphan UAT without execution artifacts" {
  cd "$TEST_TEMP_DIR"
  # Phase with UAT file but no PLAN/SUMMARY (orphan) — should be skipped
  local orphan_dir="$TEST_TEMP_DIR/.vbw-planning/phases/02-orphan"
  mkdir -p "$orphan_dir"
  printf -- '---\nphase: 02\nstatus: issues_found\n---\nSeverity: major\n' > "${orphan_dir}/02-UAT.md"

  # Phase with full execution artifacts + complete UAT — not a remediation target
  local complete_dir="$TEST_TEMP_DIR/.vbw-planning/phases/05-complete"
  mkdir -p "$complete_dir"
  printf -- '---\nphase: 05\nplan: 05-01\n---\n' > "${complete_dir}/05-01-PLAN.md"
  printf -- '---\nstatus: complete\ndeviations: 0\n---\n' > "${complete_dir}/05-01-SUMMARY.md"
  printf -- '---\nphase: 05\nstatus: complete\n---\nAll passed.\n' > "${complete_dir}/05-UAT.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found

  [ "$status" -eq 0 ]
  # Should NOT trigger remediation from orphan phase 02
  [[ "$output" != *"remediation"* ]]
  [[ "$output" != *"Phase 2"* ]]
  # Should show generic fix guidance
  [[ "$output" == *"/vbw:fix"* ]]
}