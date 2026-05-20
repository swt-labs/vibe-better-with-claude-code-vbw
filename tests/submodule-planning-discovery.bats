#!/usr/bin/env bats
# Phase 11 — Submodule-aware planning discovery scenarios.
#
# Scenarios derived from .vbw-planning/phases/11-submodule-aware-planning-discovery/
#   - 11-RESEARCH.md Section 6
#   - 11-CONTEXT.md "Decisions Made" / "Backward-compat fallback policy"
#
# T1: cwd at planning root — no banner.
# T2: cwd in non-submodule subdirectory — auto-resolve banner fires.
# T3: cwd inside a real git submodule — walk-up crosses .git-file boundary.
# T4: cwd in a sibling git worktree — resolves via git-common-dir pointer file.
# T5: cwd with no ancestor planning root — cwd-relative fallback + deprecation banner.

load test_helper

BRIDGE="$SCRIPTS_DIR/resolve-planning-root.sh"

setup() {
  setup_temp_dir
  export ORIG_UID=$(id -u)
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@test.local"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@test.local"
  export VBW_SKIP_KEYCHAIN=1
  export VBW_SKIP_AUTH_CLI=1
  export VBW_SKIP_UPDATE_CHECK=1
  cleanup_vbw_caches_under_temp_dir "$ORIG_UID"
  unset VBW_CONFIG_ROOT VBW_PLANNING_DIR VBW_PLANNING_ROOT 2>/dev/null || true
  unset _VBW_BANNER_EMITTED _VBW_FALLBACK_BANNER_EMITTED 2>/dev/null || true
}

teardown() {
  cleanup_vbw_caches_under_temp_dir "$ORIG_UID"
  unset VBW_SKIP_KEYCHAIN VBW_SKIP_AUTH_CLI VBW_SKIP_UPDATE_CHECK
  teardown_temp_dir
}

# Initialize a workspace with .vbw-planning/config.json and a seed commit.
seed_workspace() {
  local root="$1"
  mkdir -p "$root/.vbw-planning"
  git -C "$root" init -q
  cat > "$root/.vbw-planning/config.json" <<'JSON'
{"effort": "balanced", "model_profile": "balanced"}
JSON
  git -C "$root" add -A
  git -C "$root" commit -q -m "test(init): seed workspace"
}

# Canonicalize a path so /tmp -> /private/tmp comparisons hold on macOS.
canon() {
  cd "$1" && pwd -P
}

# --- T1 -------------------------------------------------------------------

@test "resolve-planning-root.sh: cwd at planning root (regression guard, no banner)" {
  local root="$TEST_TEMP_DIR/t1-workspace"
  seed_workspace "$root"
  local root_real; root_real=$(canon "$root")

  local stdout_file="$TEST_TEMP_DIR/t1.out"
  local stderr_file="$TEST_TEMP_DIR/t1.err"
  (
    cd "$root"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR VBW_PLANNING_ROOT 2>/dev/null || true
    bash "$BRIDGE" > "$stdout_file" 2> "$stderr_file"
  )

  [ "$(cat "$stdout_file")" = "$root_real/.vbw-planning" ]
  # No banner: cwd IS the root.
  [ ! -s "$stderr_file" ]
}

# --- T2 -------------------------------------------------------------------

@test "resolve-planning-root.sh: cwd in non-submodule subdirectory walks up (auto-resolve banner)" {
  local root="$TEST_TEMP_DIR/t2-workspace"
  seed_workspace "$root"
  mkdir -p "$root/src/components"
  local root_real; root_real=$(canon "$root")

  local stdout_file="$TEST_TEMP_DIR/t2.out"
  local stderr_file="$TEST_TEMP_DIR/t2.err"
  (
    cd "$root/src/components"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR VBW_PLANNING_ROOT 2>/dev/null || true
    bash "$BRIDGE" > "$stdout_file" 2> "$stderr_file"
  )

  [ "$(cat "$stdout_file")" = "$root_real/.vbw-planning" ]
  grep -q 'VBW: planning found at' "$stderr_file"
}

# --- T3 -------------------------------------------------------------------

