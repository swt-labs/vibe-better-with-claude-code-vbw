#!/usr/bin/env bash
set -euo pipefail

# verify-discussion-engine-contract.sh — Verify discussion engine structural contracts

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

echo "=== Discussion Engine Contract Verification ==="

ENGINE="$ROOT/references/discussion-engine.md"

# --- Confidence indicators in A5 presentation ---

for indicator in "✓ confirmed" "⚡ validated" "? resolved" "✗ corrected" "○ expanded"; do
  if grep -q "$indicator" "$ENGINE"; then
    pass "engine: contains confidence indicator '$indicator'"
  else
    fail "engine: missing confidence indicator '$indicator'"
  fi
done

# --- A5 has user-facing presentation instruction ---

if grep -q "present a summary" "$ENGINE"; then
  pass "engine: A5 has user-facing presentation instruction"
else
  fail "engine: A5 missing user-facing presentation instruction"
fi

# --- Step 1.7 exists ---

if grep -q "Step 1.7" "$ENGINE"; then
  pass "engine: Step 1.7 (Assumptions Path) exists"
else
  fail "engine: Step 1.7 (Assumptions Path) missing"
fi

# --- Codebase map guard ---

if grep -q "META.md" "$ENGINE"; then
  pass "engine: codebase map guard references META.md"
else
  fail "engine: codebase map guard missing META.md reference"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
