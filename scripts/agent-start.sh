#!/bin/bash
set -u
# SubagentStart hook: Record active agent type for cost attribution.
# Active-agent state is session-local when a safe session id is available; root
# .active-agent* files are rebuilt as aggregate display/legacy fallback state.

INPUT=$(cat)
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
[ ! -d "$PLANNING_DIR" ] && exit 0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/active-agent-state.sh" ]; then
  # shellcheck source=lib/active-agent-state.sh
  . "$SCRIPT_DIR/lib/active-agent-state.sh"
else
  exit 0
fi

NATIVE_AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)
LEGACY_AGENT_ROLE_SOURCE=$(echo "$INPUT" | jq -r '.agent_name // .agentName // .name // ""' 2>/dev/null)

# Only track VBW agents; maintain reference count for concurrent agents
COUNT_FILE="$PLANNING_DIR/.active-agent-count"

normalize_agent_role() {
  local value="$1"
  local lower

  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  lower="${lower#@}"
  lower="${lower#vbw:}"

  case "$lower" in
    vbw-lead|vbw-lead-[0-9]*|lead|lead-[0-9]*|team-lead|team-lead-[0-9]*)
      printf 'lead'
      return 0
      ;;
    vbw-dev|vbw-dev-[0-9]*|dev|dev-[0-9]*|team-dev|team-dev-[0-9]*)
      printf 'dev'
      return 0
      ;;
    vbw-qa|vbw-qa-[0-9]*|qa|qa-[0-9]*|team-qa|team-qa-[0-9]*)
      printf 'qa'
      return 0
      ;;
    vbw-scout|vbw-scout-[0-9]*|scout|scout-[0-9]*|team-scout|team-scout-[0-9]*)
      printf 'scout'
      return 0
      ;;
    vbw-debugger|vbw-debugger-[0-9]*|debugger|debugger-[0-9]*|team-debugger|team-debugger-[0-9]*)
      printf 'debugger'
      return 0
      ;;
    vbw-architect|vbw-architect-[0-9]*|architect|architect-[0-9]*|team-architect|team-architect-[0-9]*)
      printf 'architect'
      return 0
      ;;
    vbw-docs|vbw-docs-[0-9]*|docs|docs-[0-9]*|team-docs|team-docs-[0-9]*)
      printf 'docs'
      return 0
      ;;
  esac

  return 1
}

is_explicit_vbw_agent() {
  local value="$1"
  local lower
  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  echo "$lower" | grep -qE '^@?vbw:|^@?vbw-'
}

has_vbw_context() {
  [ -f "$PLANNING_DIR/.vbw-session" ] \
    || [ -f "$PLANNING_DIR/.active-agent" ] \
    || [ -f "$COUNT_FILE" ]
}

select_agent_role_source() {
  if [ -n "$NATIVE_AGENT_TYPE" ]; then
    if is_explicit_vbw_agent "$NATIVE_AGENT_TYPE"; then
      printf '%s' "$NATIVE_AGENT_TYPE"
      return 0
    fi

    if is_explicit_vbw_agent "$LEGACY_AGENT_ROLE_SOURCE"; then
      printf '%s' "$LEGACY_AGENT_ROLE_SOURCE"
      return 0
    fi

    return 1
  fi

  if is_explicit_vbw_agent "$LEGACY_AGENT_ROLE_SOURCE" || has_vbw_context; then
    printf '%s' "$LEGACY_AGENT_ROLE_SOURCE"
    return 0
  fi

  return 1
}

AGENT_ROLE_SOURCE=""
if AGENT_ROLE_SOURCE=$(select_agent_role_source); then
  :
else
  AGENT_ROLE_SOURCE=""
fi

ROLE=""
if ROLE=$(normalize_agent_role "$AGENT_ROLE_SOURCE"); then
  :
else
  ROLE=""
fi

AGENT_PID=$(echo "$INPUT" | jq -r '.pid // ""' 2>/dev/null)
if [ -z "$AGENT_PID" ]; then
  AGENT_PID="$PPID"
fi

if [ -n "$ROLE" ]; then
  vbw_active_agent_start "$PLANNING_DIR" "$INPUT" "$ROLE" "$AGENT_PID"

  # Register agent PID for tmux cleanup
  if [ -n "$AGENT_PID" ] && [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ]; then
    bash "$SCRIPT_DIR/agent-pid-tracker.sh" register "$AGENT_PID" 2>/dev/null || true
  fi

  # Record tmux pane for auto-close on stop
  if [ -n "${TMUX:-}" ] && [ -n "$AGENT_PID" ]; then
    PANE_MAP="$PLANNING_DIR/.agent-panes"
    # Walk agent PID's parent chain to find which tmux pane owns it
    PANE_LIST=$(tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null) || PANE_LIST=""
    if [ -n "$PANE_LIST" ]; then
      _pid="$AGENT_PID"
      _found=""
      while [ -n "$_pid" ] && [ "$_pid" != "0" ] && [ "$_pid" != "1" ]; do
        _found=$(echo "$PANE_LIST" | awk -v p="$_pid" '$1 == p { print $2; exit }')
        if [ -n "$_found" ]; then break; fi
        _pid=$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ')
      done
      if [ -n "$_found" ]; then
        echo "$AGENT_PID $_found" >> "$PANE_MAP"
      fi
    fi
  fi
fi

exit 0
