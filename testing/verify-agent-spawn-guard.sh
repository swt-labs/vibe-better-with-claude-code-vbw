#!/usr/bin/env bash
set -euo pipefail

# verify-agent-spawn-guard.sh — Behavior checks for execute-time spawn semantics

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT/scripts/agent-spawn-guard.sh"

PASS=0
FAIL=0
TMPDIR_BASE=""

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

setup_project() {
  TMPDIR_BASE=$(mktemp -d)
  PROJECT="$TMPDIR_BASE/project"
  mkdir -p "$PROJECT/.vbw-planning/phases/01-test"
  mkdir -p "$PROJECT/src/nested"
  echo '{"effort":"balanced","prefer_teams":"never"}' > "$PROJECT/.vbw-planning/config.json"
}

cleanup() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE" 2>/dev/null || true
}
trap cleanup EXIT

write_marker() {
  local mode="$1"
  local delegation_mode="$2"
  local team_name="${3:-}"
  local correlation_id="${4:-corr-123}"

  jq -n \
    --arg mode "$mode" \
    --arg delegation_mode "$delegation_mode" \
    --arg team_name "$team_name" \
    --arg correlation_id "$correlation_id" \
    '{
      mode: $mode,
      active: true,
      effort: "balanced",
      delegation_mode: $delegation_mode,
      team_name: $team_name,
      started_at: "2026-04-07T00:00:00Z",
      session_id: "session-test",
      correlation_id: $correlation_id
    }' > "$PROJECT/.vbw-planning/.delegated-workflow.json"
}

write_execution_state() {
  local correlation_id="${1:-corr-123}"
  local status="${2:-running}"

  jq -n \
    --arg correlation_id "$correlation_id" \
    --arg status "$status" \
    '{
      phase: 1,
      phase_name: "test",
      status: $status,
      effort: "balanced",
      correlation_id: $correlation_id,
      plans: []
    }' > "$PROJECT/.vbw-planning/.execution-state.json"
}

run_guard() {
  local project_dir="$1"
  local team_name="$2"
  local run_in_background="$3"
  local agent_name="${4-dev-01}"
  local working_dir="${5:-$project_dir}"
  local tool_name="${6:-Agent}"
  local active_count="${7:-}"
  local isolation="${8:-}"
  local spawn_cwd="${9:-}"
  local spawn_cwd_field="${10:-cwd}"

  local input
  input=$(jq -n \
    --arg tool_name "$tool_name" \
    --arg team_name "$team_name" \
    --arg agent_name "$agent_name" \
    --argjson run_in_background "$run_in_background" \
    --arg isolation "$isolation" \
    --arg spawn_cwd "$spawn_cwd" \
    --arg spawn_cwd_field "$spawn_cwd_field" \
    '{
      tool_name: $tool_name,
      tool_input: {
        team_name: $team_name,
        name: $agent_name,
        run_in_background: $run_in_background
      }
    }
    | if $isolation != "" then .tool_input.isolation = $isolation else . end
    | if $spawn_cwd != "" then .tool_input[$spawn_cwd_field] = $spawn_cwd else . end')

  if [ -n "$active_count" ]; then
    printf '%s\n' "$active_count" > "$project_dir/.vbw-planning/.active-agent-count"
  else
    rm -f "$project_dir/.vbw-planning/.active-agent-count" 2>/dev/null || true
  fi

  (cd "$working_dir" && VBW_PLANNING_DIR="$project_dir/.vbw-planning" bash "$GUARD" <<< "$input") 2>&1
  return ${PIPESTATUS[0]}
}

