#!/usr/bin/env bash
set -euo pipefail

# verify-debug-session-contract.sh — Structural checks for the debug session lifecycle
#
# Validates:
# - DEBUG-SESSION.md template has required sections
# - debug-session-state.sh implements all documented commands
# - write-debug-session.sh implements all modes
# - compile-debug-session-context.sh implements all modes
# - debug.md has debug_session_routing section
# - qa.md has debug_session_qa section
# - verify.md has debug_session_uat section

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

# — Template checks —

TEMPLATE="$ROOT/templates/DEBUG-SESSION.md"

if [ -f "$TEMPLATE" ]; then
  pass "DEBUG-SESSION.md template exists"
else
  fail "DEBUG-SESSION.md template missing"
fi

for section in "## Issue" "## Investigation" "## Plan" "## Implementation" "## QA" "## UAT"; do
  if grep -q "^${section}" "$TEMPLATE" 2>/dev/null; then
    pass "template has section: $section"
  else
    fail "template missing section: $section"
  fi
done

for field in session_id title status created updated qa_round qa_last_result uat_round uat_last_result; do
  if grep -q "^${field}:" "$TEMPLATE" 2>/dev/null; then
    pass "template has frontmatter field: $field"
  else
    fail "template missing frontmatter field: $field"
  fi
done

# — State machine script checks —

STATE_SCRIPT="$ROOT/scripts/debug-session-state.sh"

if [ -f "$STATE_SCRIPT" ]; then
  pass "debug-session-state.sh exists"
else
  fail "debug-session-state.sh missing"
fi

for cmd in start get get-or-latest resume set-status increment-qa increment-uat clear-active list; do
  if grep -q "\"$cmd\"\\|'$cmd'\\|${cmd})" "$STATE_SCRIPT" 2>/dev/null; then
    pass "state script handles command: $cmd"
  else
    fail "state script missing command: $cmd"
  fi
done

# — Writer script checks —

WRITER="$ROOT/scripts/write-debug-session.sh"

if [ -f "$WRITER" ]; then
  pass "write-debug-session.sh exists"
else
  fail "write-debug-session.sh missing"
fi

for mode in investigation qa uat status; do
  if grep -q "$mode" "$WRITER" 2>/dev/null; then
    pass "writer script handles mode: $mode"
  else
    fail "writer script missing mode: $mode"
  fi
done

# — Context compiler checks —

COMPILER="$ROOT/scripts/compile-debug-session-context.sh"

if [ -f "$COMPILER" ]; then
  pass "compile-debug-session-context.sh exists"
else
  fail "compile-debug-session-context.sh missing"
fi

for mode in qa uat; do
  if grep -q "$mode" "$COMPILER" 2>/dev/null; then
    pass "context compiler handles mode: $mode"
  else
    fail "context compiler missing mode: $mode"
  fi
done

# — Command integration checks —

DEBUG_CMD="$ROOT/commands/debug.md"
if grep -q "debug_session_routing" "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md has debug_session_routing section"
else
  fail "debug.md missing debug_session_routing section"
fi

QA_CMD="$ROOT/commands/qa.md"
if grep -q "debug_session_qa" "$QA_CMD" 2>/dev/null; then
  pass "qa.md has debug_session_qa section"
else
  fail "qa.md missing debug_session_qa section"
fi

VERIFY_CMD="$ROOT/commands/verify.md"
if grep -q "debug_session_uat" "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md has debug_session_uat section"
else
  fail "verify.md missing debug_session_uat section"
fi

# — Agent integration checks —

DEBUGGER_AGENT="$ROOT/agents/vbw-debugger.md"
if grep -q "Standalone Debug Session" "$DEBUGGER_AGENT" 2>/dev/null; then
  pass "vbw-debugger.md has standalone debug session section"
else
  fail "vbw-debugger.md missing standalone debug session section"
fi

QA_AGENT="$ROOT/agents/vbw-qa.md"
if grep -q "Debug Session QA" "$QA_AGENT" 2>/dev/null; then
  pass "vbw-qa.md has debug session QA section"
else
  fail "vbw-qa.md missing debug session QA section"
fi

# — Guard ordering checks (R2-01, R2-02) —

if grep -q "Debug session override" "$QA_CMD" 2>/dev/null; then
  pass "qa.md has debug session override in Guard"
else
  fail "qa.md missing debug session override in Guard"
fi

if grep -q "Debug session override" "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md has debug session override in Guard"
else
  fail "verify.md missing debug session override in Guard"
fi

# — UAT template completeness (R2-03) —

if grep -q '"result"' "$VERIFY_CMD" 2>/dev/null && grep -q 'pass|issues_found' "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md UAT template includes result field"
else
  fail "verify.md UAT template missing result field"
fi

# — Agent status alignment (R2-04) —

