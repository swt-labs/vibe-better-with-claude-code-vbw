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

# Test 8: Doctor scan reports orphaned (configless) VBW teams
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
    pass "doctor scan reports orphaned VBW configless team"
  else
    fail "doctor scan did not report orphaned VBW team. Output: $output"
  fi
  rm -rf "$TMPDIR_BASE"
}

# Test 9: Doctor scan does NOT report non-VBW configless teams
test_doctor_scan_skips_non_vbw_orphan() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/my-custom-team/inboxes"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/my-custom-team/inboxes/agent.json"

  local output
  output=$(cd "$TMPDIR_BASE/project" && \
    CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$DOCTOR_SCRIPT" scan 2>/dev/null) || true

  if echo "$output" | grep -q "orphaned_team|my-custom-team"; then
    fail "doctor scan should not report non-VBW configless team"
  else
    pass "doctor scan skips non-VBW configless team"
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

# Test 9: vibe.md states no team creation in Plan mode
test_vibe_no_team_in_plan_mode() {
  if grep -q 'No team creation in Plan mode' "$ROOT/commands/vibe.md"; then
    pass "vibe.md enforces no team creation in Plan mode"
  else
    fail "vibe.md missing 'No team creation in Plan mode' statement"
  fi
}

# Test 10: vibe.md does not contain TeamCreate/TeamDelete in Plan mode
test_vibe_no_team_machinery_in_plan() {
  if grep -q 'TeamCreate.*vbw-plan' "$ROOT/commands/vibe.md" || grep -q 'TeamDelete.*vbw-plan' "$ROOT/commands/vibe.md"; then
    fail "vibe.md still references TeamCreate/TeamDelete for planning teams"
  else
    pass "vibe.md has no planning team machinery"
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

# Test 14: clean-stale-teams.sh only targets vbw-* prefixed teams in configless pass (pass 1)
test_clean_script_vbw_prefix_guard() {
  # Scope to pass 1 only — pass 2 has its own guard tested separately (test 25)
  local pass1_region
  pass1_region=$(sed -n '/^# Pass 1/,/^# Pass 2/p' "$CLEAN_SCRIPT")
  if echo "$pass1_region" | grep -q 'case "$team_name" in vbw-\*)'; then
    pass "clean-stale-teams.sh has vbw-* prefix guard in configless pass (pass 1)"
  else
    fail "clean-stale-teams.sh missing vbw-* prefix guard in pass 1"
  fi
}

# Test 15: debug.md has pre-TeamCreate cleanup before TeamCreate
test_debug_pre_teamcreate_cleanup() {
  local cleanup_line naming_line
  cleanup_line=$(grep -n 'Pre-TeamCreate cleanup' "$ROOT/commands/debug.md" | head -1 | cut -d: -f1)
  naming_line=$(grep -n 'team_name="vbw-debug-' "$ROOT/commands/debug.md" | head -1 | cut -d: -f1)
  # Use -le: cleanup on same line as naming (single-line format) is also valid
  if [ -n "$cleanup_line" ] && [ -n "$naming_line" ] && [ "$cleanup_line" -le "$naming_line" ]; then
    pass "debug.md has pre-TeamCreate cleanup before TeamCreate"
  else
    fail "debug.md pre-TeamCreate cleanup missing or out of order (cleanup=$cleanup_line, naming=$naming_line)"
  fi
}

# Test 16: map.md Step 3-duo has pre-TeamCreate cleanup before TeamCreate
test_map_duo_pre_teamcreate_cleanup() {
  local cleanup_line naming_line
  cleanup_line=$(grep -n 'Pre-TeamCreate cleanup' "$ROOT/commands/map.md" | grep -i 'duo\|step 3-duo' | head -1 | cut -d: -f1)
  # Fallback: if duo-specific line not found, get first Pre-TeamCreate cleanup line
  [ -z "$cleanup_line" ] && cleanup_line=$(grep -n 'Pre-TeamCreate cleanup' "$ROOT/commands/map.md" | head -1 | cut -d: -f1)
  naming_line=$(grep -n 'team_name="vbw-map-duo"' "$ROOT/commands/map.md" | head -1 | cut -d: -f1)
  # Use -le: cleanup on same line as naming (single-line format) is also valid
  if [ -n "$cleanup_line" ] && [ -n "$naming_line" ] && [ "$cleanup_line" -le "$naming_line" ]; then
    pass "map.md Step 3-duo has pre-TeamCreate cleanup before vbw-map-duo naming"
  else
    fail "map.md Step 3-duo pre-TeamCreate cleanup missing or out of order (cleanup=$cleanup_line, naming=$naming_line)"
  fi
}

# Test 17: map.md Step 3-quad has pre-TeamCreate cleanup before TeamCreate
test_map_quad_pre_teamcreate_cleanup() {
  local cleanup_line naming_line
  cleanup_line=$(grep -n 'Pre-TeamCreate cleanup' "$ROOT/commands/map.md" | tail -1 | cut -d: -f1)
  naming_line=$(grep -n 'team_name="vbw-map-quad"' "$ROOT/commands/map.md" | head -1 | cut -d: -f1)
  # Use -le: cleanup on same line as naming (single-line format) is also valid
  if [ -n "$cleanup_line" ] && [ -n "$naming_line" ] && [ "$cleanup_line" -le "$naming_line" ]; then
    pass "map.md Step 3-quad has pre-TeamCreate cleanup before vbw-map-quad naming"
  else
    fail "map.md Step 3-quad pre-TeamCreate cleanup missing or out of order (cleanup=$cleanup_line, naming=$naming_line)"
  fi
}

# Test 18: debug.md uses parameter-style vbw-debug- team naming
test_debug_uses_vbw_prefix_naming() {
  if grep -q 'team_name="vbw-debug-{timestamp}"' "$ROOT/commands/debug.md"; then
    pass "debug.md uses parameter-style vbw-debug- team naming"
  else
    fail "debug.md does not use parameter-style vbw-debug- team naming"
  fi
}

# Test 19: map.md specifies parameter-style vbw-map-duo naming
test_map_duo_naming() {
  if grep -q 'team_name="vbw-map-duo"' "$ROOT/commands/map.md"; then
    pass "map.md specifies parameter-style vbw-map-duo naming"
  else
    fail "map.md missing parameter-style vbw-map-duo naming"
  fi
}

# Test 20: map.md specifies parameter-style vbw-map-quad naming
test_map_quad_naming() {
  if grep -q 'team_name="vbw-map-quad"' "$ROOT/commands/map.md"; then
    pass "map.md specifies parameter-style vbw-map-quad naming"
  else
    fail "map.md missing parameter-style vbw-map-quad naming"
  fi
}

# Test 21: Non-VBW configless team with stale inbox is preserved by pass 2
test_non_vbw_stale_configless_preserved_pass2() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/other-plugin-team/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  # No config.json — configless. Backdate inbox to make it stale (>2h).
  echo '{}' > "$claude_dir/teams/other-plugin-team/inboxes/agent.json"
  touch -t 202001010000 "$claude_dir/teams/other-plugin-team/inboxes/agent.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/other-plugin-team" ]; then
    pass "non-VBW configless team with stale inbox preserved by pass 2"
  else
    fail "non-VBW configless team with stale inbox was incorrectly removed by pass 2"
  fi
  rm -rf "$TMPDIR_BASE"
}