run_guard_without_exported_root() {
  local project_dir="$1"
  local team_name="$2"
  local run_in_background="$3"
  local agent_name="${4-dev-01}"
  local working_dir="${5:-$project_dir}"
  local tool_name="${6:-Agent}"
  local active_count="${7:-}"
  local isolation="${8:-}"
  local spawn_cwd="${9:-}"
  local spawn_cwd_field="${10:-cwd}"

  local input
  input=$(jq -n \
    --arg tool_name "$tool_name" \
    --arg team_name "$team_name" \
    --arg agent_name "$agent_name" \
    --argjson run_in_background "$run_in_background" \
    --arg isolation "$isolation" \
    --arg spawn_cwd "$spawn_cwd" \
    --arg spawn_cwd_field "$spawn_cwd_field" \
    '{
      tool_name: $tool_name,
      tool_input: {
        team_name: $team_name,
        name: $agent_name,
        run_in_background: $run_in_background
      }
    }
    | if $isolation != "" then .tool_input.isolation = $isolation else . end
    | if $spawn_cwd != "" then .tool_input[$spawn_cwd_field] = $spawn_cwd else . end')

  if [ -n "$active_count" ]; then
    printf '%s\n' "$active_count" > "$project_dir/.vbw-planning/.active-agent-count"
  else
    rm -f "$project_dir/.vbw-planning/.active-agent-count" 2>/dev/null || true
  fi

  (cd "$working_dir" && unset VBW_CONFIG_ROOT VBW_PLANNING_DIR; bash "$GUARD" <<< "$input") 2>&1
  return ${PIPESTATUS[0]}
}

setup_sidechain_project() {
  setup_project
  SIDECHAIN="$PROJECT/.claude/worktrees/agent-test"
  mkdir -p "$SIDECHAIN/.vbw-planning/phases/01-copy" "$SIDECHAIN/src"
  echo '{"effort":"turbo","prefer_teams":"always"}' > "$SIDECHAIN/.vbw-planning/config.json"
}

write_sidechain_copied_state() {
  jq -n '{phase:1,phase_name:"copy",status:"running",effort:"balanced",correlation_id:"sidechain-corr",plans:[]}' \
    > "$SIDECHAIN/.vbw-planning/.execution-state.json"
  jq -n '{mode:"execute",active:true,effort:"balanced",delegation_mode:"subagent",team_name:"",started_at:"2026-04-07T00:00:00Z",session_id:"session-test",correlation_id:"sidechain-corr"}' \
    > "$SIDECHAIN/.vbw-planning/.delegated-workflow.json"
}

echo "=== Agent Spawn Guard Tests ==="

test_non_vbw_repo_allows() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local input
  input=$(jq -n '{tool_name:"Agent",tool_input:{run_in_background:true,name:"dev-01",isolation:"worktree"}}')

  if (cd "$tmpdir" && bash "$GUARD" <<< "$input") >/dev/null 2>&1; then
    pass "Non-VBW repo: allow"
  else
    fail "Non-VBW repo: unexpected block"
  fi

  rm -rf "$tmpdir"
}
test_non_vbw_repo_allows

test_no_marker_allows() {
  setup_project
  if run_guard "$PROJECT" "" true >/dev/null 2>&1; then
    pass "No execute marker: allow"
  else
    fail "No execute marker: unexpected block"
  fi
  cleanup
}
test_no_marker_allows

