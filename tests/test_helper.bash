#!/bin/bash
# Shared test helper for VBW bats tests

# Project root (relative to tests/ dir)
export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
export CONFIG_DIR="${PROJECT_ROOT}/config"

# shellcheck source=../scripts/lib/vbw-cache-key.sh
. "${SCRIPTS_DIR}/lib/vbw-cache-key.sh"

# Create temp directory for test isolation
setup_temp_dir() {
  TEST_TEMP_DIR=$(mktemp -d)
  export TEST_TEMP_DIR
  export VBW_AGENT_PID_LOCK_DIR="$TEST_TEMP_DIR/.vbw-agent-pid-lock"
  # Isolate HOME and git config to prevent cross-worker contention under parallel execution
  export _ORIG_HOME="${HOME:-}"
  export _ORIG_GIT_CONFIG_NOSYSTEM="${GIT_CONFIG_NOSYSTEM:-}"
  export _ORIG_GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-}"
  if [ "${VBW_PLANNING_DIR+x}" = "x" ]; then
    export _ORIG_VBW_PLANNING_DIR_WAS_SET=1
    export _ORIG_VBW_PLANNING_DIR="${VBW_PLANNING_DIR}"
  else
    export _ORIG_VBW_PLANNING_DIR_WAS_SET=0
    unset _ORIG_VBW_PLANNING_DIR 2>/dev/null || true
  fi
  if [ "${CONFIG_PATH+x}" = "x" ]; then
    export _ORIG_CONFIG_PATH_WAS_SET=1
    export _ORIG_CONFIG_PATH="${CONFIG_PATH}"
  else
    export _ORIG_CONFIG_PATH_WAS_SET=0
    unset _ORIG_CONFIG_PATH 2>/dev/null || true
  fi
  if [ "${VBW_TARGET_ROOT+x}" = "x" ]; then
    export _ORIG_VBW_TARGET_ROOT_WAS_SET=1
    export _ORIG_VBW_TARGET_ROOT="${VBW_TARGET_ROOT}"
  else
    export _ORIG_VBW_TARGET_ROOT_WAS_SET=0
    unset _ORIG_VBW_TARGET_ROOT 2>/dev/null || true
  fi
  if [ "${VBW_TARGET_GIT_ROOT+x}" = "x" ]; then
    export _ORIG_VBW_TARGET_GIT_ROOT_WAS_SET=1
    export _ORIG_VBW_TARGET_GIT_ROOT="${VBW_TARGET_GIT_ROOT}"
  else
    export _ORIG_VBW_TARGET_GIT_ROOT_WAS_SET=0
    unset _ORIG_VBW_TARGET_GIT_ROOT 2>/dev/null || true
  fi
  if [ "${VBW_WORKSPACE_SUBPATH+x}" = "x" ]; then
    export _ORIG_VBW_WORKSPACE_SUBPATH_WAS_SET=1
    export _ORIG_VBW_WORKSPACE_SUBPATH="${VBW_WORKSPACE_SUBPATH}"
  else
    export _ORIG_VBW_WORKSPACE_SUBPATH_WAS_SET=0
    unset _ORIG_VBW_WORKSPACE_SUBPATH 2>/dev/null || true
  fi
  if [ "${CLAUDE_CONFIG_DIR+x}" = "x" ]; then
    export _ORIG_CLAUDE_CONFIG_DIR_WAS_SET=1
    export _ORIG_CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR}"
  else
    export _ORIG_CLAUDE_CONFIG_DIR_WAS_SET=0
    unset _ORIG_CLAUDE_CONFIG_DIR 2>/dev/null || true
  fi
  export HOME="$TEST_TEMP_DIR"
  # Scripts that source resolve-claude-dir.sh prefer CLAUDE_CONFIG_DIR over HOME,
  # so clear inherited host config unless a test opts back in explicitly.
  unset CLAUDE_CONFIG_DIR 2>/dev/null || true
  unset VBW_PLANNING_DIR CONFIG_PATH VBW_TARGET_ROOT VBW_TARGET_GIT_ROOT VBW_WORKSPACE_SUBPATH 2>/dev/null || true
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TEMP_DIR/.gitconfig"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
}

