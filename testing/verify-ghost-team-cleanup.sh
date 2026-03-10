#!/usr/bin/env bash
set -euo pipefail

# verify-ghost-team-cleanup.sh — Tests for ghost team cleanup mitigations (#203)
#
# Verifies that:
# - clean-stale-teams.sh immediately removes configless VBW team directories
# - clean-stale-teams.sh preserves non-VBW team directories even if configless
# - clean-stale-teams.sh preserves VBW teams that have config.json (intact)
# - doctor-cleanup.sh scan reports orphaned (configless) teams
# - Post-TeamDelete cleanup instructions exist in all shutdown gates

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLEAN_SCRIPT="$ROOT/scripts/clean-stale-teams.sh"
DOCTOR_SCRIPT="$ROOT/scripts/doctor-cleanup.sh"

PASS=0
FAIL=0
TEST_PARENT=$(mktemp -d)
TMPDIR_BASE=""

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

cleanup() {
  rm -rf "$TEST_PARENT" 2>/dev/null || true
}
trap cleanup EXIT

# --- Unit Tests: clean-stale-teams.sh ---

# Test 1: Configless VBW team directory is removed immediately
test_configless_vbw_team_removed() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-03/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  # Create orphaned inbox file (no config.json)
  echo '{}' > "$claude_dir/teams/vbw-phase-03/inboxes/team-lead.json"
  # Touch the inbox file to be recent (not stale by time)
  touch "$claude_dir/teams/vbw-phase-03/inboxes/team-lead.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/vbw-phase-03" ]; then
    fail "configless VBW team dir should be removed (vbw-phase-03 still exists)"
  else
    pass "configless VBW team dir removed immediately"
  fi
  rm -rf "$TMPDIR_BASE"
}

# Test 2: Non-VBW configless team directories are preserved
test_non_vbw_configless_preserved() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/my-custom-team/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/my-custom-team/inboxes/agent.json"
  touch "$claude_dir/teams/my-custom-team/inboxes/agent.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/my-custom-team" ]; then
    pass "non-VBW configless team dir preserved"
  else
    fail "non-VBW configless team dir was incorrectly removed"
  fi
  rm -rf "$TMPDIR_BASE"
}

# Test 3: VBW team with config.json is preserved (not orphaned)
test_vbw_team_with_config_preserved() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-01/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  echo '{"name":"vbw-phase-01"}' > "$claude_dir/teams/vbw-phase-01/config.json"
  echo '{}' > "$claude_dir/teams/vbw-phase-01/inboxes/team-lead.json"
  touch "$claude_dir/teams/vbw-phase-01/inboxes/team-lead.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/vbw-phase-01" ]; then
    pass "VBW team with config.json preserved"
  else
    fail "VBW team with config.json was incorrectly removed"
  fi
  rm -rf "$TMPDIR_BASE"
}

# Test 4: Paired tasks directory removed with configless team
test_paired_tasks_removed() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-plan-02/inboxes"
  mkdir -p "$claude_dir/tasks/vbw-plan-02"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/vbw-plan-02/inboxes/team-lead.json"
  touch "$claude_dir/teams/vbw-plan-02/inboxes/team-lead.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/tasks/vbw-plan-02" ]; then
    fail "paired tasks dir should be removed with configless team"
  else
    pass "paired tasks dir removed with configless team"
  fi
  rm -rf "$TMPDIR_BASE"
}

# Test 5: Multiple configless VBW teams cleaned in single pass
test_multiple_configless_cleaned() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  for team in vbw-phase-03 vbw-phase-04 vbw-plan-02 vbw-plan-03; do
    mkdir -p "$claude_dir/teams/$team/inboxes"
    echo '{}' > "$claude_dir/teams/$team/inboxes/team-lead.json"
    touch "$claude_dir/teams/$team/inboxes/team-lead.json"
  done

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  local remaining=0
  for team in vbw-phase-03 vbw-phase-04 vbw-plan-02 vbw-plan-03; do
    [ -d "$claude_dir/teams/$team" ] && remaining=$((remaining + 1))
  done

  if [ "$remaining" -eq 0 ]; then
    pass "all 4 configless VBW teams cleaned in single pass"
  else
    fail "expected 0 remaining configless teams, got $remaining"
  fi
  rm -rf "$TMPDIR_BASE"
}

