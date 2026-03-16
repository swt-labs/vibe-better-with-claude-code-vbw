#!/usr/bin/env bats
# Tests for autocompact buffer normalization in vbw-statusline.sh (#237)
#
# The statusline normalizes raw context percentages so 100% = autocompact trigger
# rather than raw window size. This removes the "dead zone" buffer that CC reserves.
#
# Algorithm (from CC v2.1.76):
#   effective = ctx_window - min(max_output, 20000)
#   default_trigger = effective - 13000
#   override_trigger = floor(effective * pct / 100) [if override]
#   trigger = min(override_trigger, default_trigger)
#   buffer = ctx_window - trigger
#
# Observable output: .vbw-planning/.context-usage contains "session|PCT|CTX_SIZE"
# where PCT and CTX_SIZE reflect the normalized values.

load test_helper

STATUSLINE="$SCRIPTS_DIR/vbw-statusline.sh"

# Helper: run the statusline with given JSON and env, return .context-usage content
run_statusline() {
  local json="$1"
  echo "$json" | bash "$STATUSLINE" >/dev/null 2>&1
  cat .vbw-planning/.context-usage 2>/dev/null
}

# Helper: extract normalized PCT from .context-usage (format: session|PCT|CTX_SIZE)
get_pct() {
  echo "$1" | cut -d'|' -f2
}

# Helper: extract normalized CTX_SIZE from .context-usage
get_ctx_size() {
  echo "$1" | cut -d'|' -f3
}

# Build a JSON input blob with the given context window parameters
make_json() {
  local pct="${1:-0}" rem="${2:-100}" ctx_size="${3:-200000}"
  printf '{"context_window":{"used_percentage":%s,"remaining_percentage":%s,"context_window_size":%s,"current_usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0,"total_duration_ms":1000,"total_api_duration_ms":500,"total_lines_added":0,"total_lines_removed":0},"model":{"display_name":"Claude"},"version":"2.1.76"}' \
    "$pct" "$rem" "$ctx_size"
}

setup() {
  setup_temp_dir
  export ORIG_UID=$(id -u)
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@test.local"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@test.local"
  # Clean caches
  rm -f /tmp/vbw-*-"${ORIG_UID}"-* /tmp/vbw-*-"${ORIG_UID}" 2>/dev/null || true
  # Create isolated repo
  export TEST_REPO="$TEST_TEMP_DIR/repo-ac"
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
  cd "$TEST_REPO"
  # Clear env vars that would interfere
  unset DISABLE_AUTO_COMPACT CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
  unset CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_MAX_OUTPUT_TOKENS
  unset CLAUDE_CONFIG_DIR
  # Create a settings.json with a dummy env value at CLAUDE_CONFIG_DIR so the
  # script's settings loop breaks on the first match and never reads the user's
  # real ~/.claude/settings.json (which may have CLAUDE_AUTOCOMPACT_PCT_OVERRIDE).
  # The loop only breaks when at least one env value is non-empty.
  mkdir -p "$TEST_TEMP_DIR/claude-config"
  echo '{"env":{"DISABLE_AUTO_COMPACT":"false"}}' > "$TEST_TEMP_DIR/claude-config/settings.json"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude-config"
}

teardown() {
  cd "$PROJECT_ROOT"
  rm -f /tmp/vbw-*-"${ORIG_UID}"-* /tmp/vbw-*-"${ORIG_UID}" 2>/dev/null || true
  teardown_temp_dir
}

# =============================================================================
# 200K window — default autocompact behavior
# =============================================================================

# 200K: effective=180K, trigger=167K, buffer=33K (16.5%)
# CTX_SIZE should be normalized to 167K (the trigger point)

@test "200K: CTX_SIZE normalized to trigger (167K)" {
  local result
  result=$(run_statusline "$(make_json 0 100 200000)")
  local ctx_size
  ctx_size=$(get_ctx_size "$result")
  [ "$ctx_size" = "167000" ]
}

@test "200K: fresh session (0% raw) → 0% normalized" {
  local result
  result=$(run_statusline "$(make_json 0 100 200000)")
  local pct
  pct=$(get_pct "$result")
  [ "$pct" = "0" ]
}

@test "200K: 50% raw → rescaled PCT within usable range" {
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  # 50% raw → REM_X10=500, BUF_PCT_X10=165
  # usable = (500-165)*1000/(1000-165) = 335000/835 = 401
  # PCT = 100 - (401+5)/10 = 100 - 40 = 60
  [ "$pct" = "60" ]
}

@test "200K: 83% raw (REM=17) → 99% normalized (near trigger)" {
  local result
  result=$(run_statusline "$(make_json 83 17 200000)")
  local pct
  pct=$(get_pct "$result")
  # REM_X10=170, BUF_PCT_X10=165, usable=(170-165)*1000/835=5000/835=5
  # PCT = 100 - (5+5)/10 = 100 - 1 = 99
  [ "$pct" = "99" ]
}

