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

if grep -q 'missing from `skills_used`' "$DEV_AGENT"; then
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

# --- Agent activation instruction checks ---

QA_AGENT="$ROOT/agents/vbw-qa.md"

if grep -q 'skills_used' "$QA_AGENT"; then
  pass "vbw-qa.md: references skills_used for plan-driven activation"
else
  fail "vbw-qa.md: missing skills_used reference"
fi

if grep -q 'Skill(skill-name)' "$QA_AGENT"; then
  pass "vbw-qa.md: references Skill() activation"
else
  fail "vbw-qa.md: missing Skill() reference"
fi

if grep -q 'available_skills' "$QA_AGENT"; then
  pass "vbw-qa.md: references available_skills for ad-hoc fallback"
else
  fail "vbw-qa.md: missing available_skills reference for ad-hoc fallback"
fi

SCOUT_AGENT="$ROOT/agents/vbw-scout.md"

if grep -q 'skills_used' "$SCOUT_AGENT"; then
  pass "vbw-scout.md: references skills_used for plan-driven path"
else
  fail "vbw-scout.md: missing skills_used reference"
fi

if grep -q 'available_skills' "$SCOUT_AGENT"; then
  pass "vbw-scout.md: references available_skills for ad-hoc path"
else
  fail "vbw-scout.md: missing available_skills reference for ad-hoc path"
fi

DEBUGGER_AGENT="$ROOT/agents/vbw-debugger.md"

if grep -q 'available_skills' "$DEBUGGER_AGENT"; then
  pass "vbw-debugger.md: references available_skills for ad-hoc activation"
else
  fail "vbw-debugger.md: missing available_skills reference"
fi

if grep -q 'Skill(skill-name)' "$DEBUGGER_AGENT"; then
  pass "vbw-debugger.md: references Skill() activation"
else
  fail "vbw-debugger.md: missing Skill() reference"
fi

ARCHITECT_AGENT="$ROOT/agents/vbw-architect.md"

if grep -q 'available_skills' "$ARCHITECT_AGENT"; then
  pass "vbw-architect.md: references available_skills for ad-hoc activation"
else
  fail "vbw-architect.md: missing available_skills reference"
fi

if grep -q 'Skill(skill-name)' "$ARCHITECT_AGENT"; then
  pass "vbw-architect.md: references Skill() activation"
else
  fail "vbw-architect.md: missing Skill() reference"
fi

DOCS_AGENT="$ROOT/agents/vbw-docs.md"

if grep -q 'skills_used' "$DOCS_AGENT"; then
  pass "vbw-docs.md: references skills_used for plan-driven activation"
else
  fail "vbw-docs.md: missing skills_used reference"
fi

if grep -q 'Skill(skill-name)' "$DOCS_AGENT"; then
  pass "vbw-docs.md: references Skill() activation"
else
  fail "vbw-docs.md: missing Skill() reference"
fi

if grep -q 'available_skills' "$DOCS_AGENT"; then
  pass "vbw-docs.md: references available_skills for ad-hoc fallback"
else
  fail "vbw-docs.md: missing available_skills reference for ad-hoc fallback"
fi

# Dev ad-hoc fallback check
if grep -q 'available_skills' "$DEV_AGENT"; then
  pass "vbw-dev.md: references available_skills for ad-hoc fallback"
else
  fail "vbw-dev.md: missing available_skills reference for ad-hoc fallback"
fi

# Protocol updated role coverage checks
if grep -q 'Dev/QA/Scout/Docs' "$PROTOCOL"; then
  pass "execute-protocol.md: documents all execution-time agents (Dev/QA/Scout/Docs)"
else
  fail "execute-protocol.md: missing updated agent coverage"
fi

if grep -q 'Debugger/Dev/Scout' "$PROTOCOL"; then
  pass "execute-protocol.md: names Debugger explicitly in ad-hoc paths"
else
  fail "execute-protocol.md: ad-hoc paths missing Debugger"
fi

if grep -q 'vbw:debug' "$PROTOCOL"; then
  pass "execute-protocol.md: documents /vbw:debug ad-hoc path"
else
  fail "execute-protocol.md: missing /vbw:debug documentation"
fi

# --- Skill-hook dispatch field name checks ---

DISPATCHER="$ROOT/scripts/skill-hook-dispatch.sh"

