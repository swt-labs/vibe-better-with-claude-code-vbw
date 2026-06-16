#!/bin/bash
set -u
# SubagentStop hook: Decrement active agent count and unregister PID.
# Active-agent state is session-local when a safe session id is available; root
# .active-agent* files are aggregate display/legacy fallback state.
# Unregisters agent PID from tmux watchdog tracking.
# Final cleanup happens in session-stop.sh.

INPUT=$(cat)
LAST_MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/active-agent-state.sh" ]; then
  # shellcheck source=lib/active-agent-state.sh
  . "$SCRIPT_DIR/lib/active-agent-state.sh"
else
  exit 0
fi
COUNT_FILE="$PLANNING_DIR/.active-agent-count"
NATIVE_AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)
LEGACY_AGENT_ROLE_SOURCE=$(echo "$INPUT" | jq -r '.agent_name // .agentName // .name // ""' 2>/dev/null)
AGENT_PID=$(echo "$INPUT" | jq -r '.pid // ""' 2>/dev/null)

has_vbw_context() {
  [ -f "$PLANNING_DIR/.vbw-session" ] \
    || [ -f "$PLANNING_DIR/.active-agent" ] \
    || [ -f "$COUNT_FILE" ]
}

is_explicit_vbw_agent() {
  local value="$1"
  local lower
  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  echo "$lower" | grep -qE '^@?vbw:|^@?vbw-'
}

normalize_agent_role() {
  local value="$1"
  local lower

  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  lower="${lower#@}"
  lower="${lower#vbw:}"

  case "$lower" in
    vbw-lead|vbw-lead-[0-9]*|lead|lead-[0-9]*|team-lead|team-lead-[0-9]*) printf 'lead'; return 0 ;;
    vbw-dev|vbw-dev-[0-9]*|dev|dev-[0-9]*|team-dev|team-dev-[0-9]*) printf 'dev'; return 0 ;;
    vbw-qa|vbw-qa-[0-9]*|qa|qa-[0-9]*|team-qa|team-qa-[0-9]*) printf 'qa'; return 0 ;;
    vbw-scout|vbw-scout-[0-9]*|scout|scout-[0-9]*|team-scout|team-scout-[0-9]*) printf 'scout'; return 0 ;;
    vbw-debugger|vbw-debugger-[0-9]*|debugger|debugger-[0-9]*|team-debugger|team-debugger-[0-9]*) printf 'debugger'; return 0 ;;
    vbw-architect|vbw-architect-[0-9]*|architect|architect-[0-9]*|team-architect|team-architect-[0-9]*) printf 'architect'; return 0 ;;
    vbw-docs|vbw-docs-[0-9]*|docs|docs-[0-9]*|team-docs|team-docs-[0-9]*) printf 'docs'; return 0 ;;
  esac

  return 1
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

  if [ -n "$LEGACY_AGENT_ROLE_SOURCE" ]; then
    if is_explicit_vbw_agent "$LEGACY_AGENT_ROLE_SOURCE" || has_vbw_context; then
      printf '%s' "$LEGACY_AGENT_ROLE_SOURCE"
      return 0
    fi
  fi

  return 1
}

should_process_stop() {
  if [ -n "$NATIVE_AGENT_TYPE" ]; then
    if is_explicit_vbw_agent "$NATIVE_AGENT_TYPE"; then
      return 0
    fi

    if is_explicit_vbw_agent "$LEGACY_AGENT_ROLE_SOURCE"; then
      return 0
    fi

    return 1
  fi

  if [ -n "$LEGACY_AGENT_ROLE_SOURCE" ]; then
    if is_explicit_vbw_agent "$LEGACY_AGENT_ROLE_SOURCE" || has_vbw_context; then
      return 0
    fi

    return 1
  fi

  # Legacy callers/tests may not provide identity fields at all.
  return 0
}

ROLE=""
if ROLE_SOURCE=$(select_agent_role_source) && ROLE=$(normalize_agent_role "$ROLE_SOURCE"); then
  :
else
  ROLE=""
fi

if ! should_process_stop; then
  exit 0
fi

vbw_active_agent_stop "$PLANNING_DIR" "$INPUT" "$ROLE" "$AGENT_PID"

# Unregister agent PID
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
