#!/bin/bash
# Shared test helper for VBW bats tests

# Project root (relative to tests/ dir)
export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
export CONFIG_DIR="${PROJECT_ROOT}/config"

# Create temp directory for test isolation
setup_temp_dir() {
  export TEST_TEMP_DIR=$(mktemp -d)
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
}

# Clean up temp directory
teardown_temp_dir() {
  [ -n "${TEST_TEMP_DIR:-}" ] && rm -rf "$TEST_TEMP_DIR"
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
  "visual_format": "unicode",
  "max_tasks_per_plan": 5,
  "prefer_teams": "always",
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
  "debug_logging": false
}
CONF
}
