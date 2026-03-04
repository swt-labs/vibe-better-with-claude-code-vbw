#!/usr/bin/env bash
set -euo pipefail

# verify-summary-status-contract.sh — Tests for SUMMARY.md status contract and helpers
#
# Verifies:
# - Status enum validation (is_valid_summary_status)
# - Completion status logic (is_completion_status)
# - Frontmatter status extraction (extract_summary_status)
# - Plan completion detection (is_plan_completed, is_plan_finalized)
# - Completed/finalized summary counting (count_completed_summaries, count_finalized_summaries)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/scripts/lib/summary-status.sh"

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

# Source the library under test
if [ ! -f "$LIB" ]; then
  echo "ERROR: $LIB not found"
  exit 1
fi
# shellcheck source=../scripts/lib/summary-status.sh
source "$LIB"

echo "=== Summary Status Contract Tests ==="

# ===== is_valid_summary_status =====

echo ""
echo "--- is_valid_summary_status ---"

if is_valid_summary_status "complete"; then
  pass "is_valid_summary_status 'complete' -> 0"
else
  fail "is_valid_summary_status 'complete' -> expected 0, got 1"
fi

if is_valid_summary_status "partial"; then
  pass "is_valid_summary_status 'partial' -> 0"
else
  fail "is_valid_summary_status 'partial' -> expected 0, got 1"
fi

if is_valid_summary_status "failed"; then
  pass "is_valid_summary_status 'failed' -> 0"
else
  fail "is_valid_summary_status 'failed' -> expected 0, got 1"
fi

if is_valid_summary_status "pending"; then
  fail "is_valid_summary_status 'pending' -> expected 1, got 0"
else
  pass "is_valid_summary_status 'pending' -> 1"
fi

if is_valid_summary_status "completed"; then
  fail "is_valid_summary_status 'completed' -> expected 1, got 0"
else
  pass "is_valid_summary_status 'completed' -> 1"
fi

if is_valid_summary_status ""; then
  fail "is_valid_summary_status '' -> expected 1, got 0"
else
  pass "is_valid_summary_status '' -> 1"
fi

if is_valid_summary_status "COMPLETE"; then
  fail "is_valid_summary_status 'COMPLETE' -> expected 1, got 0 (case-sensitive)"
else
  pass "is_valid_summary_status 'COMPLETE' -> 1 (case-sensitive at function level)"
fi

if is_valid_summary_status "in_progress"; then
  fail "is_valid_summary_status 'in_progress' -> expected 1, got 0"
else
  pass "is_valid_summary_status 'in_progress' -> 1"
fi

# ===== is_completion_status =====

echo ""
echo "--- is_completion_status ---"

if is_completion_status "complete"; then
  pass "is_completion_status 'complete' -> 0"
else
  fail "is_completion_status 'complete' -> expected 0, got 1"
fi

if is_completion_status "partial"; then
  pass "is_completion_status 'partial' -> 0"
else
  fail "is_completion_status 'partial' -> expected 0, got 1"
fi

if is_completion_status "failed"; then
  fail "is_completion_status 'failed' -> expected 1, got 0 (failed is not a completion status)"
else
  pass "is_completion_status 'failed' -> 1 (not a progression-complete status)"
fi

if is_completion_status "pending"; then
  fail "is_completion_status 'pending' -> expected 1, got 0"
else
  pass "is_completion_status 'pending' -> 1"
fi

if is_completion_status ""; then
  fail "is_completion_status '' -> expected 1, got 0"
else
  pass "is_completion_status '' -> 1"
fi

# ===== extract_summary_status =====

echo ""
echo "--- extract_summary_status ---"

TMPDIR_BASE=$(mktemp -d)

# Valid complete status
cat > "$TMPDIR_BASE/summary-complete.md" <<'EOF'
---
phase: 01
plan: 01
title: Test Plan
status: complete
completed: 2026-03-01
tasks_completed: 3
tasks_total: 3
---

Built the thing.
EOF

rc=0; result=$(extract_summary_status "$TMPDIR_BASE/summary-complete.md") || rc=$?
if [ "$result" = "complete" ] && [ "$rc" -eq 0 ]; then
  pass "extract_summary_status: status: complete -> 'complete', exit 0"
else
  fail "extract_summary_status: status: complete -> got '$result' (rc=$rc), expected 'complete' (rc=0)"
fi

# Pending status (invalid)
cat > "$TMPDIR_BASE/summary-pending.md" <<'EOF'
---
phase: 01
plan: 01
title: Test Plan
status: pending
---

