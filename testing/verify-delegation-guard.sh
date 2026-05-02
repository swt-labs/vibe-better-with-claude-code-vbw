#!/usr/bin/env bash
set -euo pipefail

# verify-delegation-guard.sh — Tests for orchestrator delegation guard in file-guard.sh
#
# Verifies that the guard:
# - Blocks orchestrator product-file writes during delegated workflows
# - Allows subagent writes, planning artifact writes, and turbo-mode writes
# - Fails open on missing/malformed/stale state
# - Does not affect non-VBW repos or repos without active delegation

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE_GUARD="$ROOT/scripts/file-guard.sh"
DELEG_SCRIPT="$ROOT/scripts/delegated-workflow.sh"
HOOK_WRAPPER="$ROOT/scripts/hook-wrapper.sh"

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
  # Minimal config — use prefer_teams=never so delegation guard stays active
  # (tests for the subagent model; teams bypass tested separately below)
  echo '{"effort":"balanced","prefer_teams":"never"}' > "$PROJECT/.vbw-planning/config.json"
  # Minimal PLAN so file-guard doesn't exit at the "no active plan" check
  cat > "$PROJECT/.vbw-planning/phases/01-test/01-01-PLAN.md" <<'EOF'
---
title: Test Plan
files_modified:
  - src/app.js
  - src/utils.js
---
# Test Plan
EOF
}

cleanup() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE" 2>/dev/null || true
}
trap cleanup EXIT

# Helper: run file-guard with given env and input
run_guard() {
  local project_dir="$1"
  local file_path="$2"
  local agent_role="${3:-}"

  local input
  input=$(jq -n --arg fp "$file_path" '{"tool_input":{"file_path":$fp}}')

  # Run from project dir so find_project_root works
  # Use env to set VBW_AGENT_ROLE only when non-empty; otherwise unset it
  if [ -n "$agent_role" ]; then
    (cd "$project_dir" && VBW_AGENT_ROLE="$agent_role" bash "$FILE_GUARD" <<< "$input") 2>&1
  else
    (cd "$project_dir" && unset VBW_AGENT_ROLE; bash "$FILE_GUARD" <<< "$input") 2>&1
  fi
  return ${PIPESTATUS[0]}
}

run_guard_from() {
  local working_dir="$1"
  local file_path="$2"
  local agent_role="${3:-}"

  local input
  input=$(jq -n --arg fp "$file_path" '{"tool_input":{"file_path":$fp}}')

  if [ -n "$agent_role" ]; then
    (cd "$working_dir" && unset VBW_CONFIG_ROOT VBW_PLANNING_DIR; VBW_AGENT_ROLE="$agent_role" bash "$FILE_GUARD" <<< "$input") 2>&1
  else
    (cd "$working_dir" && unset VBW_AGENT_ROLE VBW_CONFIG_ROOT VBW_PLANNING_DIR; bash "$FILE_GUARD" <<< "$input") 2>&1
  fi
  return ${PIPESTATUS[0]}
}

setup_sidechain_project() {
  setup_project
  SIDECHAIN="$PROJECT/.claude/worktrees/agent-test"
  mkdir -p "$SIDECHAIN/.vbw-planning/phases/01-copy" "$SIDECHAIN/src"
  echo '{"effort":"turbo","prefer_teams":"always"}' > "$SIDECHAIN/.vbw-planning/config.json"
}

write_live_execute_state() {
  jq -n '{phase:1,status:"running",effort:"balanced",correlation_id:"corr-sidechain",plans:[{id:"01-01",status:"pending"}]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  (cd "$PROJECT" && bash "$DELEG_SCRIPT" set execute balanced subagent)
}

run_sidechain_agent_hook() {
  local hook_script="$1"
  local input
  input=$(jq -n '{agent_type:"vbw:vbw-dev", pid:"12345"}')

  (
    cd "$SIDECHAIN"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR
    CLAUDE_CONFIG_DIR="$TMPDIR_BASE/claude" \
      CLAUDE_PLUGIN_ROOT="$ROOT" \
      bash "$HOOK_WRAPPER" "$hook_script" <<< "$input"
  )
}

