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
