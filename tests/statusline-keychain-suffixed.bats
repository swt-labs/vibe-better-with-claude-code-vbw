#!/usr/bin/env bats
# Issue #576 — statusline keychain lookup must handle Claude Code's per-install
# suffixed service names ("Claude Code-credentials-<8hex>"), and the
# FETCH_OK=noauth + AUTH_METHOD=claude.ai branch must emit an honest message
# rather than wrongly blaming a permissions denial.

load test_helper

STATUSLINE="$SCRIPTS_DIR/vbw-statusline.sh"

setup() {
  setup_temp_dir
  export ORIG_UID=$(id -u)
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@test.local"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@test.local"
  # NOTE: these tests intentionally do NOT set VBW_SKIP_KEYCHAIN — they exercise
  # the keychain code path with a mocked `security` binary on PATH.
  export VBW_SKIP_AUTH_CLI=1
  export VBW_SKIP_UPDATE_CHECK=1
  cleanup_vbw_caches_under_temp_dir "$ORIG_UID"
}

teardown() {
  cleanup_vbw_caches_under_temp_dir "$ORIG_UID"
  unset VBW_SKIP_AUTH_CLI VBW_SKIP_UPDATE_CHECK
  teardown_temp_dir
}

# Build a mock `security` binary that responds to find-generic-password and
# dump-keychain based on a fixture spec. Args:
#   $1 = fake_bin dir
#   $2 = "yes"|"no"   — whether the literal "Claude Code-credentials" item exists
#   $3 = suffixed service name to expose (or empty for none)
#   $4 = access token JSON value to return when matched
_install_mock_security() {
  local fake_bin="$1"
  local literal_present="$2"
  local suffixed_name="$3"
  local token_value="$4"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/security" <<SH
#!/usr/bin/env bash
LITERAL_PRESENT="$literal_present"
SUFFIXED_NAME="$suffixed_name"
TOKEN_VALUE="$token_value"

if [ "\$1" = "find-generic-password" ]; then
  svc=""
  shift
  while [ "\$#" -gt 0 ]; do
    if [ "\$1" = "-s" ]; then svc="\$2"; shift 2; continue; fi
    shift
  done
  if [ "\$svc" = "Claude Code-credentials" ] && [ "\$LITERAL_PRESENT" = "yes" ]; then
    printf '{"claudeAiOauth":{"accessToken":"%s"}}\n' "\$TOKEN_VALUE"
    exit 0
  fi
  if [ -n "\$SUFFIXED_NAME" ] && [ "\$svc" = "\$SUFFIXED_NAME" ]; then
    printf '{"claudeAiOauth":{"accessToken":"%s"}}\n' "\$TOKEN_VALUE"
    exit 0
  fi
  echo "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain." >&2
  exit 44
fi

if [ "\$1" = "dump-keychain" ]; then
  if [ -n "\$SUFFIXED_NAME" ]; then
    printf '    "svce"<blob>="%s"\n' "\$SUFFIXED_NAME"
  fi
  exit 0
fi

exit 0
SH
  chmod +x "$fake_bin/security"
}

# Build a mock curl that returns a 200 + valid usage payload (drives FETCH_OK=ok).
_install_mock_curl_ok() {
  local fake_bin="$1"
  cat > "$fake_bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n%s' '{"five_hour":{"utilization":0,"resets_at":"2030-01-01T00:00:00Z"},"seven_day":{"utilization":0,"resets_at":"2030-01-01T00:00:00Z"},"seven_day_sonnet":{"utilization":0},"extra_usage":{"is_enabled":false,"utilization":0,"used_credits":0,"monthly_limit":0}}' '200'
SH
  chmod +x "$fake_bin/curl"
}

# --- Back-compat: legacy literal service name still works ---

