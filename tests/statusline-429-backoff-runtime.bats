#!/usr/bin/env bats

load test_helper

STATUSLINE="$SCRIPTS_DIR/vbw-statusline.sh"

setup() {
  setup_temp_dir
  export ORIG_UID=$(id -u)
  export ORIG_PATH="$PATH"
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@test.local"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@test.local"
  export VBW_SKIP_KEYCHAIN=1
  export VBW_SKIP_AUTH_CLI=1
  export VBW_SKIP_UPDATE_CHECK=1
  cleanup_vbw_caches_under_temp_dir "$ORIG_UID"

  export TEST_REPO="$TEST_TEMP_DIR/repo-429"
  mkdir -p "$TEST_REPO/.vbw-planning"
  git -C "$TEST_REPO" init -q
  git -C "$TEST_REPO" commit --allow-empty -m "test(init): seed" -q
  cat > "$TEST_REPO/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_limits": false,
  "statusline_hide_limits_for_api_key": false
}
JSON
}

teardown() {
  export PATH="$ORIG_PATH"
  cleanup_vbw_caches_under_temp_dir "$ORIG_UID"
  unset VBW_SKIP_KEYCHAIN VBW_SKIP_AUTH_CLI VBW_SKIP_UPDATE_CHECK VBW_OAUTH_TOKEN
  teardown_temp_dir
}

@test "429 usage response populates ratelimited slow cache at runtime" {
  local fake_bin="$TEST_TEMP_DIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/curl" <<'SH'
#!/usr/bin/env bash
printf '\n429'
SH
  chmod +x "$fake_bin/curl"

  export PATH="$fake_bin:$PATH"
  export VBW_OAUTH_TOKEN="fake-token"

  cd "$TEST_REPO"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  cd "$PROJECT_ROOT"

  echo "$output" | grep -q 'rate limited'

  local slow_cache
  slow_cache="$(vbw_cache_prefix_for_root "$TEST_REPO" "$ORIG_UID")-slow"
  [ "$(awk -F'|' '{print $10}' "$slow_cache")" = "ratelimited" ]
}
