#!/usr/bin/env bash
set -euo pipefail

# verify-uat-recurrence.sh — Structural assertions for UAT anti-breakout
# guardrail, recurrence tracking, and priority-ranked remediation.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# =========================================================================
# Part 1: Anti-breakout guardrail in verify.md Step 5
# =========================================================================

# Test 1: verify.md contains CRITICAL BOUNDARY block
if grep -q 'CRITICAL BOUNDARY' "$SCRIPT_DIR/commands/verify.md"; then
  pass "verify.md contains CRITICAL BOUNDARY block"
else
  fail "verify.md missing CRITICAL BOUNDARY block"
fi

# Test 2: Anti-breakout block is in Step 5 (CHECKPOINT loop)
STEP5_LINE=$(grep -n 'CHECKPOINT loop' "$SCRIPT_DIR/commands/verify.md" | head -1 | cut -d: -f1)
BOUNDARY_LINE=$(grep -n 'CRITICAL BOUNDARY' "$SCRIPT_DIR/commands/verify.md" | head -1 | cut -d: -f1)
if [ -n "$STEP5_LINE" ] && [ -n "$BOUNDARY_LINE" ] && [ "$BOUNDARY_LINE" -gt "$STEP5_LINE" ]; then
  pass "CRITICAL BOUNDARY is inside Step 5 CHECKPOINT loop"
else
  fail "CRITICAL BOUNDARY should be inside Step 5 CHECKPOINT loop"
fi

# Test 3: Anti-breakout mentions recording and advancing
if grep -A5 'CRITICAL BOUNDARY' "$SCRIPT_DIR/commands/verify.md" | grep -qi 'record.*advance\|advance.*checkpoint\|remaining checkpoints'; then
  pass "Anti-breakout mentions recording and advancing to next checkpoint"
else
  fail "Anti-breakout should mention recording and advancing"
fi

# Test 4: Anti-breakout blocks investigation/debugging during UAT
if grep -A5 'CRITICAL BOUNDARY' "$SCRIPT_DIR/commands/verify.md" | grep -qi 'MUST NOT investigate.*debug\|MUST NOT.*implement fix'; then
  pass "Anti-breakout blocks investigation/debugging during UAT"
else
  fail "Anti-breakout should block investigation/debugging during UAT"
fi

# =========================================================================
# Part 2: Recurrence tracking in extract-uat-issues.sh
# =========================================================================

# Test 5: extract-uat-issues.sh outputs FAILED_IN_ROUNDS field
if grep -q 'FAILED_IN_ROUNDS' "$SCRIPT_DIR/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh references FAILED_IN_ROUNDS"
else
  fail "extract-uat-issues.sh missing FAILED_IN_ROUNDS support"
fi

# Test 6: extract-uat-issues.sh includes uat_round in header
if grep -q 'uat_round=' "$SCRIPT_DIR/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh includes uat_round in header"
else
  fail "extract-uat-issues.sh missing uat_round in header"
fi

# Test 7: extract-uat-issues.sh calls count_uat_rounds
if grep -q 'count_uat_rounds' "$SCRIPT_DIR/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh calls count_uat_rounds for round computation"
else
  fail "extract-uat-issues.sh should call count_uat_rounds"
fi

# Test 8: extract-uat-issues.sh calls extract_round_issue_ids
if grep -q 'extract_round_issue_ids' "$SCRIPT_DIR/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh calls extract_round_issue_ids for recurrence scanning"
else
  fail "extract-uat-issues.sh should call extract_round_issue_ids"
fi

# Test 9: uat-utils.sh has extract_round_issue_ids function
if grep -q 'extract_round_issue_ids()' "$SCRIPT_DIR/scripts/uat-utils.sh"; then
  pass "uat-utils.sh has extract_round_issue_ids function"
else
  fail "uat-utils.sh missing extract_round_issue_ids function"
fi

# =========================================================================
# Part 3: Priority-ranked remediation in vibe.md
# =========================================================================

# Test 10: vibe.md UAT Remediation references FAILED_IN_ROUNDS
if grep -q 'FAILED_IN_ROUNDS' "$SCRIPT_DIR/commands/vibe.md"; then
  pass "vibe.md UAT Remediation references FAILED_IN_ROUNDS"
else
  fail "vibe.md UAT Remediation missing FAILED_IN_ROUNDS reference"
fi

# Test 11: vibe.md has phase-level escalation (uat_round >= 3)
if grep -q 'uat_round >= 3' "$SCRIPT_DIR/commands/vibe.md"; then
  pass "vibe.md has phase-level escalation at uat_round >= 3"
else
  fail "vibe.md missing phase-level escalation threshold"
fi

# Test 12: vibe.md has per-test priority ranking by failure_count
if grep -q 'failure_count descending' "$SCRIPT_DIR/commands/vibe.md"; then
  pass "vibe.md has per-test priority ranking by failure_count descending"
else
  fail "vibe.md missing per-test priority ranking"
fi

# Test 13: vibe.md has RECURRING annotation for failure_count >= 2
if grep -q 'RECURRING' "$SCRIPT_DIR/commands/vibe.md" && grep -q 'failure_count >= 2' "$SCRIPT_DIR/commands/vibe.md"; then
  pass "vibe.md has RECURRING annotation for failure_count >= 2"
else
  fail "vibe.md missing RECURRING annotation logic"
fi

# Test 14: vibe.md Scout prompt includes prior-fix investigation directive
if grep -q 'Investigate WHY previous fixes failed' "$SCRIPT_DIR/commands/vibe.md"; then
  pass "vibe.md Scout prompt includes prior-fix investigation directive"
else
  fail "vibe.md Scout prompt missing prior-fix investigation directive"
fi

# Test 15: vibe.md Lead prompt includes prioritization directive
if grep -q 'Prioritize recurring failures' "$SCRIPT_DIR/commands/vibe.md"; then
  pass "vibe.md Lead prompt includes prioritization directive for recurring issues"
else
  fail "vibe.md Lead prompt missing prioritization directive"
fi

# Test 16: vibe.md remediation summary includes per-test recurrence
if grep -q 'per-test recurrence' "$SCRIPT_DIR/commands/vibe.md"; then
  pass "vibe.md remediation summary includes per-test recurrence"
else
  fail "vibe.md remediation summary missing per-test recurrence"
fi

# =========================================================================
echo ""
echo "==============================="
echo "TOTAL: $PASS_COUNT PASS, $FAIL_COUNT FAIL"
echo "==============================="
[ "$FAIL_COUNT" -eq 0 ]
