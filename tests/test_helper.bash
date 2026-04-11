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
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
}

# Clean up temp directory
teardown_temp_dir() {
  [ -n "${TEST_TEMP_DIR:-}" ] && rm -rf "$TEST_TEMP_DIR"
  unset VBW_AGENT_PID_LOCK_DIR
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
  "max_remediation_rounds": 5,
  "debug_logging": false,
  "statusline_hide_limits": false,
  "statusline_hide_limits_for_api_key": false,
  "statusline_hide_agent_in_tmux": false,
  "statusline_collapse_agent_in_tmux": false
}
CONF
}
