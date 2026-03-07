#!/bin/bash
# generate-skill-activation.sh — Pre-compute <skill_activation> block for subagent task descriptions
#
# Deterministically generates a <skill_activation> XML block containing explicit
# Skill() call instructions from installed skills. Replaces unreliable LLM-composed
# skill activation by producing a verbatim block the orchestrator includes as-is.
#
# Usage: bash generate-skill-activation.sh [plan-path ...] [--phase-dir DIR]
#   plan-path     Optional PLAN.md paths — reads skills_used frontmatter
#   --phase-dir   Phase directory to write .skill-activation-block.txt
#
# Output: <skill_activation> block to stdout (empty if no skills found)
# Side effect: writes {phase-dir}/.skill-activation-block.txt if --phase-dir given

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLAN_PATHS=()
PHASE_DIR=""

for arg in "$@"; do
  case "$arg" in
    --phase-dir=*) PHASE_DIR="${arg#--phase-dir=}" ;;
    --phase-dir) ;; # handled below with next arg
    *) if [ -n "$_NEXT_IS_PHASE_DIR" ]; then
         PHASE_DIR="$arg"
         _NEXT_IS_PHASE_DIR=""
       else
         PLAN_PATHS+=("$arg")
       fi ;;
  esac
  if [ "$arg" = "--phase-dir" ]; then
    _NEXT_IS_PHASE_DIR=1
  fi
done

# --- Collect skill names from plan frontmatter (if plan paths provided) ---
PLAN_SKILLS=""
for plan_path in "${PLAN_PATHS[@]}"; do
  [ -f "$plan_path" ] || continue
  # Extract skills_used from YAML frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$plan_path" | sed '1d;$d')
  skills_line=$(printf '%s\n' "$frontmatter" | grep '^skills_used:' || true)
  [ -z "$skills_line" ] && continue
  # Parse YAML array: skills_used: [skill1, skill2] or skills_used:\n- skill1\n- skill2
  case "$skills_line" in
    *\[*)
      # Inline array: skills_used: [swift-testing, swiftdata]
      skills=$(printf '%s' "$skills_line" | sed 's/^skills_used:[[:space:]]*\[//;s/\][[:space:]]*$//' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^["'"'"']//;s/["'"'"']$//')
      ;;
    *)
      # Block array: read subsequent lines starting with -
      skills=$(printf '%s\n' "$frontmatter" | sed -n '/^skills_used:/,/^[a-z_]*:/p' | grep '^[[:space:]]*-' | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/^["'"'"']//;s/["'"'"']$//')
      ;;
  esac
  if [ -n "$skills" ]; then
    PLAN_SKILLS="${PLAN_SKILLS:+${PLAN_SKILLS}
}${skills}"
  fi
done

# --- Collect available skills via emit-skill-xml.sh (fallback / union) ---
AVAILABLE_SKILLS=""
if [ -f "$SCRIPT_DIR/emit-skill-xml.sh" ]; then
  skill_xml=$(bash "$SCRIPT_DIR/emit-skill-xml.sh" --compact --filter-plugins 2>/dev/null || true)
  if [ -n "$skill_xml" ]; then
    # Extract <name>...</name> values from XML
    AVAILABLE_SKILLS=$(printf '%s\n' "$skill_xml" | sed -n 's/.*<name>\([^<]*\)<\/name>.*/\1/p')
  fi
fi

# --- Union plan skills + available skills, dedup ---
ALL_SKILLS=""
_SEEN=""
NL=$'\n'

_add_skill() {
  local name="$1"
  [ -z "$name" ] && return
  # Dedup check
  case "${NL}${_SEEN}${NL}" in *"${NL}${name}${NL}"*) return ;; esac
  _SEEN="${_SEEN:+${_SEEN}${NL}}${name}"
  ALL_SKILLS="${ALL_SKILLS:+${ALL_SKILLS}${NL}}${name}"
}

# Plan skills first (higher priority)
if [ -n "$PLAN_SKILLS" ]; then
  while IFS= read -r skill; do
    _add_skill "$skill"
  done <<< "$PLAN_SKILLS"
fi

# Available skills as fallback
if [ -n "$AVAILABLE_SKILLS" ]; then
  while IFS= read -r skill; do
    _add_skill "$skill"
  done <<< "$AVAILABLE_SKILLS"
fi

# --- Generate output ---
if [ -z "$ALL_SKILLS" ]; then
  # No skills: write empty file if phase-dir given, output nothing
  if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
    : > "${PHASE_DIR}/.skill-activation-block.txt"
  fi
  exit 0
fi

# Build the activation block
BLOCK="<skill_activation>"
while IFS= read -r skill; do
  [ -z "$skill" ] && continue
  BLOCK="${BLOCK}Call Skill('${skill}'). "
done <<< "$ALL_SKILLS"
BLOCK="${BLOCK}Do not skip any listed skill.</skill_activation>"

# Output to stdout
printf '%s' "$BLOCK"

# Write to phase dir if specified
if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
  printf '%s' "$BLOCK" > "${PHASE_DIR}/.skill-activation-block.txt"
fi