assert_sidechain_target_message() {
  local output="$1"
  local host_root="$2"
  local label="$3"

  if ! grep -qi 'blocked target:' <<< "$output"; then
    fail "$label: missing blocked target label ($output)"
    return 1
  fi
  if ! grep -q "$host_root" <<< "$output" && ! grep -qi 'host repo' <<< "$output"; then
    fail "$label: missing host repo path/phrase ($output)"
    return 1
  fi
  if ! grep -qi 'retry.*absolute path.*host repo' <<< "$output"; then
    fail "$label: missing retry action for absolute host path ($output)"
    return 1
  fi
  if ! grep -qi 'sidechain' <<< "$output" || ! grep -qiE 'not.*(merge|use)|will not.*(merge|use)' <<< "$output"; then
    fail "$label: missing sidechain not-merged/used reason ($output)"
    return 1
  fi
  if grep -qE 'CRITICAL|MUST' <<< "$output"; then
    fail "$label: message uses aggressive CRITICAL/MUST wording ($output)"
    return 1
  fi
  return 0
}

echo "=== Delegation Guard Tests ==="

# --- Test 1: Non-VBW repo (no .vbw-planning) → no block ---
test_non_vbw_repo() {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/src"

  local input
  input=$(jq -n '{"tool_input":{"file_path":"src/app.js"}}')
  if (cd "$tmpdir" && bash "$FILE_GUARD" <<< "$input") >/dev/null 2>&1; then
    pass "Non-VBW repo: no block"
  else
    fail "Non-VBW repo: unexpected block (exit $?)"
  fi
  rm -rf "$tmpdir"
}
test_non_vbw_repo

# --- Test 2: VBW repo, no active delegated state → no block ---
test_no_active_state() {
  setup_project

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "No active delegated state: no block"
  else
    fail "No active delegated state: unexpected block (exit $?)"
  fi
  cleanup
}
test_no_active_state

# --- Test 3: Execute path active (status: running), non-turbo, no role, product write → blocked ---
test_execute_running_blocks() {
  setup_project
  # Write execution state with status=running and non-turbo effort
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    if echo "$output" | grep -q "orchestrator cannot write product files"; then
      pass "Execute running, non-turbo, orchestrator product write: blocked (exit 2)"
    else
      fail "Execute running: blocked but wrong message: $output"
    fi
  else
    fail "Execute running, non-turbo, orchestrator product write: expected exit 2, got $rc"
  fi
  cleanup
}
test_execute_running_blocks

# --- Test 4: Fix/debug delegated marker active, non-turbo, no role, product write → blocked ---
test_delegated_marker_blocks() {
  setup_project
  jq -n '{mode:"fix", active:true, effort:"balanced", started_at:"2026-03-03T00:00:00Z"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    if echo "$output" | grep -q "orchestrator cannot write product files"; then
      pass "Delegated marker active, non-turbo, orchestrator product write: blocked (exit 2)"
    else
      fail "Delegated marker: blocked but wrong message: $output"
    fi
  else
    fail "Delegated marker active: expected exit 2, got $rc"
  fi
  cleanup
}
test_delegated_marker_blocks

# --- Test 5: Active delegated state, writing planning artifacts → allowed ---
test_planning_artifacts_allowed() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  # Planning artifacts are exempted early (line 58) before the guard runs
  local rc=0
  run_guard "$PROJECT" "$PROJECT/.vbw-planning/STATE.md" "" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "Active delegated state, planning artifact write: allowed"
  else
    fail "Active delegated state, planning artifact write: unexpected block (exit $rc)"
  fi
  cleanup
}
test_planning_artifacts_allowed

# --- Test 6: Active delegated state with turbo effort → allowed ---
test_turbo_allowed() {
  setup_project
  echo '{"effort":"turbo","prefer_teams":"never"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"turbo", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "Active delegated state, turbo effort: allowed"
  else
    fail "Active delegated state, turbo effort: unexpected block (exit $?)"
  fi
  cleanup
}
test_turbo_allowed

