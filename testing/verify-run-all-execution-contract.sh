#!/usr/bin/env bash
set -euo pipefail

# verify-run-all-execution-contract.sh — Guard AGENTS.md against removing the
# no-tail / no-wrapper guidance for run-all.sh execution.
# Checks AGENTS.md (committed artifact) rather than .github/agents/ (local-only).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS_MD="$ROOT/AGENTS.md"

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

# AGENTS.md must contain the no-tail guidance specifically for run-all.sh
if grep -Eiq 'run-all\.sh' "$AGENTS_MD" && grep -Eiq 'do not pipe.*tail|do not pipe.*tee' "$AGENTS_MD"; then
  pass "AGENTS.md: contains no-pipe/no-tail directive for run-all.sh"
else
  fail "AGENTS.md: missing no-pipe/no-tail directive for run-all.sh"
fi

if grep -Eiq 'tail -20|tail -40' "$AGENTS_MD"; then
  pass "AGENTS.md: includes concrete tail wrapper examples"
else
  fail "AGENTS.md: missing concrete tail wrapper examples"
fi

if grep -Eiq 'buffer until EOF|buffer until eof|hide live progress' "$AGENTS_MD"; then
  pass "AGENTS.md: explains why tail wrappers are unsafe"
else
  fail "AGENTS.md: missing rationale for no-tail execution"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="
[ "$FAIL" -eq 0 ] || exit 1