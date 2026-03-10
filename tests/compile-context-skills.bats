#!/usr/bin/env bats

# Tests for skill context in compile-context.sh
# Verifies emit_skills_section() does NOT inject ### Available Skills (removed)
# and only emits ### Mandatory Skill Activation when plan has skills_used

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase"
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 1: Test Phase
**Goal:** Test goal
**Success:** Tests pass
**Reqs:** REQ-01
EOF
  cat > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md" <<'EOF'
- [ ] REQ-01: Test requirement
EOF
}

teardown() {
  teardown_temp_dir
}

# --- Helper: create a fake skill ---
create_test_skill() {
  local skill_name="${1:-test-skill}"
  local skill_dir="$TEST_TEMP_DIR/.claude/skills/$skill_name"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<SKILL
---
name: $skill_name
description: A test skill for unit testing
---
# $skill_name
Body content here.
SKILL
}

# --- Helper: create a plan with skills_used frontmatter ---
create_plan_with_skills() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/PLAN.md" <<'EOF'
---
skills_used:
  - test-skill
---
# Plan
## Tasks
- [ ] TASK-01: Do something
EOF
}

@test "compile-context: no Available Skills section for any role" {
  create_test_skill "my-skill"
  for role in lead dev qa scout debugger architect; do
    cd "$TEST_TEMP_DIR"
    run bash "$SCRIPTS_DIR/compile-context.sh" 01 "$role" .vbw-planning/phases
    [ "$status" -eq 0 ]
    ! grep -q "### Available Skills" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-${role}.md"
  done
}

@test "compile-context: no available_skills XML tags in output" {
  create_test_skill "xml-test"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  ! grep -q "<available_skills>" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
  ! grep -q "</available_skills>" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
}

@test "compile-context: no mandatory skill activation (emit_skills_section removed)" {
  create_test_skill "test-skill"
  create_plan_with_skills
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  ! grep -q "### Mandatory Skill Activation" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
}

@test "compile-context: no mandatory skill activation even without skills_used" {
  cd "$TEST_TEMP_DIR"
  # Plan without skills_used frontmatter
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/PLAN.md" <<'EOF'
---
effort: balanced
---
# Plan
## Tasks
- [ ] TASK-01: Do something
EOF
  # Override HOME so no real user skills are found
  HOME="$TEST_TEMP_DIR" run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  ! grep -q "### Mandatory Skill Activation" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
}
