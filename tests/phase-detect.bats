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
  echo "$output" | grep -q "uat_issues_phase=01"
  echo "$output" | grep -q "uat_issues_major_or_higher=true"
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

@test "re-verified UAT with status complete clears remediation state" {
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
  mkdir -p .vbw-planning/phases/01-feature/remediation/round-01
  mkdir -p .vbw-planning/phases/01-feature/remediation/round-02
  touch .vbw-planning/phases/01-feature/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/01-01-SUMMARY.md
  printf 'stage=execute\nround=02\nlayout=round-dir\n' > .vbw-planning/phases/01-feature/remediation/.uat-remediation-stage
  touch .vbw-planning/phases/01-feature/remediation/round-01/R01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-feature/remediation/round-01/R01-SUMMARY.md
  touch .vbw-planning/phases/01-feature/remediation/round-02/R02-PLAN.md
  # No R02-SUMMARY.md — execution not complete for round 02

  # Round 01 UAT with issues (needed to route into UAT remediation path)
  cat > .vbw-planning/phases/01-feature/remediation/round-01/R01-UAT.md <<'EOF'
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
  grep -q "^stage=execute$" .vbw-planning/phases/01-feature/remediation/.uat-remediation-stage
}