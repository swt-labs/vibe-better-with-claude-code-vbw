#!/usr/bin/env bash
set -euo pipefail

# verify-skill-activation.sh — Verify skill activation pipeline (issue #191)
#
# Checks:
# - evaluate-skills.sh exists and is executable
# - vbw-dev.md has description-based skill activation cue
# - vbw-lead.md has Skill in tools and description-based cue
# - All agents with explicit tools: allowlists include Skill
# - compile-context.sh uses evaluate-skills.sh and emits table for all roles
# - execute-protocol.md documents forced evaluation

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

echo "=== Skill Activation Pipeline Verification (issue #191) ==="

# --- evaluate-skills.sh checks ---

EVAL_SCRIPT="$ROOT/scripts/evaluate-skills.sh"

if [ -f "$EVAL_SCRIPT" ]; then
  pass "evaluate-skills.sh: exists"
else
  fail "evaluate-skills.sh: missing"
fi

if [ -x "$EVAL_SCRIPT" ]; then
  pass "evaluate-skills.sh: is executable"
else
  fail "evaluate-skills.sh: not executable"
fi

if grep -q 'Installed:' "$EVAL_SCRIPT"; then
  pass "evaluate-skills.sh: parses **Installed:** line from STATE.md"
else
  fail "evaluate-skills.sh: missing **Installed:** parser"
fi

if grep -q 'SKILL.md' "$EVAL_SCRIPT"; then
  pass "evaluate-skills.sh: locates SKILL.md files on disk"
else
  fail "evaluate-skills.sh: missing SKILL.md lookup"
fi

if grep -q 'description' "$EVAL_SCRIPT"; then
  pass "evaluate-skills.sh: extracts description from frontmatter"
else
  fail "evaluate-skills.sh: missing description extraction"
fi

# --- vbw-dev.md checks ---

DEV_AGENT="$ROOT/agents/vbw-dev.md"

if grep -q 'Skill activation' "$DEV_AGENT"; then
  pass "vbw-dev.md: has skill activation cue"
else
  fail "vbw-dev.md: missing skill activation cue"
fi

if grep -q 'description' "$DEV_AGENT" && grep -q 'Skill(skill-name)' "$DEV_AGENT"; then
  pass "vbw-dev.md: references description-based Skill() evaluation"
else
  fail "vbw-dev.md: missing description-based Skill() evaluation"
fi

if grep -q 'skills_used' "$DEV_AGENT"; then
  pass "vbw-dev.md: references skills_used frontmatter"
else
  fail "vbw-dev.md: missing skills_used reference"
fi

# --- vbw-lead.md checks ---

LEAD_AGENT="$ROOT/agents/vbw-lead.md"
LEAD_TOOLS=$(sed -n '/^---$/,/^---$/p' "$LEAD_AGENT" | grep '^tools:' || true)

if echo "$LEAD_TOOLS" | grep -q 'Skill'; then
  pass "vbw-lead.md: Skill in tools allowlist"
else
  fail "vbw-lead.md: Skill NOT in tools allowlist"
fi

if grep -q 'description' "$LEAD_AGENT" && grep -q 'Skill(skill-name)' "$LEAD_AGENT"; then
  pass "vbw-lead.md: Stage 1 references description-based Skill() evaluation"
else
  fail "vbw-lead.md: Stage 1 missing description-based Skill() evaluation"
fi

if grep -q 'Skill completeness check' "$LEAD_AGENT"; then
  pass "vbw-lead.md: has skill completeness gate in self-review"
else
  fail "vbw-lead.md: missing skill completeness gate in self-review"
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

# --- compile-context.sh checks ---

COMPILER="$ROOT/scripts/compile-context.sh"

if grep -q 'evaluate-skills.sh' "$COMPILER"; then
  pass "compile-context.sh: calls evaluate-skills.sh"
else
  fail "compile-context.sh: missing evaluate-skills.sh call"
fi

if grep -q 'emit_skill_directive' "$COMPILER"; then
  pass "compile-context.sh: has emit_skill_directive function"
else
  fail "compile-context.sh: missing emit_skill_directive function"
fi

if grep -q '### Installed Skills' "$COMPILER"; then
  pass "compile-context.sh: emits '### Installed Skills' header"
else
  fail "compile-context.sh: missing '### Installed Skills' header"
fi

if grep -q '| Skill | Description |' "$COMPILER"; then
  pass "compile-context.sh: emits skill table with descriptions"
else
  fail "compile-context.sh: missing skill table format"
fi

if grep -q 'cat "$SKILL_FILE"' "$COMPILER"; then
  fail "compile-context.sh: still has old text bundling (cat SKILL_FILE)"
else
  pass "compile-context.sh: old text bundling removed"
fi

# Check skill directive wired to all 6 roles
for role in dev lead qa scout debugger architect; do
  if grep -A5 "context-${role}.md" "$COMPILER" | grep -q 'emit_skill_directive' 2>/dev/null || \
     grep -B50 "context-${role}.md" "$COMPILER" | grep -q 'emit_skill_directive' 2>/dev/null; then
    pass "compile-context.sh: skill directive wired to ${role} role"
  else
    fail "compile-context.sh: skill directive NOT wired to ${role} role"
  fi
done

# --- execute-protocol.md checks ---

PROTOCOL="$ROOT/references/execute-protocol.md"

if grep -q 'evaluate-skills.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: documents evaluate-skills.sh"
else
  fail "execute-protocol.md: missing evaluate-skills.sh documentation"
fi

if grep -q 'description' "$PROTOCOL" && grep -q 'Skill(skill-name)' "$PROTOCOL"; then
  pass "execute-protocol.md: documents description-based Skill() activation"
else
  fail "execute-protocol.md: missing description-based activation documentation"
fi

if grep -q 'bundles referenced SKILL.md content' "$PROTOCOL"; then
  fail "execute-protocol.md: still has old text bundling documentation"
else
  pass "execute-protocol.md: old text bundling documentation removed"
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
