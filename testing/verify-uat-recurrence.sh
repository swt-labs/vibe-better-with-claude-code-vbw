#!/usr/bin/env bash
# verify-uat-recurrence.sh — Contract tests for UAT recurrence tracking feature.
# Verifies structural assertions across verify.md, extract-uat-issues.sh, vibe.md,
# and uat-utils.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
TOTAL=0

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "FAIL: $1"; }

# Part 1: Anti-breakout guardrail in verify.md

if grep -q "CRITICAL BOUNDARY" "$PROJECT_ROOT/commands/verify.md"; then
  pass "verify.md: CRITICAL BOUNDARY block present in Step 5"
else
  fail "verify.md: CRITICAL BOUNDARY block missing"
fi

if grep -q "MUST NOT investigate, debug, or implement fixes during the UAT session" "$PROJECT_ROOT/commands/verify.md"; then
  pass "verify.md: anti-breakout prohibition language present"
else
  fail "verify.md: anti-breakout prohibition language missing"
fi

if grep -q "Issue recorded.*remaining checkpoints.*remediation" "$PROJECT_ROOT/commands/verify.md"; then
  pass "verify.md: scripted deflection response present"
else
  fail "verify.md: scripted deflection response missing"
fi

# Part 2: Recurrence tracking in extract-uat-issues.sh

if grep -q "FAILED_IN_ROUNDS" "$PROJECT_ROOT/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh: FAILED_IN_ROUNDS field referenced"
else
  fail "extract-uat-issues.sh: FAILED_IN_ROUNDS field missing"
fi

if grep -q "uat_round=" "$PROJECT_ROOT/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh: uat_round header field present"
else
  fail "extract-uat-issues.sh: uat_round header field missing"
fi

if grep -q "count_uat_rounds" "$PROJECT_ROOT/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh: uses count_uat_rounds from uat-utils"
else
  fail "extract-uat-issues.sh: missing count_uat_rounds usage"
fi

if grep -q "extract_round_issue_ids" "$PROJECT_ROOT/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh: uses extract_round_issue_ids from uat-utils"
else
  fail "extract-uat-issues.sh: missing extract_round_issue_ids usage"
fi

# Part 2b: uat-utils.sh helpers

if grep -q "^count_uat_rounds()" "$PROJECT_ROOT/scripts/uat-utils.sh"; then
  pass "uat-utils.sh: count_uat_rounds function defined"
else
  fail "uat-utils.sh: count_uat_rounds function missing"
fi

if grep -q "^extract_round_issue_ids()" "$PROJECT_ROOT/scripts/uat-utils.sh"; then
  pass "uat-utils.sh: extract_round_issue_ids function defined"
else
  fail "uat-utils.sh: extract_round_issue_ids function missing"
fi

# Part 2c: No Bash 4+ features (associative arrays)
if grep -q 'declare -A' "$PROJECT_ROOT/scripts/extract-uat-issues.sh"; then
  fail "extract-uat-issues.sh: uses 'declare -A' (Bash 4+ only, breaks macOS 3.2)"
else
  pass "extract-uat-issues.sh: no Bash 4+ associative arrays"
fi

# Part 3: Recurrence-aware remediation in vibe.md

if grep -q "FAILED_IN_ROUNDS" "$PROJECT_ROOT/commands/vibe.md"; then
  pass "vibe.md: FAILED_IN_ROUNDS field referenced in UAT Remediation"
else
  fail "vibe.md: FAILED_IN_ROUNDS field not referenced"
fi

if grep -q "failure_count descending" "$PROJECT_ROOT/commands/vibe.md"; then
  pass "vibe.md: priority ordering by failure_count descending"
else
  fail "vibe.md: priority ordering directive missing"
fi

if grep -q "RECURRING" "$PROJECT_ROOT/commands/vibe.md"; then
  pass "vibe.md: RECURRING annotation directive present"
else
  fail "vibe.md: RECURRING annotation directive missing"
fi

if grep -q "uat_round >= 3" "$PROJECT_ROOT/commands/vibe.md"; then
  pass "vibe.md: round-based escalation threshold (>= 3) present"
else
  fail "vibe.md: round-based escalation threshold missing"
fi

if grep -q "Investigate WHY previous fixes failed" "$PROJECT_ROOT/commands/vibe.md"; then
  pass "vibe.md: Scout root-cause investigation directive present"
else
  fail "vibe.md: Scout root-cause investigation directive missing"
fi

if grep -q "Prioritize recurring failures" "$PROJECT_ROOT/commands/vibe.md"; then
  pass "vibe.md: Lead priority directive present"
else
  fail "vibe.md: Lead priority directive missing"
fi

echo ""
echo "TOTAL: $PASS PASS, $FAIL FAIL out of $TOTAL"
[ "$FAIL" -eq 0 ]