# --- Test 7: Active delegated state with VBW_AGENT_ROLE=dev → allowed ---
test_subagent_allowed() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  # Subagent with role=dev — guard only fires when role is empty.
  # The subagent will be handled by the role isolation section (dev is allowed).
  if run_guard "$PROJECT" "src/app.js" "dev" >/dev/null 2>&1; then
    pass "Active delegated state, VBW_AGENT_ROLE=dev: allowed"
  else
    fail "Active delegated state, VBW_AGENT_ROLE=dev: unexpected block (exit $?)"
  fi
  cleanup
}
test_subagent_allowed

# --- Test 8: Malformed/stale state files → fail-open ---
test_malformed_state_failopen() {
  setup_project
  # Write garbage to execution state
  echo "not json" > "$PROJECT/.vbw-planning/.execution-state.json"

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "Malformed state file: fail-open"
  else
    fail "Malformed state file: unexpected block (exit $?)"
  fi
  cleanup
}
test_malformed_state_failopen

# --- Test 9: Stale state file (very old mtime) → fail-open ---
test_stale_state_failopen() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2024-01-01T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  # Set mtime to 5 hours ago (well past 4h threshold)
  touch -t "202501010000" "$PROJECT/.vbw-planning/.execution-state.json" 2>/dev/null || true

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "Stale state file (>4h): fail-open"
  else
    fail "Stale state file: unexpected block (exit $?)"
  fi
  cleanup
}
test_stale_state_failopen

# --- Test 10: Direct effort in delegated marker → allowed ---
test_direct_effort_allowed() {
  setup_project
  jq -n '{mode:"fix", active:true, effort:"direct", started_at:"2026-03-03T00:00:00Z"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "Delegated marker, direct effort: allowed"
  else
    fail "Delegated marker, direct effort: unexpected block (exit $?)"
  fi
  cleanup
}
test_direct_effort_allowed

# --- Test 10b: Execute direct marker is live and allowed through effort exemption ---
test_execute_direct_marker_allowed() {
  setup_project
  jq -n '{phase:1,status:"running",effort:"direct",correlation_id:"corr-direct",plans:[{id:"01-01",status:"pending"}]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  (cd "$PROJECT" && bash "$DELEG_SCRIPT" set execute direct direct)

  local status_json
  status_json=$(cd "$PROJECT" && bash "$DELEG_SCRIPT" status-json)
  if jq -e '.live == true and .delegation_mode == "direct" and .mode == "execute"' >/dev/null <<< "$status_json"; then
    pass "execute direct marker: status-json reports live direct mode"
  else
    fail "execute direct marker: expected live direct mode, got $status_json"
  fi

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "execute direct marker: file-guard allows direct effort product write"
  else
    fail "execute direct marker: file-guard unexpectedly blocked direct effort product write"
  fi
  cleanup
}
test_execute_direct_marker_allowed

# --- Test 11: Execution running with complete status → no block ---
test_complete_status_no_block() {
  setup_project
  jq -n '{status:"complete", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "Execution complete status: no block"
  else
    fail "Execution complete status: unexpected block (exit $?)"
  fi
  cleanup
}
test_complete_status_no_block

