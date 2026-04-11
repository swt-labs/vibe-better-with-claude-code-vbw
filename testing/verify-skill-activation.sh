#!/usr/bin/env bash
set -euo pipefail

# verify-skill-activation.sh — Verify plan-driven skill activation pipeline
#
# Checks:
# - vbw-dev.md references skills_used activation
# - vbw-lead.md references skill evaluation and wiring
# - orchestrator spawn contracts emit explicit activation OR explicit no-activation blocks
# - hooks.json does NOT contain skill-evaluation-gate.sh or skill-eval-prompt-gate.sh
# - All agents with explicit tools: allowlists include Skill
# - execute-protocol.md documents plan-driven approach

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

COMMAND_SKILL_CONTRACT_FILES=(
  "$ROOT/commands/vibe.md"
  "$ROOT/commands/research.md"
  "$ROOT/commands/map.md"
  "$ROOT/commands/fix.md"
  "$ROOT/commands/debug.md"
  "$ROOT/commands/qa.md"
  "$ROOT/references/execute-protocol.md"
)

AGENT_SKILL_CONTRACT_FILES=(
  "$ROOT/agents/vbw-lead.md"
  "$ROOT/agents/vbw-dev.md"
  "$ROOT/agents/vbw-qa.md"
  "$ROOT/agents/vbw-scout.md"
  "$ROOT/agents/vbw-debugger.md"
  "$ROOT/agents/vbw-architect.md"
  "$ROOT/agents/vbw-docs.md"
)

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

expected_skill_contract_sites() {
  case "$(basename "$1")" in
    vibe.md) echo 8 ;;
    debug.md) echo 2 ;;
    research.md|fix.md|qa.md|execute-protocol.md) echo 1 ;;
    map.md) echo 2 ;;
    *) echo 0 ;;
  esac
}

collect_skill_contract_site_lines() {
  local file="$1"
  grep -nE 'evaluate installed skills visible in your system context|Skill activation for Dev/QA tasks' "$file" 2>/dev/null | cut -d: -f1 || true
}