test_no_marker_blocks_agent_worktree_isolation_when_config_key_missing() {
  setup_project

  local output rc
  output=$(run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "Agent" "" "worktree" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'Claude-side worktree isolation'; then
    pass "No marker with missing worktree_isolation key: Agent isolation blocked"
  else
    fail "No-marker Agent isolation should block when worktree_isolation missing (rc=$rc, output=$output)"
  fi
  cleanup
}
test_no_marker_blocks_agent_worktree_isolation_when_config_key_missing

test_no_marker_blocks_taskcreate_worktree_isolation_when_config_off() {
  setup_project
  jq '.worktree_isolation = "off"' "$PROJECT/.vbw-planning/config.json" > "$PROJECT/.vbw-planning/config.json.tmp"
  mv "$PROJECT/.vbw-planning/config.json.tmp" "$PROJECT/.vbw-planning/config.json"

  local output rc
  output=$(run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "TaskCreate" "" "worktree" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'Claude-side worktree isolation'; then
    pass "No marker with config off: TaskCreate isolation blocked"
  else
    fail "No-marker TaskCreate isolation should block when worktree_isolation off (rc=$rc, output=$output)"
  fi
  cleanup
}
test_no_marker_blocks_taskcreate_worktree_isolation_when_config_off

test_no_marker_blocks_agent_worktree_isolation_when_config_on() {
  setup_project
  jq '.worktree_isolation = "on"' "$PROJECT/.vbw-planning/config.json" > "$PROJECT/.vbw-planning/config.json.tmp"
  mv "$PROJECT/.vbw-planning/config.json.tmp" "$PROJECT/.vbw-planning/config.json"

  local output rc
  output=$(run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "Agent" "" "worktree" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'Claude-side worktree isolation'; then
    pass "No marker with config on: Agent isolation blocked"
  else
    fail "No-marker Agent isolation should block when worktree_isolation on (rc=$rc, output=$output)"
  fi
  cleanup
}
test_no_marker_blocks_agent_worktree_isolation_when_config_on

test_no_marker_blocks_taskcreate_worktree_isolation_when_config_on() {
  setup_project
  jq '.worktree_isolation = "on"' "$PROJECT/.vbw-planning/config.json" > "$PROJECT/.vbw-planning/config.json.tmp"
  mv "$PROJECT/.vbw-planning/config.json.tmp" "$PROJECT/.vbw-planning/config.json"

  local output rc
  output=$(run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "TaskCreate" "" "worktree" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'Claude-side worktree isolation'; then
    pass "No marker with config on: TaskCreate isolation blocked"
  else
    fail "No-marker TaskCreate isolation should block when worktree_isolation on (rc=$rc, output=$output)"
  fi
  cleanup
}
test_no_marker_blocks_taskcreate_worktree_isolation_when_config_on

test_no_marker_blocks_sidechain_cwd_when_config_off() {
  setup_project

  local field output rc
  for field in cwd working_dir workingDirectory workdir; do
    output=$(run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "Agent" "" "" "$PROJECT/.claude/worktrees/agent-123" "$field" 2>&1) && rc=$? || rc=$?
    if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'Claude sidechain working directory'; then
      pass "No marker with config off: sidechain ${field} blocked"
    else
      fail "No-marker sidechain ${field} should block when worktree_isolation off (rc=$rc, output=$output)"
    fi
  done
  cleanup
}
test_no_marker_blocks_sidechain_cwd_when_config_off

test_no_marker_allows_non_agent_worktree_cwd_when_config_off() {
  setup_project

  if run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "Agent" "" "" "$PROJECT/.claude/worktrees/manual-workdir" "cwd" >/dev/null 2>&1; then
    pass "No marker with config off: non-agent worktree cwd allowed"
  else
    fail "No-marker non-agent .claude/worktrees cwd should be allowed when worktree_isolation off"
  fi
  cleanup
}
test_no_marker_allows_non_agent_worktree_cwd_when_config_off

test_no_marker_allows_regular_project_cwd() {
  setup_project
  mkdir -p "$PROJECT/src/nested"

  if run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "Agent" "" "" "$PROJECT/src/nested" "cwd" >/dev/null 2>&1; then
    pass "No marker: regular project cwd allowed"
  else
    fail "No-marker regular project cwd should be allowed"
  fi
  cleanup
}
test_no_marker_allows_regular_project_cwd

test_no_marker_blocks_sidechain_cwd_when_config_on() {
  setup_project
  jq '.worktree_isolation = "on"' "$PROJECT/.vbw-planning/config.json" > "$PROJECT/.vbw-planning/config.json.tmp"
  mv "$PROJECT/.vbw-planning/config.json.tmp" "$PROJECT/.vbw-planning/config.json"

  local field output rc
  for field in cwd working_dir workingDirectory workdir; do
    output=$(run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "Agent" "" "" "$PROJECT/.claude/worktrees/agent-123" "$field" 2>&1) && rc=$? || rc=$?
    if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'Claude sidechain working directory'; then
      pass "No marker with config on: sidechain ${field} blocked"
    else
      fail "No-marker sidechain ${field} should block even when worktree_isolation on (rc=$rc, output=$output)"
    fi
  done
  cleanup
}
test_no_marker_blocks_sidechain_cwd_when_config_on

test_no_marker_blocks_vbw_worktree_cwd_aliases() {
  setup_project
  mkdir -p "$PROJECT/.vbw-worktrees/dev-01"

  local config_value tool field output rc
  for config_value in off on; do
    jq --arg value "$config_value" '.worktree_isolation = $value' "$PROJECT/.vbw-planning/config.json" > "$PROJECT/.vbw-planning/config.json.tmp"
    mv "$PROJECT/.vbw-planning/config.json.tmp" "$PROJECT/.vbw-planning/config.json"
    for tool in Agent TaskCreate; do
      for field in cwd working_dir workingDirectory workdir; do
        output=$(run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "$tool" "" "" "$PROJECT/.vbw-worktrees/dev-01" "$field" 2>&1) && rc=$? || rc=$?
        if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'prompt/state metadata, not a spawn cwd'; then
          pass "No marker with config ${config_value}: ${tool} .vbw-worktrees ${field} blocked"
        else
          fail "No-marker ${tool} .vbw-worktrees ${field} should block when worktree_isolation ${config_value} (rc=$rc, output=$output)"
        fi
      done
    done
  done
  cleanup
}
test_no_marker_blocks_vbw_worktree_cwd_aliases

test_no_marker_blocks_vbw_worktree_cwd_before_isolation() {
  setup_project
  jq '.worktree_isolation = "on"' "$PROJECT/.vbw-planning/config.json" > "$PROJECT/.vbw-planning/config.json.tmp"
  mv "$PROJECT/.vbw-planning/config.json.tmp" "$PROJECT/.vbw-planning/config.json"
  mkdir -p "$PROJECT/.vbw-worktrees/dev-01"

  local output rc
  output=$(run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "Agent" "" "worktree" "$PROJECT/.vbw-worktrees/dev-01" "cwd" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'prompt/state metadata, not a spawn cwd'; then
    pass "No marker with config on: .vbw-worktrees cwd blocked before isolation"
  else
    fail "No-marker .vbw-worktrees cwd should block before isolation when both are present (rc=$rc, output=$output)"
  fi
  cleanup
}
test_no_marker_blocks_vbw_worktree_cwd_before_isolation

test_active_execute_without_live_marker_blocks() {
  setup_project
  write_execution_state "corr-123"

  local output rc
  output=$(run_guard "$PROJECT" "" true "dev-01" "$PROJECT" "Agent" "" "worktree" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'missing live runtime delegation state'; then
    pass "Active execute without live marker: blocked"
  else
    fail "Active execute without live marker should block (rc=$rc, output=$output)"
  fi
  cleanup
}
test_active_execute_without_live_marker_blocks

test_active_execute_without_live_marker_blocks_from_nested_cwd() {
  setup_project
  write_execution_state "corr-123"

  local output rc
  output=$(run_guard "$PROJECT" "" true "dev-01" "$PROJECT/src/nested" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'missing live runtime delegation state'; then
    pass "Active execute without live marker blocks from nested working directory"
  else
    fail "Nested-CWD active execute should block missing live marker (rc=$rc, output=$output)"
  fi
  cleanup
}
test_active_execute_without_live_marker_blocks_from_nested_cwd

test_team_mode_requires_team_name() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute team "vbw-phase-01" "corr-123"

  local output rc
  output=$(run_guard "$PROJECT" "" true 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'requires team-scoped agent spawns'; then
    pass "Execute team mode blocks spawn without team_name"
  else
    fail "Execute team mode should block missing team_name (rc=$rc, output=$output)"
  fi
  cleanup
}
test_team_mode_requires_team_name

test_team_mode_allows_team_scoped_spawn() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute team "vbw-phase-01" "corr-123"

  if run_guard "$PROJECT" "vbw-phase-01" true >/dev/null 2>&1; then
    pass "Execute team mode allows team-scoped spawn"
  else
    fail "Execute team mode unexpectedly blocked valid team-scoped spawn"
  fi
  cleanup
}
test_team_mode_allows_team_scoped_spawn

test_team_mode_requires_agent_name() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute team "vbw-phase-01" "corr-123"

  local output rc
  output=$(run_guard "$PROJECT" "vbw-phase-01" true "" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'requires teammate name metadata'; then
    pass "Execute team mode blocks spawn without teammate name"
  else
    fail "Execute team mode should block missing teammate name (rc=$rc, output=$output)"
  fi
  cleanup
}
test_team_mode_requires_agent_name

test_team_mode_requires_matching_team_name() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute team "vbw-phase-01" "corr-123"

  local output rc
  output=$(run_guard "$PROJECT" "vbw-phase-99" true 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q "requires team_name 'vbw-phase-01'"; then
    pass "Execute team mode blocks mismatched team_name"
  else
    fail "Execute team mode should block mismatched team_name (rc=$rc, output=$output)"
  fi
  cleanup
}
test_team_mode_requires_matching_team_name

test_non_team_mode_blocks_background_spawn() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute subagent "" "corr-123"

  local output rc
  output=$(run_guard "$PROJECT" "" true 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'cannot simulate team mode with background Agent spawns'; then
    pass "Execute subagent mode blocks faux-team background spawn"
  else
    fail "Execute subagent mode should block background spawn (rc=$rc, output=$output)"
  fi
  cleanup
}
test_non_team_mode_blocks_background_spawn

test_direct_mode_blocks_background_spawn() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute direct "" "corr-123"

  local output rc
  output=$(run_guard "$PROJECT" "" true 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'cannot simulate team mode with background Agent spawns'; then
    pass "Execute direct mode blocks faux-team background spawn"
  else
    fail "Execute direct mode should block background spawn (rc=$rc, output=$output)"
  fi
  cleanup
}
test_direct_mode_blocks_background_spawn

test_non_team_mode_allows_foreground_spawn() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute subagent "" "corr-123"

  if run_guard "$PROJECT" "" false >/dev/null 2>&1; then
    pass "Execute subagent mode allows foreground spawn"
  else
    fail "Execute subagent mode unexpectedly blocked foreground spawn"
  fi
  cleanup
}
test_non_team_mode_allows_foreground_spawn

test_non_team_mode_allows_first_taskcreate_when_no_agent_active() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute subagent "" "corr-123"

  if run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "TaskCreate" "0" >/dev/null 2>&1; then
    pass "Execute subagent mode allows first TaskCreate when no agent is active"
  else
    fail "Execute subagent mode unexpectedly blocked first TaskCreate"
  fi
  cleanup
}
test_non_team_mode_allows_first_taskcreate_when_no_agent_active

test_non_team_mode_blocks_overlapping_taskcreate() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute subagent "" "corr-123"

  local output rc
  output=$(run_guard "$PROJECT" "" false "dev-02" "$PROJECT" "TaskCreate" "1" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'must serialize non-team TaskCreate spawns'; then
    pass "Execute subagent mode blocks overlapping TaskCreate spawns"
  else
    fail "Execute subagent mode should block overlapping TaskCreate (rc=$rc, output=$output)"
  fi
  cleanup
}
test_non_team_mode_blocks_overlapping_taskcreate

test_direct_mode_blocks_overlapping_taskcreate() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute direct "" "corr-123"

  local output rc
  output=$(run_guard "$PROJECT" "" false "dev-03" "$PROJECT" "TaskCreate" "1" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'must serialize non-team TaskCreate spawns'; then
    pass "Execute direct mode blocks overlapping TaskCreate spawns"
  else
    fail "Execute direct mode should block overlapping TaskCreate (rc=$rc, output=$output)"
  fi
  cleanup
}
test_direct_mode_blocks_overlapping_taskcreate

test_team_mode_taskcreate_still_requires_team_metadata() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute team "vbw-phase-01" "corr-123"

  local output rc
  output=$(run_guard "$PROJECT" "" false "dev-01" "$PROJECT" "TaskCreate" "0" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'requires team-scoped agent spawns'; then
    pass "Team mode TaskCreate still requires team metadata"
  else
    fail "Team mode TaskCreate should still require team metadata (rc=$rc, output=$output)"
  fi
  cleanup
}
test_team_mode_taskcreate_still_requires_team_metadata

test_non_team_mode_blocks_team_name() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute direct "" "corr-123"

  local output rc
  output=$(run_guard "$PROJECT" "vbw-phase-01" false 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'cannot attach team_name'; then
    pass "Execute non-team mode blocks stray team_name"
  else
    fail "Execute non-team mode should block stray team_name (rc=$rc, output=$output)"
  fi
  cleanup
}
test_non_team_mode_blocks_team_name

test_fix_marker_is_ignored() {
  setup_project
  write_marker fix "" ""

  if run_guard "$PROJECT" "" true >/dev/null 2>&1; then
    pass "Non-execute marker ignored by spawn guard"
  else
    fail "Non-execute marker should not affect spawn guard"
  fi
  cleanup
}
test_fix_marker_is_ignored

test_correlation_mismatch_blocks_during_active_execute() {
  setup_project
  write_execution_state "live-corr"
  write_marker execute team "vbw-phase-01" "stale-corr"

  local output rc
  output=$(run_guard "$PROJECT" "" true 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'missing live runtime delegation state'; then
    pass "Mismatched execute marker blocks during active execute"
  else
    fail "Mismatched execute marker should block during active execute (rc=$rc, output=$output)"
  fi
  cleanup
}
test_correlation_mismatch_blocks_during_active_execute

test_aged_live_execute_marker_still_enforces_team_rules() {
  setup_project
  write_execution_state "corr-123"
  write_marker execute team "vbw-phase-01" "corr-123"
  touch -t 202001010000 "$PROJECT/.vbw-planning/.delegated-workflow.json"

  local output rc
  output=$(run_guard "$PROJECT" "" true 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && echo "$output" | grep -q 'requires team-scoped agent spawns'; then
    pass "Aged but correlated execute team marker still enforces team metadata"
  else
    fail "Aged live execute marker should still be enforced (rc=$rc, output=$output)"
  fi
  cleanup
}
test_aged_live_execute_marker_still_enforces_team_rules

test_sidechain_taskcreate_uses_host_state_when_host_count_absent() {
  setup_sidechain_project
  write_execution_state "corr-123"
  write_marker execute subagent "" "corr-123"
  write_sidechain_copied_state
  printf '9\n' > "$SIDECHAIN/.vbw-planning/.active-agent-count"

  if run_guard_without_exported_root "$PROJECT" "" false "dev-01" "$SIDECHAIN" "TaskCreate" "" >/dev/null 2>&1; then
    pass "Claude sidechain TaskCreate uses host state: allowed when host active count absent"
  else
    fail "Claude sidechain TaskCreate should ignore sidechain active count when host count is absent"
  fi
  cleanup
}
test_sidechain_taskcreate_uses_host_state_when_host_count_absent

test_sidechain_taskcreate_uses_host_active_count_to_block() {
  setup_sidechain_project
  write_execution_state "corr-123"
  write_marker execute subagent "" "corr-123"
  write_sidechain_copied_state
  printf '0\n' > "$SIDECHAIN/.vbw-planning/.active-agent-count"

  local output rc
  output=$(run_guard_without_exported_root "$PROJECT" "" false "dev-02" "$SIDECHAIN" "TaskCreate" "2" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && grep -q 'must serialize non-team TaskCreate spawns' <<< "$output"; then
    pass "Claude sidechain TaskCreate uses host active count: blocked when host count > 0"
  else
    fail "Claude sidechain TaskCreate should block from host active count > 0 (rc=$rc, output=$output)"
  fi
  cleanup
}
test_sidechain_taskcreate_uses_host_active_count_to_block

test_sidechain_spawn_blocks_vbw_worktree_cwd_before_isolation() {
  setup_sidechain_project
  jq '.worktree_isolation = "on"' "$SIDECHAIN/.vbw-planning/config.json" > "$SIDECHAIN/.vbw-planning/config.json.tmp"
  mv "$SIDECHAIN/.vbw-planning/config.json.tmp" "$SIDECHAIN/.vbw-planning/config.json"
  mkdir -p "$PROJECT/.vbw-worktrees/dev-01"

  local output rc
  output=$(run_guard_without_exported_root "$PROJECT" "" false "dev-01" "$SIDECHAIN" "Agent" "" "worktree" "$PROJECT/.vbw-worktrees/dev-01" "working_dir" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && grep -q 'prompt/state metadata, not a spawn cwd' <<< "$output"; then
    pass "Claude sidechain Agent .vbw-worktrees cwd alias blocked before isolation"
  else
    fail "Claude sidechain Agent .vbw-worktrees cwd alias should block before isolation (rc=$rc, output=$output)"
  fi
  cleanup
}
test_sidechain_spawn_blocks_vbw_worktree_cwd_before_isolation

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All agent spawn guard checks passed."