@test "resolve-planning-root.sh: cwd inside a real git submodule walks through .git file boundary" {
  local outer="$TEST_TEMP_DIR/t3-outer"
  local inner="$TEST_TEMP_DIR/t3-inner"
  seed_workspace "$outer"
  mkdir -p "$inner"
  git -C "$inner" init -q
  ( cd "$inner" && echo "hello" > README.md && git add README.md && git commit -q -m "seed" )

  # Add inner as a submodule of outer. Requires local-file protocol; skip if
  # the harness denies it.
  if ! git -C "$outer" -c protocol.file.allow=always submodule add --quiet "$inner" packages/submod 2>/dev/null; then
    skip "git submodule add (file://) not available in this harness"
  fi

  mkdir -p "$outer/packages/submod/src/nested"
  local outer_real; outer_real=$(canon "$outer")

  local stdout_file="$TEST_TEMP_DIR/t3.out"
  local stderr_file="$TEST_TEMP_DIR/t3.err"
  (
    cd "$outer/packages/submod/src/nested"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR VBW_PLANNING_ROOT 2>/dev/null || true
    bash "$BRIDGE" > "$stdout_file" 2> "$stderr_file"
  )

  [ "$(cat "$stdout_file")" = "$outer_real/.vbw-planning" ]
}

# --- T4 -------------------------------------------------------------------