@test "200K: at trigger (REM=16) → 100% normalized" {
  local result
  result=$(run_statusline "$(make_json 84 16 200000)")
  local pct
  pct=$(get_pct "$result")
  # REM_X10=160, BUF_PCT_X10=165 → usable=(160-165)*1000/835 < 0 → clamped to 0
  # PCT = 100 - (0+5)/10 = 100 - 0 = 100
  [ "$pct" = "100" ]
}

@test "200K: past trigger (REM=10) → clamped 100%" {
  local result
  result=$(run_statusline "$(make_json 90 10 200000)")
  local pct
  pct=$(get_pct "$result")
  [ "$pct" = "100" ]
}

# =============================================================================
# 1M window — default autocompact behavior
# =============================================================================

# 1M: effective=980K, trigger=967K, buffer=33K (3.3%)

@test "1M: CTX_SIZE normalized to trigger (967K)" {
  local result
  result=$(run_statusline "$(make_json 0 100 1000000)")
  local ctx_size
  ctx_size=$(get_ctx_size "$result")
  [ "$ctx_size" = "967000" ]
}

@test "1M: 50% raw → rescaled PCT" {
  local result
  result=$(run_statusline "$(make_json 50 50 1000000)")
  local pct
  pct=$(get_pct "$result")
  # BUF_PCT_X10 = 33000*1000/1000000 = 33
  # usable = (500-33)*1000/(1000-33) = 467000/967 = 482
  # PCT = 100 - (482+5)/10 = 100 - 48 = 52
  [ "$pct" = "52" ]
}

# =============================================================================
# 1M + CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=95
# =============================================================================

# 1M + override 95: ov_trigger = floor(980K * 950/1000) = 931K
# default_trigger = 967K, min(931K, 967K) = 931K → override applied
# buffer = 1M - 931K = 69K, BUF_PCT_X10 = 69000*1000/1000000 = 69

@test "1M override=95: CTX_SIZE normalized to 931K" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=95
  local result
  result=$(run_statusline "$(make_json 0 100 1000000)")
  local ctx_size
  ctx_size=$(get_ctx_size "$result")
  [ "$ctx_size" = "931000" ]
}

@test "1M override=95: 50% raw → rescaled PCT" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=95
  local result
  result=$(run_statusline "$(make_json 50 50 1000000)")
  local pct
  pct=$(get_pct "$result")
  # BUF_PCT_X10 = 69000*1000/1000000 = 69
  # usable = (500-69)*1000/(1000-69) = 431000/931 = 462
  # PCT = 100 - (462+5)/10 = 100 - 46 = 54
  [ "$pct" = "54" ]
}

# =============================================================================
# Override=95 on 200K — override is higher than default, so ignored
# =============================================================================

@test "200K override=95: ignored (default trigger lower), CTX_SIZE=167K" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=95
  local result
  result=$(run_statusline "$(make_json 0 100 200000)")
  local ctx_size
  ctx_size=$(get_ctx_size "$result")
  # ov_trigger = floor(180K * 950/1000) = 171K > default 167K → default wins
  [ "$ctx_size" = "167000" ]
}

# =============================================================================
# DISABLE_AUTO_COMPACT — normalization skipped
# =============================================================================

@test "DISABLE_AUTO_COMPACT=true: normalization skipped" {
  export DISABLE_AUTO_COMPACT=true
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct ctx_size
  pct=$(get_pct "$result")
  ctx_size=$(get_ctx_size "$result")
  [ "$pct" = "50" ]
  [ "$ctx_size" = "200000" ]
}

@test "DISABLE_AUTO_COMPACT=TRUE: case-insensitive handling" {
  export DISABLE_AUTO_COMPACT=TRUE
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  [ "$pct" = "50" ]
}

@test "DISABLE_AUTO_COMPACT=yes: alternative truthy value" {
  export DISABLE_AUTO_COMPACT=yes
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  [ "$pct" = "50" ]
}

@test "DISABLE_AUTO_COMPACT=1: numeric truthy value" {
  export DISABLE_AUTO_COMPACT=1
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  [ "$pct" = "50" ]
}

@test "DISABLE_AUTO_COMPACT=on: alternative truthy value" {
  export DISABLE_AUTO_COMPACT=on
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  [ "$pct" = "50" ]
}

@test "DISABLE_AUTO_COMPACT=false: normalization NOT skipped" {
  export DISABLE_AUTO_COMPACT=false
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  # Should be normalized (60%), not raw (50%)
  [ "$pct" = "60" ]
}

# =============================================================================
# CLAUDE_CODE_AUTO_COMPACT_WINDOW cap
# =============================================================================

# Window cap=150K on 200K window: capped to 150K
# effective=130K, trigger=117K, buffer=200K-117K=83K, BUF_PCT_X10=415