if grep -q 'qa_pending' "$DEBUGGER_AGENT" 2>/dev/null && ! grep -q 'fix_applied' "$DEBUGGER_AGENT" 2>/dev/null; then
  pass "vbw-debugger.md uses qa_pending (not fix_applied) for post-fix status"
else
  fail "vbw-debugger.md should use qa_pending for post-fix status, not fix_applied"
fi

# — Template remediation history section (CM1-02) —

TEMPLATE="$ROOT/templates/DEBUG-SESSION.md"
if grep -q '## Remediation History' "$TEMPLATE" 2>/dev/null; then
  pass "DEBUG-SESSION.md template has Remediation History section"
else
  fail "DEBUG-SESSION.md template missing Remediation History section"
fi

# — Guard phase_count condition (CM1-01) —

if grep -q 'phase_count=0' "$QA_CMD" 2>/dev/null || grep -q 'phase_count' "$QA_CMD" 2>/dev/null; then
  pass "qa.md debug session guard checks phase_count"
else
  fail "qa.md debug session guard does not check phase_count"
fi

if grep -q 'phase_count=0' "$VERIFY_CMD" 2>/dev/null || grep -q 'phase_count' "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md debug session guard checks phase_count"
else
  fail "verify.md debug session guard does not check phase_count"
fi

# — Writer handles skip and user_response (CM1-03) —

if grep -q 'skip' "$WRITER" 2>/dev/null && grep -q 'user_response' "$WRITER" 2>/dev/null; then
  pass "write-debug-session.sh handles skip result and user_response"
else
  fail "write-debug-session.sh missing skip or user_response handling"
fi

# — Lifecycle integration test exists (CM1-04) —

if [ -f "$ROOT/tests/debug-session-lifecycle.bats" ]; then
  pass "debug-session-lifecycle.bats end-to-end test exists"
else
  fail "debug-session-lifecycle.bats missing"
fi

# — suggest-next.sh qa path handles standalone debug sessions (CM2-01) —

if grep -q 'phase_count.*0.*debugging' "$ROOT/scripts/suggest-next.sh" 2>/dev/null || \
   grep -q '_qa_debug_handled' "$ROOT/scripts/suggest-next.sh" 2>/dev/null; then
  pass "suggest-next.sh qa branch has standalone debug-session detection"
else
  fail "suggest-next.sh qa branch missing standalone debug-session detection"
fi

# — qa.md routing decision supports --session flag alongside phase_count (CM2-02, CM3-01) —

if grep -q 'phase_count=0.*--session' "$ROOT/commands/qa.md" 2>/dev/null; then
  pass "qa.md debug-session routing decision supports --session flag"
else
  fail "qa.md debug-session routing decision missing --session flag support"
fi

# — verify.md routing decision supports --session flag alongside phase_count (CM2-02, CM3-01) —

if grep -q 'phase_count=0.*--session' "$ROOT/commands/verify.md" 2>/dev/null; then
  pass "verify.md debug-session routing decision supports --session flag"
else
  fail "verify.md debug-session routing decision missing --session flag support"
fi

# — suggest-next-debug-session.bats covers qa context (CM2-03) —

if grep -q 'suggest-next qa.*pass.*debug session' "$ROOT/tests/suggest-next-debug-session.bats" 2>/dev/null; then
  pass "suggest-next-debug-session.bats covers qa pass with debug session"
else
  fail "suggest-next-debug-session.bats missing qa pass with debug session test"
fi

# — Guard sections support --session escape hatch (CM3-01) —

if grep -q '\-\-session' "$ROOT/commands/qa.md" 2>/dev/null; then
  pass "qa.md guard mentions --session flag"
else
  fail "qa.md guard missing --session flag"
fi

if grep -q '\-\-session' "$ROOT/commands/verify.md" 2>/dev/null; then
  pass "verify.md guard mentions --session flag"
else
  fail "verify.md guard missing --session flag"
fi

# — suggest-next.sh appends --session when phases exist (CM3-01) —

if grep -q '\-\-session' "$ROOT/scripts/suggest-next.sh" 2>/dev/null; then
  pass "suggest-next.sh has --session flag logic"
else
  fail "suggest-next.sh missing --session flag logic"
fi

# — Portable sed usage (CM3-02) —

if ! grep -q "sed -i ''" "$ROOT/scripts/debug-session-state.sh" 2>/dev/null; then
  pass "debug-session-state.sh uses portable sed (no BSD-only -i '')"
else
  fail "debug-session-state.sh uses non-portable sed -i ''"
fi

if ! grep -q "sed -i ''" "$ROOT/scripts/write-debug-session.sh" 2>/dev/null; then
  pass "write-debug-session.sh uses portable sed (no BSD-only -i '')"
else
  fail "write-debug-session.sh uses non-portable sed -i ''"
fi

# — Summary —

echo ""
echo "=== Debug Session Contract: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
