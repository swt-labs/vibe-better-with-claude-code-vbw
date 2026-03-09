#!/usr/bin/env bats
# Tests for CLAUDE_CONFIG_DIR resolution across scripts
# Verifies both default ($HOME/.claude) and custom CLAUDE_CONFIG_DIR paths.

load test_helper

setup() {
  setup_temp_dir
  # Save original values
  export ORIG_HOME="$HOME"
  export ORIG_CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}"
}

teardown() {
  # Restore original values
  export HOME="$ORIG_HOME"
  unset CLAUDE_CONFIG_DIR 2>/dev/null || true
  [ -n "$ORIG_CLAUDE_CONFIG_DIR" ] && export CLAUDE_CONFIG_DIR="$ORIG_CLAUDE_CONFIG_DIR"
  teardown_temp_dir
}

# --- resolve-claude-dir.sh tests ---

@test "resolve-claude-dir.sh defaults to HOME/.claude when CLAUDE_CONFIG_DIR unset" {
  unset CLAUDE_CONFIG_DIR
  export HOME="$TEST_TEMP_DIR"
  source "$SCRIPTS_DIR/resolve-claude-dir.sh"
  [ "$CLAUDE_DIR" = "$TEST_TEMP_DIR/.claude" ]
}

@test "resolve-claude-dir.sh uses CLAUDE_CONFIG_DIR when set" {
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/custom-claude"
  source "$SCRIPTS_DIR/resolve-claude-dir.sh"
  [ "$CLAUDE_DIR" = "$TEST_TEMP_DIR/custom-claude" ]
}

@test "resolve-claude-dir.sh uses CLAUDE_CONFIG_DIR even when empty string" {
  # Empty CLAUDE_CONFIG_DIR should not fall back — it's explicitly set
  export CLAUDE_CONFIG_DIR=""
  source "$SCRIPTS_DIR/resolve-claude-dir.sh"
  # bash ${X:-default} treats empty as unset, so empty → default
  [ "$CLAUDE_DIR" = "$HOME/.claude" ]
}

@test "resolve-claude-dir.sh falls back to HOME/.config/claude-code when CLAUDE_CONFIG_DIR unset and dir exists" {
  unset CLAUDE_CONFIG_DIR
  export HOME="$TEST_TEMP_DIR"
  mkdir -p "$HOME/.config/claude-code"
  source "$SCRIPTS_DIR/resolve-claude-dir.sh"
  [ "$CLAUDE_DIR" = "$TEST_TEMP_DIR/.config/claude-code" ]
}

@test "resolve-claude-dir.sh skips HOME/.config/claude-code when it does not exist" {
  unset CLAUDE_CONFIG_DIR
  export HOME="$TEST_TEMP_DIR"
  # Do NOT create $HOME/.config/claude-code
  source "$SCRIPTS_DIR/resolve-claude-dir.sh"
  [ "$CLAUDE_DIR" = "$TEST_TEMP_DIR/.claude" ]
}

# --- hooks.json tests ---

@test "hooks.json contains no hardcoded HOME/.claude paths" {
  local count
  count=$(grep -c '"$HOME"/.claude' "$PROJECT_ROOT/hooks/hooks.json" || true)
  [ "$count" -eq 0 ]
}

@test "hooks.json all commands use CLAUDE_CONFIG_DIR fallback" {
  local count
  count=$(grep -c 'CLAUDE_CONFIG_DIR' "$PROJECT_ROOT/hooks/hooks.json" || true)
  [ "$count" -gt 0 ]
}

