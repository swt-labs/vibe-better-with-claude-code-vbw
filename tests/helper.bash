#!/usr/bin/env bash
# Shared, hermetic helper for VBW bats tests.
#
# Every test gets its own HOME, Claude config dir, plugin data dir and git
# identity, and never sees the host Claude Code session (the suite is often run
# from inside one). Lessons from v1 (ledger T1–T6): host session ids leak into
# fallbacks, checkout paths contain spaces, stdin may stay open, and SIGTERM
# may be ignored by the runner.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
PLUGIN_ROOT="${VBW_TEST_PLUGIN_ROOT:-$REPO_ROOT/plugin}"
VBW="$PLUGIN_ROOT/bin/vbw"
export REPO_ROOT PLUGIN_ROOT VBW

# Host Claude Code session identity must never reach a test.
unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA \
  CLAUDE_PROJECT_DIR CLAUDE_ENV_FILE CLAUDECODE CLAUDE_CODE_ENTRYPOINT 2>/dev/null || true

vbw_setup() {
  TEST_ROOT="$(mktemp -d)"
  export TEST_ROOT
  # Leave the repository first: a git command run from inside it, even one that
  # reads nothing of the project (git config --global), still finds and opens the
  # repository, and a proof then counts the test as reading the project through git.
  cd "$TEST_ROOT" || return 1
  export HOME="$TEST_ROOT/home"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CLAUDE_PLUGIN_DATA="$TEST_ROOT/plugin-data"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_ROOT/gitconfig"
  export LC_ALL=C
  mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR" "$CLAUDE_PLUGIN_DATA"
  git config --global user.email "test@example.com"
  git config --global user.name "VBW Test"
  git config --global init.defaultBranch main
  # No background git work. One macOS CI teardown failed with "Directory not empty" on
  # .git/objects; its cause is not proven, and a detached gc or maintenance after a commit
  # is the candidate this removes.
  git config --global gc.auto 0
  git config --global maintenance.auto false
  PROJECT="$TEST_ROOT/project with space"
  export PROJECT
  mkdir -p "$PROJECT"
  cd "$PROJECT" || return 1
}

vbw_teardown() {
  cd / || true
  [ -z "${TEST_ROOT:-}" ] || rm -rf "$TEST_ROOT"
}

# A git repository with one commit, as most kernel tests need.
vbw_git_project() {
  git init -q
  printf 'seed\n' > README.md
  git add README.md
  git commit -q -m "chore(test): seed"
}

# vbw_submodule PATH: a submodule at PATH of the repository in the current folder
# (its own repository, on branch main, holding a.js "a"), added to that index, not
# committed. Its .git is a file, as git makes it.
vbw_submodule() {
  local src="$TEST_ROOT/subsrc-${1//\//-}"
  git init -q "$src"
  printf 'a\n' > "$src/a.js"
  git -C "$src" add a.js
  git -C "$src" commit -q -m "chore: seed"
  git -c protocol.file.allow=always submodule add -q "file://$src" "$1"
}

# Run the kernel with stdin closed, so nothing can block on input.
vbw_run() {
  run "$VBW" "$@" < /dev/null
}

# vbw_kernel SNIPPET: run SNIPPET with the kernel libraries loaded for this project.
vbw_kernel() {
  bash -c 'VBW_LIB="$1/lib"; for l in core record consent contract; do . "$VBW_LIB/$l.sh"; done
    vbw_project; eval "$2"' _ "$PLUGIN_ROOT" "$1"
}

# Consent to the project's current contract directly, as /vbw:approve would but
# without its completeness checks: for tests that need an arbitrary approved record.
vbw_consent_contract() {
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel 'consent_grant contract "$(contract_hash "$(cat "$VBW_RECORD")")" "{}"'
}

vbw_contract_hash() {
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel 'contract_hash "$(cat "$VBW_RECORD")"'
}

# vbw_hook EVENT [TOOL]: run the hooks.json command for EVENT (the entry whose
# matcher matches TOOL) the way Claude Code does: through sh -c, hook input on
# stdin, with CLAUDE_PLUGIN_ROOT and CLAUDE_PROJECT_DIR (HOOK_PROJECT_DIR, default
# $PROJECT) set. Tests exercise hooks.json itself.
vbw_hook() {
  local cmd
  cmd=$(jq -r --arg e "$1" --arg t "${2:-}" '[.hooks[$e][] | select($t == "" or ((.matcher // "") as $m | $t | test("^(" + $m + ")$")))][0].hooks[0].command' "$PLUGIN_ROOT/hooks/hooks.json")
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="${HOOK_PROJECT_DIR:-$PROJECT}" sh -c "$cmd"
}

vbw_code_tree() {
  vbw_kernel 'vbw_code_tree'
}

# vbw_clone_cp DIR: put in DIR a cp that copies the way a copy-on-write clone does
# (btrfs, XFS with reflink): the data is copied, but no source's access time moves, so
# the copy is no read. Each source file's access time is kept in a reference file
# (touch -r only reads the file's times) and put back after the real cp.
vbw_clone_cp() {
  local real
  real=$(command -v cp)
  mkdir -p "$1"
  printf '#!/bin/sh\nn=$#; i=0\nfor a in "$@"; do i=$((i + 1)); [ "$i" -lt "$n" ] || break; case "$a" in -*) continue ;; esac; [ ! -f "$a" ] || touch -a -r "$a" "%s/.at.$$.$i"; done\n%s "$@"; rc=$?\ni=0\nfor a in "$@"; do i=$((i + 1)); [ ! -f "%s/.at.$$.$i" ] || { touch -a -r "%s/.at.$$.$i" "$a"; rm -f "%s/.at.$$.$i"; }; done\nexit "$rc"\n' "$1" "$real" "$1" "$1" "$1" > "$1/cp"
  chmod +x "$1/cp"
}
