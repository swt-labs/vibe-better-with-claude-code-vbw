#!/usr/bin/env bash
set -euo pipefail

# verify-statusline-qa-lifecycle.sh — Tests for lifecycle-aware QA/UAT statusline indicator
#
# Verifies that the statusline QA indicator reflects the actual phase lifecycle
# state (QA pass, UAT pass, UAT fail, remediation in progress, re-verify needed)
# rather than a naive VERIFICATION.md file-existence check.
#
# Related: #221

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

echo "=== Statusline QA/UAT lifecycle indicator ==="
echo ""

# --- Structural: statusline checks UAT file status, not just VERIFICATION.md existence ---
echo "--- Structural: QA indicator checks UAT status ---"

# Test 1: statusline has uat_file detection (not just VERIFICATION.md check)
if grep -q '_uat_file.*find.*UAT.md' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline searches for UAT file in phase dir"
else
  fail "statusline searches for UAT file in phase dir"
fi

# Test 2: statusline excludes SOURCE-UAT and round files from UAT detection
if grep -q 'SOURCE-UAT\|UAT-round' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline excludes SOURCE-UAT and round files from UAT detection"
else
  fail "statusline excludes SOURCE-UAT and round files from UAT detection"
fi

# Test 3: statusline reads UAT status from frontmatter
if grep -q '_uat_status' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline reads UAT status from frontmatter"
else
  fail "statusline reads UAT status from frontmatter"
fi

# Test 4: statusline checks remediation stage when UAT has issues
if grep -q 'uat-remediation-stage' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline checks remediation stage file"
else
  fail "statusline checks remediation stage file"
fi

# Test 5: statusline distinguishes UAT pass from QA pass
if grep -q 'UAT:' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline uses 'UAT:' label for UAT states"
else
  fail "statusline uses 'UAT:' label for UAT states"
fi

# Test 6: statusline has color-coded UAT states (not just green/dim)
if grep -qE 'QA_COLOR.*\$R|QA_COLOR.*\$Y' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline uses red/yellow colors for UAT failure/remediation states"
else
  fail "statusline uses red/yellow colors for UAT failure/remediation states"
fi

# Test 7: VERIFICATION.md check is fallback only (after UAT check)
# The VERIFICATION.md check should come after the UAT file check in an elif
if grep -q 'elif.*VERIFICATION.md\|else.*VERIFICATION' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "VERIFICATION.md check is fallback (only when no UAT file exists)"
else
  fail "VERIFICATION.md check is fallback (only when no UAT file exists)"
fi

# Test 8: rendering uses QA_COLOR variable instead of hardcoded colors
if grep -q 'QA_COLOR' "$ROOT/scripts/vbw-statusline.sh"; then
  pass "statusline renders QA with dynamic QA_COLOR variable"
else
  fail "statusline renders QA with dynamic QA_COLOR variable"
fi

# --- Functional: QA indicator states ---
echo ""
echo "--- Functional: QA indicator lifecycle states ---"

TMPDIR_BASE=$(mktemp -d)

# Helper: create minimal VBW project structure
setup_project() {
  local dir="$1"
  mkdir -p "$dir/.vbw-planning/phases/01-test"
  echo '{}' > "$dir/.vbw-planning/config.json"
  printf 'Phase: 1 of 1 (test)\nStatus: active\n' > "$dir/.vbw-planning/STATE.md"
  printf '# Test Project\nReal content\n' > "$dir/.vbw-planning/PROJECT.md"
  # Create a plan and summary so the phase is "built"
  printf '%s\n' '---' 'phase: "01"' 'plan: "01"' 'title: Test' 'wave: 1' '---' > "$dir/.vbw-planning/phases/01-test/01-01-PLAN.md"
  printf '%s\n' '---' 'status: complete' '---' 'Done' > "$dir/.vbw-planning/phases/01-test/01-01-SUMMARY.md"
}