if grep -q '\.tools // \..*\.matcher' "$DISPATCHER"; then
  pass "skill-hook-dispatch.sh: reads both tools and matcher (backward compat)"
else
  fail "skill-hook-dispatch.sh: missing backward compat for matcher field"
fi

CONFIG_CMD="$ROOT/commands/config.md"

if grep -q 'skill_hook <skill> <event> <tools>' "$CONFIG_CMD"; then
  pass "config.md: skill_hook signature uses tools (not matcher)"
else
  fail "config.md: skill_hook signature still uses matcher"
fi

if grep -q '"tools": "Write|Edit"' "$CONFIG_CMD"; then
  pass "config.md: example JSON uses tools field"
else
  fail "config.md: example JSON still uses matcher field"
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

# --- emit-skill-xml.sh contract checks ---

if [ -f "$ROOT/scripts/emit-skill-xml.sh" ]; then
  pass "emit-skill-xml.sh: exists"
else
  fail "emit-skill-xml.sh: missing"
fi

if [ -x "$ROOT/scripts/emit-skill-xml.sh" ]; then
  pass "emit-skill-xml.sh: is executable"
else
  fail "emit-skill-xml.sh: not executable"
fi

# --- emit-skill-xml.sh supports --filter-plugins flag ---

if grep -q '\-\-filter-plugins' "$ROOT/scripts/emit-skill-xml.sh"; then
  pass "emit-skill-xml.sh: supports --filter-plugins flag"
else
  fail "emit-skill-xml.sh: missing --filter-plugins flag support"
fi

# --- emit-skill-xml.sh supports --compact flag ---

if grep -q '\-\-compact' "$ROOT/scripts/emit-skill-xml.sh"; then
  pass "emit-skill-xml.sh: supports --compact flag"
else
  fail "emit-skill-xml.sh: missing --compact flag support"
fi

# --- emit-skill-xml.sh filters VBW/GSD skills ---

if grep -q 'vbw-\*|gsd-\*' "$ROOT/scripts/emit-skill-xml.sh" || grep -q '_is_plugin_skill' "$ROOT/scripts/emit-skill-xml.sh"; then
  pass "emit-skill-xml.sh: has VBW/GSD skill filtering"
else
  fail "emit-skill-xml.sh: missing VBW/GSD skill filtering"
fi

# --- inject-subagent-skills.sh contract checks ---

if [ -f "$ROOT/scripts/inject-subagent-skills.sh" ]; then
  pass "inject-subagent-skills.sh: exists"
else
  fail "inject-subagent-skills.sh: missing"
fi

if grep -q 'SKILL ACTIVATION' "$ROOT/scripts/inject-subagent-skills.sh"; then
  pass "inject-subagent-skills.sh: has evaluation instruction"
else
  fail "inject-subagent-skills.sh: missing evaluation instruction"
fi

if grep -q 'filter-plugins' "$ROOT/scripts/inject-subagent-skills.sh"; then
  pass "inject-subagent-skills.sh: calls emit-skill-xml.sh with --filter-plugins"
else
  fail "inject-subagent-skills.sh: not filtering plugins in subagent injection"
fi

if grep -q 'SubagentStart' "$ROOT/scripts/inject-subagent-skills.sh"; then
  pass "inject-subagent-skills.sh: outputs SubagentStart hookEventName"
else
  fail "inject-subagent-skills.sh: missing SubagentStart hookEventName"
fi

# --- hooks.json registers inject-subagent-skills.sh in SubagentStart ---

if grep -q 'inject-subagent-skills.sh' "$HOOKS_FILE"; then
  pass "hooks.json: inject-subagent-skills.sh registered in SubagentStart"
else
  fail "hooks.json: inject-subagent-skills.sh NOT registered in SubagentStart"
fi

# --- session-start.sh uses compact skill names (not full XML) ---

if grep -q 'Installed skills:' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: uses compact skill name list"
else
  fail "session-start.sh: not using compact skill name list"
fi

if grep -q 'filter-plugins' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: filters plugins in skill name extraction"
else
  fail "session-start.sh: not filtering plugins in session-start"
fi

# --- session-start.sh has GSD co-installation warning ---

if grep -q 'GSD_WARNING' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: has GSD co-installation warning"
else
  fail "session-start.sh: missing GSD co-installation warning"
fi

if grep -q 'gsd:\*' "$ROOT/scripts/session-start.sh" || grep -q '/gsd:' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: GSD warning references /gsd:* commands"
else
  fail "session-start.sh: GSD warning missing /gsd:* reference"