# Clean up temp directory
teardown_temp_dir() {
  [ -n "${TEST_TEMP_DIR:-}" ] && rm -rf "$TEST_TEMP_DIR"
  HOME="$_ORIG_HOME"
  if [ "${_ORIG_VBW_PLANNING_DIR_WAS_SET:-0}" = "1" ]; then
    export VBW_PLANNING_DIR="${_ORIG_VBW_PLANNING_DIR-}"
  else
    unset VBW_PLANNING_DIR 2>/dev/null || true
  fi
  if [ "${_ORIG_CONFIG_PATH_WAS_SET:-0}" = "1" ]; then
    export CONFIG_PATH="${_ORIG_CONFIG_PATH-}"
  else
    unset CONFIG_PATH 2>/dev/null || true
  fi
  if [ "${_ORIG_VBW_TARGET_ROOT_WAS_SET:-0}" = "1" ]; then
    export VBW_TARGET_ROOT="${_ORIG_VBW_TARGET_ROOT-}"
  else
    unset VBW_TARGET_ROOT 2>/dev/null || true
  fi
  if [ "${_ORIG_VBW_TARGET_GIT_ROOT_WAS_SET:-0}" = "1" ]; then
    export VBW_TARGET_GIT_ROOT="${_ORIG_VBW_TARGET_GIT_ROOT-}"
  else
    unset VBW_TARGET_GIT_ROOT 2>/dev/null || true
  fi
  if [ "${_ORIG_VBW_WORKSPACE_SUBPATH_WAS_SET:-0}" = "1" ]; then
    export VBW_WORKSPACE_SUBPATH="${_ORIG_VBW_WORKSPACE_SUBPATH-}"
  else
    unset VBW_WORKSPACE_SUBPATH 2>/dev/null || true
  fi
  if [ "${_ORIG_CLAUDE_CONFIG_DIR_WAS_SET:-0}" = "1" ]; then
    export CLAUDE_CONFIG_DIR="${_ORIG_CLAUDE_CONFIG_DIR-}"
  else
    unset CLAUDE_CONFIG_DIR 2>/dev/null || true
  fi
  if [ -n "$_ORIG_GIT_CONFIG_NOSYSTEM" ]; then
    GIT_CONFIG_NOSYSTEM="$_ORIG_GIT_CONFIG_NOSYSTEM"
  else
    unset GIT_CONFIG_NOSYSTEM
  fi
  if [ -n "$_ORIG_GIT_CONFIG_GLOBAL" ]; then
    GIT_CONFIG_GLOBAL="$_ORIG_GIT_CONFIG_GLOBAL"
  else
    unset GIT_CONFIG_GLOBAL
  fi
  unset VBW_AGENT_PID_LOCK_DIR _ORIG_HOME _ORIG_CLAUDE_CONFIG_DIR _ORIG_CLAUDE_CONFIG_DIR_WAS_SET _ORIG_GIT_CONFIG_NOSYSTEM _ORIG_GIT_CONFIG_GLOBAL \
    _ORIG_VBW_PLANNING_DIR _ORIG_VBW_PLANNING_DIR_WAS_SET _ORIG_CONFIG_PATH _ORIG_CONFIG_PATH_WAS_SET \
    _ORIG_VBW_TARGET_ROOT _ORIG_VBW_TARGET_ROOT_WAS_SET _ORIG_VBW_TARGET_GIT_ROOT _ORIG_VBW_TARGET_GIT_ROOT_WAS_SET \
    _ORIG_VBW_WORKSPACE_SUBPATH _ORIG_VBW_WORKSPACE_SUBPATH_WAS_SET
}

# Generate a PID that is guaranteed dead. Spawns a process intended to stay
# alive until killed, kills it, waits for it to exit, and returns its PID.
# Avoids hardcoded PIDs that may collide with live processes under parallel
# BATS execution.
get_dead_pid() {
  local p
  sleep 999 &
  p=$!
  [[ -n "$p" ]] || return 1
  kill "$p" 2>/dev/null || kill -9 "$p" 2>/dev/null || true
  wait "$p" 2>/dev/null || true
  if kill -0 "$p" 2>/dev/null; then
    return 1
  fi
  echo "$p"
}

# Assign a PID that is guaranteed alive for the duration of the current Bats
# test shell. Intentionally uses the top-level shell PID (`$$`) rather than a
# disposable background child, `$BASHPID` in command substitution, or an
# external `bash -c 'echo $$'` shell, all of which can produce short-lived PIDs
# that reintroduce liveness flakes.
assign_live_pid() {
  local var_name="${1:-}"
  [ -n "$var_name" ] || return 1
  kill -0 "$$" 2>/dev/null || return 1
  printf -v "$var_name" '%s' "$$"
}

