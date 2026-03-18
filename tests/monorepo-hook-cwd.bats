#!/usr/bin/env bats
# Tests for VBW root resolution when CWD != workspace root.
# Regression coverage for upstream issue #258: hooks fire from monorepo
# submodule directories where bare .vbw-planning/ paths fail silently.

load test_helper

LIB="$SCRIPTS_DIR/lib/vbw-config-root.sh"
STATUSLINE="$SCRIPTS_DIR/vbw-statusline.sh"

setup() {
  setup_temp_dir
  export ORIG_UID=$(id -u)
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@test.local"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@test.local"
  rm -f /tmp/vbw-*-"${ORIG_UID}"-* /tmp/vbw-*-"${ORIG_UID}" 2>/dev/null || true
  # Ensure VBW_CONFIG_ROOT is unset before each test for a clean walk
  unset VBW_CONFIG_ROOT 2>/dev/null || true
  unset VBW_PLANNING_DIR 2>/dev/null || true
}

teardown() {
  rm -f /tmp/vbw-*-"${ORIG_UID}"-* /tmp/vbw-*-"${ORIG_UID}" 2>/dev/null || true
  teardown_temp_dir
}

# Helper: create a minimal VBW workspace with git and config.json
setup_workspace() {
  local root="$1"
  mkdir -p "$root/.vbw-planning"
  git -C "$root" init -q
  git -C "$root" commit --allow-empty -m "test(init): seed" -q
  cat > "$root/.vbw-planning/config.json" <<'JSON'
{"effort": "balanced", "model_profile": "balanced"}
JSON
}

# --- Test 1: find_vbw_root from workspace root (backwards-compat) ---

@test "find_vbw_root: resolves to CWD when run from workspace root" {
  local root="$TEST_TEMP_DIR/workspace"
  setup_workspace "$root"
  # Resolve physical path (handles /var -> /private/var on macOS)
  local root_real; root_real=$(cd "$root" && pwd -P 2>/dev/null || echo "$root")

  local result
  result=$(
    cd "$root"
    unset VBW_CONFIG_ROOT 2>/dev/null || true
    unset VBW_PLANNING_DIR 2>/dev/null || true
    . "$LIB"
    find_vbw_root
    echo "$VBW_CONFIG_ROOT"
  )
  cd "$PROJECT_ROOT"

  [ "$result" = "$root_real" ]
}

# --- Test 2: find_vbw_root from subdirectory ---

@test "find_vbw_root: walks up from subdirectory to workspace root" {
  local root="$TEST_TEMP_DIR/monorepo"
  setup_workspace "$root"
  mkdir -p "$root/apps/rest-api"
  local root_real; root_real=$(cd "$root" && pwd -P 2>/dev/null || echo "$root")

  local result
  result=$(
    cd "$root/apps/rest-api"
    unset VBW_CONFIG_ROOT 2>/dev/null || true
    unset VBW_PLANNING_DIR 2>/dev/null || true
    . "$LIB"
    find_vbw_root
    echo "$VBW_CONFIG_ROOT"
  )
  cd "$PROJECT_ROOT"

  [ "$result" = "$root_real" ]
}

# --- Test 3: find_vbw_root from deeply nested subdirectory ---

@test "find_vbw_root: walks up from deeply nested directory to workspace root" {
  local root="$TEST_TEMP_DIR/monorepo-deep"
  setup_workspace "$root"
  mkdir -p "$root/apps/rest-api/src/handlers"
  local root_real; root_real=$(cd "$root" && pwd -P 2>/dev/null || echo "$root")

  local result
  result=$(
    cd "$root/apps/rest-api/src/handlers"
    unset VBW_CONFIG_ROOT 2>/dev/null || true
    unset VBW_PLANNING_DIR 2>/dev/null || true
    . "$LIB"
    find_vbw_root
    echo "$VBW_CONFIG_ROOT"
  )
  cd "$PROJECT_ROOT"

  [ "$result" = "$root_real" ]
}

# --- Test 4: find_vbw_root with no config anywhere (fallback to absolute CWD) ---

@test "find_vbw_root: falls back to absolute CWD when no .vbw-planning/config.json found" {
  local noconfig_dir="$TEST_TEMP_DIR/no-config-dir"
  mkdir -p "$noconfig_dir"
  local noconfig_real; noconfig_real=$(cd "$noconfig_dir" && pwd -P 2>/dev/null || echo "$noconfig_dir")

  local result
  result=$(
    cd "$noconfig_dir"
    unset VBW_CONFIG_ROOT 2>/dev/null || true
    unset VBW_PLANNING_DIR 2>/dev/null || true
    . "$LIB"
    find_vbw_root
    echo "$VBW_CONFIG_ROOT"
  )
  cd "$PROJECT_ROOT"

  # Fallback must be absolute (not relative "."), pointing to the actual CWD
  [ "$result" = "$noconfig_real" ]
}

# --- Test 5: find_vbw_root honours VBW_CONFIG_ROOT cache hit ---

@test "find_vbw_root: skips walk when VBW_CONFIG_ROOT already set (cache hit)" {
  local root="$TEST_TEMP_DIR/cache-hit-workspace"
  local other="$TEST_TEMP_DIR/other-dir"
  setup_workspace "$root"
  mkdir -p "$other"

  local result
  result=$(
    cd "$other"
    # Pre-seed the cache with the workspace root
    export VBW_CONFIG_ROOT="$root"
    . "$LIB"
    find_vbw_root
    # Should use cached root, not walk up from $other (which has no config)
    echo "$VBW_CONFIG_ROOT"
  )
  cd "$PROJECT_ROOT"

  [ "$result" = "$root" ]
}

# --- Test 6: statusline reads config from subdirectory (end-to-end) ---

@test "statusline: reads model_profile from subdirectory CWD (not hardcoded default)" {
  local root="$TEST_TEMP_DIR/monorepo-statusline"
  mkdir -p "$root/.vbw-planning" "$root/apps/mobile"
  git -C "$root" init -q
  git -C "$root" commit --allow-empty -m "test(init): seed" -q
  # Config sets model_profile "balanced"; the hardcoded default is "quality"
  cat > "$root/.vbw-planning/config.json" <<'JSON'
{"effort": "balanced", "model_profile": "balanced"}
JSON

  cd "$root/apps/mobile"
  unset VBW_CONFIG_ROOT VBW_PLANNING_DIR 2>/dev/null || true
  local output
  output=$(echo '{}' | bash "$STATUSLINE" 2>&1)
  cd "$PROJECT_ROOT"

  # "bal" must appear in the model_profile field of the output
  # Check specifically for the profile label, not just any occurrence
  echo "$output" | grep -qi "bal"
  # The hardcoded default "quality" must NOT appear as the model profile
  # (use a pattern that matches the profile display, not any word)
  ! echo "$output" | grep -qi "^.*model.*qual\|qual.*model\|profile.*qual"
}
