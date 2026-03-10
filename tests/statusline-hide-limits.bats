#!/usr/bin/env bats
# Tests for statusline_hide_limits, statusline_hide_limits_for_api_key, and
# statusline_hide_agent_in_tmux config switches.
# Verifies L3 (usage/limits) and L1 (build status) suppression behavior.

load test_helper

STATUSLINE="$SCRIPTS_DIR/vbw-statusline.sh"

setup() {
  setup_temp_dir
  export ORIG_UID=$(id -u)
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@test.local"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@test.local"
  rm -f /tmp/vbw-*-"${ORIG_UID}"-* /tmp/vbw-*-"${ORIG_UID}" 2>/dev/null || true
}

teardown() {
  rm -f /tmp/vbw-*-"${ORIG_UID}"-* /tmp/vbw-*-"${ORIG_UID}" 2>/dev/null || true
  teardown_temp_dir
}

# --- Default: L3 is present ---

@test "default config: L3 (3rd line) is present and non-empty" {
  local repo="$TEST_TEMP_DIR/repo-default"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_limits": false,
  "statusline_hide_limits_for_api_key": false
}
JSON

  cd "$repo"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  cd "$PROJECT_ROOT"

  local l3
  l3=$(echo "$output" | sed -n '3p')
  [ -n "$l3" ]
}

# --- statusline_hide_limits: true suppresses L3 ---

@test "statusline_hide_limits true: L3 is blank" {
  local repo="$TEST_TEMP_DIR/repo-hide-all"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_limits": true,
  "statusline_hide_limits_for_api_key": false
}
JSON

  cd "$repo"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  cd "$PROJECT_ROOT"

  # L3 omitted entirely — output should be 3 lines (L1, L2, L4)
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 3 ]
}

# --- statusline_hide_limits_for_api_key: true with no OAuth (API key path) ---

@test "statusline_hide_limits_for_api_key true without OAuth: L3 is blank" {
  local repo="$TEST_TEMP_DIR/repo-hide-api"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_limits": false,
  "statusline_hide_limits_for_api_key": true
}
JSON

  cd "$repo"
  # Isolate credential discovery: block env-var override and system Keychain lookup so
  # FETCH_OK="noauth" is guaranteed regardless of the developer's system credentials.
  export CLAUDE_CONFIG_DIR="$repo"
  export VBW_SKIP_KEYCHAIN=1
  export VBW_SKIP_AUTH_CLI=1
  unset VBW_OAUTH_TOKEN 2>/dev/null || true
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  unset CLAUDE_CONFIG_DIR
  unset VBW_SKIP_KEYCHAIN
  unset VBW_SKIP_AUTH_CLI
  cd "$PROJECT_ROOT"

  # L3 omitted entirely — output should be 3 lines (L1, L2, L4)
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 3 ]
}

# --- statusline_hide_limits_for_api_key: true with OAuth token (not suppressed) ---

@test "statusline_hide_limits_for_api_key true with OAuth token: L3 still has content" {
  local repo="$TEST_TEMP_DIR/repo-hide-api-oauth"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_limits": false,
  "statusline_hide_limits_for_api_key": true
}
JSON

  cd "$repo"
  # With a fake OAuth token, the API call will fail → FETCH_OK="fail"
  # "fail" is excluded from suppression, so L3 should still be present
  export VBW_OAUTH_TOKEN="fake_token_for_test"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  unset VBW_OAUTH_TOKEN
  cd "$PROJECT_ROOT"

  local l3
  l3=$(echo "$output" | sed -n '3p')
  [ -n "$l3" ]
}

# --- statusline_collapse_agent_in_tmux: collapses in worktrees, not in main repo ---

@test "statusline_collapse_agent_in_tmux: collapses to single line in git worktree" {
  local repo="$TEST_TEMP_DIR/repo-collapse-main"
  local worktree="$TEST_TEMP_DIR/repo-collapse-wt"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_collapse_agent_in_tmux": true
}
JSON
  git -C "$repo" worktree add "$worktree" -b "test-collapse-wt" -q

  cd "$worktree"
  export TMUX="mock"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  unset TMUX
  cd "$PROJECT_ROOT"

  local l1 l2
  l1=$(echo "$output" | sed -n '1p')
  l2=$(echo "$output" | sed -n '2p')
  # Single collapsed line with all three fields
  echo "$l1" | grep -q "Model:"
  echo "$l1" | grep -q "Context:"
  echo "$l1" | grep -q "Tokens:"
  # L2 must be empty (only one line rendered)
  [ -z "$l2" ]
}