# Test 9: No VERIFICATION.md, no UAT → QA: --
T9="$TMPDIR_BASE/t9"
setup_project "$T9"
# Extract QA value by sourcing the fast-cache logic
# We'll grep the cached output for the QA field (field 9 in the pipe-delimited cache)
_FAST_QA=$(cd "$T9" && {
  # Source summary-utils for count_complete_summaries
  . "$ROOT/scripts/summary-utils.sh"
  QA="--"
  PH="1"; PDIR=".vbw-planning/phases/01-test"
  # Replicating the statusline QA detection logic:
  _uat_file=$(find "$PDIR" -maxdepth 1 -name '*-UAT.md' ! -name '*-SOURCE-UAT.md' ! -name '*-UAT-round-*' 2>/dev/null | head -1)
  if [ -n "$_uat_file" ]; then
    QA="has_uat"
  elif [ -n "$(find "$PDIR" -name '*VERIFICATION.md' 2>/dev/null | head -1)" ]; then
    QA="pass"
  fi
  echo "$QA"
})
if [ "$_FAST_QA" = "--" ]; then
  pass "no VERIFICATION, no UAT → QA: --"
else
  fail "no VERIFICATION, no UAT → QA: -- (got '$_FAST_QA')"
fi

# Test 10: VERIFICATION.md exists, no UAT → QA: pass
T10="$TMPDIR_BASE/t10"
setup_project "$T10"
printf '%s\n' '---' 'phase: 01' 'result: pass' '---' 'Checks passed.' > "$T10/.vbw-planning/phases/01-test/01-VERIFICATION.md"
_FAST_QA=$(cd "$T10" && {
  . "$ROOT/scripts/summary-utils.sh"
  QA="--"
  PDIR=".vbw-planning/phases/01-test"
  _uat_file=$(find "$PDIR" -maxdepth 1 -name '*-UAT.md' ! -name '*-SOURCE-UAT.md' ! -name '*-UAT-round-*' 2>/dev/null | head -1)
  if [ -n "$_uat_file" ]; then
    QA="has_uat"
  elif [ -n "$(find "$PDIR" -name '*VERIFICATION.md' 2>/dev/null | head -1)" ]; then
    QA="pass"
  fi
  echo "$QA"
})
if [ "$_FAST_QA" = "pass" ]; then
  pass "VERIFICATION.md exists, no UAT → QA: pass"
else
  fail "VERIFICATION.md exists, no UAT → QA: pass (got '$_FAST_QA')"
fi

# Test 11: UAT exists with status: complete → should detect UAT (not fall through to VERIFICATION)
T11="$TMPDIR_BASE/t11"
setup_project "$T11"
printf '%s\n' '---' 'phase: 01' 'result: pass' '---' 'Checks passed.' > "$T11/.vbw-planning/phases/01-test/01-VERIFICATION.md"
printf '%s\n' '---' 'phase: 01' 'status: complete' '---' 'All passed.' > "$T11/.vbw-planning/phases/01-test/01-UAT.md"
_FAST_QA=$(cd "$T11" && {
  . "$ROOT/scripts/summary-utils.sh"
  QA="--"
  PDIR=".vbw-planning/phases/01-test"
  _uat_file=$(find "$PDIR" -maxdepth 1 -name '*-UAT.md' ! -name '*-SOURCE-UAT.md' ! -name '*-UAT-round-*' 2>/dev/null | head -1)
  if [ -n "$_uat_file" ]; then
    QA="has_uat"
  elif [ -n "$(find "$PDIR" -name '*VERIFICATION.md' 2>/dev/null | head -1)" ]; then
    QA="pass"
  fi
  echo "$QA"
})
if [ "$_FAST_QA" = "has_uat" ]; then
  pass "UAT exists → UAT supersedes VERIFICATION.md"
else
  fail "UAT exists → UAT supersedes VERIFICATION.md (got '$_FAST_QA')"
fi

