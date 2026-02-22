#!/usr/bin/env bats

# Tests for milestone path guards in uat-remediation-state.sh, compile-context.sh,
# and file-guard.sh — preventing execution in archived milestone directories.

load test_helper

setup() {
  setup_temp_dir
  # Active phases
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  # Archived milestone (simulating the bug scenario)
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/milestones/01-shipped/phases/08-feature"
  create_test_config
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

# --- uat-remediation-state.sh guards ---

@test "uat-remediation-state refuses init on milestone path" {
  MILESTONE_PHASE="$TEST_TEMP_DIR/.vbw-planning/milestones/01-shipped/phases/08-feature"
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$MILESTONE_PHASE" "major"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to operate on archived milestone"* ]]
}

@test "uat-remediation-state refuses get on milestone path" {
  MILESTONE_PHASE="$TEST_TEMP_DIR/.vbw-planning/milestones/01-shipped/phases/08-feature"
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" get "$MILESTONE_PHASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to operate on archived milestone"* ]]
}

@test "uat-remediation-state refuses advance on milestone path" {
  MILESTONE_PHASE="$TEST_TEMP_DIR/.vbw-planning/milestones/01-shipped/phases/08-feature"
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" advance "$MILESTONE_PHASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to operate on archived milestone"* ]]
}

@test "uat-remediation-state refuses reset on milestone path" {
  MILESTONE_PHASE="$TEST_TEMP_DIR/.vbw-planning/milestones/01-shipped/phases/08-feature"
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" reset "$MILESTONE_PHASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to operate on archived milestone"* ]]
}

@test "uat-remediation-state allows init on active phase path" {
  ACTIVE_PHASE="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  cat > "$ACTIVE_PHASE/01-UAT.md" <<'EOF'
# UAT
- Issue
EOF
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$ACTIVE_PHASE" "major"
  [ "$status" -eq 0 ]
  [ "$output" = "plan" ]
}

@test "uat-remediation-state error message suggests create-remediation-phase.sh" {
  MILESTONE_PHASE="$TEST_TEMP_DIR/.vbw-planning/milestones/01-shipped/phases/08-feature"
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$MILESTONE_PHASE" "major"
  [ "$status" -eq 1 ]
  [[ "$output" == *"create-remediation-phase.sh"* ]]
}

@test "uat-remediation-state no false positive when parent dir named milestones" {
  # Workspace path contains 'milestones' but phase is an active phase, not archived
  MILESTONES_WORKSPACE=$(mktemp -d "${TMPDIR:-/tmp}/milestones-project.XXXXXX")
  mkdir -p "$MILESTONES_WORKSPACE/.vbw-planning/phases/01-test"
  cat > "$MILESTONES_WORKSPACE/.vbw-planning/phases/01-test/01-UAT.md" <<'EOF'
# UAT
- Issue
EOF
  run bash "$SCRIPTS_DIR/uat-remediation-state.sh" init "$MILESTONES_WORKSPACE/.vbw-planning/phases/01-test" "major"
  [ "$status" -eq 0 ]
  [ "$output" = "plan" ]
  rm -rf "$MILESTONES_WORKSPACE"
}

# --- compile-context.sh guards ---

@test "compile-context refuses milestone phases_dir" {
  run bash "$SCRIPTS_DIR/compile-context.sh" 08 dev ".vbw-planning/milestones/01-shipped/phases"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to compile context for archived milestone"* ]]
}

@test "compile-context allows active phases_dir" {
  # Need ROADMAP for compile-context to work
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
## Phase 1: Test
**Goal:** Test goal
**Reqs:** REQ-01
**Success:** Tests pass
EOF
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead ".vbw-planning/phases"
  # May fail for other reasons (missing files) but NOT the milestone guard
  [[ "$output" != *"refusing to compile context for archived milestone"* ]]
}

@test "compile-context no false positive when parent dir named milestones" {
  MILESTONES_WORKSPACE=$(mktemp -d "${TMPDIR:-/tmp}/milestones-project.XXXXXX")
  mkdir -p "$MILESTONES_WORKSPACE/.vbw-planning/phases/01-test"
  cat > "$MILESTONES_WORKSPACE/.vbw-planning/ROADMAP.md" <<'EOF'
## Phase 1: Test
**Goal:** Test goal
**Reqs:** REQ-01
**Success:** Tests pass
EOF
  cd "$MILESTONES_WORKSPACE"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead ".vbw-planning/phases"
  [[ "$output" != *"refusing to compile context for archived milestone"* ]]
  cd "$TEST_TEMP_DIR"
  rm -rf "$MILESTONES_WORKSPACE"
}

# --- file-guard.sh guards ---

@test "file-guard blocks writes to milestone phase artifacts" {
  # file-guard reads JSON from stdin
  INPUT='{"tool_input":{"file_path":".vbw-planning/milestones/01-shipped/phases/08-feature/08-04-PLAN.md"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"archived milestone phases"* ]]
}

@test "file-guard allows writes to active planning dir" {
  INPUT='{"tool_input":{"file_path":".vbw-planning/phases/01-test/01-01-PLAN.md"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard blocks writes to deeply nested milestone phase paths" {
  INPUT='{"tool_input":{"file_path":".vbw-planning/milestones/02-v2/phases/03-auth/03-01-SUMMARY.md"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"archived milestone phases"* ]]
}

@test "file-guard allows SHIPPED.md writes to milestone root (archive mode)" {
  INPUT='{"tool_input":{"file_path":".vbw-planning/milestones/01-shipped/SHIPPED.md"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard allows STATE.md writes to milestone root (archive mode)" {
  INPUT='{"tool_input":{"file_path":".vbw-planning/milestones/01-shipped/STATE.md"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard allows ROADMAP.md writes to milestone root (archive mode)" {
  INPUT='{"tool_input":{"file_path":".vbw-planning/milestones/01-shipped/ROADMAP.md"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}
