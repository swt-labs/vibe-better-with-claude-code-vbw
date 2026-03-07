#!/usr/bin/env bash
set -euo pipefail

# verify-exec-state-reconciliation.sh — Tests for execution-state reconciliation
#
# Verifies that statusline and session-start correctly reconcile
# .execution-state.json plan statuses against actual SUMMARY.md files on disk.
# This prevents stale "complete" statuses after resets/undos.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

cleanup() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Execution State Reconciliation Tests ==="

# --- Statusline: EXEC_DONE reconciliation against SUMMARY.md files ---
echo ""
echo "--- Statusline EXEC_DONE reconciliation ---"

# Test 1: statusline has count_complete_summaries available for reconciliation
if grep -q 'count_complete_summaries' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline sources count_complete_summaries helper"
else
  fail "statusline sources count_complete_summaries helper"
fi

# Test 2: statusline reconciles EXEC_DONE after reading from JSON
if grep -q '_actual_done.*count_done_summaries' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline computes actual SUMMARY count for reconciliation"
else
  fail "statusline computes actual SUMMARY count for reconciliation"
fi

# Test 3: statusline caps EXEC_DONE when actual count is lower
if grep -q '_actual_done.*-lt.*EXEC_DONE' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline caps EXEC_DONE when filesystem has fewer completions"
else
  fail "statusline caps EXEC_DONE when filesystem has fewer completions"
fi

# Test 4: statusline only reconciles when execution is "running" (active build)
if grep -q 'EXEC_STATUS.*=.*running.*EXEC_DONE.*-gt.*0' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline reconciliation gated on running status"
else
  fail "statusline reconciliation gated on running status"
fi

# Test 5: statusline reads phase from execution-state.json for reconciliation
if grep -q '_exec_phase.*jq.*\.phase' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline reads phase from execution-state for SUMMARY lookup"
else
  fail "statusline reads phase from execution-state for SUMMARY lookup"
fi

# --- Session-start: execution-state.json plan status reconciliation ---
echo ""
echo "--- Session-start plan status reconciliation ---"

# Test 6: session-start compares JSON complete count vs disk SUMMARY count
if grep -q '_json_done.*plans.*select.*complete.*length' "$ROOT/scripts/session-start.sh"; then
  pass "session-start extracts JSON complete count for comparison"
else
  fail "session-start extracts JSON complete count for comparison"
fi

# Test 7: session-start triggers reconciliation when JSON > disk
if grep -q '_json_done.*-gt.*SUMMARY_COUNT' "$ROOT/scripts/session-start.sh"; then
  pass "session-start triggers reconciliation when JSON exceeds disk count"
else
  fail "session-start triggers reconciliation when JSON exceeds disk count"
fi

# Test 8: session-start builds completed IDs from actual SUMMARY.md files
if grep -q '_completed_json' "$ROOT/scripts/session-start.sh" && grep -q 'SUMMARY' "$ROOT/scripts/session-start.sh"; then
  pass "session-start builds completed ID list from SUMMARY.md files"
else
  fail "session-start builds completed ID list from SUMMARY.md files"
fi

# Test 9: session-start resets stale plan statuses to "pending"
if grep -q '"pending"' "$ROOT/scripts/session-start.sh" && grep -q 'reconcile' "$ROOT/scripts/session-start.sh"; then
  pass "session-start resets stale plans to pending via reconciliation"
else
  fail "session-start resets stale plans to pending via reconciliation"
fi

# Test 10: session-start reconciliation uses jq for atomic JSON update
if grep -q 'argjson completed' "$ROOT/scripts/session-start.sh" && grep -q 'reconcile_tmp' "$ROOT/scripts/session-start.sh"; then
  pass "session-start uses jq with argjson for atomic reconciliation"
else
  fail "session-start uses jq with argjson for atomic reconciliation"
fi

# --- Functional test: simulate stale execution state ---
echo ""
echo "--- Functional: stale execution-state detection ---"

TMPDIR_BASE=$(mktemp -d)
FAKE_PROJECT="$TMPDIR_BASE/project/.vbw-planning"
FAKE_PHASE="$FAKE_PROJECT/phases/06-build-core"
mkdir -p "$FAKE_PHASE"