Pending execution.
EOF

rc=0; result=$(extract_summary_status "$TMPDIR_BASE/summary-pending.md") || rc=$?
if [ "$result" = "pending" ] && [ "$rc" -eq 1 ]; then
  pass "extract_summary_status: status: pending -> 'pending', exit 1"
else
  fail "extract_summary_status: status: pending -> got '$result' (rc=$rc), expected 'pending' (rc=1)"
fi

# Mixed case (Completed)
cat > "$TMPDIR_BASE/summary-mixedcase.md" <<'EOF'
---
phase: 01
plan: 01
status: Completed
---

Done.
EOF

rc=0; result=$(extract_summary_status "$TMPDIR_BASE/summary-mixedcase.md") || rc=$?
if [ "$result" = "completed" ] && [ "$rc" -eq 1 ]; then
  pass "extract_summary_status: status: Completed -> 'completed' (lowered), exit 1"
else
  fail "extract_summary_status: status: Completed -> got '$result' (rc=$rc), expected 'completed' (rc=1)"
fi

# No status field
cat > "$TMPDIR_BASE/summary-nostatus.md" <<'EOF'
---
phase: 01
plan: 01
title: Test Plan
---

No status here.
EOF

rc=0; result=$(extract_summary_status "$TMPDIR_BASE/summary-nostatus.md") || rc=$?
if [ "$result" = "" ] && [ "$rc" -eq 1 ]; then
  pass "extract_summary_status: no status field -> '', exit 1"
else
  fail "extract_summary_status: no status field -> got '$result' (rc=$rc), expected '' (rc=1)"
fi

# Non-existent file
rc=0; result=$(extract_summary_status "$TMPDIR_BASE/does-not-exist.md") || rc=$?
if [ "$result" = "" ] && [ "$rc" -eq 1 ]; then
  pass "extract_summary_status: non-existent file -> '', exit 1"
else
  fail "extract_summary_status: non-existent file -> got '$result' (rc=$rc), expected '' (rc=1)"
fi

# Partial status
cat > "$TMPDIR_BASE/summary-partial.md" <<'EOF'
---
phase: 01
plan: 01
status: partial
---

Partial completion.
EOF

rc=0; result=$(extract_summary_status "$TMPDIR_BASE/summary-partial.md") || rc=$?
if [ "$result" = "partial" ] && [ "$rc" -eq 0 ]; then
  pass "extract_summary_status: status: partial -> 'partial', exit 0"
else
  fail "extract_summary_status: status: partial -> got '$result' (rc=$rc), expected 'partial' (rc=0)"
fi

# Failed status
cat > "$TMPDIR_BASE/summary-failed.md" <<'EOF'
---
phase: 01
plan: 01
status: failed
---

Failed.
EOF

rc=0; result=$(extract_summary_status "$TMPDIR_BASE/summary-failed.md") || rc=$?
if [ "$result" = "failed" ] && [ "$rc" -eq 0 ]; then
  pass "extract_summary_status: status: failed -> 'failed', exit 0"
else
  fail "extract_summary_status: status: failed -> got '$result' (rc=$rc), expected 'failed' (rc=0)"
fi

# No frontmatter at all
cat > "$TMPDIR_BASE/summary-nofm.md" <<'EOF'
# Just a markdown file

No frontmatter here.
EOF

rc=0; result=$(extract_summary_status "$TMPDIR_BASE/summary-nofm.md") || rc=$?
if [ "$result" = "" ] && [ "$rc" -eq 1 ]; then
  pass "extract_summary_status: no frontmatter -> '', exit 1"
else
  fail "extract_summary_status: no frontmatter -> got '$result' (rc=$rc), expected '' (rc=1)"
fi

# ===== is_plan_completed =====

echo ""
echo "--- is_plan_completed ---"

if is_plan_completed "$TMPDIR_BASE/summary-complete.md"; then
  pass "is_plan_completed: status: complete -> 0"
else
  fail "is_plan_completed: status: complete -> expected 0"
fi

if is_plan_completed "$TMPDIR_BASE/summary-partial.md"; then
  pass "is_plan_completed: status: partial -> 0"
else
  fail "is_plan_completed: status: partial -> expected 0"
fi

if is_plan_completed "$TMPDIR_BASE/summary-failed.md"; then
  fail "is_plan_completed: status: failed -> expected 1 (not a completion status)"
else
  pass "is_plan_completed: status: failed -> 1 (not progression-complete)"
fi