fi

# --- Agent YAML: no maxTurns in frontmatter ---

for agent_file in vbw-dev.md vbw-qa.md vbw-docs.md vbw-lead.md vbw-scout.md vbw-architect.md vbw-debugger.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"
  FRONTMATTER=$(sed -n '/^---$/,/^---$/p' "$AGENT_PATH")
  if echo "$FRONTMATTER" | grep -q '^maxTurns:'; then
    fail "$agent_file: maxTurns still in YAML frontmatter (should be removed)"
  else
    pass "$agent_file: no maxTurns in YAML frontmatter"
  fi
done

# --- session-start.sh calls emit-skill-xml.sh ---

if grep -q 'emit-skill-xml.sh' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: calls emit-skill-xml.sh"
else
  fail "session-start.sh: does not call emit-skill-xml.sh"
fi

# --- All 7 agents reference <available_skills> ---

for agent_file in vbw-dev.md vbw-qa.md vbw-docs.md vbw-lead.md vbw-scout.md vbw-architect.md vbw-debugger.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"
  if grep -q 'available_skills' "$AGENT_PATH"; then
    pass "$agent_file: references <available_skills>"
  else
    fail "$agent_file: missing <available_skills> reference"
  fi
done

# --- execute-protocol.md documents emit-skill-xml.sh ---

if grep -q 'emit-skill-xml.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: documents emit-skill-xml.sh"
else
  fail "execute-protocol.md: missing emit-skill-xml.sh documentation"
fi

if grep -q 'available_skills' "$PROTOCOL"; then
  pass "execute-protocol.md: references <available_skills> XML"
else
  fail "execute-protocol.md: missing <available_skills> reference"
fi

# --- Functional test: inject-subagent-skills.sh with VBW agent ---

_INJECT_SCRIPT="$ROOT/scripts/inject-subagent-skills.sh"
if [ -f "$_INJECT_SCRIPT" ]; then
  # Set up minimal VBW context
  _INJECT_TMP=$(mktemp -d)
  mkdir -p "$_INJECT_TMP/.vbw-planning"
  touch "$_INJECT_TMP/.vbw-planning/.vbw-session"

  # Test: VBW agent produces hookSpecificOutput JSON
  _INJECT_OUT=$(cd "$_INJECT_TMP" && echo '{"agent_type":"vbw-dev"}' | CLAUDE_PLUGIN_ROOT="$ROOT" bash "$_INJECT_SCRIPT" 2>/dev/null || true)
  if echo "$_INJECT_OUT" | grep -q '"hookEventName"'; then
    pass "inject-subagent-skills.sh: VBW agent produces hookSpecificOutput JSON"
  else
    fail "inject-subagent-skills.sh: VBW agent did not produce hookSpecificOutput JSON"
  fi

  if echo "$_INJECT_OUT" | grep -q 'SKILL ACTIVATION'; then
    pass "inject-subagent-skills.sh: output contains evaluation instruction"
  else
    fail "inject-subagent-skills.sh: output missing evaluation instruction"
  fi

  # Test: non-VBW agent produces no output
  _INJECT_OUT_NON=$(cd "$_INJECT_TMP" && echo '{"agent_type":"gsd-planner"}' | CLAUDE_PLUGIN_ROOT="$ROOT" bash "$_INJECT_SCRIPT" 2>/dev/null || true)
  if [ -z "$_INJECT_OUT_NON" ]; then
    pass "inject-subagent-skills.sh: non-VBW agent produces empty output"
  else
    fail "inject-subagent-skills.sh: non-VBW agent should produce empty output"
  fi

  # Test: bare "dev" without VBW context markers exits silently
  _INJECT_TMP2=$(mktemp -d)
  mkdir -p "$_INJECT_TMP2/.vbw-planning"
  # No .vbw-session, .active-agent, or .active-agent-count
  _INJECT_OUT_BARE=$(cd "$_INJECT_TMP2" && echo '{"agent_type":"dev"}' | CLAUDE_PLUGIN_ROOT="$ROOT" bash "$_INJECT_SCRIPT" 2>/dev/null || true)
  if [ -z "$_INJECT_OUT_BARE" ]; then
    pass "inject-subagent-skills.sh: bare 'dev' without VBW context exits silently"
  else
    fail "inject-subagent-skills.sh: bare 'dev' without VBW context should exit silently"
  fi

  rm -rf "$_INJECT_TMP" "$_INJECT_TMP2"
