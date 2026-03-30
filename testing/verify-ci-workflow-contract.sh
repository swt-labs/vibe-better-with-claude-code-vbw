#!/usr/bin/env bash
set -euo pipefail

# verify-ci-workflow-contract.sh — Validate CI workflow parity invariants.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"

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

job_block() {
  local job_name="$1"
  awk -v job="$job_name" '
    $0 ~ "^  " job ":$" { in_job=1; print; next }
    in_job && $0 ~ /^  [A-Za-z0-9_-]+:$/ { exit }
    in_job { print }
  ' "$WORKFLOW"
}

echo "=== CI Workflow Contract Verification ==="

LINT_BLOCK="$(job_block lint)"
CONTRACT_BLOCK="$(job_block contract-tests)"
TEST_BLOCK="$(job_block test)"

if grep -q 'bash testing/run-lint.sh' <<< "$LINT_BLOCK"; then
  pass "ci.yml: lint job runs shared testing/run-lint.sh"
else
  fail "ci.yml: lint job does not run shared testing/run-lint.sh"
fi

if grep -q 'bash testing/verify-ci-workflow-contract.sh' <<< "$CONTRACT_BLOCK"; then
  pass "ci.yml: contract-tests job includes verify-ci-workflow-contract.sh"
else
  fail "ci.yml: contract-tests job missing verify-ci-workflow-contract.sh"
fi

if grep -q 'needs: \[bats-tests, contract-tests, lint\]' <<< "$TEST_BLOCK"; then
  pass "ci.yml: test aggregator depends on lint, bats-tests, and contract-tests"
else
  fail "ci.yml: test aggregator missing lint in needs"
fi

if grep -q '\${{ needs.lint.result }}' <<< "$TEST_BLOCK"; then
  pass "ci.yml: test aggregator checks lint result explicitly"
else
  fail "ci.yml: test aggregator does not check lint result explicitly"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "CI workflow contract checks passed."