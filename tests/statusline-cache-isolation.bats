#!/usr/bin/env bats
# Tests for statusline cache isolation across repositories and nested workspaces.

load test_helper

STATUSLINE="$SCRIPTS_DIR/vbw-statusline.sh"

setup() {
  setup_temp_dir
  export ORIG_UID=$(id -u)
  export TEST_CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude-config"
  export CLAUDE_CONFIG_DIR="$TEST_CLAUDE_CONFIG_DIR"
  mkdir -p "$TEST_CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw"
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@test.local"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@test.local"
}

teardown() {
  cleanup_vbw_caches_under_temp_dir "$ORIG_UID"
  unset CLAUDE_CONFIG_DIR TEST_CLAUDE_CONFIG_DIR
  teardown_temp_dir
}

# --- Cache key isolation ---

@test "cache key includes repo-specific hash" {
  local repo="$TEST_TEMP_DIR/repo-hash"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q

  cd "$repo"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  cd "$PROJECT_ROOT"

  local cache_prefix
  cache_prefix=$(vbw_cache_prefix_for_root "$repo" "$ORIG_UID")
  [ -f "${cache_prefix}-fast" ]
}

@test "different repos produce different cache keys" {
  local repo1="$TEST_TEMP_DIR/repo1"
  local repo2="$TEST_TEMP_DIR/repo2"
  mkdir -p "$repo1" "$repo2"
  git -C "$repo1" init -q
  git -C "$repo1" commit --allow-empty -m "test(init): seed" -q
  git -C "$repo2" init -q
  git -C "$repo2" commit --allow-empty -m "test(init): seed" -q

  local cache1 cache2
  cache1=$(vbw_cache_prefix_for_root "$repo1" "$ORIG_UID")
  cache2=$(vbw_cache_prefix_for_root "$repo2" "$ORIG_UID")
  [ "$cache1" != "$cache2" ]

  cd "$repo1"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  cd "$repo2"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  cd "$PROJECT_ROOT"

  [ -f "${cache1}-fast" ]
  [ -f "${cache2}-fast" ]
}

@test "cache is not shared between repos within TTL window" {
  local repo_a="$TEST_TEMP_DIR/repo-a"
  local repo_b="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$repo_a" "$repo_b"
  git -C "$repo_a" init -q
  git -C "$repo_a" commit --allow-empty -m "test(init): seed" -q
  git -C "$repo_b" init -q
  git -C "$repo_b" commit --allow-empty -m "test(init): seed" -q

  local cache_a_path
  cache_a_path="$(vbw_cache_prefix_for_root "$repo_a" "$ORIG_UID")-fast"

  cd "$repo_a"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  local cache_a
  cache_a=$(cat "$cache_a_path" 2>/dev/null | head -1)

  cd "$repo_b"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1

  local cache_a_after
  cache_a_after=$(cat "$cache_a_path" 2>/dev/null | head -1)
  cd "$PROJECT_ROOT"

  [ "$cache_a" = "$cache_a_after" ]
}

@test "nested VBW workspaces inside one repo produce different cache keys" {
  local outer="$TEST_TEMP_DIR/nested-outer"
  local inner="$outer/packages/ui"
  mkdir -p "$outer/.vbw-planning" "$inner/.vbw-planning" "$inner/src"
  git -C "$outer" init -q
  git -C "$outer" commit --allow-empty -m "test(init): seed" -q
  cat > "$outer/.vbw-planning/config.json" <<'JSON'
{"effort": "balanced", "model_profile": "balanced"}
JSON
  cat > "$inner/.vbw-planning/config.json" <<'JSON'
{"effort": "balanced", "model_profile": "balanced"}
JSON

  local outer_cache inner_cache
  outer_cache=$(vbw_cache_prefix_for_root "$outer" "$ORIG_UID")
  inner_cache=$(vbw_cache_prefix_for_root "$inner" "$ORIG_UID")
  [ "$outer_cache" != "$inner_cache" ]

  cd "$outer"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  cd "$inner/src"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  cd "$PROJECT_ROOT"

  [ -f "${outer_cache}-fast" ]
  [ -f "${inner_cache}-fast" ]
}

# --- No-remote repo handling ---

@test "no-remote repo shows directory name in status line" {
  local repo="$TEST_TEMP_DIR/my-local-project"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q

  cd "$repo"
  local branch
  branch=$(git branch --show-current)
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1 | head -1)
  cd "$PROJECT_ROOT"

  echo "$output" | grep -q "my-local-project:${branch}"
}

@test "no-remote repo does not show another repo's name" {
  local repo="$TEST_TEMP_DIR/isolated-repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q

  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1

  cd "$repo"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1 | head -1)
  cd "$PROJECT_ROOT"

  ! echo "$output" | grep -q "vibe-better-with-claude-code-vbw"
  echo "$output" | grep -q "isolated-repo"
}

