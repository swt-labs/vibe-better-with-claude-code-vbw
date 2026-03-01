#!/bin/bash
set -u
# skill-eval-prompt-gate.sh — UserPromptSubmit hook for teammate skill evaluation
#
# Primary skill evaluation gate. Fires on the FIRST prompt per session (including
# agent team teammates). Injects a compact EVALUATE/ACTIVATE/IMPLEMENT protocol
# into additionalContext. Uses PID-scoped marker to fire only once per session
# (avoids token waste on every prompt).
#
# This is the primary path for teammate coverage — SubagentStart does NOT fire
# for agent team teammates (they are separate sessions, not subagents).
# See: github.com/anthropics/claude-code/issues/24175, #27755
#
# Fail-open: any error -> exit 0 with no output (never blocks prompts).

# Consume stdin (required by UserPromptSubmit hooks)
cat > /dev/null 2>&1 || true

PLANNING_DIR=".vbw-planning"

# Guard: no VBW project = silent no-op
if [ ! -d "$PLANNING_DIR" ]; then
  exit 0
fi

# PID-scoped marker: fire only once per session
MARKER_DIR="$PLANNING_DIR/.skill-eval-markers"
MARKER="$MARKER_DIR/$$"

if [ -f "$MARKER" ]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get installed skill names via evaluate-skills.sh
SKILL_OUTPUT=""
if [ -f "$SCRIPT_DIR/evaluate-skills.sh" ]; then
  SKILL_OUTPUT=$(bash "$SCRIPT_DIR/evaluate-skills.sh" "$PLANNING_DIR" "." 2>/dev/null || true)
fi

# Create marker directory and marker (even if no skills — prevents re-evaluation)
mkdir -p "$MARKER_DIR" 2>/dev/null || true
touch "$MARKER" 2>/dev/null || true

# No skills installed -> no gate needed
if [ -z "$SKILL_OUTPUT" ]; then
  exit 0
fi

# Extract skill names only (tab-separated output: name\tdescription)
SKILL_NAMES=""
while IFS=$'\t' read -r name desc; do
  [ -z "$name" ] && continue
  if [ -n "$SKILL_NAMES" ]; then
    SKILL_NAMES="${SKILL_NAMES}, ${name}"
  else
    SKILL_NAMES="${name}"
  fi
done <<< "$SKILL_OUTPUT"

# Build compact gate message (~100 tokens)
CONTEXT="=== MANDATORY SKILL EVALUATION ===
Installed project skills: ${SKILL_NAMES}

Before ANY implementation, complete this protocol:
1. EVALUATE: Write YES or NO for each skill's relevance to your task
2. ACTIVATE: Call Skill(skill-name) for each YES skill and any in plan's skills_used
3. IMPLEMENT: Only begin work after steps 1-2
Skipping is a PROTOCOL VIOLATION.
=== END ==="

# Output hookSpecificOutput JSON
jq -n --arg event "UserPromptSubmit" --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: $event,
    additionalContext: $ctx
  }
}' 2>/dev/null || true

exit 0
