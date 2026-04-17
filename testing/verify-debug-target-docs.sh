#!/usr/bin/env bash
set -euo pipefail

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

AGENTS_MD="$ROOT/AGENTS.md"
CONTRIB="$ROOT/CONTRIBUTING.md"
IGNORE="$ROOT/.gitignore"

echo "=== Debug Target Docs Contract Verification ==="

if [ -f "$AGENTS_MD" ]; then
  pass "AGENTS.md exists"
else
  fail "AGENTS.md missing"
fi

if grep -q 'vbw-debug-target.txt' "$AGENTS_MD" 2>/dev/null; then
  pass "AGENTS.md documents the local debug target file"
else
  fail "AGENTS.md missing vbw-debug-target.txt guidance"
fi

if grep -q 'resolve-debug-target.sh' "$AGENTS_MD" 2>/dev/null; then
  pass "AGENTS.md references resolve-debug-target.sh"
else
  fail "AGENTS.md missing resolve-debug-target.sh guidance"
fi

if grep -E '/Users/dpearson|ios-options-wheel-tracker|-Users-dpearson-' "$AGENTS_MD" >/dev/null 2>&1; then
  fail "AGENTS.md still contains maintainer-specific debug target paths"
else
  pass "AGENTS.md contains no maintainer-specific debug target paths"
fi

if grep -q 'vbw-debug-target.txt' "$CONTRIB" 2>/dev/null; then
  pass "CONTRIBUTING.md documents local debug target setup"
else
  fail "CONTRIBUTING.md missing local debug target setup"
fi

if grep -q '^AGENTS\.md$' "$IGNORE" 2>/dev/null; then
  fail ".gitignore still ignores AGENTS.md"
else
  pass ".gitignore allows AGENTS.md to be tracked"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[[ "$FAIL" -eq 0 ]] || exit 1