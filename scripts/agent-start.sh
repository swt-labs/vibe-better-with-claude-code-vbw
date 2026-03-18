#!/bin/bash
set -u
# SubagentStart hook: Record active agent type for cost attribution
# Writes stripped agent name to .vbw-planning/.active-agent

INPUT=$(cat)
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
[ ! -d "$PLANNING_DIR" ] && exit 0

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // .agent_name // .name // ""' 2>/dev/null)

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

ROLE=""
if ROLE=$(normalize_agent_role "$AGENT_TYPE"); then
  :
else
  ROLE=""
fi

# Only track VBW agents; maintain reference count for concurrent agents
COUNT_FILE="$PLANNING_DIR/.active-agent-count"
LOCK_DIR="$PLANNING_DIR/.active-agent-count.lock"

acquire_lock() {
  local attempts=0
  local max_attempts=100
  local now lock_mtime age
  while [ "$attempts" -lt "$max_attempts" ]; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      return 0
    fi

    attempts=$((attempts + 1))

    # Stale lock guard: if lock persists for >5s, clear and retry.
    if [ "$attempts" -eq 50 ] && [ -d "$LOCK_DIR" ]; then
      now=$(date +%s)
      if [ "$(uname)" = "Darwin" ]; then
        lock_mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)
      else
        lock_mtime=$(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0)
      fi
      age=$((now - lock_mtime))
      if [ "$age" -gt 5 ]; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
      fi
    fi

    sleep 0.01
  done
  # Could not acquire lock — proceed without it (best-effort).
  return 1
}

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

read_count() {
  local raw
  raw=$(cat "$COUNT_FILE" 2>/dev/null | tr -d '[:space:]')
  if echo "$raw" | grep -Eq '^[0-9]+$'; then
    printf '%s' "$raw"
  else
    printf '0'
  fi
}

update_agent_markers() {
  local count
  count=$(read_count)

  # Write count first: if crash between writes, an elevated count is safer
  # than a missing count (agent-stop recovery handles both cases).
  echo $((count + 1)) > "$COUNT_FILE"
  echo "$ROLE" > "$PLANNING_DIR/.active-agent"
}

if [ -n "$ROLE" ]; then
  # Accept non-prefixed role aliases only when a VBW context is already active.
  if is_explicit_vbw_agent "$AGENT_TYPE" \
    || [ -f "$PLANNING_DIR/.vbw-session" ] \
    || [ -f "$PLANNING_DIR/.active-agent" ] \
    || [ -f "$COUNT_FILE" ]; then
    if acquire_lock; then
      trap 'release_lock' EXIT INT TERM
      update_agent_markers
      release_lock
      trap - EXIT INT TERM
    else
      # Lock unavailable — proceed best-effort without lock.
      update_agent_markers
    fi

    # Register agent PID for tmux cleanup
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    AGENT_PID=$(echo "$INPUT" | jq -r '.pid // ""' 2>/dev/null)
    if [ -z "$AGENT_PID" ]; then
      AGENT_PID="$PPID"
    fi
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
fi

exit 0