@test "resolve-planning-root.sh: cwd in sibling git worktree uses pointer file" {
  local main_repo="$TEST_TEMP_DIR/t4-main"
  local worktree="$TEST_TEMP_DIR/t4-worktree"
  seed_workspace "$main_repo"
  local main_real; main_real=$(canon "$main_repo")

  # Create the worktree on a new branch.
  git -C "$main_repo" worktree add -q -b t4-branch "$worktree"

  # Pointer file in the shared git common dir of the main repo. Worktrees
  # share this directory, so the pointer is visible from the worktree too.
  local common_dir
  common_dir=$(git -C "$main_repo" rev-parse --git-common-dir)
  # rev-parse may return a relative path when run inside the repo; canonicalize.
  case "$common_dir" in
    /*) ;;
    *) common_dir="$main_repo/$common_dir" ;;
  esac
  mkdir -p "$common_dir/info"
  printf '%s\n' "$main_real" > "$common_dir/info/vbw-planning-root.txt"

  local stdout_file="$TEST_TEMP_DIR/t4.out"
  local stderr_file="$TEST_TEMP_DIR/t4.err"
  (
    cd "$worktree"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR VBW_PLANNING_ROOT 2>/dev/null || true
    bash "$BRIDGE" > "$stdout_file" 2> "$stderr_file"
  )

  [ "$(cat "$stdout_file")" = "$main_real/.vbw-planning" ]
}

# --- T5 -------------------------------------------------------------------

@test "resolve-planning-root.sh: cwd with no ancestor planning falls back to cwd and emits deprecation banner" {
  # Create a directory outside any VBW workspace. The test_helper temp dir
  # itself has $TEST_TEMP_DIR/.vbw-planning/ pre-created by setup_temp_dir,
  # which would resolve via walk-up; create a sibling temp dir outside of it.
  local orphan; orphan=$(mktemp -d)
  local orphan_real; orphan_real=$(canon "$orphan")

  local stdout_file="$TEST_TEMP_DIR/t5.out"
  local stderr_file="$TEST_TEMP_DIR/t5.err"
  (
    cd "$orphan"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR VBW_PLANNING_ROOT 2>/dev/null || true
    bash "$BRIDGE" > "$stdout_file" 2> "$stderr_file"
  )
  rm -rf "$orphan"

  [ "$(cat "$stdout_file")" = "$orphan_real/.vbw-planning" ]
  grep -q 'VBW: warning: no .vbw-planning/ ancestor found; using cwd-relative fallback' "$stderr_file"
}

# --- T6 (QA Round 1 contract) ---------------------------------------------

@test "resolve-planning-root.sh: VBW_PLANNING_ROOT env var honored prints .vbw-planning DIR (not workspace root)" {
  local root="$TEST_TEMP_DIR/t6-workspace"
  seed_workspace "$root"
  local root_real; root_real=$(canon "$root")

  local stdout_file="$TEST_TEMP_DIR/t6.out"
  local stderr_file="$TEST_TEMP_DIR/t6.err"
  (
    cd "$TEST_TEMP_DIR"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR 2>/dev/null || true
    VBW_PLANNING_ROOT="$root_real" bash "$BRIDGE" > "$stdout_file" 2> "$stderr_file"
  )

  # Contract: bridge prints the .vbw-planning DIR, matching the post-walk-up branch.
  # Consumers do "$PLANNING_ROOT/config.json" expecting this form.
  [ "$(cat "$stdout_file")" = "$root_real/.vbw-planning" ]
}

# --- T7 (QA Round 1 contract) ---------------------------------------------

@test "resolve-planning-root.sh: stale VBW_PLANNING_ROOT (non-existent dir) falls through to walk-up" {
  local root="$TEST_TEMP_DIR/t7-workspace"
  seed_workspace "$root"
  local root_real; root_real=$(canon "$root")

  local stdout_file="$TEST_TEMP_DIR/t7.out"
  (
    cd "$root"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR 2>/dev/null || true
    VBW_PLANNING_ROOT="/this/path/does/not/exist" bash "$BRIDGE" > "$stdout_file" 2>/dev/null
  )

  # Stale env var rejected; cascade falls through to walk-up from CWD.
  [ "$(cat "$stdout_file")" = "$root_real/.vbw-planning" ]
}

# --- T8 (QA Round 2 contract) ---------------------------------------------

@test "vbw-config-root: pointer file with relative path is rejected with stderr warning" {
  local root="$TEST_TEMP_DIR/t8-workspace"
  seed_workspace "$root"
  local root_real; root_real=$(canon "$root")

  # Write a relative path to the pointer file
  mkdir -p "$root/.git/info"
  echo "relative/path" > "$root/.git/info/vbw-planning-root.txt"

  local stdout_file="$TEST_TEMP_DIR/t8.out"
  local stderr_file="$TEST_TEMP_DIR/t8.err"
  (
    cd "$root"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR VBW_PLANNING_ROOT 2>/dev/null || true
    unset _VBW_PTR_RELATIVE_WARNED 2>/dev/null || true
    bash "$BRIDGE" > "$stdout_file" 2> "$stderr_file"
  )

  # Falls through to walk-up (cwd IS the workspace), so resolves correctly.
  [ "$(cat "$stdout_file")" = "$root_real/.vbw-planning" ]
  # Stderr warning fired exactly because the pointer was rejected.
  grep -q 'pointer file.*non-absolute path' "$stderr_file"
}

# --- T9 (QA Round 2 contract) ---------------------------------------------

@test "vbw-config-root: VBW_PLANNING_ROOT honored but no .vbw-planning/ under it emits stderr diagnostic" {
  local dir="$TEST_TEMP_DIR/t9-workspace-no-planning"
  mkdir -p "$dir"
  local dir_real; dir_real=$(canon "$dir")

  local stdout_file="$TEST_TEMP_DIR/t9.out"
  local stderr_file="$TEST_TEMP_DIR/t9.err"
  (
    cd "$TEST_TEMP_DIR"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR 2>/dev/null || true
    unset _VBW_ENV_VAR_WARNED 2>/dev/null || true
    VBW_PLANNING_ROOT="$dir_real" bash "$BRIDGE" > "$stdout_file" 2> "$stderr_file"
  )

  # Env var still honored (bridge prints the would-be path).
  [ "$(cat "$stdout_file")" = "$dir_real/.vbw-planning" ]
  # But user is warned that .vbw-planning/ is missing under the override.
  grep -q 'VBW_PLANNING_ROOT=.*honored but no .vbw-planning' "$stderr_file"
}

# --- T10 (QA Round 2 contract: phase-detect conditional restore) -----------

@test "phase-detect.sh: real ancestor planning root preserves resolver result (no clobber)" {
  local root="$TEST_TEMP_DIR/t10-workspace"
  seed_workspace "$root"
  mkdir -p "$root/sub/nested"
  local root_real; root_real=$(canon "$root")

  local stdout_file="$TEST_TEMP_DIR/t10.out"
  (
    cd "$root/sub/nested"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR VBW_PLANNING_ROOT 2>/dev/null || true
    bash "$SCRIPTS_DIR/phase-detect.sh" > "$stdout_file" 2>/dev/null
  )

  # phases_dir should resolve to the ANCESTOR planning root, not CWD-relative.
  grep -qE "phases_dir=${root_real}/\.vbw-planning/phases" "$stdout_file"
}

@test "phase-detect.sh: orphan cwd does NOT leak plugin dev clone planning root" {
  local orphan="$TEST_TEMP_DIR/t11-orphan"
  mkdir -p "$orphan"

  local stdout_file="$TEST_TEMP_DIR/t11.out"
  (
    cd "$orphan"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR VBW_PLANNING_ROOT 2>/dev/null || true
    bash "$SCRIPTS_DIR/phase-detect.sh" > "$stdout_file" 2>/dev/null
  )
  rm -rf "$orphan"

  # Critical: phases_dir must NOT be the plugin dev clone's own .vbw-planning/.
  # (Regression guard for the SCRIPT_DIR-based "plugin-dev clone bleed" that
  # the conditional restore in phase-detect.sh now prevents.)
  ! grep -qE "phases_dir=${SCRIPTS_DIR%/scripts}/\.vbw-planning/phases" "$stdout_file"
  # Acceptable outcomes: planning_dir_exists=false, phases_dir=none, or
  # phases_dir=.vbw-planning/phases (CWD-relative literal). Anything absolute
  # pointing outside the orphan would be a leak.
  grep -qE '^(planning_dir_exists=false|phases_dir=(none|\.vbw-planning/phases))$' "$stdout_file"
}
