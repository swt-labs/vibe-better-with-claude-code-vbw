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

# --- Test 6: find_vbw_root with start_dir resolves from script location (#266) ---

@test "find_vbw_root: resolves via start_dir when CWD is outside project" {
  local root="$TEST_TEMP_DIR/project-anchor"
  setup_workspace "$root"
  # Create a directory *inside* the project to simulate a script living in the repo
  mkdir -p "$root/scripts/lib"
  local root_real; root_real=$(cd "$root" && pwd -P 2>/dev/null || echo "$root")

  # CWD is outside the project (no .vbw-planning/ here)
  local outside="$TEST_TEMP_DIR/outside-dir"
  mkdir -p "$outside"

  local result
  result=$(
    cd "$outside"
    unset VBW_CONFIG_ROOT 2>/dev/null || true
    unset VBW_PLANNING_DIR 2>/dev/null || true
    . "$LIB"
    find_vbw_root "$root/scripts"
    echo "$VBW_CONFIG_ROOT"
  )
  cd "$PROJECT_ROOT"

  [ "$result" = "$root_real" ]
}

# --- Test 7: find_vbw_root with start_dir falls back to CWD when start_dir outside project ---

@test "find_vbw_root: falls back to CWD when start_dir is outside any project" {
  local root="$TEST_TEMP_DIR/cwd-fallback"
  setup_workspace "$root"
  local root_real; root_real=$(cd "$root" && pwd -P 2>/dev/null || echo "$root")

  # start_dir is outside any project
  local cache_dir="$TEST_TEMP_DIR/plugin-cache/scripts"
  mkdir -p "$cache_dir"

  local result
  result=$(
    cd "$root"
    unset VBW_CONFIG_ROOT 2>/dev/null || true
    unset VBW_PLANNING_DIR 2>/dev/null || true
    . "$LIB"
    find_vbw_root "$cache_dir"
    echo "$VBW_CONFIG_ROOT"
  )
  cd "$PROJECT_ROOT"

  # Should resolve via CWD since start_dir walk fails
  [ "$result" = "$root_real" ]
}

# --- Test 8: find_vbw_root skips redundant CWD walk when start_dir == CWD ---

@test "find_vbw_root: resolves correctly when start_dir equals CWD (no redundant walk)" {
  local root="$TEST_TEMP_DIR/same-dir"
  setup_workspace "$root"
  local root_real; root_real=$(cd "$root" && pwd -P 2>/dev/null || echo "$root")

  local result
  result=$(
    cd "$root"
    unset VBW_CONFIG_ROOT 2>/dev/null || true
    unset VBW_PLANNING_DIR 2>/dev/null || true
    . "$LIB"
    # start_dir == CWD — the optimization guard on line 56 should skip the
    # redundant CWD walk but still resolve via the start_dir walk
    find_vbw_root "$root"
    echo "$VBW_CONFIG_ROOT"
  )
  cd "$PROJECT_ROOT"

  [ "$result" = "$root_real" ]
}

# --- Test 9: find_vbw_root with nonexistent start_dir falls back to CWD (F-04) ---

@test "find_vbw_root: falls back to CWD when start_dir does not exist" {
  local root="$TEST_TEMP_DIR/nonexistent-start"
  setup_workspace "$root"
  local root_real; root_real=$(cd "$root" && pwd -P 2>/dev/null || echo "$root")

  local result
  result=$(
    cd "$root"
    unset VBW_CONFIG_ROOT 2>/dev/null || true
    unset VBW_PLANNING_DIR 2>/dev/null || true
    . "$LIB"
    # Pass a completely nonexistent path — cd fails, else branch fires
    find_vbw_root "/no/such/directory/anywhere"
    echo "$VBW_CONFIG_ROOT"
  )
  cd "$PROJECT_ROOT"

  # Should resolve via CWD fallback since start_dir doesn't exist
  [ "$result" = "$root_real" ]
}

# --- Test 10: find_vbw_root resolves nearest ancestor with nested .vbw-planning/ (F-12) ---

@test "find_vbw_root: resolves nearest ancestor when nested .vbw-planning/ exists" {
  local outer="$TEST_TEMP_DIR/nested-outer"
  local inner="$outer/packages/ui"
  # Set up outer workspace
  setup_workspace "$outer"
  # Set up inner (nested) workspace with its own .vbw-planning/
  mkdir -p "$inner/.vbw-planning"
  cat > "$inner/.vbw-planning/config.json" <<'JSON'
{"effort": "balanced", "model_profile": "balanced"}
JSON
  mkdir -p "$inner/src/components"

  local inner_real; inner_real=$(cd "$inner" && pwd -P 2>/dev/null || echo "$inner")

  local result
  result=$(
    cd "$inner/src/components"
    unset VBW_CONFIG_ROOT 2>/dev/null || true
    unset VBW_PLANNING_DIR 2>/dev/null || true
    . "$LIB"
    find_vbw_root
    echo "$VBW_CONFIG_ROOT"
  )
  cd "$PROJECT_ROOT"

  # Nearest ancestor (inner) should win, not outer
  [ "$result" = "$inner_real" ]
}

# --- Test 11: statusline reads config from subdirectory (end-to-end) ---
# Hermetic: copies the statusline script + deps into the test workspace so
# $_SL_SCRIPT_DIR resolves inside the workspace, preventing find_vbw_root
# from escaping to the developer's real .vbw-planning/ directory.

@test "statusline: reads model_profile from subdirectory CWD (not hardcoded default)" {
  local root="$TEST_TEMP_DIR/monorepo-statusline"
  mkdir -p "$root/.vbw-planning" "$root/apps/mobile"
  git -C "$root" init -q
  git -C "$root" commit --allow-empty -m "test(init): seed" -q
  # Config sets model_profile "balanced"; the hardcoded default is "quality"
  cat > "$root/.vbw-planning/config.json" <<'JSON'
{"effort": "balanced", "model_profile": "balanced"}
JSON

  # Copy statusline script and its dependencies into the test workspace
  # so $_SL_SCRIPT_DIR cannot resolve outside the workspace
  local sl_dir="$root/scripts"
  mkdir -p "$sl_dir/lib"
  cp "$STATUSLINE" "$sl_dir/vbw-statusline.sh"
  cp "$SCRIPTS_DIR/lib/vbw-config-root.sh" "$sl_dir/lib/"
  # Copy optional sourced helpers (statusline degrades gracefully if absent)
  for f in summary-utils.sh uat-utils.sh phase-state-utils.sh; do
    [ -f "$SCRIPTS_DIR/$f" ] && cp "$SCRIPTS_DIR/$f" "$sl_dir/"
  done
  # VERSION file lives one level up from scripts/
  [ -f "$PROJECT_ROOT/VERSION" ] && cp "$PROJECT_ROOT/VERSION" "$root/"

  cd "$root/apps/mobile"
  unset VBW_CONFIG_ROOT VBW_PLANNING_DIR 2>/dev/null || true
  local output
  output=$(echo '{}' | bash "$sl_dir/vbw-statusline.sh" 2>&1)
  cd "$PROJECT_ROOT"

  # "bal" must appear in the model_profile field of the output
  # Check specifically for the profile label, not just any occurrence
  echo "$output" | grep -qi "bal"
  # The hardcoded default "quality" must NOT appear as the model profile
  # (use a pattern that matches the profile display, not any word)
  ! echo "$output" | grep -qiE "model.*qual|qual.*model|profile.*qual"
}
