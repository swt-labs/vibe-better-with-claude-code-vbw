#!/usr/bin/env bash
set -euo pipefail

# verify-ci-workflow-contract.sh — Validate CI workflow parity invariants.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"
RUN_ALL="$ROOT/testing/run-all.sh"
LIST_BATS="$ROOT/testing/list-bats-files.sh"
LIST_CONTRACT_TESTS="$ROOT/testing/list-contract-tests.sh"

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

extract_discovery_names() {
  bash "$LIST_CONTRACT_TESTS" 2>/dev/null | cut -f1 | (sort 2>/dev/null || cat)
}

echo "=== CI Workflow Contract Verification ==="

LINT_BLOCK="$(job_block lint)"
CONTRACT_BLOCK="$(job_block contract-tests)"
TEST_BLOCK="$(job_block test)"
BATS_SERIAL_BLOCK="$(job_block bats-serial)"

if grep -q 'bash testing/run-lint.sh' <<< "$LINT_BLOCK"; then
  pass "ci.yml: lint job runs shared testing/run-lint.sh"
else
  fail "ci.yml: lint job does not run shared testing/run-lint.sh"
fi

if grep -q 'bash testing/run-bats-shard.sh' "$WORKFLOW" && grep -q 'run-bats-shard.sh' "$RUN_ALL"; then
  pass "ci.yml/testing: CI and local runner share the same bats shard helper"
else
  fail "ci.yml/testing: CI and local runner do not share the same bats shard helper"
fi

if grep -q 'bash testing/list-bats-files.sh --shardable' "$WORKFLOW" && grep -q 'bash "$LIST_BATS_FILES" --shardable' "$RUN_ALL"; then
  pass "ci.yml/testing: CI and local runner share deterministic shardable bats discovery"
else
  fail "ci.yml/testing: CI and local runner do not share deterministic shardable bats discovery"
fi

if grep -q 'bash testing/list-bats-files.sh --serial' "$WORKFLOW" && grep -q 'bash "$LIST_BATS_FILES" --serial' "$RUN_ALL"; then
  pass "ci.yml/testing: CI and local runner share deterministic serial bats discovery"
else
  fail "ci.yml/testing: CI and local runner do not share deterministic serial bats discovery"
fi

if grep -q 'BATS_WORKERS="${BATS_WORKERS:-4}"' "$RUN_ALL"; then
  pass "run-all: defaults to CI shard count (4 workers)"
else
  fail "run-all: does not default to CI shard count (4 workers)"
fi

if grep -q 'list-contract-tests.sh' <<< "$CONTRACT_BLOCK"; then
  pass "ci.yml: contract-tests job uses shared list-contract-tests.sh discovery"
else
  fail "ci.yml: contract-tests job does not use shared list-contract-tests.sh discovery"
fi

if grep -q 'list-contract-tests.sh' "$RUN_ALL"; then
  pass "run-all.sh: uses shared list-contract-tests.sh discovery"
else
  fail "run-all.sh: does not use shared list-contract-tests.sh discovery"
fi

DISCOVERY_NAMES="$(extract_discovery_names)"
if [ -n "$DISCOVERY_NAMES" ]; then
  pass "list-contract-tests.sh: produces non-empty output"
else
  fail "list-contract-tests.sh: produces no output"
fi

if echo "$DISCOVERY_NAMES" | grep -q 'ci-workflow-contract'; then
  pass "list-contract-tests.sh: includes ci-workflow-contract (self-referential)"
else
  fail "list-contract-tests.sh: missing ci-workflow-contract entry"
fi

MISSING_FILES=0
while IFS=$'\t' read -r name path; do
  [[ -z "$name" ]] && continue
  if [ ! -f "$ROOT/$path" ]; then
    echo "  MISSING: $name -> $path"
    MISSING_FILES=$((MISSING_FILES + 1))
  fi
done < <(bash "$LIST_CONTRACT_TESTS" 2>/dev/null)
if [ "$MISSING_FILES" -eq 0 ]; then
  pass "list-contract-tests.sh: all discovered paths exist"
else
  fail "list-contract-tests.sh: $MISSING_FILES discovered path(s) do not exist"
fi

if grep -q 'needs: \[bats-tests, bats-serial, contract-tests, lint\]' <<< "$TEST_BLOCK"; then
  pass "ci.yml: test aggregator depends on lint, bats-tests, bats-serial, and contract-tests"
else
  fail "ci.yml: test aggregator missing one or more required jobs in needs"
fi

if grep -q '\${{ needs.lint.result }}' <<< "$TEST_BLOCK" && grep -q '\${{ needs.bats-serial.result }}' <<< "$TEST_BLOCK"; then
  pass "ci.yml: test aggregator checks lint and serial bats results explicitly"
else
  fail "ci.yml: test aggregator does not check lint/serial bats results explicitly"
fi

if grep -q 'bats "${files\[@\]}"' <<< "$BATS_SERIAL_BLOCK"; then
  pass "ci.yml: serial bats job runs discovered serial files explicitly"
else
  fail "ci.yml: serial bats job does not run discovered serial files explicitly"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "CI workflow contract checks passed."