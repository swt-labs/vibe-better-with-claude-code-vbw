#!/usr/bin/env bats
#
# Behavioral tests for verification-freshness.sh verification_is_stale().
# Builds REAL git repos (and a real submodule) so the dirty-tree logic is
# exercised end-to-end, not asserted by string-presence.
#
# Submodule-monorepo contract (the QA-loop fix): the parent repo's gitlink pointers
# and untracked noise do NOT mark a verification stale; uncommitted work INSIDE a
# submodule does -- tracked changes plus non-ignored untracked files (a new source
# file is real work), while each submodule's .gitignore and .claude/settings* local
# config are excluded as noise. Single-repo behavior unchanged.

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
# Mirrors the pathspec in write-verification.sh / verification-freshness.sh.
write_verif() {
  local d="$1" f="$1/.vbw-planning/V.md" c
  c=$( cd "$d" && git log -1 --format='%H' -- . ':!.vbw-planning' ':!CLAUDE.md' ':!.claude/settings.local.json' ':!.claude/settings.json' )
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

# QA round 1, finding #1: a brand-new uncommitted (untracked) source file inside a
# submodule is real work the verification never covered -> must mark stale.
@test "submodule monorepo: untracked NEW file inside submodule marks stale" {
  mk_super "$TEST_TEMP_DIR/s"
  v=$(write_verif "$TEST_TEMP_DIR/s")
  echo 'package x' > "$TEST_TEMP_DIR/s/sub/newcode.go"   # untracked, not ignored
  run verdict "$TEST_TEMP_DIR/s" "$v"
  [ "$output" = "STALE:working_tree_changed" ]
}

# The untracked check inside a submodule still honors that submodule's .gitignore
# (git status --exclude-standard), so gitignored build noise does NOT mark stale.
@test "submodule monorepo: gitignored untracked inside submodule does NOT mark stale" {
  mk_super "$TEST_TEMP_DIR/s"
  ( cd "$TEST_TEMP_DIR/s/sub" && echo '*.log' > .gitignore && _git add .gitignore && _git commit -qm ignore )
  v=$(write_verif "$TEST_TEMP_DIR/s")
  echo noise > "$TEST_TEMP_DIR/s/sub/build.log"   # untracked but gitignored in the submodule
  run verdict "$TEST_TEMP_DIR/s" "$v"
  [[ "$output" == fresh:* ]]
}

# Local-config churn (.claude/settings*.json) inside a submodule is session noise,
# excluded the same way as in the parent/single-repo branches.
@test "submodule monorepo: .claude/settings.local.json churn inside submodule does NOT mark stale" {
  mk_super "$TEST_TEMP_DIR/s"
  v=$(write_verif "$TEST_TEMP_DIR/s")
  mkdir -p "$TEST_TEMP_DIR/s/sub/.claude"
  echo '{"permissions":"changed"}' > "$TEST_TEMP_DIR/s/sub/.claude/settings.local.json"  # untracked session churn
  run verdict "$TEST_TEMP_DIR/s" "$v"
  [[ "$output" == fresh:* ]]
}

# QA round 1, finding #2: the monorepo branch is gated on real submodules
# (`git submodule status` non-empty), not merely on .gitmodules existing -- so an
# empty/stale .gitmodules keeps single-repo behavior (untracked top-level -> stale).
@test "single repo with empty .gitmodules keeps single-repo behavior (untracked marks stale)" {
  mk_single "$TEST_TEMP_DIR/r"
  ( cd "$TEST_TEMP_DIR/r" && : > .gitmodules && _git add .gitmodules && _git commit -qm "empty gitmodules" )
  v=$(write_verif "$TEST_TEMP_DIR/r")
  echo x > "$TEST_TEMP_DIR/r/new.txt"   # untracked top-level product file
  run verdict "$TEST_TEMP_DIR/r" "$v"
  [ "$output" = "STALE:working_tree_changed" ]
}

# QA round 2: a declared-but-uninitialized submodule (clone without
# --recurse-submodules) enters the monorepo path (git submodule status lists it),
# but `git submodule foreach` silently skips uninitialized submodules, so a clean
# clone reports fresh rather than spuriously failing closed to stale.
@test "submodule monorepo: uninitialized submodule does not spuriously mark stale" {
  mk_super "$TEST_TEMP_DIR/s"
  _git clone -q "$TEST_TEMP_DIR/s" "$TEST_TEMP_DIR/clone"   # no --recurse-submodules: 'sub' uninitialized
  ( cd "$TEST_TEMP_DIR/clone" && mkdir -p .vbw-planning )
  v=$(write_verif "$TEST_TEMP_DIR/clone")
  run verdict "$TEST_TEMP_DIR/clone" "$v"
  [[ "$output" == fresh:* ]]
}

@test "single repo: .claude/settings.local.json churn does NOT mark stale" {
  mk_single "$TEST_TEMP_DIR/r"
  ( cd "$TEST_TEMP_DIR/r" && mkdir -p .claude && echo '{}' > .claude/settings.local.json \
    && _git add .claude/settings.local.json && _git commit -qm settings )
  v=$(write_verif "$TEST_TEMP_DIR/r")
  echo '{"permissions":"changed"}' > "$TEST_TEMP_DIR/r/.claude/settings.local.json"  # session churn, uncommitted
  run verdict "$TEST_TEMP_DIR/r" "$v"
  [[ "$output" == fresh:* ]]
}

@test "single repo: a deliverable under .claude/ (commands) STILL marks stale" {
  mk_single "$TEST_TEMP_DIR/r"
  ( cd "$TEST_TEMP_DIR/r" && mkdir -p .claude/commands && echo 'cmd' > .claude/commands/foo.md \
    && _git add .claude/commands/foo.md && _git commit -qm cmd )
  v=$(write_verif "$TEST_TEMP_DIR/r")
  echo 'cmd changed' > "$TEST_TEMP_DIR/r/.claude/commands/foo.md"  # real deliverable change, uncommitted
  run verdict "$TEST_TEMP_DIR/r" "$v"
  [ "$output" = "STALE:working_tree_changed" ]
}