@test "hooks.json all commands include CLAUDE_PLUGIN_ROOT fallback" {
  # Every hook command that resolves hook-wrapper.sh via cache should also
  # include the CLAUDE_PLUGIN_ROOT fallback for --plugin-dir installs.
  # Use jq to count commands containing each pattern independently.
  local cmd_count fallback_count
  cmd_count=$(jq '[.hooks[][] | .hooks[]? | .command | select(contains("hook-wrapper.sh"))] | length' "$PROJECT_ROOT/hooks/hooks.json")
  fallback_count=$(jq '[.hooks[][] | .hooks[]? | .command | select(contains("CLAUDE_PLUGIN_ROOT"))] | length' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$cmd_count" -gt 0 ]
  [ "$cmd_count" -eq "$fallback_count" ]
}

@test "hooks.json no commands use old cache-only pattern" {
  # Old pattern: ') && [ -f "$w" ] && exec bash' (no fallback)
  # New pattern: '); [ ! -f "$w" ] && w=...; [ -f "$w" ] && exec bash'
  local old_count
  old_count=$(grep -c ') && \[ -f' "$PROJECT_ROOT/hooks/hooks.json" || true)
  [ "$old_count" -eq 0 ]
}

@test "hooks.json is valid JSON" {
  jq empty "$PROJECT_ROOT/hooks/hooks.json"
}

# --- detect-stack.sh tests ---

@test "detect-stack.sh resolves CLAUDE_DIR from CLAUDE_CONFIG_DIR" {
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/custom-claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/test-skill"

  run bash "$SCRIPTS_DIR/detect-stack.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]

  # Should find test-skill in custom dir
  echo "$output" | jq -e '.installed.global' >/dev/null
  [[ "$output" == *"test-skill"* ]]
}

@test "detect-stack.sh uses default HOME/.claude when CLAUDE_CONFIG_DIR unset" {
  unset CLAUDE_CONFIG_DIR
  export HOME="$TEST_TEMP_DIR"
  mkdir -p "$HOME/.claude/skills/default-skill"

  run bash "$SCRIPTS_DIR/detect-stack.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.installed.global' >/dev/null
  [[ "$output" == *"default-skill"* ]]
}

# --- hook-wrapper.sh tests ---

@test "hook-wrapper.sh sources resolve-claude-dir.sh" {
  grep -q 'resolve-claude-dir.sh' "$SCRIPTS_DIR/hook-wrapper.sh"
}

@test "hook-wrapper.sh includes CLAUDE_PLUGIN_ROOT fallback" {
  grep -q 'CLAUDE_PLUGIN_ROOT' "$SCRIPTS_DIR/hook-wrapper.sh"
}

# --- install-hooks.sh tests ---

@test "install-hooks.sh hook content uses CLAUDE_CONFIG_DIR fallback" {
  grep -q 'CLAUDE_CONFIG_DIR' "$SCRIPTS_DIR/install-hooks.sh"
}

@test "install-hooks.sh hook content does not hardcode HOME/.claude" {
  # The HOOK_CONTENT heredoc should use ${CLAUDE_CONFIG_DIR:-$HOME/.claude}
  # not bare $HOME/.claude
  local bare_count
  bare_count=$(grep -c '"$HOME"/.claude' "$SCRIPTS_DIR/install-hooks.sh" || true)
  [ "$bare_count" -eq 0 ]
}

# --- compile-context.sh tests ---

@test "compile-context.sh no longer sources resolve-claude-dir.sh (skills via STATE.md)" {
  ! grep -q 'resolve-claude-dir.sh' "$SCRIPTS_DIR/compile-context.sh"
}

# --- skill-hook-dispatch.sh tests ---

@test "skill-hook-dispatch.sh sources resolve-claude-dir.sh" {
  grep -q 'resolve-claude-dir.sh' "$SCRIPTS_DIR/skill-hook-dispatch.sh"
}

@test "skill-hook-dispatch.sh uses CLAUDE_DIR for plugin cache" {
  grep -q '$CLAUDE_DIR.*plugins/cache' "$SCRIPTS_DIR/skill-hook-dispatch.sh"
}

# --- session-start.sh tests ---

@test "session-start.sh sources resolve-claude-dir.sh" {
  grep -q 'resolve-claude-dir.sh' "$SCRIPTS_DIR/session-start.sh"
}

# --- blocker-notify.sh tests ---

@test "blocker-notify.sh sources resolve-claude-dir.sh" {
  grep -q 'resolve-claude-dir.sh' "$SCRIPTS_DIR/blocker-notify.sh"
}

# --- cache-nuke.sh tests ---

@test "cache-nuke.sh sources resolve-claude-dir.sh" {
  grep -q 'resolve-claude-dir.sh' "$SCRIPTS_DIR/cache-nuke.sh"
}

# --- Cross-cutting: no script hardcodes HOME/.claude without fallback ---

@test "no script uses bare HOME/.claude without CLAUDE_CONFIG_DIR fallback" {
  # Find scripts that use $HOME/.claude but NOT via ${CLAUDE_CONFIG_DIR:-...} pattern
  # Exclude: resolve-claude-dir.sh (defines the pattern), hooks.json (checked separately),
  # test files, docs, changelog, and non-script files
  local violations
  violations=$(grep -rn '"$HOME"/.claude\|$HOME/.claude' "$SCRIPTS_DIR"/*.sh \
    | grep -v 'resolve-claude-dir.sh' \
    | grep -v 'CLAUDE_CONFIG_DIR' \
    | grep -v '# shellcheck' \
    || true)
  [ -z "$violations" ]
}