# --- Test 12: delegated-workflow.sh script contract ---
test_delegated_workflow_script() {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.vbw-planning"
  echo '{"effort":"balanced"}' > "$tmpdir/.vbw-planning/config.json"

  # set action
  (cd "$tmpdir" && bash "$DELEG_SCRIPT" set fix balanced)
  if [ -f "$tmpdir/.vbw-planning/.delegated-workflow.json" ]; then
    local mode
    mode=$(jq -r '.mode' "$tmpdir/.vbw-planning/.delegated-workflow.json" 2>/dev/null)
    if [ "$mode" = "fix" ]; then
      pass "delegated-workflow.sh set: creates marker with correct mode"
    else
      fail "delegated-workflow.sh set: wrong mode ($mode)"
    fi
  else
    fail "delegated-workflow.sh set: marker file not created"
  fi

  # execute team marker with runtime delegation metadata
  jq -n '{phase:1,status:"running",effort:"balanced",correlation_id:"corr-123",plans:[]}' > "$tmpdir/.vbw-planning/.execution-state.json"
  (cd "$tmpdir" && bash "$DELEG_SCRIPT" set execute balanced team vbw-phase-01)
  if [ -f "$tmpdir/.vbw-planning/.delegated-workflow.json" ]; then
    local execute_mode execute_delegation execute_team execute_correlation
    execute_mode=$(jq -r '.mode' "$tmpdir/.vbw-planning/.delegated-workflow.json" 2>/dev/null)
    execute_delegation=$(jq -r '.delegation_mode // ""' "$tmpdir/.vbw-planning/.delegated-workflow.json" 2>/dev/null)
    execute_team=$(jq -r '.team_name // ""' "$tmpdir/.vbw-planning/.delegated-workflow.json" 2>/dev/null)
    execute_correlation=$(jq -r '.correlation_id // ""' "$tmpdir/.vbw-planning/.delegated-workflow.json" 2>/dev/null)
    if [ "$execute_mode" = "execute" ] && [ "$execute_delegation" = "team" ] && [ "$execute_team" = "vbw-phase-01" ] && [ "$execute_correlation" = "corr-123" ]; then
      pass "delegated-workflow.sh set execute: records delegation_mode, team_name, and correlation_id"
    else
      fail "delegated-workflow.sh set execute: unexpected marker contents (mode=$execute_mode delegation_mode=$execute_delegation team_name=$execute_team correlation_id=$execute_correlation)"
    fi
  else
    fail "delegated-workflow.sh set execute: marker file not created"
  fi

  local live_status
  live_status=$(cd "$tmpdir" && bash "$DELEG_SCRIPT" status-json)
  if echo "$live_status" | jq -e '.live == true and .preserve_on_session_start == true and .reason == "ok"' >/dev/null 2>&1; then
    pass "delegated-workflow.sh status-json: live execute marker validates against execution state"
  else
    fail "delegated-workflow.sh status-json: expected live execute marker, got: $live_status"
  fi

  touch -t 202001010000 "$tmpdir/.vbw-planning/.execution-state.json"
  local stale_status
  stale_status=$(cd "$tmpdir" && bash "$DELEG_SCRIPT" status-json)
  if echo "$stale_status" | jq -e '.live == false and .reason == "stale_execution_state"' >/dev/null 2>&1; then
    pass "delegated-workflow.sh status-json: stale running execution state is not treated as live"
  else
    fail "delegated-workflow.sh status-json: expected stale execution state, got: $stale_status"
  fi

  (cd "$tmpdir" && bash "$DELEG_SCRIPT" set fix balanced)
  local fix_status
  fix_status=$(cd "$tmpdir" && bash "$DELEG_SCRIPT" status-json)
  if echo "$fix_status" | jq -e '.live == true and .preserve_on_session_start == false and .mode == "fix"' >/dev/null 2>&1; then
    pass "delegated-workflow.sh status-json: fix marker stays live for same-session guard use but is not preserved across SessionStart"
  else
    fail "delegated-workflow.sh status-json: expected non-preserved fix marker, got: $fix_status"
  fi

  # check action (active)
  if (cd "$tmpdir" && bash "$DELEG_SCRIPT" check) >/dev/null 2>&1; then
    pass "delegated-workflow.sh check: returns 0 when active"
  else
    fail "delegated-workflow.sh check: should return 0 when active"
  fi

  # clear action
  (cd "$tmpdir" && bash "$DELEG_SCRIPT" clear)
  if [ ! -f "$tmpdir/.vbw-planning/.delegated-workflow.json" ]; then
    pass "delegated-workflow.sh clear: removes marker"
  else
    fail "delegated-workflow.sh clear: marker still exists"
  fi

  # check action (inactive)
  local rc=0
  (cd "$tmpdir" && bash "$DELEG_SCRIPT" check) >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "delegated-workflow.sh check: returns non-zero when inactive"
  else
    fail "delegated-workflow.sh check: should return non-zero when inactive"
  fi

  rm -rf "$tmpdir"
}
test_delegated_workflow_script

# --- Test 13: GSD / non-VBW directory unaffected ---
test_gsd_unaffected() {
  local tmpdir
  tmpdir=$(mktemp -d)
  # .planning/ (GSD) but no .vbw-planning/
  mkdir -p "$tmpdir/.planning/phases/01-test"

  local input
  input=$(jq -n '{"tool_input":{"file_path":"src/app.js"}}')
  if (cd "$tmpdir" && bash "$FILE_GUARD" <<< "$input") >/dev/null 2>&1; then
    pass "GSD-only repo (.planning/ without .vbw-planning/): no block"
  else
    fail "GSD-only repo: unexpected block (exit $?)"
  fi
  rm -rf "$tmpdir"
}
test_gsd_unaffected

