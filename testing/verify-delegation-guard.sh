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

# --- Test 17: Agent teams bypass — prefer_teams=always, active execution → allowed ---
# Teammates are separate Claude Code sessions, not subagents. SubagentStart never
# fires for them, so .active-agent-count is 0. The prefer_teams check bypasses the
# guard when teams are configured (can't distinguish orchestrator from teammate).
test_teams_always_bypasses_guard() {
  setup_project
  echo '{"effort":"balanced","prefer_teams":"always"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  # No .active-agent-count (SubagentStart doesn't fire for teammates)
  rm -f "$PROJECT/.vbw-planning/.active-agent-count" 2>/dev/null

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "prefer_teams=always, active execution, no agent count: allowed (teams bypass)"
  else
    fail "prefer_teams=always: unexpected block (exit $?)"
  fi
  cleanup
}
test_teams_always_bypasses_guard

# --- Test 18: Agent teams bypass — prefer_teams=auto, active execution → allowed ---
test_teams_auto_bypasses_guard() {
  setup_project
  echo '{"effort":"balanced","prefer_teams":"auto"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "prefer_teams=auto, active execution: allowed (teams bypass)"
  else
    fail "prefer_teams=auto: unexpected block (exit $?)"
  fi
  cleanup
}
test_teams_auto_bypasses_guard

# --- Test 19: Agent teams bypass — prefer_teams=when_parallel, active execution → allowed ---
test_teams_when_parallel_bypasses_guard() {
  setup_project
  echo '{"effort":"balanced","prefer_teams":"when_parallel"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "prefer_teams=when_parallel, active execution: allowed (teams bypass)"
  else
    fail "prefer_teams=when_parallel: unexpected block (exit $?)"
  fi
  cleanup
}
test_teams_when_parallel_bypasses_guard

# --- Test 20: Agent teams bypass NOT active — prefer_teams=never, active execution → blocked ---
test_teams_never_does_not_bypass() {
  setup_project
  echo '{"effort":"balanced","prefer_teams":"never"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "prefer_teams=never, active execution: blocked (no teams bypass)"
  else
    fail "prefer_teams=never: expected exit 2, got $rc"
  fi
  cleanup
}
test_teams_never_does_not_bypass

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All delegation guard checks passed."
exit 0
