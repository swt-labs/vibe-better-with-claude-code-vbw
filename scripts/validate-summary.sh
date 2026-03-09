#!/bin/bash
set -u
# PostToolUse/SubagentStop: Validate SUMMARY.md structure (non-blocking, exit 0)

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.command // ""')

# Only check SUMMARY.md files in .vbw-planning/
if ! echo "$FILE_PATH" | grep -qE '\.vbw-planning/.*SUMMARY\.md$'; then
  exit 0
fi

# If SUMMARY.md doesn't exist, check for crash recovery fallback
if [ ! -f "$FILE_PATH" ]; then
  PLANNING_DIR=".vbw-planning"
  LAST_WORDS_DIR="$PLANNING_DIR/.agent-last-words"

  # Look for recent .agent-last-words files (within last 60 seconds)
  if [ -d "$LAST_WORDS_DIR" ]; then
    NOW=$(date +%s 2>/dev/null || echo 0)
    FALLBACK_FOUND=""
    STALE_FOUND=false

    for lw_file in "$LAST_WORDS_DIR"/*.txt; do
      [ -f "$lw_file" ] || continue

      # Check file age
      if [ "$(uname)" = "Darwin" ]; then
        FILE_MTIME=$(stat -f %m "$lw_file" 2>/dev/null || echo 0)
      else
        FILE_MTIME=$(stat -c %Y "$lw_file" 2>/dev/null || echo 0)
      fi

      AGE=$((NOW - FILE_MTIME))
      if [ "$AGE" -ge 0 ] && [ "$AGE" -le 60 ]; then
        FALLBACK_FOUND="$lw_file"
        break
      elif [ "$AGE" -gt 60 ]; then
        STALE_FOUND=true
      fi
    done

    if [ -n "$FALLBACK_FOUND" ]; then
      jq -n --arg file "$(basename "$FALLBACK_FOUND")" '{
        "hookSpecificOutput": {
          "hookEventName": "PostToolUse",
          "additionalContext": ("SUMMARY.md missing but crash recovery fallback available: " + $file + ". Agent may have crashed before writing SUMMARY.md. Check .agent-last-words/ for final output.")
        }
      }'
    elif [ "$STALE_FOUND" = true ]; then
      jq -n '{
        "hookSpecificOutput": {
          "hookEventName": "PostToolUse",
          "additionalContext": "SUMMARY.md missing and only stale crash recovery artifacts were found in .agent-last-words/ (>60s old). Check those files if this was a prior crash, then rerun or regenerate SUMMARY.md."
        }
      }'
    fi
  fi

  exit 0
fi

MISSING=""

# YAML frontmatter required (compact format relies on it)
if ! head -1 "$FILE_PATH" | grep -q '^---$'; then
  MISSING="Missing YAML frontmatter. "
fi

# Validate status value (must be complete|partial|failed per SUMMARY.md contract)
_VS_STATUS=$(sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' "$FILE_PATH" 2>/dev/null | head -1 | tr -d '[:space:]')
if [ -n "$_VS_STATUS" ]; then
  case "$_VS_STATUS" in
    complete|partial|failed) ;;  # valid terminal statuses
    completed)
      MISSING="${MISSING}Status 'completed' should be 'complete' (canonical form). "
      ;;
    pending|in_progress)
      MISSING="${MISSING}Invalid status '${_VS_STATUS}' -- SUMMARY.md must only be created at plan completion (status: complete|partial|failed). "
      ;;
    *)
      MISSING="${MISSING}Invalid status '${_VS_STATUS}' (must be complete|partial|failed). "
      ;;
  esac
else
  # Status field missing from frontmatter -- required for completion detection
  if head -1 "$FILE_PATH" | grep -q '^---$'; then
    MISSING="${MISSING}Missing 'status' field in frontmatter (must be complete|partial|failed). "
  fi
fi

if ! grep -q "## What Was Built" "$FILE_PATH"; then
  MISSING="${MISSING}Missing '## What Was Built'. "
fi

if ! grep -q "## Files Modified" "$FILE_PATH"; then
  MISSING="${MISSING}Missing '## Files Modified'. "
fi

if [ -n "$MISSING" ]; then
  jq -n --arg msg "$MISSING" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": ("SUMMARY validation: " + $msg)
    }
  }'
fi

exit 0
