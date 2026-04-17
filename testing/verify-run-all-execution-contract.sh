#!/usr/bin/env bash
set -euo pipefail

# verify-run-all-execution-contract.sh — Guard issue workflow prompts against
# reintroducing tail-wrapped run-all.sh execution in shared terminals.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX_AGENT="$ROOT/.github/agents/fix-issue.agent.md"
REVIEW_AGENT="$ROOT/.github/agents/review-contributor-pr.agent.md"

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

echo "=== run-all Execution Contract Verification ==="

# fix-issue agent checks
if grep -Eiq 'execute tool.*run-all\.sh|run-all\.sh.*execute tool|use the `execute` tool' "$FIX_AGENT"; then
  pass "fix-issue.agent.md: prefers execute tool for authoritative run-all"
else
  fail "fix-issue.agent.md: missing execute-tool preference for authoritative run-all"
fi

if grep -Eiq 'tail -20|tail -40|tail -60|tail -80' "$FIX_AGENT"; then
  pass "fix-issue.agent.md: includes concrete tail wrapper examples"
else
  fail "fix-issue.agent.md: missing concrete tail wrapper examples"
fi

if grep -Eiq 'buffer until EOF|buffer until eof|look idle|look hung|shared-terminal|shared terminal|isolates process state|preserves the real exit code' "$FIX_AGENT"; then
  pass "fix-issue.agent.md: explains why wrapped/shared-terminal run-all execution is unsafe"
else
  fail "fix-issue.agent.md: missing rationale for no-tail isolated run-all execution"
fi

# review-contributor-pr agent checks
if grep -Eiq 'execute tool.*run-all\.sh|run-all\.sh.*execute tool|use the `execute` tool' "$REVIEW_AGENT"; then
  pass "review-contributor-pr.agent.md: prefers execute tool for authoritative run-all"
else
  fail "review-contributor-pr.agent.md: missing execute-tool preference for authoritative run-all"
fi

if grep -Eiq 'tail -20|tail -40|tail -60|tail -80' "$REVIEW_AGENT"; then
  pass "review-contributor-pr.agent.md: includes concrete tail wrapper examples"
else
  fail "review-contributor-pr.agent.md: missing concrete tail wrapper examples"
fi

if grep -Eiq 'buffer until EOF|buffer until eof|look idle|look hung|shared-terminal|shared terminal|preserves the real exit code' "$REVIEW_AGENT"; then
  pass "review-contributor-pr.agent.md: explains why wrapped/shared-terminal run-all execution is unsafe"
else
  fail "review-contributor-pr.agent.md: missing rationale for no-tail isolated run-all execution"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="
[ "$FAIL" -eq 0 ] || exit 1