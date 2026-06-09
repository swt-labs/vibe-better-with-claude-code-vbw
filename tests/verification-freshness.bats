#!/usr/bin/env bats
#
# Behavioral tests for verification-freshness.sh verification_is_stale().
# Builds REAL git repos (and a real submodule) so the dirty-tree logic is
# exercised end-to-end, not asserted by string-presence.
#
# Submodule-monorepo contract (the QA-loop fix): parent gitlink pointers and
# untracked files do NOT mark a verification stale; only uncommitted tracked
# CONTENT (top-level or inside a submodule) does. Single-repo behavior unchanged.

load test_helper

setup() {
  setup_temp_dir
  FRESH="$SCRIPTS_DIR/verification-freshness.sh"
}

teardown() {
  teardown_temp_dir
}

_git() { git -c protocol.file.allow=always -c user.name=t -c user.email=t@t.io "$@"; }

# Single (non-submodule) repo at $1
mk_single() {
  local d="$1"; mkdir -p "$d"
  ( cd "$d" && _git init -q && echo a > a.txt && _git add a.txt && _git commit -qm init && mkdir -p .vbw-planning )
}

# Super repo with one real submodule at $1 (sub source lives under TEST_TEMP_DIR/sub-src)
mk_super() {
  local d="$1"
  mkdir -p "$TEST_TEMP_DIR/sub-src"
  ( cd "$TEST_TEMP_DIR/sub-src" && _git init -q && echo s > s.txt && _git add s.txt && _git commit -qm subinit )
  mkdir -p "$d"
  ( cd "$d" \
    && _git init -q \
    && echo p > p.txt && _git add p.txt && _git commit -qm superinit \
    && _git submodule add -q "$TEST_TEMP_DIR/sub-src" sub \
    && _git commit -qm "add sub" \
    && mkdir -p .vbw-planning )
}

# Write VERIFICATION.md whose verified_at_commit == the current product commit.
write_verif() {
  local d="$1" f="$1/.vbw-planning/V.md" c
  c=$( cd "$d" && git log -1 --format='%H' -- . ':!.vbw-planning' ':!CLAUDE.md' )
  printf -- '---\nverified_at_commit: %s\n---\nok\n' "$c" > "$f"
  echo "$f"
}

# Echo STALE:<reason> or fresh:<reason> for repo $1, verification file $2.
verdict() {
  ( cd "$1"; source "$FRESH"
    if verification_is_stale "$2"; then echo "STALE:$VERIFICATION_FRESHNESS_REASON"
    else echo "fresh:$VERIFICATION_FRESHNESS_REASON"; fi )
}

@test "single repo: untracked file marks stale (original behavior preserved)" {
  mk_single "$TEST_TEMP_DIR/r"
  v=$(write_verif "$TEST_TEMP_DIR/r")
  echo x > "$TEST_TEMP_DIR/r/new.txt"
  run verdict "$TEST_TEMP_DIR/r" "$v"
  [ "$output" = "STALE:working_tree_changed" ]
}

@test "submodule monorepo: clean tree is fresh" {
  mk_super "$TEST_TEMP_DIR/s"
  v=$(write_verif "$TEST_TEMP_DIR/s")
  run verdict "$TEST_TEMP_DIR/s" "$v"
  [[ "$output" == fresh:* ]]
}

@test "submodule monorepo: untracked parent file does NOT mark stale" {
  mk_super "$TEST_TEMP_DIR/s"
  v=$(write_verif "$TEST_TEMP_DIR/s")
  echo x > "$TEST_TEMP_DIR/s/.env.local"
  run verdict "$TEST_TEMP_DIR/s" "$v"
  [[ "$output" == fresh:* ]]
}

@test "submodule monorepo: submodule pointer drift does NOT mark stale" {
  mk_super "$TEST_TEMP_DIR/s"
  v=$(write_verif "$TEST_TEMP_DIR/s")
  # advance the submodule HEAD (committed inside sub) -> parent gitlink dirty (pointer only)
  ( cd "$TEST_TEMP_DIR/s/sub" && echo more >> s.txt && _git commit -qam more )
  run verdict "$TEST_TEMP_DIR/s" "$v"
  [[ "$output" == fresh:* ]]
}

@test "submodule monorepo: uncommitted CONTENT inside submodule marks stale" {
  mk_super "$TEST_TEMP_DIR/s"
  v=$(write_verif "$TEST_TEMP_DIR/s")
  echo dirty >> "$TEST_TEMP_DIR/s/sub/s.txt"   # tracked, uncommitted
  run verdict "$TEST_TEMP_DIR/s" "$v"
  [ "$output" = "STALE:working_tree_changed" ]
}
