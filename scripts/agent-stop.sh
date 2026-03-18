#!/bin/bash
set -u
# SubagentStop hook: Decrement active agent count and unregister PID
# Uses reference counting so concurrent agents (e.g., Scout + Lead) don't
# delete the marker while siblings are still running.
# Unregisters agent PID from tmux watchdog tracking.
# Final cleanup happens in session-stop.sh.

INPUT=$(cat)
LAST_MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
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

decrement_or_cleanup() {
  local count

  if [ -f "$COUNT_FILE" ]; then
    count=$(read_count)
    # Corrupted count + active marker => treat as one active agent left.
    if [ "$count" -le 0 ] && [ -f "$PLANNING_DIR/.active-agent" ]; then
      count=1
    fi

    count=$((count - 1))
    if [ "$count" -le 0 ]; then
      rm -f "$PLANNING_DIR/.active-agent" "$COUNT_FILE"
    else
      echo "$count" > "$COUNT_FILE"
    fi
  elif [ -f "$PLANNING_DIR/.active-agent" ]; then
    # Legacy: no count file but marker exists — remove (single agent case)
    rm -f "$PLANNING_DIR/.active-agent"
  fi
}

if acquire_lock; then
  trap 'release_lock' EXIT INT TERM
  decrement_or_cleanup
  release_lock
  trap - EXIT INT TERM
else
  # Lock unavailable — proceed best-effort without lock.
  decrement_or_cleanup
fi

# Unregister agent PID
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_PID=$(echo "$INPUT" | jq -r '.pid // ""' 2>/dev/null)
if [ -n "$AGENT_PID" ] && [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ]; then
  bash "$SCRIPT_DIR/agent-pid-tracker.sh" unregister "$AGENT_PID" 2>/dev/null || true
fi

# Capture last_assistant_message for crash recovery (REQ-07)
# If agent exited without SUMMARY.md, preserve final output for debugging
if [ -n "$LAST_MESSAGE" ] && [ -n "$AGENT_PID" ]; then
  # Detect current phase from execution state
  EXEC_STATE="$PLANNING_DIR/.execution-state.json"
  if [ -f "$EXEC_STATE" ]; then
    PHASE_NUM=$(jq -r '.phase // ""' "$EXEC_STATE" 2>/dev/null)
    if [ -n "$PHASE_NUM" ]; then
      PHASE_DIR=$(ls -d "$PLANNING_DIR/phases/${PHASE_NUM}-"* 2>/dev/null | head -1)
      if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
        # Check if any SUMMARY.md exists for this phase.
        # If phase directory cannot be read, treat summary existence as unknown
        # and skip last-words write (avoid false crash fallback artifacts).
        SUMMARY_COUNT=""
        if [ -r "$PHASE_DIR" ]; then
          SUMMARY_COUNT=$(find "$PHASE_DIR" -maxdepth 1 -type f -name '*-SUMMARY.md' 2>/dev/null | wc -l | tr -d ' ') || SUMMARY_COUNT=""
        fi

        if [ -n "$SUMMARY_COUNT" ] && [ "$SUMMARY_COUNT" -eq 0 ]; then
          # No SUMMARY.md found — write last words for crash recovery
          LAST_WORDS_DIR="$PLANNING_DIR/.agent-last-words"
          LAST_WORDS_FILE="$LAST_WORDS_DIR/${AGENT_PID}.txt"
          LAST_WORDS_LOCK="$LAST_WORDS_DIR/.${AGENT_PID}.lock"
          mkdir -p "$LAST_WORDS_DIR" 2>/dev/null || true
          TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)

          # Serialize writes per PID to avoid clobber when multiple stop events
          # race for the same agent identifier.
          _lw_attempts=0
          while [ "$_lw_attempts" -lt 100 ]; do
            if mkdir "$LAST_WORDS_LOCK" 2>/dev/null; then
              break
            fi
            _lw_attempts=$((_lw_attempts + 1))
            sleep 0.01
          done

          if [ -d "$LAST_WORDS_LOCK" ]; then
            if [ -f "$LAST_WORDS_FILE" ]; then
              {
                echo ""
                echo "---"
                echo ""
              } >> "$LAST_WORDS_FILE" 2>/dev/null || true
            fi
            {
              echo "# Agent Last Words (Crash Recovery)"
              echo "Timestamp: $TIMESTAMP"
              echo "Agent PID: $AGENT_PID"
              echo "Phase: $PHASE_NUM"
              echo ""
              echo "$LAST_MESSAGE"
            } >> "$LAST_WORDS_FILE" 2>/dev/null || true
            rmdir "$LAST_WORDS_LOCK" 2>/dev/null || true
          else
            # Best-effort fallback without lock if contention persists.
            {
              echo "# Agent Last Words (Crash Recovery)"
              echo "Timestamp: $TIMESTAMP"
              echo "Agent PID: $AGENT_PID"
              echo "Phase: $PHASE_NUM"
              echo ""
              echo "$LAST_MESSAGE"
            } >> "$LAST_WORDS_FILE" 2>/dev/null || true
          fi
        fi
      fi
    fi
  fi
fi

# Log agent shutdown event with last_message metadata
if [ -n "$AGENT_PID" ] && [ -f "$SCRIPT_DIR/log-event.sh" ]; then
  LAST_MSG_LEN=$(echo -n "$LAST_MESSAGE" | wc -c | tr -d ' ')
  bash "$SCRIPT_DIR/log-event.sh" agent_shutdown \
    "pid=$AGENT_PID" \
    "last_message_length=$LAST_MSG_LEN" \
    2>/dev/null || true
fi

# Auto-close tmux pane if recorded at start
PANE_MAP="$PLANNING_DIR/.agent-panes"
if [ -n "${TMUX:-}" ] && [ -n "$AGENT_PID" ] && [ -f "$PANE_MAP" ]; then
  PANE_ID=$(awk -v p="$AGENT_PID" '$1 == p { print $2; exit }' "$PANE_MAP" 2>/dev/null)
  if [ -n "$PANE_ID" ]; then
    # Remove entry from map
    grep -v "^${AGENT_PID} " "$PANE_MAP" > "${PANE_MAP}.tmp" 2>/dev/null || true
    mv "${PANE_MAP}.tmp" "$PANE_MAP" 2>/dev/null || true
    # Kill pane (delay briefly so agent process exits cleanly first)
    (sleep 1 && tmux kill-pane -t "$PANE_ID" 2>/dev/null || true) &
  fi
fi

exit 0
