#!/bin/bash
set -u
# PostToolUse/SubagentStop: Validate SUMMARY.md structure (non-blocking, exit 0)

HOOK_EVENT="${1:-PostToolUse}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_OUTPUT_GUARD="$SCRIPT_DIR/lib/hook-output-guard.sh"
if [ -f "$HOOK_OUTPUT_GUARD" ]; then
  # shellcheck source=scripts/lib/hook-output-guard.sh
  source "$HOOK_OUTPUT_GUARD"
fi
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.command // ""')

hook_event_allows_output() {
  local event_name="$1"

  if type should_emit_hook_output >/dev/null 2>&1; then
    should_emit_hook_output "$event_name"
    return $?
  fi

  [ "$event_name" = "PostToolUse" ]
}

emit_posttool_context() {
  local context="$1"

  [ "$HOOK_EVENT" = "PostToolUse" ] || return 0
  hook_event_allows_output "$HOOK_EVENT" || return 0
  jq -n --arg context "$context" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $context
    }
  }'
}

# Only check SUMMARY.md files in .vbw-planning/
if ! echo "$FILE_PATH" | grep -qE '\.vbw-planning/.*SUMMARY\.md$'; then
  exit 0
fi

# If SUMMARY.md doesn't exist, check for crash recovery fallback
if [ ! -f "$FILE_PATH" ]; then
  PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
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
      emit_posttool_context "SUMMARY.md missing but crash recovery fallback available: $(basename "$FALLBACK_FOUND"). Agent may have crashed before writing SUMMARY.md. Check .agent-last-words/ for final output."
    elif [ "$STALE_FOUND" = true ]; then
      emit_posttool_context "SUMMARY.md missing and only stale crash recovery artifacts were found in .agent-last-words/ (>60s old). Check those files if this was a prior crash, then rerun or regenerate SUMMARY.md."
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

# Conditional ac_results check: only when corresponding PLAN has must_haves
# Skip remediation summaries — they use a different template without ac_results
# Matches both template-named (*REMEDIATION*) and runtime-named (R01-SUMMARY.md) files
case "$(basename "$FILE_PATH")" in
  *REMEDIATION*|R[0-9]*-SUMMARY.md) ;;
  *)
PLAN_PATH=$(echo "$FILE_PATH" | sed 's/SUMMARY\.md$/PLAN.md/')
if [ -f "$PLAN_PATH" ]; then
  # Check if plan has non-empty must_haves.
  # Two forms: (1) inline flow-style on must_haves: line itself, e.g. must_haves: ["text"]
  #            (2) indented children under block-style must_haves: key
  # Flow-style: require at least one non-whitespace, non-] char inside brackets (rejects [] and [ ])
  _VS_HAS_MH=""
  if grep -qE '^must_haves:[[:space:]]*\[[^]]*[^][:space:]][^]]*\]' "$PLAN_PATH" 2>/dev/null; then
    _VS_HAS_MH=true
  elif sed -n '/^must_haves:/,/^[^ ]/p' "$PLAN_PATH" 2>/dev/null | grep '^ ' | grep -qE '^ *- |: *\[[^]]*[^][:space:]][^]]*\]'; then
    _VS_HAS_MH=true
  fi
  if [ "$_VS_HAS_MH" = true ]; then
    # Extract frontmatter and check for ac_results
    if ! sed -n '/^---$/,/^---$/p' "$FILE_PATH" 2>/dev/null | grep -q '^ac_results:'; then
      MISSING="${MISSING}Missing 'ac_results' in frontmatter (plan has must_haves). "
    else
      # Validate verdict values are pass/fail/partial
      _VS_VERDICTS=$(sed -n '/^---$/,/^---$/{ /^ *verdict:/{ s/^ *verdict:[[:space:]]*//; s/["'"'"']//g; p; }; }' "$FILE_PATH" 2>/dev/null)
      for _VS_V in $_VS_VERDICTS; do  # unquoted intentional: verdicts are single-word enums
        case "$_VS_V" in
          pass|fail|partial) ;;
          *) MISSING="${MISSING}Invalid ac_results verdict '${_VS_V}' (must be pass/fail/partial). " ;;
        esac
      done
    fi
  fi
fi
  ;;
esac

if [ -n "$MISSING" ]; then
  emit_posttool_context "SUMMARY validation: $MISSING"
fi

exit 0
