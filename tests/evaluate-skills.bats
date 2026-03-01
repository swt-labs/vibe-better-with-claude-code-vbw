#!/usr/bin/env bats
# Tests for evaluate-skills.sh — Forced skill evaluation (issue #191)

load test_helper

setup() {
  setup_temp_dir
  export ORIG_HOME="$HOME"
  export ORIG_CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}"
  export HOME="$TEST_TEMP_DIR"
  unset CLAUDE_CONFIG_DIR 2>/dev/null || true
}

teardown() {
  export HOME="$ORIG_HOME"
  unset CLAUDE_CONFIG_DIR 2>/dev/null || true
  [ -n "$ORIG_CLAUDE_CONFIG_DIR" ] && export CLAUDE_CONFIG_DIR="$ORIG_CLAUDE_CONFIG_DIR"
  teardown_temp_dir
}

# Helper: create a minimal SKILL.md with description
create_skill_md() {
  local dir="$1" name="$2" desc="$3"
  mkdir -p "$dir/$name"
  cat > "$dir/$name/SKILL.md" <<EOF
---
name: $name
description: $desc
---
# $name
Body content here.
EOF
}

# --- Basic functionality ---

@test "evaluate-skills.sh: exits 0 when STATE.md is missing" {
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/nonexistent"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "evaluate-skills.sh: exits 0 when STATE.md has no Skills section" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
**Project:** Test
## Todos
- Something
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "evaluate-skills.sh: exits 0 when Installed is None detected" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** None detected
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "evaluate-skills.sh: exits 0 when Installed is None" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** None
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Happy path: single skill in global location ---

@test "evaluate-skills.sh: finds skill in CLAUDE_DIR/skills with description" {
  mkdir -p "$TEST_TEMP_DIR/.claude/skills"
  create_skill_md "$TEST_TEMP_DIR/.claude/skills" "test-skill" "A test skill for unit testing."

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** test-skill
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-skill"*"A test skill for unit testing."* ]]
}

# --- Happy path: two skills, comma-separated ---

@test "evaluate-skills.sh: handles two comma-separated skills" {
  mkdir -p "$TEST_TEMP_DIR/.claude/skills"
  create_skill_md "$TEST_TEMP_DIR/.claude/skills" "skill-a" "First skill description."
  create_skill_md "$TEST_TEMP_DIR/.claude/skills" "skill-b" "Second skill description."

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** skill-a, skill-b
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  # Check both skills present in output
  echo "$output" | grep -q "skill-a"
  echo "$output" | grep -q "skill-b"
  echo "$output" | grep -q "First skill description."
  echo "$output" | grep -q "Second skill description."
}

# --- Fallback: skill not found on disk ---

@test "evaluate-skills.sh: outputs (not found on disk) for missing skill" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** nonexistent-skill
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nonexistent-skill"*"(not found on disk)"* ]]
}

# --- Fallback: SKILL.md exists but no description field ---

@test "evaluate-skills.sh: outputs (no description) when SKILL.md lacks description" {
  mkdir -p "$TEST_TEMP_DIR/.claude/skills/no-desc-skill"
  cat > "$TEST_TEMP_DIR/.claude/skills/no-desc-skill/SKILL.md" <<'EOF'
---
name: no-desc-skill
---
# No Desc Skill
Body only.
EOF

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** no-desc-skill
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no-desc-skill"*"(no description)"* ]]
}

# --- Multi-line description ---

@test "evaluate-skills.sh: handles multi-line YAML description" {
  mkdir -p "$TEST_TEMP_DIR/.claude/skills/multi-line-skill"
  cat > "$TEST_TEMP_DIR/.claude/skills/multi-line-skill/SKILL.md" <<'EOF'
---
name: multi-line-skill
description: First line of description.
  Second line continues here.
  Third line too.
---
# Multi Line Skill
EOF

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** multi-line-skill
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"First line of description."* ]]
  [[ "$output" == *"Second line continues here."* ]]
  [[ "$output" == *"Third line too."* ]]
}

# --- Project-scoped skill location ---

@test "evaluate-skills.sh: finds skill in project .claude/skills/" {
  mkdir -p "$TEST_TEMP_DIR/project/.claude/skills"
  create_skill_md "$TEST_TEMP_DIR/project/.claude/skills" "project-skill" "A project-scoped skill."

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** project-skill
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning" "$TEST_TEMP_DIR/project"
  [ "$status" -eq 0 ]
  [[ "$output" == *"project-skill"*"A project-scoped skill."* ]]
}

# --- Agents location ---

@test "evaluate-skills.sh: finds skill in ~/.agents/skills/" {
  mkdir -p "$TEST_TEMP_DIR/.agents/skills"
  create_skill_md "$TEST_TEMP_DIR/.agents/skills" "agents-skill" "An agents-installed skill."

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** agents-skill
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents-skill"*"An agents-installed skill."* ]]
}

# --- Tab-separated output format ---

@test "evaluate-skills.sh: output is tab-separated" {
  mkdir -p "$TEST_TEMP_DIR/.claude/skills"
  create_skill_md "$TEST_TEMP_DIR/.claude/skills" "tab-test" "Tab check description."

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** tab-test
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  # Verify tab character separates name and description
  echo "$output" | grep -P 'tab-test\t' || echo "$output" | grep "$(printf 'tab-test\t')"
}

# --- CLAUDE_CONFIG_DIR override ---

@test "evaluate-skills.sh: respects CLAUDE_CONFIG_DIR for skill location" {
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/custom-claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"
  create_skill_md "$CLAUDE_CONFIG_DIR/skills" "custom-skill" "Custom dir skill."

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** custom-skill
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/evaluate-skills.sh" "$TEST_TEMP_DIR/.vbw-planning" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"custom-skill"*"Custom dir skill."* ]]
}
