#!/usr/bin/env bash
set -euo pipefail

# verify-skill-activation.sh — Verify plan-driven skill activation pipeline
#
# Checks:
# - vbw-dev.md references skills_used activation
# - vbw-lead.md references skill evaluation and wiring
# - hooks.json does NOT contain skill-evaluation-gate.sh or skill-eval-prompt-gate.sh
# - All agents with explicit tools: allowlists include Skill
# - execute-protocol.md documents plan-driven approach

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

echo "=== Skill Activation Pipeline Verification (plan-driven model) ==="

# --- vbw-dev.md checks ---

DEV_AGENT="$ROOT/agents/vbw-dev.md"

if grep -q 'skills_used' "$DEV_AGENT"; then
  pass "vbw-dev.md: references skills_used frontmatter"
else
  fail "vbw-dev.md: missing skills_used reference"
fi

if grep -q 'Skill(skill-name)' "$DEV_AGENT"; then
  pass "vbw-dev.md: references Skill() activation"
else
  fail "vbw-dev.md: missing Skill() reference"
fi

if ! grep -q 'protocol violation' "$DEV_AGENT"; then
  pass "vbw-dev.md: no enforcement language"
else
  fail "vbw-dev.md: still has 'protocol violation' enforcement language"
fi

if grep -q 'clearly relevant but missing' "$DEV_AGENT"; then
  pass "vbw-dev.md: has soft fallback for missing skills"
else
  fail "vbw-dev.md: missing soft fallback language"
fi

# --- vbw-lead.md checks ---

LEAD_AGENT="$ROOT/agents/vbw-lead.md"
LEAD_TOOLS=$(sed -n '/^---$/,/^---$/p' "$LEAD_AGENT" | grep '^tools:' || true)

if echo "$LEAD_TOOLS" | grep -q 'Skill'; then
  pass "vbw-lead.md: Skill in tools allowlist"
else
  fail "vbw-lead.md: Skill NOT in tools allowlist"
fi

if grep -q 'Wire relevant skills into plans' "$LEAD_AGENT"; then
  pass "vbw-lead.md: emphasizes wiring skills into plans"
else
  fail "vbw-lead.md: missing plan wiring language"
fi

if grep -q 'Skill completeness check' "$LEAD_AGENT"; then
  pass "vbw-lead.md: has skill completeness gate in self-review"
else
  fail "vbw-lead.md: missing skill completeness gate in self-review"
fi

if ! grep -q 'write YES or NO' "$LEAD_AGENT"; then
  pass "vbw-lead.md: no written YES/NO evaluation"
else
  fail "vbw-lead.md: still has written YES/NO evaluation"
fi

# --- hooks.json negative checks (enforcement gates removed) ---

HOOKS_FILE="$ROOT/hooks/hooks.json"

if ! grep -q 'skill-evaluation-gate.sh' "$HOOKS_FILE"; then
  pass "hooks.json: skill-evaluation-gate.sh removed"
else
  fail "hooks.json: skill-evaluation-gate.sh still present"
fi

if ! grep -q 'skill-eval-prompt-gate.sh' "$HOOKS_FILE"; then
  pass "hooks.json: skill-eval-prompt-gate.sh removed"
else
  fail "hooks.json: skill-eval-prompt-gate.sh still present"
fi

# --- hooks.json positive check (skill-hook-dispatch.sh preserved) ---

if grep -q 'skill-hook-dispatch.sh' "$HOOKS_FILE"; then
  pass "hooks.json: skill-hook-dispatch.sh preserved (runtime skill hooks)"
else
  fail "hooks.json: skill-hook-dispatch.sh missing (should be preserved)"
fi

# --- Skill in all agent tools: allowlists ---

for agent_file in vbw-qa.md vbw-scout.md vbw-debugger.md vbw-architect.md vbw-docs.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"
  AGENT_TOOLS=$(sed -n '/^---$/,/^---$/p' "$AGENT_PATH" | grep '^tools:' || true)
  if echo "$AGENT_TOOLS" | grep -q 'Skill'; then
    pass "$agent_file: Skill in tools allowlist"
  else
    fail "$agent_file: Skill NOT in tools allowlist"
  fi
done

# --- Negative check: compile-context.sh no longer has emit_skill_directive ---

COMPILER="$ROOT/scripts/compile-context.sh"

if grep -q 'emit_skill_directive' "$COMPILER"; then
  fail "compile-context.sh: still has emit_skill_directive (should be removed)"
else
  pass "compile-context.sh: emit_skill_directive removed"
fi

# --- execute-protocol.md checks ---

PROTOCOL="$ROOT/references/execute-protocol.md"

if grep -q 'plan-driven' "$PROTOCOL"; then
  pass "execute-protocol.md: documents plan-driven architecture"
else
  fail "execute-protocol.md: missing plan-driven documentation"
fi

if grep -q 'skills_used' "$PROTOCOL"; then
  pass "execute-protocol.md: references skills_used frontmatter"
else
  fail "execute-protocol.md: missing skills_used reference"
fi

if grep -q 'skill-hook-dispatch.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: documents runtime skill hooks (separate concern)"
else
  fail "execute-protocol.md: missing skill-hook-dispatch.sh documentation"
fi

if ! grep -q 'three-layer' "$PROTOCOL"; then
  pass "execute-protocol.md: old three-layer documentation removed"
else
  fail "execute-protocol.md: still has three-layer documentation"
fi

# --- Deleted scripts should not exist ---

if [ ! -f "$ROOT/scripts/skill-eval-prompt-gate.sh" ]; then
  pass "skill-eval-prompt-gate.sh: deleted"
else
  fail "skill-eval-prompt-gate.sh: still exists"
fi

if [ ! -f "$ROOT/scripts/skill-evaluation-gate.sh" ]; then
  pass "skill-evaluation-gate.sh: deleted"
else
  fail "skill-evaluation-gate.sh: still exists"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All skill activation pipeline checks passed."
exit 0
