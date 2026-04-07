#!/bin/bash
set -u
# agent-spawn-guard.sh — PreToolUse guard for execute-mode agent spawn shapes
#
# Protects the execute workflow from faux-team launches where plain background
# Agent spawns are used without real team semantics.
#
# Exit 2 = definitive invalid spawn shape
# Exit 0 = allow / fail-open

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.vbw-planning/phases" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

find_project_root >/dev/null || exit 0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MARKER_STATUS=$(bash "$SCRIPT_DIR/delegated-workflow.sh" status-json 2>/dev/null) || exit 0
[ -n "$MARKER_STATUS" ] || exit 0

MARKER_LIVE=$(echo "$MARKER_STATUS" | jq -r '.live // false' 2>/dev/null) || exit 0
[ "$MARKER_LIVE" = "true" ] || exit 0

MODE=$(echo "$MARKER_STATUS" | jq -r '.mode // ""' 2>/dev/null) || exit 0
[ "$MODE" = "execute" ] || exit 0

DELEGATION_MODE=$(echo "$MARKER_STATUS" | jq -r '.delegation_mode // ""' 2>/dev/null) || exit 0
[ -n "$DELEGATION_MODE" ] || exit 0

TEAM_NAME=$(echo "$INPUT" | jq -r '.tool_input.team_name // ""' 2>/dev/null) || exit 0
AGENT_NAME=$(echo "$INPUT" | jq -r '.tool_input.name // ""' 2>/dev/null) || exit 0
RUN_IN_BACKGROUND=$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null) || exit 0

case "$DELEGATION_MODE" in
  team)
    if [ -z "$TEAM_NAME" ]; then
      echo "Blocked: execute team mode requires team-scoped agent spawns. Missing team_name on Agent spawn${AGENT_NAME:+ ($AGENT_NAME)}." >&2
      exit 2
    fi
    ;;
  subagent|direct)
    if [ -n "$TEAM_NAME" ]; then
      echo "Blocked: execute delegation mode '$DELEGATION_MODE' cannot attach team_name '$TEAM_NAME'. Use true team mode or explicit non-team execution." >&2
      exit 2
    fi
    if [ "$RUN_IN_BACKGROUND" = "true" ]; then
      echo "Blocked: execute delegation mode '$DELEGATION_MODE' cannot simulate team mode with background Agent spawns. Use explicit non-team execution (wait for each agent) or switch to true team mode." >&2
      exit 2
    fi
    ;;
esac

exit 0