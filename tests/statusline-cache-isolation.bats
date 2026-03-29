#!/usr/bin/env bats
# Tests for statusline cache isolation across repositories
# Verifies cache keys include repo identity and no-remote repos display correctly.

load test_helper

STATUSLINE="$SCRIPTS_DIR/vbw-statusline.sh"

setup() {
  setup_temp_dir
  export ORIG_UID=$(id -u)
  export TEST_CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude-config"
  export CLAUDE_CONFIG_DIR="$TEST_CLAUDE_CONFIG_DIR"
  mkdir -p "$TEST_CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw"
  # Ensure git identity is available (CI runners may not have global config)
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@test.local"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@test.local"
}

# Compute the repo hash the same way vbw-statusline.sh does
_repo_hash() {
  local repo_root
  repo_root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null || echo "$1")
  if command -v md5sum &>/dev/null; then
    echo "$repo_root" | md5sum | cut -c1-8
  elif command -v md5 &>/dev/null; then
    echo "$repo_root" | md5 -q | cut -c1-8
  else
    printf '%s' "$repo_root" | cksum | cut -d' ' -f1
  fi
}

teardown() {
  rm -f /tmp/vbw-*-"${ORIG_UID}"-* /tmp/vbw-*-"${ORIG_UID}" 2>/dev/null || true
  unset CLAUDE_CONFIG_DIR TEST_CLAUDE_CONFIG_DIR
  teardown_temp_dir
}

# --- Cache key includes repo hash ---

@test "cache key includes repo-specific hash" {
  local uid=$(id -u)
  # Run statusline in an isolated repo (not the real project root) to avoid
  # race conditions with concurrent dsR invocations from active Claude Code
  # sessions that also run vbw-statusline.sh in the same repo.
  local repo="$TEST_TEMP_DIR/repo-hash"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cd "$repo"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  cd "$PROJECT_ROOT"
  # Compute expected hash for this repo
  local expected_hash
  expected_hash=$(_repo_hash "$repo")
  # Cache file with this repo's hash should exist
  [ -f "/tmp/vbw-0-${uid}-${expected_hash}-fast" ] || \
    ls /tmp/vbw-*-"${uid}"-"${expected_hash}"-fast 2>/dev/null | grep -q .
}

@test "different repos produce different cache keys" {
  local uid=$(id -u)

  # Create two isolated repos
  local repo1="$TEST_TEMP_DIR/repo1"
  mkdir -p "$repo1"
  git -C "$repo1" init -q
  git -C "$repo1" commit --allow-empty -m "test(init): seed" -q

  local repo2="$TEST_TEMP_DIR/repo2"
  mkdir -p "$repo2"
  git -C "$repo2" init -q
  git -C "$repo2" commit --allow-empty -m "test(init): seed" -q

  # Compute expected hashes
  local hash1 hash2
  hash1=$(_repo_hash "$repo1")
  hash2=$(_repo_hash "$repo2")

  # Hashes should differ
  [ "$hash1" != "$hash2" ]

  # Run statusline in both
  cd "$repo1"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  cd "$repo2"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  cd "$PROJECT_ROOT"

  # Both repo-specific cache files should exist
  ls /tmp/vbw-*-"${uid}"-"${hash1}"-fast &>/dev/null
  ls /tmp/vbw-*-"${uid}"-"${hash2}"-fast &>/dev/null
}

@test "cache is not shared between repos within TTL window" {
  local uid=$(id -u)

  # Create two isolated repos
  local repo_a="$TEST_TEMP_DIR/repo-a"
  local repo_b="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$repo_a" "$repo_b"
  git -C "$repo_a" init -q
  git -C "$repo_a" commit --allow-empty -m "test(init): seed" -q
  git -C "$repo_b" init -q
  git -C "$repo_b" commit --allow-empty -m "test(init): seed" -q

  # Compute repo A's specific cache file
  local hash_a
  hash_a=$(_repo_hash "$repo_a")

  # Run statusline in repo A
  cd "$repo_a"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  local cache_a
  cache_a=$(cat /tmp/vbw-*-"${uid}"-"${hash_a}"-fast 2>/dev/null | head -1)

  # Run statusline in repo B (within 5s TTL)
  cd "$repo_b"
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1

  # Repo A's cache should be unchanged
  local cache_a_after
  cache_a_after=$(cat /tmp/vbw-*-"${uid}"-"${hash_a}"-fast 2>/dev/null | head -1)
  cd "$PROJECT_ROOT"

  [ "$cache_a" = "$cache_a_after" ]
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

  # Should contain directory name and branch (branch varies: main or master)
  echo "$output" | grep -q "my-local-project:${branch}"
}

@test "no-remote repo does not show another repo's name" {
  local uid=$(id -u)
  local repo="$TEST_TEMP_DIR/isolated-repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q

  # First run in main project (has origin remote)
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1

  # Then run in local-only repo
  cd "$repo"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1 | head -1)
  cd "$PROJECT_ROOT"

  # Should NOT contain the main project's GitHub repo name
  ! echo "$output" | grep -q "vibe-better-with-claude-code-vbw"
  # Should contain the local directory name
  echo "$output" | grep -q "isolated-repo"
}

@test "repo with remote shows GitHub link, not bare directory name" {
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1 | head -1)
  # Should contain the OSC 8 link escape sequence (clickable link)
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

  # Detached HEAD has no branch name, but remote repos should still render OSC 8 links
  echo "$output" | grep -q ']8;;https://'
}

# --- Cache cleanup ---

@test "stale cache cleanup removes old-format caches" {
  local uid=$(id -u)
  # Create fake old-format cache (no repo hash)
  touch "/tmp/vbw-0.0.0-${uid}-fast"
  touch "/tmp/vbw-0.0.0-${uid}-slow"
  touch "/tmp/vbw-0.0.0-${uid}-ok"

  # Run statusline — should clean up old format
  # Tolerate non-zero exit (e.g. SIGINT from bats runner); we only need the cleanup side-effect
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1 || true

  # Old caches should be gone (cleaned by the -ok check or glob cleanup)
  [ ! -f "/tmp/vbw-0.0.0-${uid}-fast" ]
  [ ! -f "/tmp/vbw-0.0.0-${uid}-slow" ]
}

@test "cache-nuke.sh cleans repo-scoped caches" {
  local uid=$(id -u)
  # Create cache files in new format
  echo '{}' | bash "$STATUSLINE" >/dev/null 2>&1
  local before
  before=$(ls /tmp/vbw-*-"${uid}"-* 2>/dev/null | wc -l | tr -d ' ')
  [ "$before" -gt 0 ]

  # Nuke caches
  run bash "$SCRIPTS_DIR/cache-nuke.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.wiped | has("plugin_cache") and has("temp_caches") and has("versions_removed")' >/dev/null

  local after
  after=$(ls /tmp/vbw-*-"${uid}"-* 2>/dev/null | wc -l | tr -d ' ')
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

  # Make parent non-writable so keep-latest deletion attempt fails.
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
  # Should produce 4 lines without errors
  local lines
  lines=$(echo "$output" | wc -l | tr -d ' ')
  [ "$lines" -eq 4 ]
}
