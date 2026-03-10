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
if [ -z "$TOOLS_LINE" ]; then
  fail "3: vbw-qa.md has no tools line in frontmatter"
elif echo "$TOOLS_LINE" | grep -qv 'Write'; then
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

# ── Team-mode persistence checks ─────────────────────────────────────

# 11. QA agent Communication "As teammate" paragraph references persistence
if grep -qi 'teammate.*persist\|sending.*qa_verdict.*persist\|After sending.*persist' "$QA_AGENT"; then
  pass "11: vbw-qa.md teammate Communication references persistence"
else
  fail "11: vbw-qa.md teammate Communication does not reference persistence"
fi

# 12. QA agent Persistence section applies to both modes
if grep -qi 'both modes\|teammate and subagent' "$QA_AGENT"; then
  pass "12: vbw-qa.md Persistence section covers both modes"
else
  fail "12: vbw-qa.md Persistence section does not explicitly cover both modes"
fi

# ── Finding-regression checks (QA round 2) ───────────────────────────

# 13. Execute protocol does NOT pass a literal `echo ...` snippet as plugin root
#     (must use $VBW_PLUGIN_ROOT or `!` executable expansion, not a bare code span)
if grep -q 'Plugin root:.*`echo /tmp/' "$EXEC_PROTO"; then
  fail "13: execute-protocol.md passes literal echo snippet instead of resolved plugin root"
else
  pass "13: execute-protocol.md does not pass literal echo snippet as plugin root"
fi

# 15. Execute protocol QA task descriptions use VBW_PLUGIN_ROOT (not CLAUDE_PLUGIN_ROOT)
#     CLAUDE_PLUGIN_ROOT is only set for --plugin-dir installs; VBW_PLUGIN_ROOT is the
#     resolved variable from the 6-step cascade at the top of execute-protocol.md.
if grep -q 'Plugin root: \${CLAUDE_PLUGIN_ROOT}' "$EXEC_PROTO"; then
  fail "15: execute-protocol.md QA task descriptions use CLAUDE_PLUGIN_ROOT instead of VBW_PLUGIN_ROOT"
else
  pass "15: execute-protocol.md QA task descriptions use correct plugin root variable"
fi

# 14. No orchestrator fallback that reintroduces manual VERIFICATION.md writes
FALLBACK_COUNT=0
for f in "$QA_CMD" "$EXEC_PROTO"; do
  if grep -qi 'fall back to writing.*VERIFICATION' "$f"; then
    FALLBACK_COUNT=$((FALLBACK_COUNT + 1))
  fi
done
if [ "$FALLBACK_COUNT" -gt 0 ]; then
  fail "14: orchestrator docs still contain manual VERIFICATION.md fallback ($FALLBACK_COUNT files)"
else
  pass "14: no orchestrator manual VERIFICATION.md fallback found"
fi

# ── Finding-regression checks (QA round 4) ───────────────────────────

# 16. Execute protocol QA task descriptions use ${VBW_PLUGIN_ROOT} consistently
#     (same pattern as all other script invocations — orchestrator resolves at top of file)
PLUGIN_ROOT_COUNT=$(grep -c 'Plugin root: \${VBW_PLUGIN_ROOT}' "$EXEC_PROTO" || true)
if [ "$PLUGIN_ROOT_COUNT" -ge 2 ]; then
  pass "16: execute-protocol.md QA task descriptions use \${VBW_PLUGIN_ROOT} consistently ($PLUGIN_ROOT_COUNT occurrences)"
else
  fail "16: execute-protocol.md QA task descriptions missing \${VBW_PLUGIN_ROOT} (found $PLUGIN_ROOT_COUNT, expected ≥2)"
fi

# 17. vbw-qa.md Constraints does NOT have blanket "No file modification" without qualification
#     Must qualify with "(Write, Edit, NotebookEdit are platform-denied)" or similar
if grep -q 'No file modification\.' "$QA_AGENT" && ! grep -q 'No direct file modification' "$QA_AGENT"; then
  fail "17: vbw-qa.md Constraints has unqualified 'No file modification' contradicting Persistence section"
else
  pass "17: vbw-qa.md Constraints properly qualifies file modification prohibition"
fi

# 18. README permission model QA line does NOT say "can't write" without qualification
if grep -q "QA.*Can verify, can't write" "$ROOT/README.md"; then
  fail "18: README permission model still says QA 'can't write' without qualifying deterministic writer"
else
  pass "18: README permission model QA line does not have unqualified 'can't write'"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "==============================="
echo "QA persistence contract: $PASS passed, $FAIL failed"
echo "==============================="
[ "$FAIL" -eq 0 ] || exit 1
