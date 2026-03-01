#!/bin/bash
set -u
# skill-evaluation-gate.sh — SubagentStart hook for mandatory skill evaluation
#
# SUPPLEMENTARY PATH: This hook fires for non-team subagent spawns (e.g.,
# /vbw:fix direct Agent tool calls). For agent team teammates, the primary
# skill evaluation gate is skill-eval-prompt-gate.sh (UserPromptSubmit hook),
# since SubagentStart does NOT fire for teammates (separate sessions).
# See: github.com/anthropics/claude-code/issues/24175, #27755
#
# Injects a MANDATORY SKILL EVALUATION SEQUENCE into subagent additionalContext
# at spawn-time (high attention position). This forces agents to commit YES/NO
# per skill in writing before coding (~95% activation reliability).
#
# Uses evaluate-skills.sh for skill name+description discovery from STATE.md + SKILL.md.
# Follows hookSpecificOutput JSON contract (same as agent-health.sh).
#
# Fail-open: any error → exit 0 with no output (never blocks agent spawn).

# Consume stdin (required to avoid broken pipe on SubagentStart hooks)
cat > /dev/null 2>&1 || true

# Guard: no VBW project = silent no-op
if [ ! -d ".vbw-planning" ]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLANNING_DIR=".vbw-planning"

# Get skill name+description pairs via evaluate-skills.sh
SKILL_OUTPUT=""
if [ -f "$SCRIPT_DIR/evaluate-skills.sh" ]; then
  SKILL_OUTPUT=$(bash "$SCRIPT_DIR/evaluate-skills.sh" "$PLANNING_DIR" "." 2>/dev/null || true)
fi

# No skills installed → valid hook contract with empty context (no-op)
if [ -z "$SKILL_OUTPUT" ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "SubagentStart",
      additionalContext: ""
    }
  }' 2>/dev/null || true
  exit 0
fi

# Build the skills table from tab-separated output
SKILLS_TABLE="| Skill | Description |\n|-------|-------------|"
while IFS=$'\t' read -r name desc; do
  [ -z "$name" ] && continue
  SKILLS_TABLE="${SKILLS_TABLE}\n| \`${name}\` | ${desc} |"
done <<< "$SKILL_OUTPUT"

# Build the mandatory evaluation sequence
CONTEXT="=== MANDATORY SKILL EVALUATION SEQUENCE ===

CRITICAL: You MUST complete this 3-step protocol BEFORE writing any code.

Installed skills for this project:

${SKILLS_TABLE}

Step 1 — EVALUATE: For EACH skill above, write YES or NO:
  - YES if the skill's description is relevant to your current task/plan
  - NO if it is not relevant
  You MUST produce a written YES/NO verdict for every skill. Skipping is a PROTOCOL VIOLATION.

Step 2 — ACTIVATE: For each YES skill, call Skill(skill-name) to load its full instructions.
  Also activate any skills listed in the plan's skills_used frontmatter.

Step 3 — IMPLEMENT: Only after Steps 1-2 are complete, begin your implementation work.

=== END MANDATORY SEQUENCE ==="

# Output hookSpecificOutput JSON (jq handles escaping)
jq -n --arg event "SubagentStart" --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: $event,
    additionalContext: $ctx
  }
}' 2>/dev/null || true

exit 0
