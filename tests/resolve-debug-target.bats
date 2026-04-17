#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/resolve-debug-target.sh"
  TEST_ROOT="$(mktemp -d)"
  FAKE_PLUGIN_ROOT="$TEST_ROOT/plugin"
  CLAUDE_CONFIG_DIR="$TEST_ROOT/claude-config"
  TARGET_A="$TEST_ROOT/consumer-a"
  TARGET_B="$TEST_ROOT/consumer-b"

  mkdir -p "$FAKE_PLUGIN_ROOT/.claude" "$CLAUDE_CONFIG_DIR/vbw" "$TARGET_A" "$TARGET_B"

  TARGET_A="$(cd "$TARGET_A" && pwd -P)"
  TARGET_B="$(cd "$TARGET_B" && pwd -P)"

  export CLAUDE_CONFIG_DIR
}

teardown() {
  rm -rf "$TEST_ROOT"
  unset VBW_DEBUG_TARGET_REPO
  unset CLAUDE_CONFIG_DIR
}

@test "resolve-debug-target: repo-local file resolves repo path" {
  printf '%s\n' "$TARGET_A" > "$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_A" ]
}

@test "resolve-debug-target: env override wins over repo-local file" {
  printf '%s\n' "$TARGET_A" > "$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"
  export VBW_DEBUG_TARGET_REPO="$TARGET_B"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_B" ]
}

@test "resolve-debug-target: global fallback works when repo-local file is absent" {
  printf '%s\n' "$TARGET_A" > "$CLAUDE_CONFIG_DIR/vbw/debug-target.txt"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_A" ]
}

@test "resolve-debug-target: planning-dir appends .vbw-planning" {
  printf '%s\n' "$TARGET_A" > "$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"

  run bash "$SCRIPT" planning-dir --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_A/.vbw-planning" ]
}

@test "resolve-debug-target: encoded-path matches Claude project encoding rule" {
  printf '%s\n' "$TARGET_A" > "$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"
  expected="${TARGET_A//\//-}"

  run bash "$SCRIPT" encoded-path --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "resolve-debug-target: claude-project-dir uses CLAUDE_CONFIG_DIR fallback root" {
  printf '%s\n' "$TARGET_A" > "$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"
  expected="$CLAUDE_CONFIG_DIR/projects/${TARGET_A//\//-}"

  run bash "$SCRIPT" claude-project-dir --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "resolve-debug-target: source reports where the target came from" {
  printf '%s\n' "$TARGET_A" > "$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"

  run bash "$SCRIPT" source --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt" ]
}

@test "resolve-debug-target: missing config exits with clear guidance" {
  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"No VBW debug target repo configured."* ]]
  [[ "$output" == *"VBW_DEBUG_TARGET_REPO"* ]]
  [[ "$output" == *"$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"* ]]
}
