#!/usr/bin/env bash
set -euo pipefail

# verify-human-only-uat-contract.sh — Prevent drift between execute-time UAT
# generation and standalone /vbw:verify UAT generation rules.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXEC_PROTO="$ROOT/references/execute-protocol.md"
VERIFY_FILE="$ROOT/commands/verify.md"

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

require_all() {
  local file="$1"
  local label="$2"
  shift 2

  local needle=""
  for needle in "$@"; do
    if ! grep -Fq "$needle" "$file"; then
      fail "$label (missing: $needle)"
      return
    fi
  done

  pass "$label"
}

echo "=== Human-Only UAT Contract Verification ==="

require_all "$EXEC_PROTO" \
  "execute-protocol: keeps UAT focused on human judgment" \
  "Generate 1-3 test scenarios per plan requiring HUMAN judgment" \
  "**UAT tests must require human judgment.**"

require_all "$VERIFY_FILE" \
  "verify: keeps UAT focused on human judgment" \
  "Generate 1-3 test scenarios that require HUMAN judgment" \
  "**UAT tests must be things only a human can judge.**"

require_all "$EXEC_PROTO" \
  "execute-protocol: excludes automated QA checks from UAT" \
  "**NEVER generate tests that can be performed programmatically.**" \
  "Grep/search files for expected content or missing imports" \
  "Verify file existence, deletion, or structure" \
  "Run a test suite or individual test" \
  "Run a CLI command and check its exit code or output" \
  "Execute a script and verify it passes" \
  "Run a linter, type-checker, or build command"

require_all "$VERIFY_FILE" \
  "verify: excludes automated QA checks from UAT" \
  "**NEVER generate tests that ask the user to run automated checks.**" \
  "Run a test suite or individual test" \
  "Run a CLI command and check its exit code or output" \
  "Execute a script and verify it passes" \
  "Run a linter, type-checker, or build command" \
  "Running test suites — QA runs these during execution. Do NOT ask the user to run tests." \
  "Checking command output, exit codes, or build success" \
  "Grepping files for expected content" \
  "Verifying file existence or structure"

require_all "$EXEC_PROTO" \
  "execute-protocol: defines the positive UAT scope" \
  "**What belongs in UAT (ask the user):**" \
  "Visual/UI correctness" \
  "Domain-specific data validation" \
  "UX flows and usability" \
  "Behavior that requires the running app or hardware" \
  "Subjective quality"

require_all "$VERIFY_FILE" \
  "verify: defines the positive UAT scope" \
  "**What belongs in UAT (ask the user):**" \
  "Visual/UI correctness" \
  "Domain-specific data validation" \
  "UX flows and usability" \
  "Behavior that requires the running app or hardware" \
  "Subjective quality"

require_all "$EXEC_PROTO" \
  "execute-protocol: rejects programmatic Bash/Grep/Glob checks" \
  "**What does NOT belong in UAT (the agent or QA already handles these):**" \
  "Any check that can be performed programmatically via Bash, Grep, or Glob"

require_all "$VERIFY_FILE" \
  "verify: rejects programmatic Bash/Grep/Glob checks" \
  "**What does NOT belong in UAT (the agent or QA already handles these):**" \
  "Any check that can be performed programmatically via Bash, Grep, or Glob"

require_all "$EXEC_PROTO" \
  "execute-protocol: routes UI automation capabilities to QA" \
  "**Skill-aware exclusion:**" \
  "describe-UI" \
  "tap/click simulation" \
  "accessibility inspection" \
  "screenshot capture" \
  "DOM querying" \
  "Only include scenarios that require true human judgment"

require_all "$VERIFY_FILE" \
  "verify: routes UI automation capabilities to QA" \
  "**Skill-aware exclusion:**" \
  "describe-UI" \
  "tap/click simulation" \
  "accessibility inspection" \
  "screenshot capture" \
  "DOM querying" \
  "Only include scenarios that require true human judgment"

require_all "$EXEC_PROTO" \
  "execute-protocol: internal-only plans avoid asking users to run automation" \
  "If a plan's work is purely internal (refactor, test infrastructure, script changes) with no user-facing behavior" \
  "rather than asking them to run automated checks"

require_all "$VERIFY_FILE" \
  "verify: internal-only plans avoid asking users to run automation" \
  "If a plan's work is purely internal (refactor, test infrastructure, script changes) with no user-facing behavior" \
  "rather than asking them to run automated checks"

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All human-only UAT contract checks passed."