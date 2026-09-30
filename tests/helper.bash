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
  PROJECT="$TEST_ROOT/project with space"
  export PROJECT
  mkdir -p "$PROJECT"
  cd "$PROJECT" || return 1
}

vbw_teardown() {
  cd / || true
  [ -n "${TEST_ROOT:-}" ] && rm -rf "$TEST_ROOT"
}

# A git repository with one commit, as most kernel tests need.
vbw_git_project() {
  git init -q
  printf 'seed\n' > README.md
  git add README.md
  git commit -q -m "chore(test): seed"
}

# Run the kernel with stdin closed, so nothing can block on input.
vbw_run() {
  run "$VBW" "$@" < /dev/null
}
