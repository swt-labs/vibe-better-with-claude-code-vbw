#!/bin/bash
set -u
# inject-subagent-skills.sh — SubagentStart hook: inject filtered skill XML into subagents
#
# Reads agent_type from stdin JSON, checks if it's a VBW agent, then outputs
# filtered <available_skills> XML (excluding VBW/GSD command-based skills) via
# hookSpecificOutput.additionalContext.
#
# Usage: Called by hooks.json SubagentStart handler via hook-wrapper.sh

INPUT=$(cat)
PLANNING_DIR=".vbw-planning"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Extract and normalize agent type ---
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // .agent_name // .name // ""' 2>/dev/null)

# Reuse normalize pattern from agent-start.sh
normalize_agent_role() {
  local value="$1"
  local lower
  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  lower="${lower#@}"
  lower="${lower#vbw:}"

  case "$lower" in
    vbw-lead|vbw-lead-[0-9]*|lead|lead-[0-9]*|team-lead|team-lead-[0-9]*)
      printf 'lead'; return 0 ;;
    vbw-dev|vbw-dev-[0-9]*|dev|dev-[0-9]*|team-dev|team-dev-[0-9]*)
      printf 'dev'; return 0 ;;
    vbw-qa|vbw-qa-[0-9]*|qa|qa-[0-9]*|team-qa|team-qa-[0-9]*)
      printf 'qa'; return 0 ;;
    vbw-scout|vbw-scout-[0-9]*|scout|scout-[0-9]*|team-scout|team-scout-[0-9]*)
      printf 'scout'; return 0 ;;
    vbw-debugger|vbw-debugger-[0-9]*|debugger|debugger-[0-9]*|team-debugger|team-debugger-[0-9]*)
      printf 'debugger'; return 0 ;;
    vbw-architect|vbw-architect-[0-9]*|architect|architect-[0-9]*|team-architect|team-architect-[0-9]*)
      printf 'architect'; return 0 ;;
    vbw-docs|vbw-docs-[0-9]*|docs|docs-[0-9]*|team-docs|team-docs-[0-9]*)
      printf 'docs'; return 0 ;;
  esac
  return 1
}

is_explicit_vbw_agent() {
  local value="$1"
  local lower
  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  echo "$lower" | grep -qE '^@?vbw:|^@?vbw-'
}

# --- Guard: only fire for VBW agents ---
if ! normalize_agent_role "$AGENT_TYPE" >/dev/null; then
  exit 0
fi

# Accept non-prefixed role aliases only when a VBW context is already active
if ! is_explicit_vbw_agent "$AGENT_TYPE" \
  && [ ! -f "$PLANNING_DIR/.vbw-session" ] \
  && [ ! -f "$PLANNING_DIR/.active-agent" ] \
  && [ ! -f "$PLANNING_DIR/.active-agent-count" ]; then
  exit 0
fi

# --- Resolve skill injection mode from config ---
# Values:
#   off        - no skill injection
#   names_only - inject compact skill-name list with activation instruction
#   full       - inject full <available_skills> XML with activation instruction
SKILL_XML_MODE="names_only"
if [ -f "$PLANNING_DIR/config.json" ] && command -v jq >/dev/null 2>&1; then
  _MODE_VAL=$(jq -r '.subagent_skill_xml_mode // "names_only"' "$PLANNING_DIR/config.json" 2>/dev/null || echo "names_only")
  case "$_MODE_VAL" in
    off|names_only|full) SKILL_XML_MODE="$_MODE_VAL" ;;
    *) SKILL_XML_MODE="names_only" ;;
  esac
fi

# Explicit off: skip injection completely
if [ "$SKILL_XML_MODE" = "off" ]; then
  exit 0
fi

# --- Generate filtered skill data based on mode ---
SKILL_XML=""
SKILL_NAMES=""
if [ -f "$SCRIPT_DIR/emit-skill-xml.sh" ]; then
  case "$SKILL_XML_MODE" in
    full)
      SKILL_XML=$(bash "$SCRIPT_DIR/emit-skill-xml.sh" --filter-plugins 2>/dev/null || true)
      ;;
    names_only)
      SKILL_NAMES=$(bash "$SCRIPT_DIR/emit-skill-xml.sh" --compact --filter-plugins 2>/dev/null | sed -n 's/.*<name>\([^<]*\)<\/name>.*/\1/p' | paste -sd ', ' - || true)
      ;;
  esac
fi

# No third-party skills installed — nothing to inject
if [ "$SKILL_XML_MODE" = "full" ] && [ -z "$SKILL_XML" ]; then
  exit 0
fi
if [ "$SKILL_XML_MODE" = "names_only" ] && [ -z "$SKILL_NAMES" ]; then
  exit 0
fi

# --- Build additionalContext with evaluation instruction ---
EVAL_INSTRUCTION="SKILL ACTIVATION: Evaluate which of the available skills are relevant to your current task. For each relevant skill, call Skill(name) to load its full instructions before proceeding."

CONTEXT=""
if [ "$SKILL_XML_MODE" = "full" ]; then
  CONTEXT="${EVAL_INSTRUCTION}
${SKILL_XML}"
else
  CONTEXT="${EVAL_INSTRUCTION}
Available skills: ${SKILL_NAMES}."
fi

# --- Output via hookSpecificOutput ---
jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": $ctx
  }
}'

exit 0
