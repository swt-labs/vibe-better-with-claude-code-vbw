#!/bin/bash
set -euo pipefail
# agent-pid-tracker.sh — Track active VBW agent PIDs for cleanup on tmux detach
#
# Usage:
#   agent-pid-tracker.sh register <pid>
#   agent-pid-tracker.sh unregister <pid>
#   agent-pid-tracker.sh list
#   agent-pid-tracker.sh prune
#
# Stores newline-delimited PIDs in .vbw-planning/.agent-pids
# Uses mkdir-based file locking (macOS-compatible, no flock needed)

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
PID_FILE="$PLANNING_DIR/.agent-pids"
LOCK_DIR="/tmp/vbw-agent-pid-lock"

# --- File locking helpers ---
acquire_lock() {
  local retries=50
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "ERROR: Failed to acquire lock after 50 attempts" >&2
      return 1
    fi
    # Check for stale lock on every iteration
    if [ -f "${LOCK_DIR}/pid" ]; then
      local lock_pid
      lock_pid=$(cat "${LOCK_DIR}/pid" 2>/dev/null || echo "")
      if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
        # Lock holder is dead — remove stale lock and retry immediately
        rm -f "${LOCK_DIR}/pid"
        rmdir "$LOCK_DIR" 2>/dev/null || true
        continue
      fi
    else
      # Lock dir exists but no pid file — holder may still be writing it.
      # Wait for pid file to appear before concluding orphaned.
      local pid_wait=0
      while [ "$pid_wait" -lt 5 ] && [ ! -f "${LOCK_DIR}/pid" ]; do
        sleep 0.1
        pid_wait=$((pid_wait + 1))
      done
      # If pid file appeared, loop back to validate the holder normally
      if [ -f "${LOCK_DIR}/pid" ]; then
        continue
      fi
      # No pid file after 0.5s — lock is orphaned, remove it
      rmdir "$LOCK_DIR" 2>/dev/null || true
      continue
    fi
    sleep 0.1
  done
  # Record our PID immediately so stale detection works
  echo $$ > "${LOCK_DIR}/pid" 2>/dev/null || true
  return 0
}

release_lock() {
  rm -f "${LOCK_DIR}/pid" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

# --- Subcommands ---
cmd_register() {
  local pid="$1"
  # Validate PID format (positive integer, no leading zeros)
  if ! echo "$pid" | grep -qE '^[1-9][0-9]*$'; then
    echo "ERROR: Invalid PID format: $pid" >&2
    return 1
  fi

  acquire_lock || return 1
  trap release_lock EXIT

  # Create .vbw-planning if missing
  mkdir -p "$(dirname "$PID_FILE")"

  # Append PID if not already present
  if [ -f "$PID_FILE" ]; then
    if grep -q "^${pid}$" "$PID_FILE" 2>/dev/null; then
      return 0  # Already registered
    fi
  fi

  echo "$pid" >> "$PID_FILE"
  release_lock
  trap - EXIT
}

cmd_unregister() {
  local pid="$1"
  # Validate PID format (positive integer, no leading zeros)
  if ! echo "$pid" | grep -qE '^[1-9][0-9]*$'; then
    echo "ERROR: Invalid PID format: $pid" >&2
    return 1
  fi

  acquire_lock || return 1
  trap release_lock EXIT

  if [ ! -f "$PID_FILE" ]; then
    release_lock
    trap - EXIT
    return 0
  fi

  # Remove the PID line (defensive rm -f mirrors cmd_prune pattern)
  rm -f "${PID_FILE}.tmp" 2>/dev/null || true
  grep -v "^${pid}$" "$PID_FILE" > "${PID_FILE}.tmp" 2>/dev/null || true
  mv "${PID_FILE}.tmp" "$PID_FILE"

  # Remove empty PID file (all entries unregistered)
  if [ ! -s "$PID_FILE" ]; then
    rm -f "$PID_FILE"
  fi

  release_lock
  trap - EXIT
}

cmd_list() {
  if [ ! -f "$PID_FILE" ]; then
    return 0
  fi

  # Filter out dead PIDs (kill -0 checks existence without signaling)
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    # Validate positive integer PID
    if ! echo "$pid" | grep -qE '^[1-9][0-9]*$'; then
      continue
    fi
    # Check if process exists
    if kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
    fi
  done < "$PID_FILE"
}

cmd_prune() {
  if [ ! -f "$PID_FILE" ]; then
    return 0
  fi

  acquire_lock || return 1
  trap release_lock EXIT

  local temp_file="${PID_FILE}.tmp"
  local kept=0

  # Remove any leftover temp file from a previously interrupted prune
  rm -f "$temp_file" 2>/dev/null || true

  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    echo "$pid" | grep -qE '^[1-9][0-9]*$' || continue
    if kill -0 "$pid" 2>/dev/null; then
      echo "$pid" >> "$temp_file"
      kept=$((kept + 1))
    fi
  done < "$PID_FILE"

  if [ "$kept" -gt 0 ] && [ -f "$temp_file" ]; then
    mv "$temp_file" "$PID_FILE"
  else
    rm -f "$PID_FILE"
  fi
  # Clean up temp file in case mv didn't consume it (defensive)
  rm -f "$temp_file" 2>/dev/null || true

  release_lock
  trap - EXIT
}

# --- Main ---
CMD="${1:-}"
case "$CMD" in
  register)
    [ -z "${2:-}" ] && { echo "Usage: $0 register <pid>" >&2; exit 1; }
    cmd_register "$2"
    ;;
  unregister)
    [ -z "${2:-}" ] && { echo "Usage: $0 unregister <pid>" >&2; exit 1; }
    cmd_unregister "$2"
    ;;
  list)
    cmd_list
    ;;
  prune)
    cmd_prune
    ;;
  *)
    echo "Usage: $0 {register|unregister|list|prune} [pid]" >&2
    exit 1
    ;;
esac
