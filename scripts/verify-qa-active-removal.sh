#!/usr/bin/env bash
set -euo pipefail

# verify-qa-active-removal.sh — Focused QA verifier for ACTIVE-removal milestone refactor.
#
# Usage: bash scripts/verify-qa-active-removal.sh
# Exit: 0 if all checks pass, 1 if any check fails.

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

check_cmd() {
  local label="$1"
  shift
  if "$@"; then
    pass "$label"
  else
    fail "$label"
  fi
}

run_bats_suite() {
  local suite="$1"
  if bats "$suite"; then
    pass "$(basename "$suite")"
  else
    fail "$(basename "$suite")"
  fi
}

echo "=== QA Verification: ACTIVE Removal / Worktree Compatibility ==="

echo ""
echo "--- Scenario checks: session-start no-phases path ---"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cd "$TMP_DIR"
mkdir -p .vbw-planning
printf '# Test Project\n' > .vbw-planning/PROJECT.md

if bash "$ROOT/scripts/session-start.sh" > out1.txt 2> err1.txt; then
  pass "session-start succeeds with PROJECT.md and no phases/"
else
  fail "session-start succeeds with PROJECT.md and no phases/"
fi

if grep -q "Next: /vbw:vibe (needs scoping)." out1.txt; then
  pass "session-start no-phases next action is needs scoping"
else
  fail "session-start no-phases next action is needs scoping"
fi

mkdir -p .vbw-planning/milestones/01-foundation
printf '# SHIPPED\n' > .vbw-planning/milestones/01-foundation/SHIPPED.md

if bash "$ROOT/scripts/session-start.sh" > out2.txt 2> err2.txt; then
  pass "session-start succeeds with shipped milestones and no phases/"
else
  fail "session-start succeeds with shipped milestones and no phases/"
fi

if grep -q "Shipped milestones: true." out2.txt; then
  pass "session-start context reports shipped milestones"
else
  fail "session-start context reports shipped milestones"
fi

if grep -q "Next: /vbw:vibe (all milestones shipped, start next milestone)." out2.txt; then
  pass "session-start no-phases shipped flow suggests next milestone"
else
  fail "session-start no-phases shipped flow suggests next milestone"
fi

echo ""
echo "--- Contract check: stale ACTIVE references ---"

check_cmd "verify-commands-contract.sh" bash "$ROOT/testing/verify-commands-contract.sh"

echo ""
echo "--- Targeted BATS suites ---"

if ! command -v bats >/dev/null 2>&1; then
  fail "bats installed"
else
  pass "bats installed"

  run_bats_suite "$ROOT/tests/sessionstart-compact-hooks.bats"
  run_bats_suite "$ROOT/tests/phase-detect.bats"
  run_bats_suite "$ROOT/tests/persist-state-after-ship.bats"
  run_bats_suite "$ROOT/tests/list-todos.bats"
  run_bats_suite "$ROOT/tests/rename-default-milestone.bats"
  run_bats_suite "$ROOT/tests/unarchive-milestone.bats"
  run_bats_suite "$ROOT/tests/worktree.bats"
  run_bats_suite "$ROOT/tests/worktree-boundary.bats"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "QA verification passed."
exit 0