@test "statusline_collapse_agent_in_tmux: no collapse in main repo (orchestrator pane)" {
  local repo="$TEST_TEMP_DIR/repo-collapse-orchestrator"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_collapse_agent_in_tmux": true
}
JSON

  cd "$repo"
  export TMUX="mock"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  unset TMUX
  cd "$PROJECT_ROOT"

  local l2
  l2=$(echo "$output" | sed -n '2p')
  # Full 4-line output: L2 must be present
  [ -n "$l2" ]
}

# --- statusline_hide_agent_in_tmux: true inside tmux suppresses Build: in L1 ---

@test "statusline_hide_agent_in_tmux true in tmux: L1 does not contain Build:" {
  local repo="$TEST_TEMP_DIR/repo-hide-agent-tmux"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_agent_in_tmux": true
}
JSON
  # Create a fake execution-state.json with running status
  cat > "$repo/.vbw-planning/.execution-state.json" <<'JSON'
{
  "status": "running",
  "wave": 1,
  "total_waves": 1,
  "plans": [
    {"title": "test-plan", "status": "running"},
    {"title": "other-plan", "status": "pending"}
  ]
}
JSON

  cd "$repo"
  export TMUX="mock"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  unset TMUX
  cd "$PROJECT_ROOT"

  local l1
  l1=$(echo "$output" | sed -n '1p')
  # L1 should NOT contain "Build:" — it should fall through to standard VBW state
  ! echo "$l1" | grep -q "Build:"
}

# --- Edge case: both hide_limits flags true simultaneously ---

@test "both statusline_hide_limits and statusline_hide_limits_for_api_key true: L3 is blank" {
  local repo="$TEST_TEMP_DIR/repo-hide-both"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_limits": true,
  "statusline_hide_limits_for_api_key": true
}
JSON

  cd "$repo"
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  cd "$PROJECT_ROOT"

  # L3 omitted entirely — output should be 3 lines (L1, L2, L4)
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 3 ]
}

# --- Negative: statusline_hide_agent_in_tmux true but NOT in tmux (no effect) ---

@test "statusline_hide_agent_in_tmux true outside tmux: L1 still contains Build:" {
  local repo="$TEST_TEMP_DIR/repo-hide-agent-no-tmux"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_hide_agent_in_tmux": true
}
JSON
  cat > "$repo/.vbw-planning/.execution-state.json" <<'JSON'
{
  "status": "running",
  "wave": 1,
  "total_waves": 1,
  "plans": [{"title": "test-plan", "status": "running"}]
}
JSON

  cd "$repo"
  unset TMUX 2>/dev/null || true
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  cd "$PROJECT_ROOT"

  local l1
  l1=$(echo "$output" | sed -n '1p')
  # Outside tmux, hide_agent_in_tmux has no effect — Build: should be present
  echo "$l1" | grep -q "Build:"
}

# --- Negative: statusline_collapse_agent_in_tmux true but NOT in tmux (no collapse) ---

@test "statusline_collapse_agent_in_tmux true outside tmux: full multi-line output" {
  local repo="$TEST_TEMP_DIR/repo-collapse-no-tmux"
  local worktree="$TEST_TEMP_DIR/repo-collapse-no-tmux-wt"
  mkdir -p "$repo/.vbw-planning"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "test(init): seed" -q
  cat > "$repo/.vbw-planning/config.json" <<'JSON'
{
  "effort": "balanced",
  "statusline_collapse_agent_in_tmux": true
}
JSON
  git -C "$repo" worktree add "$worktree" -b "test-no-tmux-wt" -q

  cd "$worktree"
  unset TMUX 2>/dev/null || true
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  cd "$PROJECT_ROOT"

  local l2
  l2=$(echo "$output" | sed -n '2p')
  # Without TMUX, no collapse — L2 must be present
  [ -n "$l2" ]
}
