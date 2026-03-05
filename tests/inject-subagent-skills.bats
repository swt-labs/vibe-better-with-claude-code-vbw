#!/usr/bin/env bats
# Tests for debug logging in hook-wrapper.sh and inject-subagent-skills.sh

load test_helper

setup() {
  setup_temp_dir
  export ORIG_HOME="$HOME"
  export ORIG_CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}"
  export HOME="$TEST_TEMP_DIR"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/.claude-config"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  # Create VBW session markers so non-prefixed agent names are accepted
  echo "lead" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
}

teardown() {
  export HOME="$ORIG_HOME"
  unset CLAUDE_CONFIG_DIR 2>/dev/null || true
  [ -n "$ORIG_CLAUDE_CONFIG_DIR" ] && export CLAUDE_CONFIG_DIR="$ORIG_CLAUDE_CONFIG_DIR"
  unset VBW_DEBUG 2>/dev/null || true
  unset CLAUDE_PLUGIN_ROOT 2>/dev/null || true
  teardown_temp_dir
}

# Helper: create a skill directory with SKILL.md frontmatter
create_skill() {
  local base_dir="$1" skill_name="$2" name_val="${3:-}" desc_val="${4:-}"
  mkdir -p "$base_dir/$skill_name"
  {
    echo "---"
    [ -n "$name_val" ] && echo "name: $name_val"
    [ -n "$desc_val" ] && echo "description: $desc_val"
    echo "---"
    echo ""
    echo "# $skill_name"
  } > "$base_dir/$skill_name/SKILL.md"
}

# --- inject-subagent-skills.sh functional tests ---

@test "inject-subagent-skills: VBW agent produces hookSpecificOutput JSON" {
  create_skill "$TEST_TEMP_DIR/.claude/skills" "test-skill" "test-skill" "A test skill"
  echo '{"subagent_skill_xml_mode":"names_only"}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(echo '{"agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/inject-subagent-skills.sh")
  echo "$OUTPUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
}

@test "inject-subagent-skills: output contains SKILL ACTIVATION instruction" {
  create_skill "$TEST_TEMP_DIR/.claude/skills" "test-skill" "test-skill" "A test skill"
  echo '{"subagent_skill_xml_mode":"names_only"}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(echo '{"agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/inject-subagent-skills.sh")
  echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "SKILL ACTIVATION"
}

@test "inject-subagent-skills: names_only mode emits compact skill names" {
  create_skill "$TEST_TEMP_DIR/.claude/skills" "test-skill" "test-skill" "A test skill"
  echo '{"subagent_skill_xml_mode":"names_only"}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(echo '{"agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/inject-subagent-skills.sh")
  CTX=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')
  echo "$CTX" | grep -q "Available skills: test-skill"
  ! echo "$CTX" | grep -q "<available_skills>"
}

@test "inject-subagent-skills: full mode emits available_skills XML" {
  create_skill "$TEST_TEMP_DIR/.claude/skills" "test-skill" "test-skill" "A test skill"
  echo '{"subagent_skill_xml_mode":"full"}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(echo '{"agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/inject-subagent-skills.sh")
  echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "<available_skills>"
}

@test "inject-subagent-skills: off mode emits no output" {
  create_skill "$TEST_TEMP_DIR/.claude/skills" "test-skill" "test-skill" "A test skill"
  echo '{"subagent_skill_xml_mode":"off"}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(echo '{"agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/inject-subagent-skills.sh" || true)
  [ -z "$OUTPUT" ]
}

@test "inject-subagent-skills: invalid mode falls back to names_only" {
  create_skill "$TEST_TEMP_DIR/.claude/skills" "test-skill" "test-skill" "A test skill"
  echo '{"subagent_skill_xml_mode":"garbage"}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(echo '{"agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/inject-subagent-skills.sh")
  CTX=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')
  echo "$CTX" | grep -q "Available skills: test-skill"
  ! echo "$CTX" | grep -q "<available_skills>"
}

@test "inject-subagent-skills: no output for non-VBW agent" {
  create_skill "$TEST_TEMP_DIR/.claude/skills" "test-skill" "test-skill" "A test skill"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(echo '{"agent_type":"gsd-planner"}' | bash "$SCRIPTS_DIR/inject-subagent-skills.sh" || true)
  [ -z "$OUTPUT" ]
}

@test "inject-subagent-skills: no output when no skills installed" {
  echo '{"subagent_skill_xml_mode":"full"}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(echo '{"agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/inject-subagent-skills.sh" || true)
  [ -z "$OUTPUT" ]
}

# --- hook-wrapper.sh debug logging tests ---

@test "hook-wrapper: debug log written when config.json debug_logging=true" {
  echo '{"debug_logging": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  # Create a trivial hook script that produces output
  mkdir -p "$TEST_TEMP_DIR/scripts"
  echo '#!/bin/bash
echo "test-output"' > "$TEST_TEMP_DIR/scripts/test-hook.sh"
  chmod +x "$TEST_TEMP_DIR/scripts/test-hook.sh"
  cd "$TEST_TEMP_DIR"
  CLAUDE_PLUGIN_ROOT="$TEST_TEMP_DIR" bash "$SCRIPTS_DIR/hook-wrapper.sh" test-hook.sh
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.hook-debug.log" ]
  grep -q "hook=test-hook.sh" "$TEST_TEMP_DIR/.vbw-planning/.hook-debug.log"
}

