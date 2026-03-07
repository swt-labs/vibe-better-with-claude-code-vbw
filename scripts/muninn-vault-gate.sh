#!/bin/bash
set -u
# SubagentStart hook: Block agent spawn if MuninnDB vault is not configured.
# Blocks Lead and Architect (exit 2); advisory for others (JSON stdout).
# Fast check — only reads config.json, no network calls.

INPUT=$(cat)
PLANNING_DIR=".vbw-planning"
CONFIG="$PLANNING_DIR/config.json"

# No VBW project — let it pass
[ ! -d "$PLANNING_DIR" ] && exit 0
[ ! -f "$CONFIG" ] && exit 0

# Read vault name from config
VAULT=""
if command -v jq &>/dev/null; then
  VAULT=$(jq -r '.muninndb_vault // ""' "$CONFIG" 2>/dev/null) || VAULT=""
fi

# Vault is configured — all good
[ -n "$VAULT" ] && exit 0

# Vault is empty — determine agent role
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // .agent_name // .name // ""' 2>/dev/null)
LOWER=$(printf '%s' "$AGENT_TYPE" | tr '[:upper:]' '[:lower:]')
LOWER="${LOWER#@}"
LOWER="${LOWER#vbw:}"

case "$LOWER" in
  vbw-lead|vbw-lead-[0-9]*|lead|lead-[0-9]*|team-lead|team-lead-[0-9]*)
    ROLE="lead" ;;
  vbw-architect|vbw-architect-[0-9]*|architect|architect-[0-9]*|team-architect|team-architect-[0-9]*)
    ROLE="architect" ;;
  *)
    ROLE="other" ;;
esac

if [ "$ROLE" = "lead" ] || [ "$ROLE" = "architect" ]; then
  # Block — Lead and Architect MUST have memory context
  jq -n '{
    "error": "MuninnDB vault not configured. Set muninndb_vault in .vbw-planning/config.json or run /vbw:init before spawning Lead or Architect agents."
  }'
  exit 2
fi

# Advisory — other agents can proceed without memory
jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "⚠ MuninnDB vault not configured. Memory recall will be unavailable. Run /vbw:init or set muninndb_vault in .vbw-planning/config.json."
  }
}'

exit 0
