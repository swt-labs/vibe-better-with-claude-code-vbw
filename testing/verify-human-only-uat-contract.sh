#!/usr/bin/env bash
set -euo pipefail

# verify-human-only-uat-contract.sh — Prevent drift between execute-time UAT
# generation and verify.md UAT generation rules.

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

require_absent() {
  local file="$1"
  local label="$2"
  shift 2

  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    fail "$label (missing or unreadable file: $file)"
    return
  fi

  local needle=""
  for needle in "$@"; do
    if grep -Fq "$needle" "$file"; then
      fail "$label (unexpected: $needle)"
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

require_all "$EXEC_PROTO" \
  "execute-protocol: synthesizes UAT issue descriptions" \
  'synthesize an actionable persisted `Description`' \
  "checkpoint expectation" \
  "current user response" \
  "visible attachment/image content" \
  "Correct typos" \
  "preserve user intent" \
  "state the observed actual behavior" \
  "Do not invent facts that are not present in the checkpoint, user response, or visible attachment/image evidence"

require_all "$VERIFY_FILE" \
  "verify: synthesizes UAT issue descriptions" \
  'Synthesize an actionable persisted `Description`' \
  'current checkpoint `Scenario` and `Expected` text' \
  "the user's response" \
  "visible attachment/image content" \
  "corrects typos" \
  "preserves user intent" \
  "states the observed actual behavior" \
  "Do not invent facts that are not present in the checkpoint, user response, or visible attachment/image evidence"

require_all "$EXEC_PROTO" \
  "execute-protocol: avoids non-durable attachment placeholders" \
  'do not persist `image attached`, `(Image attached)`' \
  "similar placeholders as evidence" \
  "Never persist raw screenshots, raw attachment blobs, or base64 data" \
  'keep the existing `Description` and `Severity` issue shape'

require_all "$VERIFY_FILE" \
  "verify: avoids non-durable attachment placeholders" \
  'do not persist `image attached`, `(Image attached)`' \
  "similar placeholders as evidence" \
  "Never persist raw screenshots, raw attachment blobs, or base64 data" \
  "Record the limitation only if it matters to remediation"

require_all "$VERIFY_FILE" \
  "verify: preserves human-only boundary during issue synthesis" \
  "Preserve the human-only UAT boundary" \
  "do not debug, inspect project files, run commands, or implement fixes during UAT capture"

require_all "$EXEC_PROTO" \
  "execute-protocol: preserves human-only boundary during issue synthesis" \
  "Preserve the human-only UAT boundary" \
  "do not debug, inspect project files, run commands, or implement fixes during UAT capture"

require_all "$ROOT/templates/UAT.md" \
  "UAT template: preserves synthesized Description schema" \
  'Issue `Description` values are synthesized, remediation-ready text' \
  "not raw user responses" \
  'Do not persist `image attached`, `(Image attached)`' \
  "raw attachment blobs, or base64 data"

require_all "$VERIFY_FILE" \
  "verify: discovered issues synthesize Description text" \
  "The captured observation is source material for Step 7 issue capture rules" \
  'Description: {synthesized remediation-ready description}' \
  "Severity: {inferred severity}"

require_all "$VERIFY_FILE" \
  "verify: discovered issue cross-references target Step 7a" \
  "capture the separate observation as a discovered issue (see Step 7a)" \
  "capture the additional text as a discovered issue (see Step 7a)" \
  "capture the post-separator observation text as a discovered issue (Step 7a)" \
  "Infer severity using the same keyword table from Step 7"

require_absent "$VERIFY_FILE" \
  "verify: removes stale discovered-issue cross-references" \
  "Step 6a" \
  "keyword table from Step 6"

require_all "$ROOT/templates/UAT.md" \
  "UAT template: discovered issues preserve synthesized Description shape" \
  'Description: {synthesized remediation-ready description}' \
  "Severity: {critical|major|minor}"

require_absent "$VERIFY_FILE" \
  "verify: removes raw-response persistence contract" \
  "The user's response text IS the issue description" \
  "use the verbatim observation"

require_absent "$EXEC_PROTO" \
  "execute-protocol: removes raw-response persistence contract" \
  "treat the entire response text as an issue description"

require_absent "$VERIFY_FILE" \
  "verify: removes raw discovered-issue Description placeholder" \
  "Description: {observation text}"

require_absent "$ROOT/templates/UAT.md" \
  "UAT template: removes raw discovered-issue Description placeholder" \
  "Description: {observation text}"

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All human-only UAT contract checks passed."