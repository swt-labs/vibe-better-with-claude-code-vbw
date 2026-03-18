#!/bin/bash
set -u
# PreToolUse hook: Block destructive Bash commands
# Exit 2 = block, Exit 0 = allow
# Fail-CLOSED: exit 2 on parse error (never allow unvalidated input through)

# --- Override checks (fast path) ---

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"

# Env var override
[ "${VBW_ALLOW_DESTRUCTIVE:-0}" = "1" ] && exit 0

# Config override: bash_guard=false disables entirely
if command -v jq >/dev/null 2>&1 && [ -f "$PLANNING_DIR/config.json" ]; then
  GUARD=$(jq -r '.bash_guard // true' "$PLANNING_DIR/config.json" 2>/dev/null)
  [ "$GUARD" = "false" ] && exit 0
fi

# --- Parse input ---

if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq not available, cannot validate bash command" >&2
  exit 2
fi

INPUT=$(cat 2>/dev/null) || exit 2
[ -z "$INPUT" ] && exit 2

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 2
[ -z "$COMMAND" ] && exit 0  # No command = nothing to check

# --- Resolve pattern files ---

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
DEFAULT_PATTERNS="$PLUGIN_ROOT/config/destructive-commands.txt"
LOCAL_PATTERNS="$PLANNING_DIR/destructive-commands.local.txt"

# Build combined pattern from all sources
PATTERNS=""
for PFILE in "$DEFAULT_PATTERNS" "$LOCAL_PATTERNS"; do
  [ -f "$PFILE" ] || continue
  # Strip comments and empty lines, join with |
  FILE_PATTERNS=$(grep -v '^\s*#' "$PFILE" | grep -v '^\s*$' | tr '\n' '|' | sed 's/|$//')
  [ -n "$FILE_PATTERNS" ] && {
    [ -n "$PATTERNS" ] && PATTERNS="$PATTERNS|$FILE_PATTERNS" || PATTERNS="$FILE_PATTERNS"
  }
done

# No patterns loaded = nothing to check
[ -z "$PATTERNS" ] && exit 0

# --- Match ---

if echo "$COMMAND" | grep -iqE "$PATTERNS"; then
  # Extract which pattern matched (for logging)
  MATCHED=$(echo "$COMMAND" | grep -ioE "$PATTERNS" | head -1)
  echo "Blocked: destructive command detected ($MATCHED)" >&2
  echo "Hint: Use VBW_ALLOW_DESTRUCTIVE=1 to override, or run outside VBW." >&2
  echo "See: config/destructive-commands.txt for the full blocklist." >&2

  # Event logging (best-effort, non-blocking)
  if [ -d "$PLANNING_DIR" ]; then
    PREVIEW=$(echo "$COMMAND" | head -c 40)
    AGENT="${VBW_ACTIVE_AGENT:-unknown}"
    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
    # Escape double quotes in preview for valid JSON
    PREVIEW=$(echo "$PREVIEW" | sed 's/"/\\"/g')
    MATCHED_ESC=$(echo "$MATCHED" | sed 's/"/\\"/g')
    printf '{"event":"bash_guard_block","command_preview":"%s","pattern_matched":"%s","agent":"%s","timestamp":"%s"}\n' \
      "$PREVIEW" "$MATCHED_ESC" "$AGENT" "$TS" >> "$PLANNING_DIR/.event-log.jsonl" 2>/dev/null
  fi

  exit 2
fi

exit 0