# Test 6: Configless vbw-debug-* team directory is removed immediately
test_configless_vbw_debug_team_removed() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-debug-1741625400/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/vbw-debug-1741625400/inboxes/debugger.json"
  touch "$claude_dir/teams/vbw-debug-1741625400/inboxes/debugger.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/vbw-debug-1741625400" ]; then
    fail "configless vbw-debug-* team dir should be removed"
  else
    pass "configless vbw-debug-* team dir removed immediately"
  fi
  rm -rf "$TMPDIR_BASE"
}

# Test 7: Pass 2 removes stale VBW team WITH config.json after time threshold
test_pass2_stale_team_with_config_removed() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-09/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  echo '{"name":"vbw-phase-09"}' > "$claude_dir/teams/vbw-phase-09/config.json"
  echo '{}' > "$claude_dir/teams/vbw-phase-09/inboxes/team-lead.json"
  # Backdate inbox file to >2 hours ago (stale threshold)
  touch -t 202001010000 "$claude_dir/teams/vbw-phase-09/inboxes/team-lead.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/vbw-phase-09" ]; then
    fail "stale VBW team with config.json should be removed by pass 2"
  else
    pass "pass 2 removes stale VBW team with config.json after threshold"
  fi
  rm -rf "$TMPDIR_BASE"
}

# --- Integration Tests: doctor-cleanup.sh scan ---

# Test 6: Doctor scan reports orphaned (configless) teams
test_doctor_scan_reports_orphaned() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-05/inboxes"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/vbw-phase-05/inboxes/team-lead.json"

  local output
  output=$(cd "$TMPDIR_BASE/project" && \
    CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$DOCTOR_SCRIPT" scan 2>/dev/null) || true

  if echo "$output" | grep -q "orphaned_team|vbw-phase-05"; then
    pass "doctor scan reports orphaned configless team"
  else
    fail "doctor scan did not report orphaned team. Output: $output"
  fi
  rm -rf "$TMPDIR_BASE"
}

# --- Content Tests: protocol instructions ---

# Test 7: execute-protocol.md has post-TeamDelete cleanup
test_exec_protocol_post_teamdelete_cleanup() {
  if grep -q 'Post-TeamDelete residual cleanup' "$ROOT/references/execute-protocol.md"; then
    pass "execute-protocol.md has post-TeamDelete residual cleanup"
  else
    fail "execute-protocol.md missing post-TeamDelete residual cleanup"
  fi
}

# Test 8: execute-protocol.md has pre-TeamCreate cleanup
test_exec_protocol_pre_teamcreate_cleanup() {
  if grep -q 'Pre-TeamCreate cleanup' "$ROOT/references/execute-protocol.md"; then
    pass "execute-protocol.md has pre-TeamCreate cleanup"
  else
    fail "execute-protocol.md missing pre-TeamCreate cleanup"
  fi
}

# Test 9: vibe.md has post-TeamDelete cleanup in plan mode
test_vibe_post_teamdelete_cleanup() {
  if grep -q 'Post-TeamDelete residual cleanup' "$ROOT/commands/vibe.md"; then
    pass "vibe.md has post-TeamDelete residual cleanup"
  else
    fail "vibe.md missing post-TeamDelete residual cleanup"
  fi
}

# Test 10: vibe.md has pre-TeamCreate cleanup in plan mode
test_vibe_pre_teamcreate_cleanup() {
  if grep -q 'Pre-TeamCreate cleanup' "$ROOT/commands/vibe.md"; then
    pass "vibe.md has pre-TeamCreate cleanup"
  else
    fail "vibe.md missing pre-TeamCreate cleanup"
  fi
}

