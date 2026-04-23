#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/resolve-debug-target.sh"
  ORIG_HOME="$HOME"
  ORIG_CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR-__UNSET__}"
  ORIG_VBW_DEBUG_TARGET_REPO="${VBW_DEBUG_TARGET_REPO-__UNSET__}"
  TEST_ROOT="$(mktemp -d)"
  FAKE_PLUGIN_ROOT="$TEST_ROOT/plugin"
  WORKTREE_PLUGIN_ROOT="$TEST_ROOT/plugin-worktree"
  NON_GIT_PLUGIN_ROOT="$TEST_ROOT/plugin-non-git"
  CLAUDE_CONFIG_DIR="$TEST_ROOT/claude-config"
  TARGET_A="$TEST_ROOT/consumer-a"
  TARGET_B="$TEST_ROOT/consumer-b"

  mkdir -p "$FAKE_PLUGIN_ROOT/.claude" "$NON_GIT_PLUGIN_ROOT/.claude" "$CLAUDE_CONFIG_DIR/vbw" "$TARGET_A" "$TARGET_B"

  git init "$FAKE_PLUGIN_ROOT" >/dev/null 2>&1
  git -C "$FAKE_PLUGIN_ROOT" config user.name 'VBW Test'
  git -C "$FAKE_PLUGIN_ROOT" config user.email 'vbw-test@example.com'
  printf 'test fixture\n' > "$FAKE_PLUGIN_ROOT/README.md"
  git -C "$FAKE_PLUGIN_ROOT" add README.md
  git -C "$FAKE_PLUGIN_ROOT" commit -m 'test fixture' >/dev/null 2>&1
  git -C "$FAKE_PLUGIN_ROOT" worktree add --detach "$WORKTREE_PLUGIN_ROOT" HEAD >/dev/null 2>&1
  mkdir -p "$WORKTREE_PLUGIN_ROOT/.claude"

  FAKE_PLUGIN_ROOT="$(cd "$FAKE_PLUGIN_ROOT" && pwd -P)"
  WORKTREE_PLUGIN_ROOT="$(cd "$WORKTREE_PLUGIN_ROOT" && pwd -P)"
  NON_GIT_PLUGIN_ROOT="$(cd "$NON_GIT_PLUGIN_ROOT" && pwd -P)"
  TARGET_A="$(cd "$TARGET_A" && pwd -P)"
  TARGET_B="$(cd "$TARGET_B" && pwd -P)"

  COMMON_DIR_RAW="$(git -C "$FAKE_PLUGIN_ROOT" rev-parse --git-common-dir)"
  case "$COMMON_DIR_RAW" in
    /*) COMMON_DIR="$COMMON_DIR_RAW" ;;
    *) COMMON_DIR="$(cd "$FAKE_PLUGIN_ROOT/$COMMON_DIR_RAW" && pwd -P)" ;;
  esac
  COMMON_FILE="$COMMON_DIR/info/vbw-debug-target.txt"

  export CLAUDE_CONFIG_DIR
  unset VBW_DEBUG_TARGET_REPO
}

teardown() {
  rm -rf "$TEST_ROOT"
  unset VBW_DEBUG_TARGET_REPO
  export HOME="$ORIG_HOME"
  if [ "$ORIG_CLAUDE_CONFIG_DIR" = "__UNSET__" ]; then
    unset CLAUDE_CONFIG_DIR
  else
    export CLAUDE_CONFIG_DIR="$ORIG_CLAUDE_CONFIG_DIR"
  fi

  if [ "$ORIG_VBW_DEBUG_TARGET_REPO" = "__UNSET__" ]; then
    unset VBW_DEBUG_TARGET_REPO
  else
    export VBW_DEBUG_TARGET_REPO="$ORIG_VBW_DEBUG_TARGET_REPO"
  fi
}

@test "resolve-debug-target: shared common-dir file resolves repo path" {
  printf '%s\n' "$TARGET_A" > "$COMMON_FILE"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_A" ]
}

@test "resolve-debug-target: shared common-dir file resolves from a worktree plugin root" {
  printf '%s\n' "$TARGET_A" > "$COMMON_FILE"

  run bash "$SCRIPT" repo --plugin-root "$WORKTREE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_A" ]
}

@test "resolve-debug-target: env override wins over shared common-dir file" {
  printf '%s\n' "$TARGET_A" > "$COMMON_FILE"
  export VBW_DEBUG_TARGET_REPO="$TARGET_B"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_B" ]
}

@test "resolve-debug-target: relative env override is rejected before cwd-sensitive fallback" {
  printf '%s\n' "$TARGET_A" > "$COMMON_FILE"
  export VBW_DEBUG_TARGET_REPO="../consumer-b"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"VBW_DEBUG_TARGET_REPO"* ]]
  [[ "$output" == *"must be an absolute path"* ]]

  run bash -c 'cd / && bash "$1" repo --plugin-root "$2"' _ "$SCRIPT" "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"VBW_DEBUG_TARGET_REPO"* ]]
  [[ "$output" == *"must be an absolute path"* ]]
}

@test "resolve-debug-target: shared common-dir file wins over checkout-local fallback" {
  printf '%s\n' "$TARGET_A" > "$COMMON_FILE"
  printf '%s\n' "$TARGET_B" > "$WORKTREE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"

  run bash "$SCRIPT" repo --plugin-root "$WORKTREE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_A" ]
}

@test "resolve-debug-target: global fallback works when clone-local files are absent" {
  printf '%s\n' "$TARGET_A" > "$CLAUDE_CONFIG_DIR/vbw/debug-target.txt"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_A" ]
}

@test "resolve-debug-target: global fallback uses HOME/.config/claude-code when CLAUDE_CONFIG_DIR is unset" {
  rm -f "$COMMON_FILE"
  unset CLAUDE_CONFIG_DIR
  export HOME="$TEST_ROOT/home"
  mkdir -p "$HOME/.config/claude-code/vbw"
  printf '%s\n' "$TARGET_A" > "$HOME/.config/claude-code/vbw/debug-target.txt"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_A" ]
}

@test "resolve-debug-target: relative shared common-dir file is rejected" {
  printf '%s\n' '../consumer-a' > "$COMMON_FILE"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"$COMMON_FILE"* ]]
  [[ "$output" == *"must be an absolute path"* ]]
}

@test "resolve-debug-target: blank shared common-dir file is a hard error even when checkout-local fallback exists" {
  cat > "$COMMON_FILE" <<'EOF'
# comment only

EOF
  printf '%s\n' "$TARGET_A" > "$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"$COMMON_FILE"* ]]
  [[ "$output" == *"first non-empty, non-comment line"* ]]
}

@test "resolve-debug-target: relative repo-local fallback is rejected when shared config is absent" {
  rm -f "$COMMON_FILE"
  printf '%s\n' '../consumer-a' > "$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"* ]]
  [[ "$output" == *"must be an absolute path"* ]]
}

@test "resolve-debug-target: relative global fallback is rejected" {
  rm -f "$COMMON_FILE"
  printf '%s\n' '../consumer-a' > "$CLAUDE_CONFIG_DIR/vbw/debug-target.txt"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"$CLAUDE_CONFIG_DIR/vbw/debug-target.txt"* ]]
  [[ "$output" == *"must be an absolute path"* ]]
}

@test "resolve-debug-target: blank repo-local fallback is a hard error even when global fallback exists" {
  rm -f "$COMMON_FILE"
  cat > "$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt" <<'EOF'
# comment only

EOF
  printf '%s\n' "$TARGET_A" > "$CLAUDE_CONFIG_DIR/vbw/debug-target.txt"

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"* ]]
  [[ "$output" == *"first non-empty, non-comment line"* ]]
}

@test "resolve-debug-target: blank global fallback is a hard error" {
  rm -f "$COMMON_FILE"
  cat > "$CLAUDE_CONFIG_DIR/vbw/debug-target.txt" <<'EOF'
# comment only

EOF

  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"$CLAUDE_CONFIG_DIR/vbw/debug-target.txt"* ]]
  [[ "$output" == *"first non-empty, non-comment line"* ]]
}

@test "resolve-debug-target: planning-dir appends .vbw-planning" {
  printf '%s\n' "$TARGET_A" > "$COMMON_FILE"

  run bash "$SCRIPT" planning-dir --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_A/.vbw-planning" ]
}

@test "resolve-debug-target: encoded-path matches Claude project encoding rule" {
  printf '%s\n' "$TARGET_A" > "$COMMON_FILE"
  expected="${TARGET_A//\//-}"

  run bash "$SCRIPT" encoded-path --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "resolve-debug-target: claude-project-dir uses CLAUDE_CONFIG_DIR fallback root" {
  printf '%s\n' "$TARGET_A" > "$COMMON_FILE"
  expected="$CLAUDE_CONFIG_DIR/projects/${TARGET_A//\//-}"

  run bash "$SCRIPT" claude-project-dir --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "resolve-debug-target: source reports where the target came from" {
  printf '%s\n' "$TARGET_A" > "$COMMON_FILE"

  run bash "$SCRIPT" source --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$COMMON_FILE" ]
}

@test "resolve-debug-target: missing config exits with clear guidance" {
  run bash "$SCRIPT" repo --plugin-root "$FAKE_PLUGIN_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"No VBW debug target repo configured."* ]]
  [[ "$output" == *"VBW_DEBUG_TARGET_REPO"* ]]
  [[ "$output" == *"$COMMON_FILE"* ]]
  [[ "$output" == *"$FAKE_PLUGIN_ROOT/.claude/vbw-debug-target.txt"* ]]
}

@test "resolve-debug-target: non-git plugin roots still use the legacy checkout-local fallback" {
  printf '%s\n' "$TARGET_A" > "$NON_GIT_PLUGIN_ROOT/.claude/vbw-debug-target.txt"

  run bash "$SCRIPT" repo --plugin-root "$NON_GIT_PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = "$TARGET_A" ]
}