# Run phase-detect.sh with retry on empty or incomplete output.
# Under heavy parallel BATS execution, transient late failures can produce
# partial output that already includes early routing keys like
# "next_phase_state=" but did not reach the true end of phase-detect.sh.
# Retries with exponential backoff (sleeps of 0.1, 0.2, 0.4, 0.8s ≈ 1.5s total)
# handle empty, trap-only, and partial-output cases.
# Output is considered complete only when it includes the explicit
# "phase_detect_complete=true" marker, which phase-detect.sh emits only on its
# normal full-output path.
# Returns 1 and sets status=1 if all 5 attempts produce empty or incomplete
# output, so callers' `[ "$status" -eq 0 ]` assertions fail with a clear
# diagnostic rather than a confusing content mismatch.
# Sets BATS globals: $output, $status (same as `run`).
run_phase_detect() {
  local _pd_script_dir="${1:-$SCRIPTS_DIR}"
  local _pd_sleeps=(0.1 0.2 0.4 0.8)
  local _pd_attempt=0
  while [ $_pd_attempt -lt 5 ]; do
    run bash "$_pd_script_dir/phase-detect.sh"
    if [ -n "$output" ] && [[ "$output" == *"phase_detect_complete=true"* ]]; then
      return 0
    fi
    if [ $_pd_attempt -lt 4 ]; then
      sleep "${_pd_sleeps[$_pd_attempt]}"
    fi
    _pd_attempt=$((_pd_attempt + 1))
  done
  output="run_phase_detect: all 5 retries returned empty or incomplete output"
  status=1
  echo "$output" >&2
  return 1
}

vbw_cache_prefix_for_root() {
  local root="$1" uid="${2:-$(id -u)}" version root_real
  version=$(tr -d '[:space:]' < "${PROJECT_ROOT}/VERSION" 2>/dev/null || echo 0)
  if root_real=$(cd "$root" 2>/dev/null && pwd -P 2>/dev/null); then
    :
  else
    root_real="$root"
  fi
  vbw_cache_prefix "$version" "$uid" "$root_real"
}

cleanup_vbw_cache_for_root() {
  local prefix
  prefix=$(vbw_cache_prefix_for_root "$1" "${2:-$(id -u)}")
  rm -f "${prefix}-fast" "${prefix}-slow" "${prefix}-cost" "${prefix}-ok" 2>/dev/null || true
}

cleanup_vbw_caches_under_temp_dir() {
  local uid="${1:-$(id -u)}" path root
  [ -n "${TEST_TEMP_DIR:-}" ] || return 0
  [ -d "$TEST_TEMP_DIR" ] || return 0

  while IFS= read -r path; do
    root=$(dirname "$path")
    cleanup_vbw_cache_for_root "$root" "$uid"
  done < <(find "$TEST_TEMP_DIR" \( -type d -o -type f \) \( -name .git -o -name .vbw-planning \) -print 2>/dev/null)
}

# Create minimal VBW workspace in a directory so find_vbw_root resolves there
create_test_vbw_workspace() {
  local dir="$1"
  mkdir -p "$dir/.vbw-planning"
  echo '{}' > "$dir/.vbw-planning/config.json"
}

# Create minimal config.json for tests
create_test_config() {
  local dir="${1:-.vbw-planning}"
  cat > "$TEST_TEMP_DIR/$dir/config.json" <<'CONF'
{
  "effort": "balanced",
  "autonomy": "standard",
  "auto_commit": true,
  "planning_tracking": "manual",
  "auto_push": "never",
  "verification_tier": "standard",
  "skill_suggestions": true,
  "auto_install_skills": false,
  "discovery_questions": true,
  "discussion_mode": "questions",
  "visual_format": "unicode",
  "max_tasks_per_plan": 5,
  "prefer_teams": "auto",
  "branch_per_milestone": false,
  "plain_summary": true,
  "qa_skip_agents": ["docs"],
  "active_profile": "default",
  "custom_profiles": {},
  "model_profile": "quality",
  "model_overrides": {},
  "agent_max_turns": {
    "scout": 15,
    "qa": 25,
    "architect": 30,
    "debugger": 80,
    "lead": 50,
    "dev": 75
  },
  "context_compiler": true,
  "worktree_isolation": "on",
  "token_budgets": true,
  "two_phase_completion": true,
  "metrics": true,
  "smart_routing": true,
  "validation_gates": true,
  "snapshot_resume": true,
  "lease_locks": false,
  "event_recovery": false,
  "monorepo_routing": true,
  "rolling_summary": false,
  "require_phase_discussion": false,
  "auto_uat": false,
  "max_uat_remediation_rounds": false,
  "debug_logging": false,
  "statusline_hide_limits": false,
  "statusline_hide_limits_for_api_key": false,
  "statusline_hide_agent_in_tmux": false,
  "statusline_collapse_agent_in_tmux": false,
  "caveman_style": "none",
  "caveman_commit": false,
  "caveman_review": false
}
CONF
}

# Shared git repo fixture for off-root / isolation tests
setup_unrelated_git_repo() {
  local repo_dir="$1"

  mkdir -p "$repo_dir"
  cd "$repo_dir" || return 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"
  echo "initial" > unrelated.txt
  git add unrelated.txt
  git commit -qm "init"
}