# Test 11: map.md has post-TeamDelete cleanup
test_map_post_teamdelete_cleanup() {
  if grep -q 'Post-TeamDelete residual cleanup' "$ROOT/commands/map.md"; then
    pass "map.md has post-TeamDelete residual cleanup"
  else
    fail "map.md missing post-TeamDelete residual cleanup"
  fi
}

# Test 12: debug.md has post-TeamDelete cleanup
test_debug_post_teamdelete_cleanup() {
  if grep -q 'Post-TeamDelete residual cleanup' "$ROOT/commands/debug.md"; then
    pass "debug.md has post-TeamDelete residual cleanup"
  else
    fail "debug.md missing post-TeamDelete residual cleanup"
  fi
}

# Test 13: clean-stale-teams.sh has configless pass
test_clean_script_has_configless_pass() {
  if grep -q 'config.json' "$CLEAN_SCRIPT" && grep -q 'Orphaned team cleanup' "$CLEAN_SCRIPT"; then
    pass "clean-stale-teams.sh has configless orphan detection"
  else
    fail "clean-stale-teams.sh missing configless orphan detection"
  fi
}

# Test 14: clean-stale-teams.sh only targets vbw-* prefixed teams in configless pass
test_clean_script_vbw_prefix_guard() {
  if grep -q 'case "$team_name" in vbw-\*)' "$CLEAN_SCRIPT"; then
    pass "clean-stale-teams.sh has vbw-* prefix guard in configless pass"
  else
    fail "clean-stale-teams.sh missing vbw-* prefix guard"
  fi
}

# Test 15: debug.md has pre-TeamCreate cleanup
test_debug_pre_teamcreate_cleanup() {
  if grep -q 'Pre-TeamCreate cleanup' "$ROOT/commands/debug.md"; then
    pass "debug.md has pre-TeamCreate cleanup"
  else
    fail "debug.md missing pre-TeamCreate cleanup"
  fi
}

# Test 16: map.md has pre-TeamCreate cleanup
test_map_pre_teamcreate_cleanup() {
  if grep -q 'Pre-TeamCreate cleanup' "$ROOT/commands/map.md"; then
    pass "map.md has pre-TeamCreate cleanup"
  else
    fail "map.md missing pre-TeamCreate cleanup"
  fi
}

# Test 17: debug.md uses vbw-debug- team naming convention
test_debug_uses_vbw_prefix_naming() {
  if grep -q 'vbw-debug-{timestamp}' "$ROOT/commands/debug.md"; then
    pass "debug.md uses vbw-debug- team naming"
  else
    fail "debug.md does not use vbw-debug- team naming"
  fi
}

# Test 18: map.md specifies vbw-map- team naming convention
test_map_specifies_vbw_prefix_naming() {
  if grep -q 'vbw-map-duo\|vbw-map-quad' "$ROOT/commands/map.md"; then
    pass "map.md specifies vbw-map- team naming"
  else
    fail "map.md does not specify vbw-map- team naming"
  fi
}

# --- Run all tests ---
echo "=== Ghost Team Cleanup Tests (#203) ==="
echo ""

test_configless_vbw_team_removed
test_non_vbw_configless_preserved
test_vbw_team_with_config_preserved
test_paired_tasks_removed
test_multiple_configless_cleaned
test_configless_vbw_debug_team_removed
test_pass2_stale_team_with_config_removed
test_doctor_scan_reports_orphaned
test_exec_protocol_post_teamdelete_cleanup
test_exec_protocol_pre_teamcreate_cleanup
test_vibe_post_teamdelete_cleanup
test_vibe_pre_teamcreate_cleanup
test_map_post_teamdelete_cleanup
test_map_pre_teamcreate_cleanup
test_debug_post_teamdelete_cleanup
test_debug_pre_teamcreate_cleanup
test_debug_uses_vbw_prefix_naming
test_map_specifies_vbw_prefix_naming
test_clean_script_has_configless_pass
test_clean_script_vbw_prefix_guard

echo ""
echo "==============================="
echo "Ghost Team Cleanup: $PASS passed, $FAIL failed"
echo "==============================="

[ "$FAIL" -eq 0 ] || exit 1
