#!/bin/bash
# hook-wrapper.sh — Universal VBW hook wrapper (DXP-01)
#
# Wraps every VBW hook with error logging and graceful degradation.
# No hook failure can ever break a session.
#
# Usage: hook-wrapper.sh <script-name.sh> [extra-args...]
#
# - Resolves the target script from the VBW plugin cache (prod)
#   or CLAUDE_PLUGIN_ROOT (local dev via --plugin-dir)
# - Passes through stdin (hook JSON context) and extra arguments
# - Logs failures to .vbw-planning/.hook-errors.log
# - Always exits 0

SCRIPT="$1"; shift
[ -z "$SCRIPT" ] && exit 0

# --- SIGHUP trap for terminal force-close ---
# Cleanup orphaned agents on unexpected terminal termination.
# This is a backup for tmux watchdog — handles direct terminal force-close.
cleanup_on_sighup() {
  PLANNING_DIR=".vbw-planning"
  if [ ! -d "$PLANNING_DIR" ]; then
    exit 1
  fi

  # Resolve agent-pid-tracker.sh from cache
  # shellcheck source=resolve-claude-dir.sh
  . "$(dirname "$0")/resolve-claude-dir.sh" 2>/dev/null || true
  CACHE="${CLAUDE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/plugins/cache/vbw-marketplace/vbw"
  TRACKER=$(ls -1 "$CACHE"/*/scripts/agent-pid-tracker.sh 2>/dev/null \
    | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)

  if [ -z "$TRACKER" ] || [ ! -f "$TRACKER" ]; then
    exit 1
  fi

  # Log SIGHUP trigger
  LOG="$PLANNING_DIR/.hook-errors.log"
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  echo "[$TS] SIGHUP received, cleaning up agent PIDs" >> "$LOG" 2>/dev/null || true

  # Get active PIDs and terminate with escalation
  PIDS=$(bash "$TRACKER" list 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    for pid in $PIDS; do
      kill -TERM "$pid" 2>/dev/null || true
    done

    # Wait 3s for graceful shutdown, then SIGKILL survivors
    sleep 3
    for pid in $PIDS; do
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
      fi
    done
  fi

  exit 1
}

trap cleanup_on_sighup SIGHUP

# Debug mode: VBW_DEBUG=1 enables verbose hook tracing to stderr
VBW_DEBUG="${VBW_DEBUG:-0}"

# Resolve debug_logging from config.json (shared flag for all hook diagnostics)
_DBG_ENABLED=0
[ "$VBW_DEBUG" = "1" ] && _DBG_ENABLED=1
if [ "$_DBG_ENABLED" != "1" ] && [ -f ".vbw-planning/config.json" ] && command -v jq &>/dev/null; then
  _DBG_VAL=$(jq -r '.debug_logging // false' ".vbw-planning/config.json" 2>/dev/null || echo "false")
  case "$_DBG_VAL" in true|1) _DBG_ENABLED=1 ;; esac
fi

# Resolve from plugin cache (version-sorted, latest wins)
# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh"
CACHE="$CLAUDE_DIR/plugins/cache/vbw-marketplace/vbw"
TARGET=$(ls -1 "$CACHE"/*/scripts/"$SCRIPT" 2>/dev/null \
  | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)

# Fallback to CLAUDE_PLUGIN_ROOT for --plugin-dir installs (local dev)
if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
  TARGET="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/$SCRIPT}"
fi

# Fallback: sibling script — if we're running, the target is next to us
if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
  _SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
  [ -f "$_SELF_DIR/$SCRIPT" ] && TARGET="$_SELF_DIR/$SCRIPT"
fi
[ -z "$TARGET" ] || [ ! -f "$TARGET" ] && exit 0

[ "$VBW_DEBUG" = "1" ] && echo "[VBW DEBUG] hook-wrapper: $SCRIPT → $TARGET" >&2

# Execute — stdin flows through to the target script
# When debug logging is enabled, capture stdout for the debug log while still passing it through
if [ "$_DBG_ENABLED" = "1" ] && [ -d ".vbw-planning" ]; then
  _DBG_LOG=".vbw-planning/.hook-debug.log"
  _DBG_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  _DBG_TMP=$(mktemp 2>/dev/null || echo "/tmp/.vbw-hook-dbg-$$")
  bash "$TARGET" "$@" | tee "$_DBG_TMP"
  RC=${PIPESTATUS[0]}
  _DBG_OUTPUT=$(cat "$_DBG_TMP" 2>/dev/null)
  rm -f "$_DBG_TMP" 2>/dev/null
  # Log the hook execution and its full output
  {
    echo "${_DBG_TS} hook=${SCRIPT} exit=${RC}"
    if [ -n "$_DBG_OUTPUT" ]; then
      _DBG_B64=$(echo -n "$_DBG_OUTPUT" | base64 2>/dev/null | tr -d '\n' || echo "encode-failed")
      echo "${_DBG_TS} hook=${SCRIPT} output_base64=${_DBG_B64}"
    fi
  } >> "$_DBG_LOG" 2>/dev/null || true
  # Trim to last 200 entries
  if [ -f "$_DBG_LOG" ]; then
    _DBG_LC=$(wc -l < "$_DBG_LOG" 2>/dev/null | tr -d ' ')
    [ "${_DBG_LC:-0}" -gt 200 ] && { tail -100 "$_DBG_LOG" > "${_DBG_LOG}.tmp" && mv "${_DBG_LOG}.tmp" "$_DBG_LOG"; } 2>/dev/null
  fi
else
  bash "$TARGET" "$@"
  RC=$?
fi
[ "$VBW_DEBUG" = "1" ] && [ "$RC" -ne 0 ] && echo "[VBW DEBUG] hook-wrapper: $SCRIPT exit=$RC" >&2
[ "$RC" -eq 0 ] && exit 0

# Exit 2 = intentional block (PreToolUse/UserPromptSubmit) — pass through, not a failure
[ "$RC" -eq 2 ] && exit 2

# --- Failure: log and exit 0 ---
if [ -d ".vbw-planning" ]; then
  LOG=".vbw-planning/.hook-errors.log"
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  printf '%s %s exit=%d\n' "$TS" "$SCRIPT" "$RC" >> "$LOG" 2>/dev/null
  # Trim to last 50 entries to prevent unbounded growth
  if [ -f "$LOG" ]; then
    LC=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
    [ "${LC:-0}" -gt 50 ] && { tail -30 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"; } 2>/dev/null
  fi
fi

exit 0