@test "hook-wrapper: debug log contains base64 encoded output" {
  echo '{"debug_logging": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/scripts"
  echo '#!/bin/bash
echo "hello-from-hook"' > "$TEST_TEMP_DIR/scripts/test-hook.sh"
  chmod +x "$TEST_TEMP_DIR/scripts/test-hook.sh"
  cd "$TEST_TEMP_DIR"
  CLAUDE_PLUGIN_ROOT="$TEST_TEMP_DIR" bash "$SCRIPTS_DIR/hook-wrapper.sh" test-hook.sh
  # Extract base64 and decode
  B64=$(grep 'output_base64=' "$TEST_TEMP_DIR/.vbw-planning/.hook-debug.log" | sed 's/.*output_base64=//')
  [ -n "$B64" ]
  DECODED=$(echo "$B64" | base64 -d 2>/dev/null)
  echo "$DECODED" | grep -q "hello-from-hook"
}

@test "hook-wrapper: no debug log when debug_logging=false" {
  echo '{"debug_logging": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/scripts"
  echo '#!/bin/bash
echo "test"' > "$TEST_TEMP_DIR/scripts/test-hook.sh"
  chmod +x "$TEST_TEMP_DIR/scripts/test-hook.sh"
  cd "$TEST_TEMP_DIR"
  CLAUDE_PLUGIN_ROOT="$TEST_TEMP_DIR" bash "$SCRIPTS_DIR/hook-wrapper.sh" test-hook.sh
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.hook-debug.log" ]
}

@test "hook-wrapper: VBW_DEBUG=1 env var enables debug log" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/scripts"
  echo '#!/bin/bash
echo "debug-test"' > "$TEST_TEMP_DIR/scripts/test-hook.sh"
  chmod +x "$TEST_TEMP_DIR/scripts/test-hook.sh"
  VBW_DEBUG=1 CLAUDE_PLUGIN_ROOT="$TEST_TEMP_DIR" bash "$SCRIPTS_DIR/hook-wrapper.sh" test-hook.sh
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.hook-debug.log" ]
}

@test "hook-wrapper: hook stdout still passes through when debug enabled" {
  echo '{"debug_logging": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/scripts"
  echo '#!/bin/bash
echo "passthrough-test"' > "$TEST_TEMP_DIR/scripts/test-hook.sh"
  chmod +x "$TEST_TEMP_DIR/scripts/test-hook.sh"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(CLAUDE_PLUGIN_ROOT="$TEST_TEMP_DIR" bash "$SCRIPTS_DIR/hook-wrapper.sh" test-hook.sh)
  echo "$OUTPUT" | grep -q "passthrough-test"
}

@test "hook-wrapper: silent hooks produce no output_base64 line" {
  echo '{"debug_logging": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/scripts"
  echo '#!/bin/bash
exit 0' > "$TEST_TEMP_DIR/scripts/silent-hook.sh"
  chmod +x "$TEST_TEMP_DIR/scripts/silent-hook.sh"
  cd "$TEST_TEMP_DIR"
  CLAUDE_PLUGIN_ROOT="$TEST_TEMP_DIR" bash "$SCRIPTS_DIR/hook-wrapper.sh" silent-hook.sh
  grep -q "hook=silent-hook.sh exit=0" "$TEST_TEMP_DIR/.vbw-planning/.hook-debug.log"
  ! grep -q "output_base64=" "$TEST_TEMP_DIR/.vbw-planning/.hook-debug.log"
}

# --- emit-skill-prompt-line.sh tests ---

@test "emit-skill-prompt-line: outputs activation line when .skill-names exists" {
  echo "foo, bar, baz" > "$TEST_TEMP_DIR/.vbw-planning/.skill-names"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(bash "$SCRIPTS_DIR/emit-skill-prompt-line.sh" .vbw-planning)
  echo "$OUTPUT" | grep -q "SKILL ACTIVATION"
  echo "$OUTPUT" | grep -q "foo, bar, baz"
}

@test "emit-skill-prompt-line: empty output when .skill-names missing" {
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(bash "$SCRIPTS_DIR/emit-skill-prompt-line.sh" .vbw-planning 2>/dev/null || true)
  [ -z "$OUTPUT" ]
}

@test "emit-skill-prompt-line: empty output when .skill-names is empty" {
  touch "$TEST_TEMP_DIR/.vbw-planning/.skill-names"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(bash "$SCRIPTS_DIR/emit-skill-prompt-line.sh" .vbw-planning 2>/dev/null || true)
  [ -z "$OUTPUT" ]
}

@test "emit-skill-prompt-line: empty output when .skill-names has only whitespace" {
  printf '   \n  ' > "$TEST_TEMP_DIR/.vbw-planning/.skill-names"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(bash "$SCRIPTS_DIR/emit-skill-prompt-line.sh" .vbw-planning 2>/dev/null || true)
  [ -z "$OUTPUT" ]
}

@test "emit-skill-prompt-line: default planning dir when no argument" {
  echo "test-skill" > "$TEST_TEMP_DIR/.vbw-planning/.skill-names"
  cd "$TEST_TEMP_DIR"
  OUTPUT=$(bash "$SCRIPTS_DIR/emit-skill-prompt-line.sh")
  echo "$OUTPUT" | grep -q "test-skill"
}
