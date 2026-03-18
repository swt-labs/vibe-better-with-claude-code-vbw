#!/bin/bash
set -u
# tmux-watchdog.sh — Terminate orphaned agents when tmux session detaches
#                     and kill agents stuck in compaction (> 5 minutes)
#
# Usage: tmux-watchdog.sh [session-name]
#
# Polls `tmux list-clients -t SESSION` every 5 seconds. Requires 2 consecutive
# empty results before cleanup. On confirmed detach: reads PIDs from
# agent-pid-tracker.sh list, sends SIGTERM, waits 3s, sends SIGKILL if needed.
# Also checks .vbw-planning/.compacting/*.json for agents stuck in compaction
# longer than COMPACTION_TIMEOUT seconds (default 300 = 5 minutes).
# Logs to stderr. Exits when session is gone (not just detached).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"

# --- Session name resolution ---
SESSION="${1:-}"
if [ -z "$SESSION" ]; then
  # Auto-detect from $TMUX environment variable
  # Format: /path/to/socket,server_pid,session_num
  if [ -n "${TMUX:-}" ]; then
    SESSION=$(tmux display-message -p '#S' 2>/dev/null || true)
  fi
fi

if [ -z "$SESSION" ]; then
  echo "ERROR: No session name provided and not running in tmux" >&2
  exit 1
fi

LOG="$PLANNING_DIR/.watchdog.log"
mkdir -p "$PLANNING_DIR"

log() {
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $*" >> "$LOG" 2>/dev/null || echo "[$timestamp] $*" >&2
}

log "Watchdog started for session: $SESSION (PID=$$)"