else
  fail "inject-subagent-skills.sh: script not found"
fi

# --- normalize_agent_role consistency: agent-start.sh and inject-subagent-skills.sh ---

_AGENT_START="$ROOT/scripts/agent-start.sh"
_INJECT_SCRIPT="$ROOT/scripts/inject-subagent-skills.sh"

# Extract role patterns from both scripts and compare
_ROLES_AGENT_START=$(sed -n '/normalize_agent_role/,/^}/p' "$_AGENT_START" | grep "printf '" | sed "s/.*printf '\\([^']*\\)'.*/\\1/" | sort)
_ROLES_INJECT=$(sed -n '/normalize_agent_role/,/^}/p' "$_INJECT_SCRIPT" | grep "printf '" | sed "s/.*printf '\\([^']*\\)'.*/\\1/" | sort)

if [ "$_ROLES_AGENT_START" = "$_ROLES_INJECT" ]; then
  pass "normalize_agent_role: agent-start.sh and inject-subagent-skills.sh handle same roles"
else
  fail "normalize_agent_role: role mismatch between agent-start.sh and inject-subagent-skills.sh"
fi

# Verify all 7 roles are present in agent-start.sh
for _role in architect debugger dev docs lead qa scout; do
  if echo "$_ROLES_AGENT_START" | grep -q "^${_role}$"; then
    pass "agent-start.sh: normalize handles '$_role' role"
  else
    fail "agent-start.sh: normalize missing '$_role' role"
  fi
done

# --- maxTurns conditional omission: all commands that spawn agents ---

# Every command that references maxTurns: ${...} must also have "omit" or "do NOT include"
_MAX_TURNS_COMMANDS=$(grep -rl 'maxTurns.*\${' "$ROOT/commands/" "$ROOT/references/" 2>/dev/null || true)
_MT_FAIL=0
for _cmd_file in $_MAX_TURNS_COMMANDS; do
  _cmd_name=$(basename "$_cmd_file")
  if grep -q 'omit\|do NOT include maxTurns' "$_cmd_file"; then
    pass "$_cmd_name: maxTurns has conditional omission logic"
  else
    fail "$_cmd_name: maxTurns passed unconditionally (missing zero check)"
    _MT_FAIL=1
  fi
done
if [ -z "$_MAX_TURNS_COMMANDS" ]; then
  pass "maxTurns: no commands reference maxTurns (nothing to check)"
fi

# --- 3-Layer skill activation pipeline checks ---

echo ""
echo "=== 3-Layer Skill Activation Pipeline ==="

# Layer 1: All 7 agents have mandatory skill activation section
for agent_file in vbw-lead.md vbw-dev.md vbw-qa.md vbw-scout.md vbw-debugger.md vbw-architect.md vbw-docs.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"
  if grep -q '## Skill Activation (mandatory)' "$AGENT_PATH"; then
    pass "$agent_file: has ## Skill Activation (mandatory) section"
  else
    fail "$agent_file: missing ## Skill Activation (mandatory) section"
  fi
done

# Layer 2: Script-driven skill activation (generate-skill-activation.sh)
if [ -f "$ROOT/scripts/generate-skill-activation.sh" ]; then
  pass "generate-skill-activation.sh: exists"
else
  fail "generate-skill-activation.sh: missing"
fi

if [ -x "$ROOT/scripts/generate-skill-activation.sh" ]; then
  pass "generate-skill-activation.sh: is executable"
else
  fail "generate-skill-activation.sh: not executable"
fi

# generate-skill-activation.sh calls emit-skill-xml.sh for available skills
if grep -q 'emit-skill-xml.sh' "$ROOT/scripts/generate-skill-activation.sh"; then
  pass "generate-skill-activation.sh: calls emit-skill-xml.sh for available skills"
else
  fail "generate-skill-activation.sh: missing emit-skill-xml.sh call"
fi

# generate-skill-activation.sh supports --phase-dir for sidecar file
if grep -q '\-\-phase-dir' "$ROOT/scripts/generate-skill-activation.sh"; then
  pass "generate-skill-activation.sh: supports --phase-dir flag"
else
  fail "generate-skill-activation.sh: missing --phase-dir support"
fi

