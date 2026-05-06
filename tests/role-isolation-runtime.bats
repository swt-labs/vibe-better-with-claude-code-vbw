#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.contracts"
}

teardown() {
  teardown_temp_dir
}

create_plan_with_files() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-PLAN.md" << 'PLAN'
---
phase: 1
plan: 1
title: Test Plan
wave: 1
depends_on: []
files_modified:
  - src/allowed.js
tasks:
  - id: 1-1-T1
    title: Test task
    files: [src/allowed.js]
---
PLAN
}

create_contract() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/.contracts/01-01.json" << 'CONTRACT'
{"phase_id":"phase-1","plan_id":"01-01","phase":1,"plan":1,"objective":"Test","task_ids":["1-1-T1"],"task_count":1,"allowed_paths":["src/allowed.js"],"forbidden_paths":[],"depends_on":[],"must_haves":["Works"],"verification_checks":[],"max_token_budget":50000,"timeout_seconds":300,"contract_hash":"abc123"}
CONTRACT
}

# --- Role isolation runtime enforcement ---

@test "file-guard: blocks lead from writing outside .vbw-planning/ when role isolation enabled" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/code.js","content":"bad"}}'
  run bash -c "VBW_AGENT_ROLE=lead echo '$INPUT' | VBW_AGENT_ROLE=lead bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot write outside .vbw-planning/"* ]]
}

@test "file-guard: allows lead to write planning files" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  INPUT='{"tool_name":"Write","tool_input":{"file_path":".vbw-planning/test.md","content":"ok"}}'
  run bash -c "VBW_AGENT_ROLE=lead echo '$INPUT' | VBW_AGENT_ROLE=lead bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: blocks scout from any non-planning write" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/file.js","content":"bad"}}'
  run bash -c "VBW_AGENT_ROLE=scout echo '$INPUT' | VBW_AGENT_ROLE=scout bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"read-only"* ]]
}

@test "file-guard: active scout marker blocks non-planning writes before broad exemptions" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"

  for target in "src/file.js" "CLAUDE.md" "STATE.md" "foo-SUMMARY.md" "foo-VERIFICATION.md" ".execution-state.json"; do
    INPUT=$(jq -n --arg fp "$target" '{"tool_name":"Write","tool_input":{"file_path":$fp,"content":"bad"}}')
    run bash -c "unset VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"read-only outside .vbw-planning/"* ]]
  done
}

@test "file-guard: active scout marker allows planning artifact writes" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"

  INPUT='{"tool_name":"Write","tool_input":{"file_path":".vbw-planning/phases/01-test/01-RESEARCH.md","content":"ok"}}'
  run bash -c "unset VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: allows dev to write contract-scoped files" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  create_contract
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/allowed.js","content":"ok"}}'
  run bash -c "VBW_AGENT_ROLE=dev echo '$INPUT' | VBW_AGENT_ROLE=dev bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: role isolation always enforced (v2_role_isolation graduated)" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  # v2_role_isolation graduated — always enforced, config key absence doesn't matter
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/allowed.js","content":"ok"}}'
  run bash -c "VBW_AGENT_ROLE=scout echo '$INPUT' | VBW_AGENT_ROLE=scout bash '$SCRIPTS_DIR/file-guard.sh'"
  # Scout is read-only — always blocked (graduated)
  [ "$status" -eq 2 ]
  [[ "$output" == *"read-only"* ]]
}

@test "file-guard: fails open when VBW_AGENT_ROLE unset" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/allowed.js","content":"ok"}}'
  run bash -c "unset VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}