# --- Test 14: Active delegated state, no VBW_AGENT_ROLE, but .active-agent-count > 0 → allowed ---
# This is the real runtime scenario: PreToolUse hooks don't inherit VBW_AGENT_ROLE,
# but agent-start.sh has incremented the count. The guard should allow the write.
test_active_agent_count_bypass() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  # Simulate agent-start.sh having run: subagent active
  echo "1" > "$PROJECT/.vbw-planning/.active-agent-count"
  echo "dev" > "$PROJECT/.vbw-planning/.active-agent"

  # No VBW_AGENT_ROLE set (matches real PreToolUse hook behavior)
  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "Active agent count > 0, no VBW_AGENT_ROLE: allowed (subagent bypass)"
  else
    fail "Active agent count > 0, no VBW_AGENT_ROLE: unexpected block (exit $?)"
  fi
  cleanup
}
test_active_agent_count_bypass

# --- Test 15: Active delegated state, .active-agent-count = 0 (all agents stopped), no role → blocked ---
test_zero_agent_count_still_blocks() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  # Count is 0 — all subagents have stopped, so this is an orchestrator write
  echo "0" > "$PROJECT/.vbw-planning/.active-agent-count"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "Active agent count = 0, no VBW_AGENT_ROLE: blocked (orchestrator)"
  else
    fail "Active agent count = 0: expected exit 2, got $rc"
  fi
  cleanup
}
test_zero_agent_count_still_blocks

# --- Test 16: Active delegated state, .active-agent-count missing (no file), no role → blocked ---
test_no_count_file_still_blocks() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  # No count file at all (agent-start never ran) — should still block
  rm -f "$PROJECT/.vbw-planning/.active-agent-count" 2>/dev/null

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "No agent count file, no VBW_AGENT_ROLE: blocked (orchestrator)"
  else
    fail "No agent count file: expected exit 2, got $rc"
  fi
  cleanup
}
test_no_count_file_still_blocks

# --- Test 17: Execute team marker bypasses guard for teammate writes ---
test_execute_team_marker_bypasses_guard() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  jq -n '{mode:"execute", active:true, effort:"balanced", delegation_mode:"team", team_name:"vbw-phase-01", started_at:"2026-03-03T00:00:00Z", session_id:"session-test", correlation_id:"corr-123"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"
  tmp=$(mktemp)
  jq '.correlation_id = "corr-123"' "$PROJECT/.vbw-planning/.execution-state.json" > "$tmp" && mv "$tmp" "$PROJECT/.vbw-planning/.execution-state.json"

  rm -f "$PROJECT/.vbw-planning/.active-agent-count" 2>/dev/null

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "execute team marker, active execution, no agent count: allowed"
  else
    fail "execute team marker: unexpected block (exit $?)"
  fi
  cleanup
}
test_execute_team_marker_bypasses_guard

# --- Test 18: aged live execute team marker still bypasses guard ---
test_aged_live_execute_team_marker_bypasses_guard() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", correlation_id:"corr-123", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  jq -n '{mode:"execute", active:true, effort:"balanced", delegation_mode:"team", team_name:"vbw-phase-01", started_at:"2026-03-03T00:00:00Z", session_id:"session-test", correlation_id:"corr-123"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"
  touch -t 202001010000 "$PROJECT/.vbw-planning/.delegated-workflow.json"

  rm -f "$PROJECT/.vbw-planning/.active-agent-count" 2>/dev/null

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "aged live execute team marker: allowed"
  else
    fail "aged live execute team marker: unexpected block (exit $?)"
  fi
  cleanup
}
test_aged_live_execute_team_marker_bypasses_guard

