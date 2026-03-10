#!/usr/bin/env bash
set -euo pipefail

# verify-qa-persistence-contract.sh — Tests for issue #202 fix
#
# Verifies that:
# - QA agent does NOT contain heredoc escape hatch for VERIFICATION.md
# - QA agent instructs calling write-verification.sh directly
# - Orchestrator (commands/qa.md) does NOT pipe qa_verdict through write-verification.sh
# - Orchestrator passes output path to QA in the task description
# - execute-protocol.md describes QA calling write-verification.sh (not orchestrator)
# - verification-protocol.md reflects QA-side persistence

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

# ── QA agent checks ─────────────────────────────────────────────────
QA_AGENT="$ROOT/agents/vbw-qa.md"

# 1. No heredoc escape hatch
if grep -qi 'heredoc' "$QA_AGENT"; then
  fail "1: vbw-qa.md still mentions heredoc"
else
  pass "1: vbw-qa.md does not mention heredoc"
fi

# 2. QA agent references write-verification.sh
if grep -q 'write-verification\.sh' "$QA_AGENT"; then
  pass "2: vbw-qa.md references write-verification.sh"
else
  fail "2: vbw-qa.md does not reference write-verification.sh"
fi

# 3. QA agent tools allowlist omits Write (enforced via tools: line in frontmatter)
TOOLS_LINE=$(grep '^tools:' "$QA_AGENT" || true)
if echo "$TOOLS_LINE" | grep -qv 'Write'; then
  pass "3: vbw-qa.md tools allowlist omits Write"
else
  fail "3: vbw-qa.md tools allowlist includes Write (should be read-only)"
fi

# 4. QA agent still has Bash in tools
if grep -q 'tools:.*Bash' "$QA_AGENT"; then
  pass "4: vbw-qa.md still has Bash in tools"
else
  fail "4: vbw-qa.md missing Bash in tools"
fi

# ── Orchestrator (commands/qa.md) checks ─────────────────────────────
QA_CMD="$ROOT/commands/qa.md"

# 5. Orchestrator does NOT pipe qa_verdict through write-verification.sh
if grep -q 'echo.*QA_VERDICT.*write-verification' "$QA_CMD"; then
  fail "5: commands/qa.md still pipes qa_verdict through write-verification.sh"
else
  pass "5: commands/qa.md does not pipe qa_verdict through write-verification.sh"
fi

# 6. Orchestrator passes output path in task description to QA
if grep -qi 'output.path\|verification.path\|VERIFICATION.md.*path\|persist.*write-verification' "$QA_CMD"; then
  pass "6: commands/qa.md passes persistence info to QA in task description"
else
  fail "6: commands/qa.md does not pass persistence info to QA"
fi

# ── Execute protocol checks ─────────────────────────────────────────
EXEC_PROTO="$ROOT/references/execute-protocol.md"

# 7. Execute protocol does NOT have orchestrator-side pipe to write-verification.sh
#    (The old pattern was: echo "$QA_VERDICT_JSON" | bash ... write-verification.sh)
EXEC_PIPE_COUNT=$(grep -c 'echo.*QA_VERDICT.*write-verification' "$EXEC_PROTO" || true)
if [ "$EXEC_PIPE_COUNT" -gt 0 ]; then
  fail "7: execute-protocol.md still has orchestrator-side pipe to write-verification.sh ($EXEC_PIPE_COUNT occurrences)"
else
  pass "7: execute-protocol.md does not have orchestrator-side pipe to write-verification.sh"
fi

# 8. Execute protocol mentions QA persists directly (via task description)
if grep -qi 'QA.*persist\|QA.*write-verification\|QA.*calls.*write-verification\|task description.*output.path\|task description.*write-verification' "$EXEC_PROTO"; then
  pass "8: execute-protocol.md describes QA-side persistence"
else
  fail "8: execute-protocol.md does not describe QA-side persistence"
fi

# ── Verification protocol checks ────────────────────────────────────
VERIF_PROTO="$ROOT/references/verification-protocol.md"

# 9. Verification protocol does NOT say "parent command persists"
if grep -qi 'parent command persists' "$VERIF_PROTO"; then
  fail "9: verification-protocol.md still says 'parent command persists'"
else
  pass "9: verification-protocol.md no longer says 'parent command persists'"
fi

# 10. Verification protocol reflects QA-side persistence
if grep -qi 'QA.*write-verification\|QA.*persists\|QA agent.*calls\|agent.*write-verification' "$VERIF_PROTO"; then
  pass "10: verification-protocol.md reflects QA-side persistence"
else
  fail "10: verification-protocol.md does not reflect QA-side persistence"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "==============================="
echo "QA persistence contract: $PASS passed, $FAIL failed"
echo "==============================="
[ "$FAIL" -eq 0 ] || exit 1