@test "repo with remote shows GitHub link, not bare directory name" {
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1 | head -1)
  echo "$output" | grep -q ']8;;https://'
}

@test "detached HEAD repo with remote still shows GitHub link" {
  local repo="$TEST_TEMP_DIR/detached-remote-repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  git -C "$repo" remote add origin "https://github.com/example/detached-remote-repo.git"
  git -C "$repo" checkout --detach -q

  cd "$repo"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1 | head -1)
  cd "$PROJECT_ROOT"

  echo "$output" | grep -q ']8;;https://'
}

# --- Cache cleanup ---

@test "stale cache cleanup removes old-format caches" {
  local uid=$(id -u)
  local repo="$TEST_TEMP_DIR/stale-cleanup-repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  touch "/tmp/vbw-0.0.0-${uid}-fast"
  touch "/tmp/vbw-0.0.0-${uid}-slow"
  touch "/tmp/vbw-0.0.0-${uid}-ok"

  cd "$repo"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1 || true
  cd "$PROJECT_ROOT"

  [ ! -f "/tmp/vbw-0.0.0-${uid}-fast" ]
  [ ! -f "/tmp/vbw-0.0.0-${uid}-slow" ]
}

@test "cache-nuke.sh cleans repo-scoped caches" {
  local uid=$(id -u)
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  local before
  before=$(ls /tmp/vbw-*-${uid}-* 2>/dev/null | wc -l | tr -d ' ')
  [ "$before" -gt 0 ]

  run bash "$SCRIPTS_DIR/cache-nuke.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.wiped | has("plugin_cache") and has("temp_caches") and has("versions_removed")' >/dev/null

  local after
  after=$(ls /tmp/vbw-*-${uid}-* 2>/dev/null | wc -l | tr -d ' ')
  [ "$after" -eq 0 ]
}

@test "cache-nuke.sh succeeds with empty plugin cache glob under pipefail" {
  local claude_dir="$TEST_TEMP_DIR/claude-empty-cache"
  mkdir -p "$claude_dir/plugins/cache/vbw-marketplace/vbw"

  run env CLAUDE_CONFIG_DIR="$claude_dir" bash "$SCRIPTS_DIR/cache-nuke.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.wiped.versions_removed == 0' >/dev/null
  echo "$output" | jq -e '.wiped | has("plugin_cache") and has("temp_caches") and has("versions_removed")' >/dev/null
}

@test "cache-nuke.sh returns JSON summary on no-op run" {
  local claude_dir="$TEST_TEMP_DIR/claude-noop"
  mkdir -p "$claude_dir"

  run env CLAUDE_CONFIG_DIR="$claude_dir" bash "$SCRIPTS_DIR/cache-nuke.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.wiped.plugin_cache == false' >/dev/null
  echo "$output" | jq -e '.wiped.temp_caches == false' >/dev/null
  echo "$output" | jq -e '.wiped.versions_removed == 0' >/dev/null
}

@test "cache-nuke.sh --keep-latest keeps newest real version when local symlink exists" {
  local claude_dir="$TEST_TEMP_DIR/claude-keep-latest"
  local cache_dir="$claude_dir/plugins/cache/vbw-marketplace/vbw"
  mkdir -p "$cache_dir/1.29.0" "$cache_dir/1.30.0" "$TEST_TEMP_DIR/local-plugin"
  ln -s "$TEST_TEMP_DIR/local-plugin" "$cache_dir/local"

  run env CLAUDE_CONFIG_DIR="$claude_dir" bash "$SCRIPTS_DIR/cache-nuke.sh" --keep-latest
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.wiped.plugin_cache == true' >/dev/null
  echo "$output" | jq -e '.wiped.versions_removed == 1' >/dev/null

  [ ! -d "$cache_dir/1.29.0" ]
  [ -d "$cache_dir/1.30.0" ]
  [ -L "$cache_dir/local" ]
}

@test "cache-nuke.sh always returns JSON summary even when delete fails" {
  local claude_dir="$TEST_TEMP_DIR/claude-delete-fail"
  local cache_dir="$claude_dir/plugins/cache/vbw-marketplace/vbw"
  mkdir -p "$cache_dir/1.29.0" "$cache_dir/1.30.0"

  chmod 500 "$cache_dir"
  run env CLAUDE_CONFIG_DIR="$claude_dir" bash "$SCRIPTS_DIR/cache-nuke.sh" --keep-latest
  chmod 700 "$cache_dir"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.wiped | has("plugin_cache") and has("temp_caches") and has("versions_removed")' >/dev/null
}

# --- Non-git directory handling ---

@test "statusline works in non-git directory" {
  local noGitDir="$TEST_TEMP_DIR/not-a-repo"
  mkdir -p "$noGitDir"
  cd "$noGitDir"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  cd "$PROJECT_ROOT"
  local lines
  lines=$(echo "$output" | wc -l | tr -d ' ')
  [ "$lines" -eq 4 ]
}