# Clean stale compaction markers from previous (possibly crashed) sessions.
# Only remove markers whose PIDs are dead — live PIDs may be actively compacting.
mkdir -p "$PLANNING_DIR/.compacting" 2>/dev/null || true
for _stale_marker in "$PLANNING_DIR/.compacting"/*.json; do
  [ ! -f "$_stale_marker" ] && continue
  _stale_pid=$(jq -r '.pid // ""' "$_stale_marker" 2>/dev/null)
  _stale_ts=$(jq -r '.started_at // ""' "$_stale_marker" 2>/dev/null)
  # Full schema validation: PID and started_at must be sane positive integers
  if ! echo "$_stale_pid" | grep -Eq '^[1-9][0-9]{0,9}$' \
     || ! echo "$_stale_ts" | grep -Eq '^[1-9][0-9]{0,9}$' \
     || ! kill -0 "$_stale_pid" 2>/dev/null; then
    rm -f "$_stale_marker" 2>/dev/null || true
  fi
done

# Validate timeout: must be a positive integer, fallback to 300
COMPACTION_TIMEOUT="${VBW_COMPACTION_TIMEOUT:-300}"
if ! echo "$COMPACTION_TIMEOUT" | grep -Eq '^[1-9][0-9]{0,5}$'; then
  log "Invalid VBW_COMPACTION_TIMEOUT='$COMPACTION_TIMEOUT', using default 300"
  COMPACTION_TIMEOUT=300
fi

# --- Compaction timeout check ---
# Scans .compacting/*.json for agents stuck longer than COMPACTION_TIMEOUT.
# Kills the agent process and its tmux pane, then cleans up.
check_compaction_timeouts() {
  local compacting_dir="$PLANNING_DIR/.compacting"
  [ ! -d "$compacting_dir" ] && return

  local now marker pid agent_name started_at age
  now=$(date +%s)

  for marker in "$compacting_dir"/*.json; do
    [ ! -f "$marker" ] && continue

    pid=$(jq -r '.pid // ""' "$marker" 2>/dev/null)
    agent_name=$(jq -r '.agent_name // "unknown"' "$marker" 2>/dev/null)
    started_at=$(jq -r '.started_at // 0' "$marker" 2>/dev/null)

    # Clean markers with missing/invalid critical data — they can never become valid
    # PID must be a positive integer, max 10 digits (prevents special PIDs like -1)
    # started_at must be a positive integer, max 10 digits (prevents arithmetic overflow)
    if ! echo "$pid" | grep -Eq '^[1-9][0-9]{0,9}$' || ! echo "$started_at" | grep -Eq '^[1-9][0-9]{0,9}$'; then
      rm -f "$marker" 2>/dev/null || true
      continue
    fi

    # Reject future timestamps (clock skew > 60s)
    if [ "$started_at" -gt $((now + 60)) ]; then
      rm -f "$marker" 2>/dev/null || true
      continue
    fi

    # Clean stale markers for dead PIDs (compaction finished but cleanup missed)
    if ! kill -0 "$pid" 2>/dev/null; then
      log "Compaction marker for dead PID $pid ($agent_name), cleaning up"
      rm -f "$marker" 2>/dev/null || true
      continue
    fi

    age=$((now - started_at))
    if [ "$age" -gt "$COMPACTION_TIMEOUT" ]; then
      # Always resolve pane_id from live tmux state using validated PID.
      # Never trust stored pane_id — it may be stale or corrupted.
      local _live_pane_id="" _pane_list _walk_pid _resolved
      _pane_list=$(tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null) || _pane_list=""
      if [ -n "$_pane_list" ]; then
        _walk_pid="$pid"
        while [ -n "$_walk_pid" ] && [ "$_walk_pid" != "0" ] && [ "$_walk_pid" != "1" ]; do
          _resolved=$(echo "$_pane_list" | awk -v p="$_walk_pid" '$1 == p { print $2; exit }')
          if [ -n "$_resolved" ]; then
            _live_pane_id="$_resolved"
            break
          fi
          _walk_pid=$(ps -o ppid= -p "$_walk_pid" 2>/dev/null | tr -d ' ')
        done
      fi

      log "COMPACTION TIMEOUT: agent=$agent_name pid=$pid pane=$_live_pane_id age=${age}s (limit=${COMPACTION_TIMEOUT}s)"

      # Kill agent process then pane in background to avoid blocking the poll loop.
      # Order matters: SIGTERM first so the Stop hook can fire, then kill pane.
      (
        log "Sending SIGTERM to stuck agent PID $pid"
        kill -TERM "$pid" 2>/dev/null || true
        sleep 2
        if kill -0 "$pid" 2>/dev/null; then
          log "Agent PID $pid survived SIGTERM, sending SIGKILL"
          kill -KILL "$pid" 2>/dev/null || true
        fi
        # Kill tmux pane after agent process is terminated
        if [ -n "$_live_pane_id" ]; then
          log "Killing tmux pane $_live_pane_id"
          tmux kill-pane -t "$_live_pane_id" 2>/dev/null || true
        fi
      ) &

      # Unregister from PID tracker
      if [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ]; then
        bash "$SCRIPT_DIR/agent-pid-tracker.sh" unregister "$pid" 2>/dev/null || true
      fi

      # Remove pane mapping entry
      local pane_map="$PLANNING_DIR/.agent-panes"
      if [ -f "$pane_map" ]; then
        grep -v "^${pid} " "$pane_map" > "${pane_map}.tmp" 2>/dev/null || true
        mv "${pane_map}.tmp" "$pane_map" 2>/dev/null || true
      fi

      # Clean up marker
      rm -f "$marker" 2>/dev/null || true

      log "Compaction timeout cleanup complete for $agent_name (PID $pid)"
    fi
  done
}

# --- Main polling loop ---
consecutive_empty=0
while true; do
  # Check if session still exists
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    log "Session $SESSION no longer exists, exiting"
    break
  fi

  # Poll for attached clients
  CLIENTS=$(tmux list-clients -t "$SESSION" 2>/dev/null | wc -l | tr -d ' ')

  if [ "${CLIENTS:-0}" -eq 0 ]; then
    consecutive_empty=$((consecutive_empty + 1))
    log "No clients attached (consecutive: $consecutive_empty)"

    if [ "$consecutive_empty" -ge 2 ]; then
      log "Session detached (2 consecutive polls), cleaning up agents"

      # Read active agent PIDs
      PIDS=""
      if [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ]; then
        PIDS=$(bash "$SCRIPT_DIR/agent-pid-tracker.sh" list 2>/dev/null || true)
      fi

      if [ -z "$PIDS" ]; then
        log "No active agent PIDs to terminate"
      else
        # Terminate with SIGTERM
        for pid in $PIDS; do
          if kill -0 "$pid" 2>/dev/null; then
            log "Sending SIGTERM to agent PID $pid"
            kill -TERM "$pid" 2>/dev/null || true
          fi
        done

        # Wait 3 seconds for graceful shutdown
        sleep 3

        # SIGKILL fallback for survivors
        for pid in $PIDS; do
          if kill -0 "$pid" 2>/dev/null; then
            log "Agent PID $pid survived SIGTERM, sending SIGKILL"
            kill -KILL "$pid" 2>/dev/null || true
          fi
        done

        log "Agent cleanup complete"
      fi

      # Clean up PID file and compaction markers
      if [ -f "$PLANNING_DIR/.agent-pids" ]; then
        rm -f "$PLANNING_DIR/.agent-pids" 2>/dev/null || true
        log "Removed .agent-pids file"
      fi
      rm -rf "$PLANNING_DIR/.compacting" 2>/dev/null || true

      # Exit after cleanup
      log "Watchdog exiting"
      break
    fi
  else
    # Clients attached, reset counter
    if [ "$consecutive_empty" -gt 0 ]; then
      log "Client attached, resetting empty counter"
    fi
    consecutive_empty=0
  fi

  # Check for agents stuck in compaction
  check_compaction_timeouts

  sleep 5
done

exit 0