verify_skill_contract_sites() {
  local file="$1"
  local file_name expected_count total_lines start_line end_line site_number
  local segment
  local site_lines=()

  file_name=$(basename "$file")
  expected_count=$(expected_skill_contract_sites "$file")
  total_lines=$(wc -l < "$file" | tr -d ' ')

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    site_lines+=("$line")
  done < <(collect_skill_contract_site_lines "$file")

  if [ "${#site_lines[@]}" -eq "$expected_count" ]; then
    pass "$file_name: found $expected_count explicit skill-evaluation site(s)"
  else
    fail "$file_name: expected $expected_count explicit skill-evaluation site(s), found ${#site_lines[@]}"
  fi

  site_number=1
  while [ "$site_number" -le "${#site_lines[@]}" ]; do
    start_line="${site_lines[$((site_number - 1))]}"
    if [ "$site_number" -lt "${#site_lines[@]}" ]; then
      end_line=$(( ${site_lines[$site_number]} - 1 ))
    else
      end_line="$total_lines"
    fi
    segment=$(sed -n "${start_line},${end_line}p" "$file")

    if grep -q '<skill_activation>' <<< "$segment" \
      && grep -q 'Call Skill(' <<< "$segment"; then
      pass "$file_name: site $site_number has local activation path"
    else
      fail "$file_name: site $site_number missing local activation path"
    fi

    if grep -q '<skill_no_activation>' <<< "$segment" \
      && grep -q 'No installed skills apply\. Reason:' <<< "$segment"; then
      pass "$file_name: site $site_number has local no-activation path"
    else
      fail "$file_name: site $site_number missing local no-activation path"
    fi

    if grep -q 'exactly one explicit' <<< "$segment"; then
      pass "$file_name: site $site_number states explicit one-of-two outcome contract"
    else
      fail "$file_name: site $site_number missing explicit one-of-two outcome wording"
    fi

    if grep -q 'omit the skill_activation block entirely\|omit the block entirely' <<< "$segment"; then
      fail "$file_name: site $site_number still allows silent omission"
    else
      pass "$file_name: site $site_number rejects silent omission"
    fi

    site_number=$((site_number + 1))
  done
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

if grep -Eq 'skill_activation.*skill_no_activation|explicit outcome block' "$DEV_AGENT"; then
  pass "vbw-dev.md: has orchestrator-aware conditional in deeper protocol"
else
  fail "vbw-dev.md: missing orchestrator-aware conditional in deeper protocol"
fi

# --- vbw-lead.md checks ---

LEAD_AGENT="$ROOT/agents/vbw-lead.md"
LEAD_TOOLS=$(sed -n '/^---$/,/^---$/p' "$LEAD_AGENT" | grep '^tools:' || true)

if grep -q 'Skill' <<< "$LEAD_TOOLS"; then
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

if grep -q 'skill_no_activation' "$LEAD_AGENT"; then
  pass "vbw-lead.md: recognizes explicit no-activation block"
else
  fail "vbw-lead.md: missing explicit no-activation handling"
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

# --- Skill in all agent tools: allowlists (or inherited via disallowedTools pattern) ---

for agent_file in vbw-qa.md vbw-scout.md vbw-debugger.md vbw-architect.md vbw-docs.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"
  AGENT_TOOLS=$(sed -n '/^---$/,/^---$/p' "$AGENT_PATH" | grep '^tools:' || true)
  AGENT_DISALLOWED=$(sed -n '/^---$/,/^---$/p' "$AGENT_PATH" | grep '^disallowedTools:' || true)
  if [ -n "$AGENT_TOOLS" ]; then
    # Agent uses tools: allowlist — Skill must be explicitly listed
    if grep -q 'Skill' <<< "$AGENT_TOOLS"; then
      pass "$agent_file: Skill in tools allowlist"
    else
      fail "$agent_file: Skill NOT in tools allowlist"
    fi
  elif [ -n "$AGENT_DISALLOWED" ]; then
    # Agent uses disallowedTools: denylist — Skill is inherited from parent
    if grep -q 'Skill' <<< "$AGENT_DISALLOWED"; then
      fail "$agent_file: Skill is in disallowedTools (should be inherited)"
    else
      pass "$agent_file: Skill inherited via disallowedTools pattern (not denied)"
    fi
  else
    fail "$agent_file: Neither tools: nor disallowedTools: found in frontmatter"
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

if grep -q 'skill_no_activation' "$PROTOCOL"; then
  pass "execute-protocol.md: documents explicit no-activation outcome"
else
  fail "execute-protocol.md: missing explicit no-activation outcome"
fi

if ! grep -q 'No written YES/NO evaluation required' "$PROTOCOL"; then
  pass "execute-protocol.md: legacy silent-decision wording removed"
else
  fail "execute-protocol.md: still says no written YES/NO evaluation is required"
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

if grep -q 'skill_no_activation' "$QA_AGENT"; then
  pass "vbw-qa.md: recognizes explicit no-activation block"
else
  fail "vbw-qa.md: missing explicit no-activation handling"
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

if grep -q 'skill_no_activation' "$SCOUT_AGENT"; then
  pass "vbw-scout.md: recognizes explicit no-activation block"
else
  fail "vbw-scout.md: missing explicit no-activation handling"
fi

if ! grep -q 'may still honor' "$SCOUT_AGENT"; then
  pass "vbw-scout.md: no permissive may-still-honor wording on no-activation path"
else
  fail "vbw-scout.md: still uses permissive may-still-honor wording on no-activation path"
fi

if grep -q 'still honor any `skills_used` frontmatter' "$SCOUT_AGENT"; then
  pass "vbw-scout.md: preserves plan-driven skills_used behavior on no-activation path"
else
  fail "vbw-scout.md: missing mandatory skills_used preservation on no-activation path"
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

if grep -q 'skill_no_activation' "$DEBUGGER_AGENT"; then
  pass "vbw-debugger.md: recognizes explicit no-activation block"
else
  fail "vbw-debugger.md: missing explicit no-activation handling"
fi

if grep -q 'only in standalone/ad-hoc mode when neither `<skill_activation>` nor `<skill_no_activation>` was provided' "$DEBUGGER_AGENT"; then
  pass "vbw-debugger.md: downstream skill activation is gated to true ad-hoc mode"
else
  fail "vbw-debugger.md: downstream skill activation can still bypass explicit no-activation"
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

if grep -q 'skill_no_activation' "$ARCHITECT_AGENT"; then
  pass "vbw-architect.md: recognizes explicit no-activation block"
else
  fail "vbw-architect.md: missing explicit no-activation handling"
fi

if grep -q 'only in standalone/ad-hoc mode when neither `<skill_activation>` nor `<skill_no_activation>` was provided' "$ARCHITECT_AGENT"; then
  pass "vbw-architect.md: downstream skill activation is gated to true ad-hoc mode"
else
  fail "vbw-architect.md: downstream skill activation can still bypass explicit no-activation"
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

if grep -q 'skill_no_activation' "$DOCS_AGENT"; then
  pass "vbw-docs.md: recognizes explicit no-activation block"
else
  fail "vbw-docs.md: missing explicit no-activation handling"
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

# --- emit-skill-xml.sh deleted (skill visibility is native to Claude Code) ---

if [ ! -f "$ROOT/scripts/emit-skill-xml.sh" ]; then
  pass "emit-skill-xml.sh: deleted (native CC skill visibility)"
else
  fail "emit-skill-xml.sh: still exists (should be deleted)"
fi

# --- inject-subagent-skills.sh removed (skill visibility is native to Claude Code) ---

if [ ! -f "$ROOT/scripts/inject-subagent-skills.sh" ]; then
  pass "inject-subagent-skills.sh: deleted (additionalContext injection removed)"
else
  fail "inject-subagent-skills.sh: still exists (should be deleted)"
fi

if ! grep -q 'inject-subagent-skills.sh' "$HOOKS_FILE"; then
  pass "hooks.json: inject-subagent-skills.sh removed from SubagentStart"
else
  fail "hooks.json: inject-subagent-skills.sh still present in SubagentStart"
fi

# --- session-start.sh no longer injects skill names (native CC skill visibility) ---

if ! grep -q 'emit-skill-xml.sh' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: no longer calls emit-skill-xml.sh (additionalContext injection removed)"
else
  fail "session-start.sh: still calls emit-skill-xml.sh (should be removed)"
fi

if ! grep -q 'Installed skills:' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: no longer injects skill names into additionalContext"
else
  fail "session-start.sh: still injects skill names into additionalContext"
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
  if grep -q '^maxTurns:' <<< "$FRONTMATTER"; then
    fail "$agent_file: maxTurns still in YAML frontmatter (should be removed)"
  else
    pass "$agent_file: no maxTurns in YAML frontmatter"
  fi
done

# --- session-start.sh no longer calls emit-skill-xml.sh ---

if ! grep -q 'emit-skill-xml.sh' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: emit-skill-xml.sh call removed"
else
  fail "session-start.sh: still calls emit-skill-xml.sh (should be removed)"
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

# --- execute-protocol.md no longer documents emit-skill-xml.sh ---

if ! grep -q 'emit-skill-xml.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: emit-skill-xml.sh references removed"
else
  fail "execute-protocol.md: still references emit-skill-xml.sh (should be removed)"
fi

if grep -q 'available_skills' "$PROTOCOL"; then
  pass "execute-protocol.md: references skills awareness"
else
  fail "execute-protocol.md: missing skills awareness reference"
fi

# --- Functional test: inject-subagent-skills.sh removed ---

# inject-subagent-skills.sh has been deleted; skill visibility is native to Claude Code.
# The functional tests for that script are no longer applicable.

# --- normalize_agent_role consistency: agent-start.sh role coverage ---

_AGENT_START="$ROOT/scripts/agent-start.sh"

# Extract role patterns from agent-start.sh
_ROLES_AGENT_START=$(sed -n '/normalize_agent_role/,/^}/p' "$_AGENT_START" | grep "printf '" | sed "s/.*printf '\\([^']*\\)'.*/\\1/" | sort)

# Verify all 7 roles are present in agent-start.sh
for _role in architect debugger dev docs lead qa scout; do
  if grep -q "^${_role}$" <<< "$_ROLES_AGENT_START"; then
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

echo ""
echo "=== Explicit Skill Outcome Contract ==="

for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  contract_name=$(basename "$contract_file")
  if grep -q 'skill_no_activation' "$contract_file"; then
    pass "$contract_name: contains explicit no-activation outcome"
  else
    fail "$contract_name: missing explicit no-activation outcome"
  fi
done

for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  verify_skill_contract_sites "$contract_file"
done

for agent_file in "${AGENT_SKILL_CONTRACT_FILES[@]}"; do
  agent_name=$(basename "$agent_file")
  if grep -q 'skill_no_activation' "$agent_file"; then
    pass "$agent_name: handles explicit no-activation outcome"
  else
    fail "$agent_name: missing explicit no-activation handling"
  fi
done

for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  contract_name=$(basename "$contract_file")
  if grep -q 'omit the skill_activation block entirely\|omit the block entirely' "$contract_file"; then
    fail "$contract_name: still allows silent omission of skill outcome blocks"
  else
    pass "$contract_name: bans silent omission wording"
  fi
done

if ! grep -q 'Same as Add Phase step 5' "$ROOT/commands/vibe.md"; then
  pass "vibe.md: insert-phase Scout contract is local, not shorthand"
else
  fail "vibe.md: insert-phase Scout contract still relies on Add Phase shorthand"
fi

# Layer 1: All 7 agents have conditional skill activation section
for agent_file in vbw-lead.md vbw-dev.md vbw-qa.md vbw-scout.md vbw-debugger.md vbw-architect.md vbw-docs.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"
  if grep -q '## Skill Activation' "$AGENT_PATH"; then
    pass "$agent_file: has ## Skill Activation section"
  else
    fail "$agent_file: missing ## Skill Activation section"
  fi
done

# Layer 1b: Agents using disallowedTools (denylist) must have MCP Tool Usage section
# Agents with disallowedTools inherit MCP tools from the parent session, so they need
# guidance on when/how to use them. Agents with tools allowlist block MCP inheritance.
echo ""
echo "=== MCP Tool Usage Section (disallowedTools agents) ==="
for agent_file in "$ROOT"/agents/vbw-*.md; do
  agent_name=$(basename "$agent_file")
  if grep -q '^disallowedTools:' "$agent_file"; then
    if grep -q '## MCP Tool Usage' "$agent_file"; then
      pass "$agent_name: has ## MCP Tool Usage section (uses disallowedTools denylist)"
    else
      fail "$agent_name: missing ## MCP Tool Usage section (uses disallowedTools but no MCP guidance)"
    fi
  fi
done

# Layer 2: Script-driven skill activation removed (replaced by orchestrator-composed intelligent selection)
if [ ! -f "$ROOT/scripts/generate-skill-activation.sh" ]; then
  pass "generate-skill-activation.sh: deleted (replaced by intelligent orchestrator selection)"
else
  fail "generate-skill-activation.sh: still exists (should be deleted)"
fi

# compile-context.sh should NOT call generate-skill-activation.sh or emit_skills_section
if ! grep -q 'generate-skill-activation.sh' "$COMPILER"; then
  pass "compile-context.sh: no longer calls generate-skill-activation.sh"
else
  fail "compile-context.sh: still calls generate-skill-activation.sh (should be removed)"
fi

if ! grep -q 'emit_skills_section' "$COMPILER"; then
  pass "compile-context.sh: emit_skills_section removed"
else
  fail "compile-context.sh: still has emit_skills_section (should be removed)"
fi

if ! grep -q 'Mandatory Skill Activation' "$COMPILER"; then
  pass "compile-context.sh: Mandatory Skill Activation section removed"
else
  fail "compile-context.sh: still has Mandatory Skill Activation (should be removed)"
fi

# execute-protocol.md should NOT reference .skill-activation-block.txt or SKILL_BLOCK
if ! grep -q 'skill-activation-block.txt' "$PROTOCOL"; then
  pass "execute-protocol.md: .skill-activation-block.txt references removed"
else
  fail "execute-protocol.md: still references .skill-activation-block.txt"
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

# Positive: orchestrator-composed intelligent skill selection in execute-protocol
if grep -q 'evaluate installed skills' "$PROTOCOL"; then
  pass "execute-protocol.md: intelligent skill selection documented"
else
  fail "execute-protocol.md: missing intelligent skill selection documentation"
fi

# Negative: old LLM-composed skill selection removed from execute-protocol
if ! grep -q 'select skills from installed skills visible in your system context' "$PROTOCOL"; then
  pass "execute-protocol.md: old LLM-composed skill selection removed"
else
  fail "execute-protocol.md: still has old LLM-composed skill selection instruction"
fi

# Negative: SKILL_BLOCK variable removed from execute-protocol
if ! grep -q 'SKILL_BLOCK' "$PROTOCOL"; then
  pass "execute-protocol.md: SKILL_BLOCK variable removed"
else
  fail "execute-protocol.md: SKILL_BLOCK still referenced (should be removed)"
fi

# Negative: generate-skill-activation.sh removed from execute-protocol
if ! grep -q 'generate-skill-activation.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: generate-skill-activation.sh references removed"
else
  fail "execute-protocol.md: still references generate-skill-activation.sh"
fi

# Positive: orchestrator-composed explicit skill outcomes in Scout/Lead spawn templates
if grep -q 'skill_activation' "$VIBE_CMD" && grep -q 'skill_no_activation' "$VIBE_CMD" && grep -q 'skill_activation' "$RESEARCH_CMD" && grep -q 'skill_no_activation' "$RESEARCH_CMD"; then
  pass "vibe.md + research.md: orchestrator-composed explicit positive and negative skill outcomes"
else
  fail "vibe.md or research.md: missing explicit positive or negative skill outcomes"
fi

# Positive: intelligent selection language in vibe.md
if grep -q 'evaluate installed skills' "$VIBE_CMD"; then
  pass "vibe.md: uses intelligent skill evaluation language"
else
  fail "vibe.md: missing intelligent skill evaluation language"
fi

# Negative: old "Do not skip any listed skill" removed
if ! grep -q 'Do not skip any listed skill' "$VIBE_CMD" && ! grep -q 'Do not skip any listed skill' "$RESEARCH_CMD"; then
  pass "vibe.md + research.md: 'Do not skip any listed skill' removed"
else
  fail "vibe.md or research.md: still has 'Do not skip any listed skill'"
fi

# Anti-LLM-composition directive removed (no longer using pre-computed blocks)
if ! grep -q 'Do NOT attempt to compose skill activation yourself' "$PROTOCOL"; then
  pass "execute-protocol.md: anti-LLM-composition directive removed (intelligent selection now)"
else
  fail "execute-protocol.md: anti-LLM-composition directive still present"
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

# Layer 3: SubagentStart hook removed (skill visibility is native to Claude Code)
if ! grep -q 'inject-subagent-skills.sh' "$HOOKS_FILE"; then
  pass "hooks.json: inject-subagent-skills.sh removed (Layer 3 — native CC skill visibility)"
else
  fail "hooks.json: inject-subagent-skills.sh still present (should be removed)"
fi

# Compaction durability: compile-context.sh should NOT call emit_skills_section for any role
COMPILER="$ROOT/scripts/compile-context.sh"
if ! grep -q 'emit_skills_section' "$COMPILER"; then
  pass "compile-context.sh: emit_skills_section fully removed (all roles)"
else
  fail "compile-context.sh: emit_skills_section still present"
fi

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
