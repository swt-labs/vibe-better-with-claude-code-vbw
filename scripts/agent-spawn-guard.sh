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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

resolve_project_root() {
  if [ -n "${VBW_PLANNING_DIR:-}" ] && [ -d "$VBW_PLANNING_DIR" ]; then
    cd "$VBW_PLANNING_DIR/.." 2>/dev/null && pwd -P 2>/dev/null
    return $?
  fi

  if [ -f "$SCRIPT_DIR/lib/vbw-config-root.sh" ]; then
    # shellcheck source=lib/vbw-config-root.sh
    if source "$SCRIPT_DIR/lib/vbw-config-root.sh" 2>/dev/null; then
      if find_vbw_root "$SCRIPT_DIR" >/dev/null 2>&1 && [ -n "${VBW_CONFIG_ROOT:-}" ] && [ -n "${VBW_PLANNING_DIR:-}" ] && [ -d "$VBW_PLANNING_DIR" ]; then
        printf '%s\n' "$VBW_CONFIG_ROOT"
        return 0
      fi
    fi
  fi

  find_project_root
}

PROJECT_ROOT=$(resolve_project_root) || exit 0
MARKER_STATUS=$(VBW_PLANNING_DIR="$PROJECT_ROOT/.vbw-planning" bash "$SCRIPT_DIR/delegated-workflow.sh" status-json 2>/dev/null) || exit 0
[ -n "$MARKER_STATUS" ] || exit 0

MARKER_LIVE=$(echo "$MARKER_STATUS" | jq -r '.live // false' 2>/dev/null) || exit 0
MODE=$(echo "$MARKER_STATUS" | jq -r '.mode // ""' 2>/dev/null) || exit 0
DELEGATION_MODE=$(echo "$MARKER_STATUS" | jq -r '.delegation_mode // ""' 2>/dev/null) || exit 0
EXPECTED_TEAM_NAME=$(echo "$MARKER_STATUS" | jq -r '.team_name // ""' 2>/dev/null) || exit 0
MARKER_REASON=$(echo "$MARKER_STATUS" | jq -r '.reason // ""' 2>/dev/null) || exit 0
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

is_teammate_spawn_tool() {
  [ "$TOOL_NAME" = "Agent" ] || [ "$TOOL_NAME" = "TaskCreate" ]
}

config_worktree_isolation() {
  local config_file="$PROJECT_ROOT/.vbw-planning/config.json"
  jq -r '.worktree_isolation // "off"' "$config_file" 2>/dev/null || printf '%s\n' "off"
}

requested_worktree_isolation() {
  local isolation=""
  isolation=$(echo "$INPUT" | jq -r '.tool_input.isolation // ""' 2>/dev/null) || return 1
  [ "$isolation" = "worktree" ]
}

requested_sidechain_cwd() {
  echo "$INPUT" | jq -r '[.tool_input.cwd? // empty, .tool_input.working_dir? // empty, .tool_input.workingDirectory? // empty, .tool_input.workdir? // empty] | map(select(type == "string")) | .[]' 2>/dev/null \
    | grep -Fq '.claude/worktrees/'
}

EXEC_STATE_FILE="$PROJECT_ROOT/.vbw-planning/.execution-state.json"
EXEC_ACTIVE=false
if [ -f "$EXEC_STATE_FILE" ] && jq empty "$EXEC_STATE_FILE" >/dev/null 2>&1; then
  EXEC_STATUS=$(jq -r '.status // ""' "$EXEC_STATE_FILE" 2>/dev/null) || EXEC_STATUS=""
  if [ "$EXEC_STATUS" = "running" ]; then
    if [ "$(uname)" = "Darwin" ]; then
      EXEC_MTIME=$(stat -f %m "$EXEC_STATE_FILE" 2>/dev/null || echo 0)
    else
      EXEC_MTIME=$(stat -c %Y "$EXEC_STATE_FILE" 2>/dev/null || echo 0)
    fi
    EXEC_NOW=$(date +%s 2>/dev/null || echo 0)
    EXEC_AGE=$((EXEC_NOW - EXEC_MTIME))
    if [ "$EXEC_AGE" -ge 0 ] && [ "$EXEC_AGE" -lt 14400 ]; then
      EXEC_ACTIVE=true
    fi
  fi
fi

if [ "$EXEC_ACTIVE" = true ] && { [ "$MARKER_LIVE" != "true" ] || [ "$MODE" != "execute" ] || [ -z "$DELEGATION_MODE" ]; }; then
  echo "Blocked: active execute run is missing live runtime delegation state (reason=${MARKER_REASON:-missing_marker}). Initialize execute delegation before spawning teammates." >&2
  exit 2
fi

if is_teammate_spawn_tool; then
  WORKTREE_ISOLATION=$(config_worktree_isolation)
  if [ "$WORKTREE_ISOLATION" != "on" ]; then
    if requested_worktree_isolation; then
      echo "Blocked: teammate spawn requested Claude worktree isolation while VBW worktree_isolation is off. Omit isolation or enable VBW worktree isolation." >&2
      exit 2
    fi
    if requested_sidechain_cwd; then
      echo "Blocked: teammate spawn requested a Claude sidechain working directory while VBW worktree_isolation is off. Omit the sidechain cwd/working_dir or enable VBW worktree isolation." >&2
      exit 2
    fi
  fi
fi

[ "$MARKER_LIVE" = "true" ] || exit 0
[ "$MODE" = "execute" ] || exit 0
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
    if [ -z "$AGENT_NAME" ]; then
      echo "Blocked: execute team mode requires teammate name metadata on team-scoped spawns." >&2
      exit 2
    fi
    if [ -n "$EXPECTED_TEAM_NAME" ] && [ "$TEAM_NAME" != "$EXPECTED_TEAM_NAME" ]; then
      echo "Blocked: execute team mode requires team_name '$EXPECTED_TEAM_NAME', got '$TEAM_NAME'." >&2
      exit 2
    fi
    ;;
  subagent|direct)
    if [ -n "$TEAM_NAME" ]; then
      echo "Blocked: execute delegation mode '$DELEGATION_MODE' cannot attach team_name '$TEAM_NAME'. Use true team mode or explicit non-team execution." >&2
      exit 2
    fi
    if [ "$TOOL_NAME" = "TaskCreate" ]; then
      ACTIVE_COUNT_FILE="$PROJECT_ROOT/.vbw-planning/.active-agent-count"
      ACTIVE_COUNT=0
      if [ -f "$ACTIVE_COUNT_FILE" ]; then
        ACTIVE_COUNT=$(cat "$ACTIVE_COUNT_FILE" 2>/dev/null | tr -d '[:space:]')
      fi
      if ! printf '%s' "$ACTIVE_COUNT" | grep -Eq '^[0-9]+$'; then
        ACTIVE_COUNT=0
      fi
      if [ "$ACTIVE_COUNT" -gt 0 ]; then
        echo "Blocked: execute delegation mode '$DELEGATION_MODE' must serialize non-team TaskCreate spawns. Wait for the current teammate to finish before starting another." >&2
        exit 2
      fi
    fi
    if [ "$RUN_IN_BACKGROUND" = "true" ]; then
      echo "Blocked: execute delegation mode '$DELEGATION_MODE' cannot simulate team mode with background Agent spawns. Use explicit non-team execution (wait for each agent) or switch to true team mode." >&2
      exit 2
    fi
    ;;
esac

exit 0