# Create execution-state with 3 plans, 2 "complete" + 1 "pending"
cat > "$FAKE_PROJECT/.execution-state.json" <<'EXECJSON'
{
  "phase": 6, "phase_name": "06-build-core", "status": "running",
  "wave": 1, "total_waves": 1,
  "plans": [
    {"id": "06-01", "title": "Plan 1", "wave": 1, "status": "complete"},
    {"id": "06-02", "title": "Plan 2", "wave": 1, "status": "complete"},
    {"id": "06-03", "title": "Plan 3", "wave": 1, "status": "pending"}
  ]
}
EXECJSON

# Only create SUMMARY for plan 1 (simulate plan 2 was undone/reset)
cat > "$FAKE_PHASE/06-01-SUMMARY.md" <<'SUMMARY'
---
phase: 6
plan: 01
status: complete
---
# Plan 1 Summary
SUMMARY

# Verify JSON says 2 complete
JSON_DONE=$(jq '[.plans[] | select(.status == "complete")] | length' "$FAKE_PROJECT/.execution-state.json")
if [ "$JSON_DONE" -eq 2 ]; then
  pass "pre-condition: JSON reports 2 complete plans"
else
  fail "pre-condition: JSON reports 2 complete plans (got $JSON_DONE)"
fi

# Verify disk has only 1 complete SUMMARY
DISK_DONE=0
for sf in "$FAKE_PHASE"/*-SUMMARY.md; do
  [ -f "$sf" ] || continue
  st=$(sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' "$sf" 2>/dev/null | head -1 | tr -d '[:space:]')
  case "$st" in complete|completed) DISK_DONE=$((DISK_DONE + 1)) ;; esac
done
if [ "$DISK_DONE" -eq 1 ]; then
  pass "pre-condition: disk has 1 complete SUMMARY.md"
else
  fail "pre-condition: disk has 1 complete SUMMARY.md (got $DISK_DONE)"
fi

# Simulate the reconciliation logic from session-start
_completed_json="[]"
for _sf in "$FAKE_PHASE"/*-SUMMARY.md; do
  [ -f "$_sf" ] || continue
  _sf_st=$(sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' "$_sf" 2>/dev/null | head -1 | tr -d '[:space:]')
  case "$_sf_st" in
    complete|completed)
      _sf_id=$(basename "$_sf" | sed 's/-SUMMARY\.md$//')
      _completed_json=$(echo "$_completed_json" | jq --arg id "$_sf_id" '. + [$id]')
      ;;
  esac
done

EXEC_STATE="$FAKE_PROJECT/.execution-state.json"
_reconcile_tmp="${EXEC_STATE}.reconcile.$$"
jq --argjson completed "$_completed_json" '
  .plans |= map(
    if .status == "complete" and (.id as $pid | $completed | any(. == $pid) | not) then
      .status = "pending"
    else .
    end
  )
' "$EXEC_STATE" > "$_reconcile_tmp" 2>/dev/null && mv "$_reconcile_tmp" "$EXEC_STATE" 2>/dev/null

# Verify reconciliation result
POST_DONE=$(jq '[.plans[] | select(.status == "complete")] | length' "$EXEC_STATE")
if [ "$POST_DONE" -eq 1 ]; then
  pass "reconciliation: stale plan 06-02 reset to pending (1 complete)"
else
  fail "reconciliation: stale plan 06-02 reset to pending (got $POST_DONE complete)"
fi

PLAN2_STATUS=$(jq -r '.plans[] | select(.id == "06-02") | .status' "$EXEC_STATE")
if [ "$PLAN2_STATUS" = "pending" ]; then
  pass "reconciliation: plan 06-02 specifically set to pending"
else
  fail "reconciliation: plan 06-02 specifically set to pending (got $PLAN2_STATUS)"
fi

PLAN1_STATUS=$(jq -r '.plans[] | select(.id == "06-01") | .status' "$EXEC_STATE")
if [ "$PLAN1_STATUS" = "complete" ]; then
  pass "reconciliation: plan 06-01 preserved as complete (has SUMMARY)"
else
  fail "reconciliation: plan 06-01 preserved as complete (got $PLAN1_STATUS)"
fi

PLAN3_STATUS=$(jq -r '.plans[] | select(.id == "06-03") | .status' "$EXEC_STATE")
if [ "$PLAN3_STATUS" = "pending" ]; then
  pass "reconciliation: plan 06-03 stays pending (was already pending)"
else
  fail "reconciliation: plan 06-03 stays pending (got $PLAN3_STATUS)"
fi

# --- Functional: partial SUMMARY → reconciliation preserves "complete" in JSON ---
echo ""
echo "--- Functional: partial SUMMARY accepted by reconciliation ---"

PARTIAL_PROJECT="$TMPDIR_BASE/partial-project/.vbw-planning"
PARTIAL_PHASE="$PARTIAL_PROJECT/phases/03-build"
mkdir -p "$PARTIAL_PHASE"

cat > "$PARTIAL_PROJECT/.execution-state.json" <<'EXECJSON'
{
  "phase": 3, "phase_name": "03-build", "status": "running",
  "wave": 1, "total_waves": 1,
  "plans": [
    {"id": "03-01", "title": "Plan 1", "wave": 1, "status": "complete"},
    {"id": "03-02", "title": "Plan 2", "wave": 1, "status": "complete"},
    {"id": "03-03", "title": "Plan 3", "wave": 1, "status": "pending"}
  ]
}
EXECJSON

# Plan 1: complete SUMMARY, Plan 2: partial SUMMARY (no SUMMARY for plan 3)
cat > "$PARTIAL_PHASE/03-01-SUMMARY.md" <<'SUMMARY'
---
phase: 3
plan: 01
status: complete
---
# Plan 1 Summary
SUMMARY

cat > "$PARTIAL_PHASE/03-02-SUMMARY.md" <<'SUMMARY'
---
phase: 3
plan: 02
status: partial
---
# Plan 2 Summary (partial — crash during execution)
SUMMARY

# Reconciliation should count both complete and partial as "done"
_completed_json="[]"
for _sf in "$PARTIAL_PHASE"/*-SUMMARY.md; do
  [ -f "$_sf" ] || continue
  _sf_st=$(sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' "$_sf" 2>/dev/null | head -1 | tr -d '[:space:]')
  case "$_sf_st" in
    complete|completed|partial)
      _sf_id=$(basename "$_sf" | sed 's/-SUMMARY\.md$//')
      _completed_json=$(echo "$_completed_json" | jq --arg id "$_sf_id" '. + [$id]')
      ;;
  esac
done

EXEC_STATE="$PARTIAL_PROJECT/.execution-state.json"
_reconcile_tmp="${EXEC_STATE}.reconcile.$$"
jq --argjson completed "$_completed_json" '
  .plans |= map(
    if .status == "complete" and (.id as $pid | $completed | any(. == $pid) | not) then
      .status = "pending"
    else .
    end
  )
' "$EXEC_STATE" > "$_reconcile_tmp" 2>/dev/null && mv "$_reconcile_tmp" "$EXEC_STATE" 2>/dev/null

# Both plans should stay "complete" because both have SUMMARY.md (one complete, one partial)
PARTIAL_DONE=$(jq '[.plans[] | select(.status == "complete")] | length' "$EXEC_STATE")
if [ "$PARTIAL_DONE" -eq 2 ]; then
  pass "partial: both plans preserved as complete (2 done)"
else
  fail "partial: both plans preserved as complete (got $PARTIAL_DONE)"
fi

PARTIAL_P2=$(jq -r '.plans[] | select(.id == "03-02") | .status' "$EXEC_STATE")
if [ "$PARTIAL_P2" = "complete" ]; then
  pass "partial: plan 03-02 with partial SUMMARY kept as complete"
else
  fail "partial: plan 03-02 with partial SUMMARY kept as complete (got $PARTIAL_P2)"
fi

# --- Functional: statusline reconciliation (count_done_summaries) ---
echo ""
echo "--- Functional: statusline reconciliation via count_done_summaries ---"

# Source summary-utils.sh for count_done_summaries
if [ -f "$ROOT/scripts/summary-utils.sh" ]; then
  . "$ROOT/scripts/summary-utils.sh"
fi

SL_PROJECT="$TMPDIR_BASE/sl-project/.vbw-planning"
SL_PHASE="$SL_PROJECT/phases/02-core"
mkdir -p "$SL_PHASE"

# 3 plans in JSON, 2 marked complete — but only 1 complete SUMMARY + 1 partial SUMMARY on disk
cat > "$SL_PROJECT/.execution-state.json" <<'EXECJSON'
{
  "phase": 2, "status": "running",
  "plans": [
    {"id": "02-01", "status": "complete"},
    {"id": "02-02", "status": "complete"},
    {"id": "02-03", "status": "complete"}
  ]
}
EXECJSON

cat > "$SL_PHASE/02-01-SUMMARY.md" <<'SUMMARY'
---
status: complete
---
Done
SUMMARY

cat > "$SL_PHASE/02-02-SUMMARY.md" <<'SUMMARY'
---
status: partial
---
Partial
SUMMARY

# count_done_summaries should return 2 (complete + partial), not 3
DONE_COUNT=$(count_done_summaries "$SL_PHASE")
if [ "$DONE_COUNT" -eq 2 ]; then
  pass "statusline: count_done_summaries returns 2 (1 complete + 1 partial)"
else
  fail "statusline: count_done_summaries returns 2 (got $DONE_COUNT)"
fi

# count_complete_summaries should return 1 (only strict complete)
COMPLETE_COUNT=$(count_complete_summaries "$SL_PHASE")
if [ "$COMPLETE_COUNT" -eq 1 ]; then
  pass "statusline: count_complete_summaries returns 1 (only strict complete)"
else
  fail "statusline: count_complete_summaries returns 1 (got $COMPLETE_COUNT)"
fi

# Simulate the statusline reconciliation: EXEC_DONE=3 from JSON, _actual_done=2 from disk
EXEC_DONE=3
_actual_done="$DONE_COUNT"
if [ "${_actual_done:-0}" -lt "${EXEC_DONE:-0}" ] 2>/dev/null; then
  EXEC_DONE="$_actual_done"
fi
if [ "$EXEC_DONE" -eq 2 ]; then
  pass "statusline: EXEC_DONE capped from 3 to 2 (missing plan 02-03)"
else
  fail "statusline: EXEC_DONE capped from 3 to 2 (got $EXEC_DONE)"
fi

# --- Structural: JQ queries count partial as done ---
echo ""
echo "--- Structural: JQ queries count partial as done ---"

if grep -q 'select(.status == "complete" or .status == "partial")' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline JQ counts partial plans as done"
else
  fail "statusline JQ counts partial plans as done"
fi

if grep -q 'select(.status == "complete" or .status == "partial")' "$ROOT/scripts/session-start.sh"; then
  pass "session-start JQ counts partial plans as done"
else
  fail "session-start JQ counts partial plans as done"
fi

if grep -q 'select(.status == "complete" or .status == "partial")' "$ROOT/scripts/recover-state.sh"; then
  pass "recover-state JQ counts partial plans as done"
else
  fail "recover-state JQ counts partial plans as done"
fi

# --- Structural: count_done_summaries exists in summary-utils.sh ---
if grep -q 'count_done_summaries' "$ROOT/scripts/summary-utils.sh"; then
  pass "summary-utils.sh exports count_done_summaries function"
else
  fail "summary-utils.sh exports count_done_summaries function"
fi

# --- Structural: session-start accepts partial in reconciliation ---
if grep -q 'complete|completed|partial.*SUMMARY_COUNT' "$ROOT/scripts/session-start.sh"; then
  pass "session-start reconciliation accepts partial status"
else
  fail "session-start reconciliation accepts partial status"
fi

# --- Functional: literal "partial" in execution-state counted as done ---
echo ""
echo "--- Functional: literal partial JSON plan counted as done ---"

LP_PROJECT="$TMPDIR_BASE/lp-project/.vbw-planning"
LP_PHASE="$LP_PROJECT/phases/04-test"
mkdir -p "$LP_PHASE"

# state-updater.sh writes literal "partial" into execution-state JSON;
# the JQ query must count it as done alongside "complete"
cat > "$LP_PROJECT/.execution-state.json" <<'EXECJSON'
{
  "phase": 4, "status": "running",
  "wave": 1, "total_waves": 1,
  "plans": [
    {"id": "04-01", "title": "Plan 1", "wave": 1, "status": "complete"},
    {"id": "04-02", "title": "Plan 2", "wave": 1, "status": "partial"},
    {"id": "04-03", "title": "Plan 3", "wave": 1, "status": "pending"}
  ]
}
EXECJSON

# Both complete and partial disk SUMMARY files exist
cat > "$LP_PHASE/04-01-SUMMARY.md" <<'SUMMARY'
---
status: complete
---
Done
SUMMARY

cat > "$LP_PHASE/04-02-SUMMARY.md" <<'SUMMARY'
---
status: partial
---
Partial (crash during execution)
SUMMARY

# JQ query should return 2 (complete + partial)
LP_JSON_DONE=$(jq -r '[.plans[] | select(.status == "complete" or .status == "partial")] | length' "$LP_PROJECT/.execution-state.json" 2>/dev/null)
if [ "$LP_JSON_DONE" -eq 2 ]; then
  pass "literal partial: JQ counts 2 done (1 complete + 1 partial)"
else
  fail "literal partial: JQ counts 2 done (got $LP_JSON_DONE)"
fi

# Reconciliation should NOT reset partial plan (disk SUMMARY exists)
_lp_completed="[]"
for _sf in "$LP_PHASE"/*-SUMMARY.md; do
  [ -f "$_sf" ] || continue
  _sf_st=$(sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' "$_sf" 2>/dev/null | head -1 | tr -d '[:space:]')
  case "$_sf_st" in
    complete|completed|partial)
      _sf_id=$(basename "$_sf" | sed 's/-SUMMARY\.md$//')
      _lp_completed=$(echo "$_lp_completed" | jq --arg id "$_sf_id" '. + [$id]')
      ;;
  esac
done

LP_STATE="$LP_PROJECT/.execution-state.json"
_lp_tmp="${LP_STATE}.reconcile.$$"
jq --argjson completed "$_lp_completed" '
  .plans |= map(
    if (.status == "complete" or .status == "partial") and (.id as $pid | $completed | any(. == $pid) | not) then
      .status = "pending"
    else .
    end
  )
' "$LP_STATE" > "$_lp_tmp" 2>/dev/null && mv "$_lp_tmp" "$LP_STATE" 2>/dev/null

LP_P2_STATUS=$(jq -r '.plans[] | select(.id == "04-02") | .status' "$LP_STATE")
if [ "$LP_P2_STATUS" = "partial" ]; then
  pass "literal partial: plan 04-02 preserved (disk SUMMARY exists)"
else
  fail "literal partial: plan 04-02 preserved (got $LP_P2_STATUS)"
fi

# --- Functional: Phase parsing regression for "proof-of-concept" ---
echo ""
echo "--- Functional: Phase parsing handles 'of' in phase names ---"

# Test the same sed patterns used by statusline and session-start
_test_line="Phase: 2 of 4 (02-proof-of-concept)"

_parsed_ph=$(echo "$_test_line" | sed -n 's/^Phase:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
_parsed_tt=$(echo "$_test_line" | sed -n 's/.*[[:space:]]of[[:space:]]*\([0-9][0-9]*\).*/\1/p')