# generate-skill-activation.sh reads skills_used from plan frontmatter
if grep -q 'skills_used' "$ROOT/scripts/generate-skill-activation.sh"; then
  pass "generate-skill-activation.sh: reads skills_used from plan frontmatter"
else
  fail "generate-skill-activation.sh: missing skills_used reading"
fi

# compile-context.sh calls generate-skill-activation.sh
if grep -q 'generate-skill-activation.sh' "$COMPILER"; then
  pass "compile-context.sh: calls generate-skill-activation.sh"
else
  fail "compile-context.sh: missing generate-skill-activation.sh call"
fi

# compile-context.sh emits Mandatory Skill Activation section
if grep -q 'Mandatory Skill Activation' "$COMPILER"; then
  pass "compile-context.sh: emits Mandatory Skill Activation section"
else
  fail "compile-context.sh: missing Mandatory Skill Activation section"
fi

# execute-protocol.md references .skill-activation-block.txt sidecar
if grep -q 'skill-activation-block.txt' "$PROTOCOL"; then
  pass "execute-protocol.md: references .skill-activation-block.txt sidecar"
else
  fail "execute-protocol.md: missing .skill-activation-block.txt reference"
fi

if [ ! -f "$ROOT/scripts/emit-skill-prompt-line.sh" ]; then
  pass "emit-skill-prompt-line.sh: deleted (replaced by generate-skill-activation.sh)"
else
  fail "emit-skill-prompt-line.sh: still exists (should be deleted)"
fi

# Negative: SKILL_PROMPT_LINE should NOT appear in any command/reference
VIBE_CMD="$ROOT/commands/vibe.md"
RESEARCH_CMD="$ROOT/commands/research.md"
if ! grep -q 'SKILL_PROMPT_LINE' "$PROTOCOL"; then
  pass "execute-protocol.md: no SKILL_PROMPT_LINE references (removed)"
else
  fail "execute-protocol.md: still references SKILL_PROMPT_LINE"
fi

if ! grep -q 'SKILL_PROMPT_LINE' "$VIBE_CMD"; then
  pass "vibe.md: no SKILL_PROMPT_LINE references (removed)"
else
  fail "vibe.md: still references SKILL_PROMPT_LINE"
fi

if ! grep -q 'SKILL_PROMPT_LINE' "$RESEARCH_CMD"; then
  pass "research.md: no SKILL_PROMPT_LINE references (removed)"
else
  fail "research.md: still references SKILL_PROMPT_LINE"
fi

# Positive: script-driven skill activation block in execute-protocol (team swarm spawns)
if grep -q 'generate-skill-activation.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: references generate-skill-activation.sh"
else
  fail "execute-protocol.md: missing generate-skill-activation.sh reference"
fi

# Negative: old LLM-composed skill selection removed from execute-protocol
# (vibe.md and research.md correctly use orchestrator-composed skill_activation for Scout/Lead)
if ! grep -q 'select skills from installed skills visible in your system context' "$PROTOCOL"; then
  pass "execute-protocol.md: old LLM-composed skill selection removed"
else
  fail "execute-protocol.md: still has old LLM-composed skill selection instruction"
fi

# Positive: SKILL_BLOCK variable used in execute-protocol (Dev/QA team spawns)
if grep -q 'SKILL_BLOCK' "$PROTOCOL"; then
  pass "execute-protocol.md: SKILL_BLOCK variable referenced for team spawns"
else
  fail "execute-protocol.md: SKILL_BLOCK variable missing"
fi

# Positive: orchestrator-composed skill_activation in Scout/Lead spawn templates
if grep -q 'skill_activation' "$VIBE_CMD" && grep -q 'skill_activation' "$RESEARCH_CMD"; then
  pass "vibe.md + research.md: orchestrator-composed skill_activation for Scout/Lead spawns"
else
  fail "vibe.md or research.md: missing skill_activation in Scout/Lead spawn templates"
fi

# Anti-LLM-composition directive in execute-protocol (Dev/QA teams)
if grep -q 'Do NOT attempt to compose skill activation yourself' "$PROTOCOL"; then
  pass "execute-protocol.md: anti-LLM-composition directive present"
else
  fail "execute-protocol.md: missing anti-LLM-composition directive"
fi

if ! (grep -Ei 'skill_activation|Skill\(' "$PROTOCOL" "$VIBE_CMD" "$RESEARCH_CMD" | grep -qiE 'if you need|if relevant|clearly relevant'); then
  pass "skill activation prompts: no weak conditional phrasing in skill-instruction lines"
