#!/usr/bin/env bash
set -euo pipefail

# verify-run-all-execution-contract.sh — Guard CONTRIBUTING.md against removing the
# no-tail / no-wrapper guidance for run-all.sh execution.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/CONTRIBUTING.md"

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

if [[ ! -f "$TARGET" ]]; then
  echo "SKIP  CONTRIBUTING.md not found — nothing to verify"
  exit 0
fi

# CONTRIBUTING.md must contain the no-tail guidance specifically for run-all.sh
if grep -Eiq 'run-all\.sh' "$TARGET" && grep -Eiq 'do not pipe.*tail|do not pipe.*tee' "$TARGET"; then
  pass "CONTRIBUTING.md: contains no-pipe/no-tail directive for run-all.sh"
else
  fail "CONTRIBUTING.md: missing no-pipe/no-tail directive for run-all.sh"
fi

if grep -Eiq 'tail -20|tail -40' "$TARGET"; then
  pass "CONTRIBUTING.md: includes concrete tail wrapper examples"
else
  fail "CONTRIBUTING.md: missing concrete tail wrapper examples"
fi

if grep -Eiq 'buffer until EOF|buffer until eof|hide live progress' "$TARGET"; then
  pass "CONTRIBUTING.md: explains why tail wrappers are unsafe"
else
  fail "CONTRIBUTING.md: missing rationale for no-tail execution"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="
[ "$FAIL" -eq 0 ] || exit 1