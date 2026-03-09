#!/usr/bin/env bats
# Tests for debug logging in hook-wrapper.sh
# inject-subagent-skills.sh was removed — verify it stays deleted

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

# --- inject-subagent-skills.sh removal verification ---

@test "inject-subagent-skills: script is deleted" {
  [ ! -f "$SCRIPTS_DIR/inject-subagent-skills.sh" ]
}

@test "inject-subagent-skills: not registered in hooks.json" {
  ! grep -q "inject-subagent-skills" "$ROOT_DIR/hooks/hooks.json"
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