@test "window cap 150K on 200K: CTX_SIZE normalized to capped trigger (117K)" {
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000
  local result
  result=$(run_statusline "$(make_json 0 100 200000)")
  local ctx_size
  ctx_size=$(get_ctx_size "$result")
  [ "$ctx_size" = "117000" ]
}

# =============================================================================
# CLAUDE_CODE_MAX_OUTPUT_TOKENS deduction
# =============================================================================

# Custom max_output=8000 on 200K: effective=192K, trigger=179K, buffer=21K
# BUF_PCT_X10 = 21000*1000/200000 = 105

@test "max_output=8000 on 200K: CTX_SIZE normalized to 179K" {
  export CLAUDE_CODE_MAX_OUTPUT_TOKENS=8000
  local result
  result=$(run_statusline "$(make_json 0 100 200000)")
  local ctx_size
  ctx_size=$(get_ctx_size "$result")
  [ "$ctx_size" = "179000" ]
}

# max_output larger than 20000 should be capped at 20000 (same as default)
@test "max_output=30000 on 200K: capped at 20K, CTX_SIZE=167K" {
  export CLAUDE_CODE_MAX_OUTPUT_TOKENS=30000
  local result
  result=$(run_statusline "$(make_json 0 100 200000)")
  local ctx_size
  ctx_size=$(get_ctx_size "$result")
  # min(30000, 20000) = 20000, same as default → trigger=167K
  [ "$ctx_size" = "167000" ]
}

# =============================================================================
# Non-numeric / garbage override values → graceful no-op
# =============================================================================

@test "garbage override 'abc': ignored, defaults apply" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=abc
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  # Default normalization should apply (60% for 200K at 50% raw)
  [ "$pct" = "60" ]
}

@test "empty override: ignored, defaults apply" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=""
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  [ "$pct" = "60" ]
}

@test "override=0: ignored (out of range)" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=0
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  [ "$pct" = "60" ]
}

@test "override=101: ignored (out of range)" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=101
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  [ "$pct" = "60" ]
}

# =============================================================================
# CTX_SIZE=0 / empty → skipped safely
# =============================================================================

@test "CTX_SIZE=0: normalization skipped, raw values preserved" {
  local result
  result=$(run_statusline "$(make_json 50 50 0)")
  local pct ctx_size
  pct=$(get_pct "$result")
  ctx_size=$(get_ctx_size "$result")
  [ "$pct" = "50" ]
  [ "$ctx_size" = "0" ]
}

@test "empty JSON: defaults applied safely" {
  local result
  result=$(run_statusline '{}')
  local pct ctx_size
  pct=$(get_pct "$result")
  ctx_size=$(get_ctx_size "$result")
  # ctx_window_size defaults to 200000 per jq expression; PCT defaults to 0
  # With normalization: CTX_SIZE → 167K, PCT=0
  [ "$pct" = "0" ]
  [ "$ctx_size" = "167000" ]
}

# =============================================================================
# Settings.json env block resolution
# =============================================================================

@test "settings.json DISABLE_AUTO_COMPACT=true: normalization skipped" {
  mkdir -p "$TEST_TEMP_DIR/claude-config"
  cat > "$TEST_TEMP_DIR/claude-config/settings.json" <<'JSON'
{"env": {"DISABLE_AUTO_COMPACT": "true"}}
JSON
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude-config"
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  [ "$pct" = "50" ]
}

@test "settings.json override=80: applied (lower than default)" {
  mkdir -p "$TEST_TEMP_DIR/claude-config"
  cat > "$TEST_TEMP_DIR/claude-config/settings.json" <<'JSON'
{"env": {"CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "80"}}
JSON
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude-config"
  local result
  result=$(run_statusline "$(make_json 0 100 200000)")
  local ctx_size
  ctx_size=$(get_ctx_size "$result")
  # ov_trigger = floor(180K * 800/1000) = 144K, default=167K, min=144K
  [ "$ctx_size" = "144000" ]
}

@test "real env overrides settings.json" {
  mkdir -p "$TEST_TEMP_DIR/claude-config"
  cat > "$TEST_TEMP_DIR/claude-config/settings.json" <<'JSON'
{"env": {"DISABLE_AUTO_COMPACT": "true"}}
JSON
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude-config"
  export DISABLE_AUTO_COMPACT=false
  local result
  result=$(run_statusline "$(make_json 50 50 200000)")
  local pct
  pct=$(get_pct "$result")
  # Real env says false → normalization applied → 60%
  [ "$pct" = "60" ]
}

# =============================================================================
# Decimal override values (fixed-point x10 math)
# =============================================================================

@test "override=95.5 on 1M: decimal handled correctly" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=95.5
  local result
  result=$(run_statusline "$(make_json 0 100 1000000)")
  local ctx_size
  ctx_size=$(get_ctx_size "$result")
  # ov_trigger = floor(980000 * 955 / 1000) = floor(935900) = 935900
  # default=967K, min(935900, 967000) = 935900
  [ "$ctx_size" = "935900" ]
}
