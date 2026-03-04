#!/usr/bin/env bats

# Tests for compaction-safe skill context in compile-context.sh
# Verifies emit_skills_section() injects ### Available Skills for all 6 roles

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

@test "compile-context: skills section present for lead when skills installed" {
  create_test_skill "my-skill"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "### Available Skills" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-lead.md"
  grep -q "my-skill" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-lead.md"
}

@test "compile-context: skills section present for dev when skills installed" {
  create_test_skill "dev-skill"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "### Available Skills" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
  grep -q "dev-skill" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
}

@test "compile-context: skills section present for qa when skills installed" {
  create_test_skill "qa-skill"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 qa .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "### Available Skills" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-qa.md"
  grep -q "qa-skill" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-qa.md"
}

@test "compile-context: skills section present for scout when skills installed" {
  create_test_skill "scout-skill"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 scout .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "### Available Skills" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-scout.md"
  grep -q "scout-skill" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-scout.md"
}

@test "compile-context: skills section present for debugger when skills installed" {
  create_test_skill "debug-skill"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 debugger .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "### Available Skills" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-debugger.md"
  grep -q "debug-skill" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-debugger.md"
}

@test "compile-context: skills section present for architect when skills installed" {
  create_test_skill "arch-skill"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 architect .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "### Available Skills" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-architect.md"
  grep -q "arch-skill" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-architect.md"
}

@test "compile-context: skills section absent when no skills installed" {
  cd "$TEST_TEMP_DIR"
  # Override HOME so emit-skill-xml.sh won't find real user skills
  HOME="$TEST_TEMP_DIR" run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  ! grep -q "### Available Skills" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
}

@test "compile-context: skills section contains Skill() call instruction" {
  create_test_skill "useful-skill"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "Skill(name)" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
}

@test "compile-context: VBW/GSD plugin skills filtered out" {
  create_test_skill "vbw-internal"
  create_test_skill "real-skill"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "real-skill" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
  ! grep -q "vbw-internal" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
}

@test "compile-context: skills section uses XML format" {
  create_test_skill "xml-test"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  grep -q "<available_skills>" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
  grep -q "</available_skills>" "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/.context-dev.md"
}