@test "issue #576: legacy literal 'Claude Code-credentials' still works (back-compat)" {
  local repo="$TEST_TEMP_DIR/repo-literal"
  local fake_bin="$TEST_TEMP_DIR/fake-bin-literal"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{ "effort": "balanced", "statusline_hide_limits": false, "statusline_hide_limits_for_api_key": false }
JSON

  _install_mock_security "$fake_bin" "yes" "" "fake-token-literal"
  _install_mock_curl_ok "$fake_bin"

  cd "$repo"
  local old_path="$PATH"
  export PATH="$fake_bin:$PATH"
  unset VBW_OAUTH_TOKEN 2>/dev/null || true
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  export PATH="$old_path"
  cd "$PROJECT_ROOT"

  local l3
  l3=$(echo "$output" | sed -n '3p')
  # Token retrieved → FETCH_OK=ok → real usage line, not the unavailable branch.
  # NOTE: `[[ ! ... =~ ... ]]` fails the test on match; `! grep -q` does not (SC2314).
  [[ ! "$l3" =~ "OAuth token unavailable" ]]
  [[ ! "$l3" =~ "keychain access denied" ]]
}

# --- New behavior: suffixed service name discovered when literal is absent ---

@test "issue #576: suffixed 'Claude Code-credentials-<hex>' discovered when literal is absent" {
  local repo="$TEST_TEMP_DIR/repo-suffixed"
  local fake_bin="$TEST_TEMP_DIR/fake-bin-suffixed"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{ "effort": "balanced", "statusline_hide_limits": false, "statusline_hide_limits_for_api_key": false }
JSON

  _install_mock_security "$fake_bin" "no" "Claude Code-credentials-126018b2" "fake-token-suffixed"
  _install_mock_curl_ok "$fake_bin"

  cd "$repo"
  local old_path="$PATH"
  export PATH="$fake_bin:$PATH"
  unset VBW_OAUTH_TOKEN 2>/dev/null || true
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  export PATH="$old_path"
  cd "$PROJECT_ROOT"

  local l3
  l3=$(echo "$output" | sed -n '3p')
  # Suffixed lookup succeeds → no fallback message.
  # NOTE: `[[ ! ... =~ ... ]]` fails the test on match; `! grep -q` does not (SC2314).
  [[ ! "$l3" =~ "OAuth token unavailable" ]]
  [[ ! "$l3" =~ "keychain access denied" ]]
}

# --- New honest message: when no token is reachable but claude.ai login is detected ---

@test "issue #576: claude.ai login + no reachable token emits 'OAuth token unavailable' (no longer blames keychain)" {
  local repo="$TEST_TEMP_DIR/repo-claude-ai-no-token"
  local fake_bin="$TEST_TEMP_DIR/fake-bin-no-token"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{ "effort": "balanced", "statusline_hide_limits": false, "statusline_hide_limits_for_api_key": false }
JSON

  # security: literal absent, no suffixed entry — every find-generic-password returns exit 44.
  _install_mock_security "$fake_bin" "no" "" ""

  # claude CLI: report OAuth login (claude.ai) so AUTH_METHOD=claude.ai is set.
  cat > "$fake_bin/claude" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  printf '{"loggedIn":true,"authMethod":"claude.ai"}'
fi
exit 0
SH
  chmod +x "$fake_bin/claude"

  cd "$repo"
  local old_path="$PATH"
  export PATH="$fake_bin:$PATH"
  unset VBW_OAUTH_TOKEN 2>/dev/null || true
  unset VBW_SKIP_AUTH_CLI 2>/dev/null || true
  export CLAUDE_CONFIG_DIR="$repo"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  unset CLAUDE_CONFIG_DIR
  export VBW_SKIP_AUTH_CLI=1
  export PATH="$old_path"
  cd "$PROJECT_ROOT"

  local l3
  l3=$(echo "$output" | sed -n '3p')
  # Positive grep failure DOES fail a Bats test; the negation does not (SC2314),
  # so use [[ ... =~ ... ]] for the negative assertion.
  echo "$l3" | grep -q "OAuth token unavailable"
  [[ ! "$l3" =~ "keychain access denied" ]]
}
