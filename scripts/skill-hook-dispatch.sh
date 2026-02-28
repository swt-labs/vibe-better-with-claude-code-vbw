#!/bin/bash
set -u
# skill-hook-dispatch.sh — Runtime skill-hook dispatcher
# Reads config.json skill_hooks at runtime and invokes matching skill scripts
# Fail-open design: exit 0 on any error, never block legitimate work

# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh"

EVENT_TYPE="${1:-}"
[ -z "$EVENT_TYPE" ] && exit 0

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
[ -z "$TOOL_NAME" ] && exit 0

# Find config.json in .vbw-planning/ relative to project root
# Walk up from $PWD looking for .vbw-planning/config.json
find_config() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.vbw-planning/config.json" ]; then
      echo "$dir/.vbw-planning/config.json"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

CONFIG_PATH=$(find_config) || exit 0
[ ! -f "$CONFIG_PATH" ] && exit 0

# Read skill_hooks from config.json
# Format: { "skill_hooks": { "skill-name": { "event": "PostToolUse", "tools": "Write|Edit" } } }
# Backward compat: also reads "matcher" if "tools" is absent (pre-v1.33 configs)
SKILL_HOOKS=$(jq -r '.skill_hooks // empty' "$CONFIG_PATH" 2>/dev/null) || exit 0
[ -z "$SKILL_HOOKS" ] && exit 0

# Iterate through each skill-hook mapping
for SKILL_NAME in $(echo "$SKILL_HOOKS" | jq -r 'keys[]' 2>/dev/null); do
  SKILL_EVENT=$(echo "$SKILL_HOOKS" | jq -r --arg s "$SKILL_NAME" '.[$s].event // ""' 2>/dev/null) || continue
  SKILL_TOOLS=$(echo "$SKILL_HOOKS" | jq -r --arg s "$SKILL_NAME" '.[$s].tools // .[$s].matcher // ""' 2>/dev/null) || continue

  # Check event type matches
  [ "$SKILL_EVENT" != "$EVENT_TYPE" ] && continue

  # Check tool name matches (pipe-delimited pattern)
  if ! echo "$TOOL_NAME" | grep -qE "^($SKILL_TOOLS)$"; then
    continue
  fi

  # Find and invoke the skill's hook script from plugin cache (latest version)
  SCRIPT=$(ls -1 "$CLAUDE_DIR"/plugins/cache/vbw-marketplace/vbw/*/scripts/"${SKILL_NAME}-hook.sh" 2>/dev/null | sort -V | tail -1)
  if [ -f "$SCRIPT" ]; then
    echo "$INPUT" | bash "$SCRIPT" 2>/dev/null || true
  fi
done

exit 0