if is_plan_completed "$TMPDIR_BASE/summary-pending.md"; then
  fail "is_plan_completed: status: pending -> expected 1"
else
  pass "is_plan_completed: status: pending -> 1"
fi

if is_plan_completed "$TMPDIR_BASE/does-not-exist.md"; then
  fail "is_plan_completed: non-existent file -> expected 1"
else
  pass "is_plan_completed: non-existent file -> 1"
fi

if is_plan_completed "$TMPDIR_BASE/summary-nostatus.md"; then
  fail "is_plan_completed: no status field -> expected 1"
else
  pass "is_plan_completed: no status field -> 1"
fi

# ===== is_plan_finalized =====

echo ""
echo "--- is_plan_finalized ---"

if is_plan_finalized "$TMPDIR_BASE/summary-complete.md"; then
  pass "is_plan_finalized: status: complete -> 0"
else
  fail "is_plan_finalized: status: complete -> expected 0"
fi

if is_plan_finalized "$TMPDIR_BASE/summary-failed.md"; then
  pass "is_plan_finalized: status: failed -> 0 (failed is terminal)"
else
  fail "is_plan_finalized: status: failed -> expected 0"
fi

if is_plan_finalized "$TMPDIR_BASE/summary-pending.md"; then
  fail "is_plan_finalized: status: pending -> expected 1"
else
  pass "is_plan_finalized: status: pending -> 1"
fi

if is_plan_finalized "$TMPDIR_BASE/does-not-exist.md"; then
  fail "is_plan_finalized: non-existent -> expected 1"
else
  pass "is_plan_finalized: non-existent -> 1"
fi

# ===== count_completed_summaries =====

echo ""
echo "--- count_completed_summaries ---"

PHASE_DIR="$TMPDIR_BASE/phase-test"
mkdir -p "$PHASE_DIR"

# Create a mix: complete, partial, pending, failed
cat > "$PHASE_DIR/01-01-SUMMARY.md" <<'EOF'
---
status: complete
---
Done.
EOF

cat > "$PHASE_DIR/01-02-SUMMARY.md" <<'EOF'
---
status: partial
---
Partial.
EOF

cat > "$PHASE_DIR/01-03-SUMMARY.md" <<'EOF'
---
status: pending
---
Stub.
EOF

cat > "$PHASE_DIR/01-04-SUMMARY.md" <<'EOF'
---
status: failed
---
Failed.
EOF

count=$(count_completed_summaries "$PHASE_DIR")
if [ "$count" -eq 2 ]; then
  pass "count_completed_summaries: 4 files (complete, partial, pending, failed) -> 2"
else
  fail "count_completed_summaries: expected 2, got $count"
fi

# ===== count_finalized_summaries =====

echo ""
echo "--- count_finalized_summaries ---"

count=$(count_finalized_summaries "$PHASE_DIR")
if [ "$count" -eq 3 ]; then
  pass "count_finalized_summaries: 4 files (complete, partial, pending, failed) -> 3"
else
  fail "count_finalized_summaries: expected 3, got $count"
fi

# Empty directory
EMPTY_DIR="$TMPDIR_BASE/phase-empty"
mkdir -p "$EMPTY_DIR"

count=$(count_completed_summaries "$EMPTY_DIR")
if [ "$count" -eq 0 ]; then
  pass "count_completed_summaries: empty directory -> 0"
else
  fail "count_completed_summaries: empty directory -> expected 0, got $count"
fi

# All complete
ALL_COMPLETE_DIR="$TMPDIR_BASE/phase-allcomplete"
mkdir -p "$ALL_COMPLETE_DIR"

cat > "$ALL_COMPLETE_DIR/02-01-SUMMARY.md" <<'EOF'
---
status: complete
---
Done 1.
EOF

cat > "$ALL_COMPLETE_DIR/02-02-SUMMARY.md" <<'EOF'
---
status: complete
---
Done 2.
EOF

count=$(count_completed_summaries "$ALL_COMPLETE_DIR")
if [ "$count" -eq 2 ]; then
  pass "count_completed_summaries: 2 complete files -> 2"
else
  fail "count_completed_summaries: 2 complete files -> expected 2, got $count"
fi

# ===== Double-source guard =====

echo ""
echo "--- Double-source guard ---"

# Source the lib again — should be a no-op (guard prevents re-init)
source "$LIB"
if is_valid_summary_status "complete"; then
  pass "Double-source: functions still work after re-sourcing"
else
  fail "Double-source: functions broken after re-sourcing"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All summary status contract checks passed."
exit 0