# --- Test 19: stale/mismatched execute team marker does not bypass guard ---
test_execute_team_marker_mismatch_does_not_bypass() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", correlation_id:"live-corr", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  jq -n '{mode:"execute", active:true, effort:"balanced", delegation_mode:"team", team_name:"vbw-phase-01", started_at:"2026-03-03T00:00:00Z", session_id:"session-test", correlation_id:"stale-corr"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"
  touch -t 202001010000 "$PROJECT/.vbw-planning/.delegated-workflow.json"

  rm -f "$PROJECT/.vbw-planning/.active-agent-count" 2>/dev/null

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "mismatched execute team marker: blocked (no stale teams bypass)"
  else
    fail "mismatched execute team marker: expected exit 2, got $rc"
  fi
  cleanup
}
test_execute_team_marker_mismatch_does_not_bypass

# --- Test 20: prefer_teams=always alone no longer bypasses guard ---
test_prefer_teams_always_alone_does_not_bypass() {
  setup_project
  echo '{"effort":"balanced","prefer_teams":"always"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "prefer_teams=always without execute team marker: blocked"
  else
    fail "prefer_teams=always without execute team marker: expected exit 2, got $rc"
  fi
  cleanup
}
test_prefer_teams_always_alone_does_not_bypass

# --- Test 21: prefer_teams=auto alone no longer bypasses guard ---
test_prefer_teams_auto_alone_does_not_bypass() {
  setup_project
  echo '{"effort":"balanced","prefer_teams":"auto"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "prefer_teams=auto without execute team marker: blocked"
  else
    fail "prefer_teams=auto without execute team marker: expected exit 2, got $rc"
  fi
  cleanup
}
test_prefer_teams_auto_alone_does_not_bypass

# --- Test 22: Legacy when_parallel alias alone no longer bypasses guard ---
test_prefer_teams_legacy_when_parallel_alone_does_not_bypass() {
  setup_project
  echo '{"effort":"balanced","prefer_teams":"when_parallel"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "legacy prefer_teams=when_parallel without execute team marker: blocked"
  else
    fail "legacy prefer_teams=when_parallel without execute team marker: expected exit 2, got $rc"
  fi
  cleanup
}
test_prefer_teams_legacy_when_parallel_alone_does_not_bypass

# --- Test 23: session-start clears fresh fix marker before a new session guard evaluation ---
test_session_start_clears_fresh_fix_marker() {
  setup_project
  jq -n '{mode:"fix", active:true, effort:"balanced", delegation_mode:"", team_name:"", started_at:"2026-03-03T00:00:00Z", session_id:"session-test", correlation_id:""}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"

  (cd "$PROJECT" && bash "$ROOT/scripts/session-start.sh") >/dev/null 2>&1

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "session-start clears fresh fix marker before next-session file-guard evaluation"
  else
    fail "session-start should clear fresh fix marker before next-session guard evaluation"
  fi
  cleanup
}
test_session_start_clears_fresh_fix_marker

# --- Test 24: session-stop preserves live execute team marker for downstream file-guard bypass ---
test_session_stop_preserves_live_execute_team_marker() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", correlation_id:"corr-123", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  jq -n '{mode:"execute", active:true, effort:"balanced", delegation_mode:"team", team_name:"vbw-phase-01", started_at:"2026-03-03T00:00:00Z", session_id:"session-test", correlation_id:"corr-123"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"

  echo '{"cost_usd":0.01,"duration_ms":5000,"tokens_in":100,"tokens_out":50,"model":"test"}' \
    | (cd "$PROJECT" && bash "$ROOT/scripts/session-stop.sh") >/dev/null 2>&1

  [ -f "$PROJECT/.vbw-planning/.delegated-workflow.json" ] || {
    fail "session-stop should preserve live execute team marker"
    cleanup
    return
  }

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "session-stop preserves live execute team marker for file-guard bypass"
  else
    fail "session-stop preserved marker path did not keep file-guard bypass"
  fi
  cleanup
}
test_session_stop_preserves_live_execute_team_marker