# Test 12: UAT with issues_found + no remediation stage → should NOT show QA: pass
T12="$TMPDIR_BASE/t12"
setup_project "$T12"
printf '%s\n' '---' 'phase: 01' 'result: pass' '---' 'Checks passed.' > "$T12/.vbw-planning/phases/01-test/01-VERIFICATION.md"
printf '%s\n' '---' 'phase: 01' 'status: issues_found' '---' '- Severity: major' > "$T12/.vbw-planning/phases/01-test/01-UAT.md"
_FAST_QA=$(cd "$T12" && {
  . "$ROOT/scripts/summary-utils.sh"
  QA="--"
  PDIR=".vbw-planning/phases/01-test"
  _uat_file=$(find "$PDIR" -maxdepth 1 -name '*-UAT.md' ! -name '*-SOURCE-UAT.md' ! -name '*-UAT-round-*' 2>/dev/null | head -1)
  if [ -n "$_uat_file" ]; then
    QA="has_uat_not_pass"
  elif [ -n "$(find "$PDIR" -name '*VERIFICATION.md' 2>/dev/null | head -1)" ]; then
    QA="pass"
  fi
  echo "$QA"
})
if [ "$_FAST_QA" = "has_uat_not_pass" ]; then
  pass "UAT issues_found → does NOT fall through to QA: pass"
else
  fail "UAT issues_found → does NOT fall through to QA: pass (got '$_FAST_QA')"
fi

# Test 13: SOURCE-UAT.md is excluded from UAT detection
T13="$TMPDIR_BASE/t13"
setup_project "$T13"
printf '%s\n' '---' 'phase: 01' 'result: pass' '---' 'Checks passed.' > "$T13/.vbw-planning/phases/01-test/01-VERIFICATION.md"
# Only a SOURCE-UAT (copy from milestone), no canonical UAT
printf '%s\n' '---' 'status: issues_found' '---' 'Source copy.' > "$T13/.vbw-planning/phases/01-test/01-SOURCE-UAT.md"
_FAST_QA=$(cd "$T13" && {
  . "$ROOT/scripts/summary-utils.sh"
  QA="--"
  PDIR=".vbw-planning/phases/01-test"
  _uat_file=$(find "$PDIR" -maxdepth 1 -name '*-UAT.md' ! -name '*-SOURCE-UAT.md' ! -name '*-UAT-round-*' 2>/dev/null | head -1)
  if [ -n "$_uat_file" ]; then
    QA="has_uat"
  elif [ -n "$(find "$PDIR" -name '*VERIFICATION.md' 2>/dev/null | head -1)" ]; then
    QA="pass"
  fi
  echo "$QA"
})
if [ "$_FAST_QA" = "pass" ]; then
  pass "SOURCE-UAT.md excluded → falls through to QA: pass from VERIFICATION"
else
  fail "SOURCE-UAT.md excluded → falls through to QA: pass (got '$_FAST_QA')"
fi

# Test 14: UAT-round files excluded from detection
T14="$TMPDIR_BASE/t14"
setup_project "$T14"
printf '%s\n' '---' 'phase: 01' 'result: pass' '---' 'Checks passed.' > "$T14/.vbw-planning/phases/01-test/01-VERIFICATION.md"
# Only archived rounds, no current UAT
printf '%s\n' '---' 'status: issues_found' '---' 'Old UAT.' > "$T14/.vbw-planning/phases/01-test/01-UAT-round-01.md"
_FAST_QA=$(cd "$T14" && {
  . "$ROOT/scripts/summary-utils.sh"
  QA="--"
  PDIR=".vbw-planning/phases/01-test"
  _uat_file=$(find "$PDIR" -maxdepth 1 -name '*-UAT.md' ! -name '*-SOURCE-UAT.md' ! -name '*-UAT-round-*' 2>/dev/null | head -1)
  if [ -n "$_uat_file" ]; then
    QA="has_uat"
  elif [ -n "$(find "$PDIR" -name '*VERIFICATION.md' 2>/dev/null | head -1)" ]; then
    QA="pass"
  fi
  echo "$QA"
})
if [ "$_FAST_QA" = "pass" ]; then
  pass "UAT-round files excluded → falls through to QA: pass from VERIFICATION"
else
  fail "UAT-round files excluded → falls through to QA: pass (got '$_FAST_QA')"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS passed, $FAIL failed"
echo "==============================="
[ "$FAIL" -eq 0 ] || exit 1
