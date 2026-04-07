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
}

cleanup() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE" 2>/dev/null || true
}
trap cleanup EXIT

write_marker() {
  local mode="$1"
  local delegation_mode="$2"
  local team_name="${3:-}"

  jq -n \
    --arg mode "$mode" \
    --arg delegation_mode "$delegation_mode" \
    --arg team_name "$team_name" \
    '{
      mode: $mode,
      active: true,
      effort: "balanced",
      delegation_mode: $delegation_mode,
      team_name: $team_name,
      started_at: "2026-04-07T00:00:00Z"
    }' > "$PROJECT/.vbw-planning/.delegated-workflow.json"
}

run_guard() {
  local project_dir="$1"
  local team_name="$2"
  local run_in_background="$3"
  local agent_name="${4:-dev-01}"

  local input
  input=$(jq -n \
    --arg team_name "$team_name" \
    --arg agent_name "$agent_name" \
    --argjson run_in_background "$run_in_background" \
    '{
      tool_input: {
        team_name: $team_name,
        name: $agent_name,
        run_in_background: $run_in_background
      }
    }')

  (cd "$project_dir" && bash "$GUARD" <<< "$input") 2>&1
  return ${PIPESTATUS[0]}
}

echo "=== Agent Spawn Guard Tests ==="

test_non_vbw_repo_allows() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local input
  input=$(jq -n '{tool_input:{run_in_background:true,name:"dev-01"}}')

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

test_team_mode_requires_team_name() {
  setup_project
  write_marker execute team "vbw-phase-01"

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
  write_marker execute team "vbw-phase-01"

  if run_guard "$PROJECT" "vbw-phase-01" true >/dev/null 2>&1; then
    pass "Execute team mode allows team-scoped spawn"
  else
    fail "Execute team mode unexpectedly blocked valid team-scoped spawn"
  fi
  cleanup
}
test_team_mode_allows_team_scoped_spawn

test_non_team_mode_blocks_background_spawn() {
  setup_project
  write_marker execute subagent ""

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

test_non_team_mode_allows_foreground_spawn() {
  setup_project
  write_marker execute subagent ""

  if run_guard "$PROJECT" "" false >/dev/null 2>&1; then
    pass "Execute subagent mode allows foreground spawn"
  else
    fail "Execute subagent mode unexpectedly blocked foreground spawn"
  fi
  cleanup
}
test_non_team_mode_allows_foreground_spawn

test_non_team_mode_blocks_team_name() {
  setup_project
  write_marker execute direct ""

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

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All agent spawn guard checks passed."