# Test 22: clean-stale-teams.sh pass 2 has vbw-* prefix guard
test_clean_script_pass2_vbw_prefix_guard() {
  # Pass 2 is the second for-loop block; verify it contains a vbw-* case guard
  local pass2_region
  pass2_region=$(sed -n '/^# Pass 2/,/^done$/p' "$CLEAN_SCRIPT")
  if echo "$pass2_region" | grep -q 'case "$team_name" in vbw-\*)'; then
    pass "clean-stale-teams.sh pass 2 has vbw-* prefix guard"
  else
    fail "clean-stale-teams.sh pass 2 missing vbw-* prefix guard"
  fi
}

# Test 23: Doctor scan reports paired tasks dir for orphaned team
test_doctor_scan_reports_paired_tasks() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-07/inboxes"
  mkdir -p "$claude_dir/tasks/vbw-phase-07"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/vbw-phase-07/inboxes/team-lead.json"

  local output
  output=$(cd "$TMPDIR_BASE/project" && \
    CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$DOCTOR_SCRIPT" scan 2>/dev/null) || true

  if echo "$output" | grep -q "orphaned_tasks|vbw-phase-07"; then
    pass "doctor scan reports paired tasks dir for orphaned team"
  else
    fail "doctor scan did not report paired tasks dir. Output: $output"
  fi
  rm -rf "$TMPDIR_BASE"
}

# Test 24: Doctor scan reports paired tasks dir for stale team
test_doctor_scan_reports_stale_paired_tasks() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-12/inboxes"
  mkdir -p "$claude_dir/tasks/vbw-phase-12"
  mkdir -p "$planning_dir"
  echo '{"name":"vbw-phase-12"}' > "$claude_dir/teams/vbw-phase-12/config.json"
  echo '{}' > "$claude_dir/teams/vbw-phase-12/inboxes/team-lead.json"
  touch -t 202001010000 "$claude_dir/teams/vbw-phase-12/inboxes/team-lead.json"

  local output
  output=$(cd "$TMPDIR_BASE/project" && \
    CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$DOCTOR_SCRIPT" scan 2>/dev/null) || true

  if echo "$output" | grep -q "stale_tasks|vbw-phase-12"; then
    pass "doctor scan reports paired tasks dir for stale team"
  else
    fail "doctor scan did not report stale paired tasks dir. Output: $output"
  fi
  rm -rf "$TMPDIR_BASE"
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
test_doctor_scan_skips_non_vbw_orphan
test_exec_protocol_post_teamdelete_cleanup
test_exec_protocol_pre_teamcreate_cleanup
test_vibe_no_team_in_plan_mode
test_vibe_no_team_machinery_in_plan
test_map_post_teamdelete_cleanup
test_debug_post_teamdelete_cleanup
test_debug_pre_teamcreate_cleanup
test_map_duo_pre_teamcreate_cleanup
test_map_quad_pre_teamcreate_cleanup
test_debug_uses_vbw_prefix_naming
test_map_duo_naming
test_map_quad_naming
test_clean_script_has_configless_pass
test_clean_script_vbw_prefix_guard
test_non_vbw_stale_configless_preserved_pass2
test_clean_script_pass2_vbw_prefix_guard
test_doctor_scan_reports_paired_tasks
test_doctor_scan_reports_stale_paired_tasks

echo ""
echo "==============================="
echo "Ghost Team Cleanup: $PASS passed, $FAIL failed"
echo "==============================="

[ "$FAIL" -eq 0 ] || exit 1
