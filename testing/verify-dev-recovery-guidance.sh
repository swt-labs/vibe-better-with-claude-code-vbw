#!/usr/bin/env bash
set -euo pipefail

# verify-dev-recovery-guidance.sh — Verify vbw-dev.md has deterministic recovery rules
#
# Checks that the Dev agent prompt includes explicit recovery guidance for:
# - Read-before-edit tool precondition errors
# - Live-validation contradiction / empty-result handling
# - Reread/no-progress loop detection

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV_FILE="$ROOT/agents/vbw-dev.md"

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

echo "=== Dev Agent Recovery Guidance Verification ==="

# 1. Read-before-edit recovery
if grep -qi 'read.*before.*edit\|read.*before.*writ\|file has not been read\|read the target file' "$DEV_FILE"; then
  pass "vbw-dev.md: mentions read-before-edit recovery"
else
  fail "vbw-dev.md: missing read-before-edit recovery guidance"
fi

# 2. Retry-once-then-escalate pattern
if grep -qi 'retry.*once\|retry the.*edit\|retry the.*write\|one retry' "$DEV_FILE"; then
  pass "vbw-dev.md: mentions retry-once pattern for tool precondition errors"
else
  fail "vbw-dev.md: missing retry-once-then-escalate for tool precondition errors"
fi

# 3. Validation contradiction as blocker
if grep -qi 'contradicts\|contradiction.*blocker\|contradictory.*validation\|contradictory.*result' "$DEV_FILE"; then
  pass "vbw-dev.md: mentions validation contradiction as blocker"
else
  fail "vbw-dev.md: missing validation-contradiction-as-blocker guidance"
fi

# 4. Empty results as potential blocker
if grep -qi 'empty.*result.*blocker\|empty.*response.*blocker\|empty.*result.*escalat\|empty.*validation.*stop\|empty.*result.*not.*success\|empty results are not success' "$DEV_FILE"; then
  pass "vbw-dev.md: mentions empty validation results as blocker condition"
else
  fail "vbw-dev.md: missing empty-result-as-blocker guidance"
fi

# 5. Reread/no-progress loop detection
if grep -qi 'reread.*loop\|no.progress.*loop\|rereading.*same.*file\|read.*loop.*circuit\|no forward progress' "$DEV_FILE"; then
  pass "vbw-dev.md: mentions reread/no-progress loop detection"
else
  fail "vbw-dev.md: missing reread/no-progress loop detection guidance"
fi

# 6. Reread loop counted as circuit-breaker condition
if grep -qi 'no.progress.*escalat\|reread.*escalat\|no.progress.*blocker\|reread.*blocker\|two consecutive.*no.progress' "$DEV_FILE"; then
  pass "vbw-dev.md: reread loops trigger escalation"
else
  fail "vbw-dev.md: reread loops not linked to escalation/blocker"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="
[ "$FAIL" -eq 0 ] || exit 1