# --- Test 25: Claude sidechain agent-start/stop uses host planning dir ---
test_claude_sidechain_agent_hooks_use_host_planning_dir() {
  setup_sidechain_project
  write_live_execute_state

  run_sidechain_agent_hook agent-start.sh >/dev/null 2>&1 || true

  local host_count sidechain_count
  host_count=$(cat "$PROJECT/.vbw-planning/.active-agent-count" 2>/dev/null || true)
  sidechain_count=$(cat "$SIDECHAIN/.vbw-planning/.active-agent-count" 2>/dev/null || true)
  if [ "$host_count" = "1" ] && [ -z "$sidechain_count" ]; then
    pass "Claude sidechain agent-start writes active count to host planning dir"
  else
    fail "Claude sidechain agent-start should write host count=1 and no sidechain count (host=$host_count sidechain=$sidechain_count)"
  fi

  run_sidechain_agent_hook agent-stop.sh >/dev/null 2>&1 || true
  if [ ! -f "$PROJECT/.vbw-planning/.active-agent-count" ] && [ ! -f "$PROJECT/.vbw-planning/.active-agent" ]; then
    pass "Claude sidechain agent-stop cleans host active-agent markers"
  else
    fail "Claude sidechain agent-stop should remove host active-agent markers"
  fi
  cleanup
}
test_claude_sidechain_agent_hooks_use_host_planning_dir

# --- Test 26: Claude sidechain subagent can write declared host product path ---
test_claude_sidechain_host_absolute_write_allowed_after_agent_start() {
  setup_sidechain_project
  write_live_execute_state
  run_sidechain_agent_hook agent-start.sh >/dev/null 2>&1 || true

  if run_guard_from "$SIDECHAIN" "$PROJECT/src/app.js" "" >/dev/null 2>&1; then
    pass "Claude sidechain active subagent: host-root declared product write allowed"
  else
    fail "Claude sidechain active subagent: host-root declared product write unexpectedly blocked"
  fi

  run_sidechain_agent_hook agent-stop.sh >/dev/null 2>&1 || true
  cleanup
}
test_claude_sidechain_host_absolute_write_allowed_after_agent_start

# --- Test 27: Claude sidechain host write without active marker still blocks orchestrator ---
test_claude_sidechain_host_absolute_write_blocks_without_agent_marker() {
  setup_sidechain_project
  write_live_execute_state

  rm -f "$PROJECT/.vbw-planning/.active-agent" "$PROJECT/.vbw-planning/.active-agent-count"
  local output rc
  output=$(run_guard_from "$SIDECHAIN" "$PROJECT/src/app.js" "" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && grep -q 'orchestrator cannot write product files' <<< "$output"; then
    pass "Claude sidechain orchestrator host-root product write: blocked"
  else
    fail "Claude sidechain orchestrator host-root product write should block (rc=$rc, output=$output)"
  fi
  cleanup
}
test_claude_sidechain_host_absolute_write_blocks_without_agent_marker

# --- Test 28: Claude sidechain relative Write/Edit target is blocked early ---
test_claude_sidechain_relative_write_target_blocks() {
  setup_sidechain_project
  write_live_execute_state
  echo "1" > "$PROJECT/.vbw-planning/.active-agent-count"
  echo "dev" > "$PROJECT/.vbw-planning/.active-agent"

  local output rc
  output=$(run_guard_from "$SIDECHAIN" "src/app.js" "" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ]; then
    if assert_sidechain_target_message "$output" "$PROJECT" "Claude sidechain relative target"; then
      pass "Claude sidechain relative Write/Edit target: blocked with retry guidance"
    fi
  else
    fail "Claude sidechain relative Write/Edit target should block (rc=$rc, output=$output)"
  fi
  cleanup
}
test_claude_sidechain_relative_write_target_blocks

# --- Test 29: Claude sidechain absolute target under sidechain is blocked early ---
test_claude_sidechain_absolute_sidechain_target_blocks() {
  setup_sidechain_project
  write_live_execute_state
  echo "1" > "$PROJECT/.vbw-planning/.active-agent-count"
  echo "dev" > "$PROJECT/.vbw-planning/.active-agent"

  local output rc
  output=$(run_guard_from "$SIDECHAIN" "$SIDECHAIN/src/app.js" "" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ]; then
    if assert_sidechain_target_message "$output" "$PROJECT" "Claude sidechain absolute target"; then
      pass "Claude sidechain absolute sidechain target: blocked with retry guidance"
    fi
  else
    fail "Claude sidechain absolute target should block (rc=$rc, output=$output)"
  fi
  cleanup
}
test_claude_sidechain_absolute_sidechain_target_blocks

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All delegation guard checks passed."
exit 0