if [ "$_parsed_ph" = "2" ]; then
  pass "phase parsing: 'proof-of-concept' → phase number = 2"
else
  fail "phase parsing: 'proof-of-concept' → phase number = 2 (got '$_parsed_ph')"
fi

if [ "$_parsed_tt" = "4" ]; then
  pass "phase parsing: 'proof-of-concept' → phase total = 4"
else
  fail "phase parsing: 'proof-of-concept' → phase total = 4 (got '$_parsed_tt')"
fi

# Also test standard format
_std_line="Phase: 1 of 3 (01-context-diet)"
_std_ph=$(echo "$_std_line" | sed -n 's/^Phase:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
_std_tt=$(echo "$_std_line" | sed -n 's/.*[[:space:]]of[[:space:]]*\([0-9][0-9]*\).*/\1/p')

if [ "$_std_ph" = "1" ] && [ "$_std_tt" = "3" ]; then
  pass "phase parsing: standard format '1 of 3' parsed correctly"
else
  fail "phase parsing: standard format '1 of 3' parsed correctly (got ph='$_std_ph' tt='$_std_tt')"
fi

# Test single-phase (no "of") — graceful degradation
_single_line="Phase: 1 (01-monolith)"
_single_ph=$(echo "$_single_line" | sed -n 's/^Phase:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
_single_tt=$(echo "$_single_line" | sed -n 's/.*[[:space:]]of[[:space:]]*\([0-9][0-9]*\).*/\1/p')

if [ "$_single_ph" = "1" ] && [ -z "$_single_tt" ]; then
  pass "phase parsing: single phase (no 'of') → ph=1, tt=empty"
else
  fail "phase parsing: single phase (no 'of') → ph=1, tt=empty (got ph='$_single_ph' tt='$_single_tt')"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[ "$FAIL" -eq 0 ] || exit 1