else
  fail "skill activation prompts: weak conditional phrasing present in skill-instruction lines"
fi

# Agent system prompts: no 'clearly relevant' in any agent file
if ! grep -rq 'clearly relevant' "$ROOT/agents/"; then
  pass "agent prompts: no 'clearly relevant' conditional phrasing"
else
  fail "agent prompts: 'clearly relevant' still present — use direct imperative language"
fi

# Negative: no STATE.md Installed fallback in agent skill activation sections
if ! grep -rq 'STATE.md.*Installed\|Installed.*STATE.md' "$ROOT/agents/"; then
  pass "agent prompts: no STATE.md Installed fallback (removed — skills surfaced via available_skills)"
else
  fail "agent prompts: STATE.md Installed fallback still present in agents"
fi

# Negative: .skill-names should NOT be in planning-git transient gitignore
if ! grep -q '\.skill-names' "$ROOT/scripts/planning-git.sh"; then
  pass "planning-git.sh: no .skill-names in transient gitignore (removed)"
else
  fail "planning-git.sh: still has .skill-names in transient gitignore"
fi

# Brownfield: session-start.sh should clean up stale .skill-names
if grep -q 'rm.*\.skill-names' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: has brownfield .skill-names cleanup"
else
  fail "session-start.sh: missing brownfield .skill-names cleanup"
fi

# Layer 3: SubagentStart hook (preserved)
if grep -q 'inject-subagent-skills.sh' "$HOOKS_FILE"; then
  pass "hooks.json: inject-subagent-skills.sh registered (Layer 3)"
else
  fail "hooks.json: inject-subagent-skills.sh missing (Layer 3)"
fi

# Compaction durability: compile-context.sh emits skills for all 6 compiled roles
COMPILER="$ROOT/scripts/compile-context.sh"
for role in lead dev qa scout debugger architect; do
  # Check that the role case block calls emit_skills_section
  if awk "/^  ${role}\\)/,/;;/" "$COMPILER" | grep -q 'emit_skills_section'; then
    pass "compile-context.sh: calls emit_skills_section for $role"
  else
    fail "compile-context.sh: missing emit_skills_section for $role"
  fi
done

# Negative check: no file should use the old "is 0" / "is a positive integer" phrasing
for _cmd_file in $_MAX_TURNS_COMMANDS; do
  _cmd_name=$(basename "$_cmd_file")
  if grep -q 'MAX_TURNS.*is 0' "$_cmd_file" || grep -q 'MAX_TURNS.*is a positive integer' "$_cmd_file"; then
    fail "$_cmd_name: uses old 'is 0'/'is a positive integer' phrasing (should use non-empty/empty)"
  else
    pass "$_cmd_name: uses non-empty/empty phrasing for maxTurns"
  fi
done

# --- Subagent type specification: all spawn points must specify subagent_type ---

echo ""
echo "=== Subagent Type Verification ==="

# Count subagent_type occurrences across commands and references
_SAT_TOTAL=$(grep -r 'subagent_type.*vbw:' "$ROOT/commands/" "$ROOT/references/" 2>/dev/null | wc -l | tr -d ' ')

if [ "$_SAT_TOTAL" -ge 16 ]; then
  pass "subagent_type: ${_SAT_TOTAL} spawn points specify subagent_type (>= 16 expected)"
else
  fail "subagent_type: only ${_SAT_TOTAL} spawn points specify subagent_type (>= 16 expected)"
fi

# Each role that spawns agents must have subagent_type for that role
for _role_check in "vbw-scout:commands/vibe.md" "vbw-scout:commands/research.md" "vbw-scout:commands/map.md" "vbw-dev:commands/fix.md" "vbw-dev:references/execute-protocol.md" "vbw-debugger:commands/debug.md" "vbw-qa:commands/qa.md" "vbw-qa:references/execute-protocol.md" "vbw-lead:commands/vibe.md"; do
  _sat_role="${_role_check%%:*}"
  _sat_file="${_role_check#*:}"
  if grep -q "subagent_type.*${_sat_role}" "$ROOT/$_sat_file"; then
    pass "$_sat_file: specifies subagent_type for $_sat_role"
  else
    fail "$_sat_file: missing subagent_type for $_sat_role"
  fi
done

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All skill activation pipeline checks passed."
exit 0
