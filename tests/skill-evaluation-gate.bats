#!/usr/bin/env bats
# Tests for skill-evaluation-gate.sh — SubagentStart hook (issue #191)

load test_helper

setup() {
  setup_temp_dir
  export ORIG_HOME="$HOME"
  export ORIG_CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}"
  export HOME="$TEST_TEMP_DIR"
  unset CLAUDE_CONFIG_DIR 2>/dev/null || true
  # Save original dir and switch to temp dir (hook checks .vbw-planning relative to cwd)
  export ORIG_DIR="$PWD"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cd "$ORIG_DIR"
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

# --- Guard: no .vbw-planning directory ---

@test "skill-evaluation-gate.sh: exits 0 when .vbw-planning is missing" {
  rm -rf "$TEST_TEMP_DIR/.vbw-planning"
  run bash "$SCRIPTS_DIR/skill-evaluation-gate.sh" < /dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- No skills installed: empty additionalContext ---

@test "skill-evaluation-gate.sh: outputs empty additionalContext when no skills installed" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** None detected
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/skill-evaluation-gate.sh" < /dev/null
  [ "$status" -eq 0 ]
  # Should output valid JSON with empty additionalContext
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext == ""'
}

# --- hookEventName is always SubagentStart ---

@test "skill-evaluation-gate.sh: outputs hookEventName SubagentStart" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** None
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/skill-evaluation-gate.sh" < /dev/null
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SubagentStart"'
}

# --- Single skill: injects MANDATORY SKILL EVALUATION SEQUENCE ---

@test "skill-evaluation-gate.sh: injects MANDATORY SKILL EVALUATION SEQUENCE for installed skill" {
  mkdir -p "$TEST_TEMP_DIR/.claude/skills"
  create_skill_md "$TEST_TEMP_DIR/.claude/skills" "test-skill" "A test skill for unit testing."

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** test-skill
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/skill-evaluation-gate.sh" < /dev/null
  [ "$status" -eq 0 ]
  # Check for the mandatory sequence header in additionalContext
  local ctx
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"MANDATORY SKILL EVALUATION SEQUENCE"* ]]
  [[ "$ctx" == *"test-skill"* ]]
  [[ "$ctx" == *"A test skill for unit testing."* ]]
}

# --- Multiple skills in table ---

@test "skill-evaluation-gate.sh: includes multiple skills in table" {
  mkdir -p "$TEST_TEMP_DIR/.claude/skills"
  create_skill_md "$TEST_TEMP_DIR/.claude/skills" "skill-alpha" "First skill description."
  create_skill_md "$TEST_TEMP_DIR/.claude/skills" "skill-beta" "Second skill description."

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** skill-alpha, skill-beta
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/skill-evaluation-gate.sh" < /dev/null
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"skill-alpha"* ]]
  [[ "$ctx" == *"First skill description."* ]]
  [[ "$ctx" == *"skill-beta"* ]]
  [[ "$ctx" == *"Second skill description."* ]]
}

# --- Valid JSON output ---

@test "skill-evaluation-gate.sh: outputs valid JSON with skills" {
  mkdir -p "$TEST_TEMP_DIR/.claude/skills"
  create_skill_md "$TEST_TEMP_DIR/.claude/skills" "json-skill" "A skill to test JSON output."

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** json-skill
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/skill-evaluation-gate.sh" < /dev/null
  [ "$status" -eq 0 ]
  # jq parse check — must be valid JSON
  echo "$output" | jq empty
}

@test "skill-evaluation-gate.sh: outputs valid JSON without skills" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** None detected
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/skill-evaluation-gate.sh" < /dev/null
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

# --- 3-step gate content ---

@test "skill-evaluation-gate.sh: contains EVALUATE, ACTIVATE, IMPLEMENT steps" {
  mkdir -p "$TEST_TEMP_DIR/.claude/skills"
  create_skill_md "$TEST_TEMP_DIR/.claude/skills" "gate-skill" "Gate test skill."

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** gate-skill
**Suggested:** None
EOF
  run bash "$SCRIPTS_DIR/skill-evaluation-gate.sh" < /dev/null
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"EVALUATE"* ]]
  [[ "$ctx" == *"ACTIVATE"* ]]
  [[ "$ctx" == *"IMPLEMENT"* ]]
  [[ "$ctx" == *"PROTOCOL VIOLATION"* ]]
}

# --- Stdin consumption ---

@test "skill-evaluation-gate.sh: handles stdin gracefully" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# VBW State
### Skills
**Installed:** None
**Suggested:** None
EOF
  # Feed stdin JSON (as SubagentStart would)
  run bash -c 'echo "{\"agent_type\":\"vbw-dev\",\"pid\":\"12345\"}" | bash "'"$SCRIPTS_DIR"'/skill-evaluation-gate.sh"'
  [ "$status" -eq 0 ]
}
