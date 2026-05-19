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
