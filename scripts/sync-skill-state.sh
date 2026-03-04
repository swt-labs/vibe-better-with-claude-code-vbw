#!/usr/bin/env bash
set -euo pipefail

# sync-skill-state.sh — Sync skill inventory to STATE.md and CLAUDE.md
#
# Reads detect-stack.sh JSON output and updates:
#   1. STATE.md ### Skills section (under ## Decisions)
#   2. CLAUDE.md ## Installed Skills section
#
# Usage: bash sync-skill-state.sh [project-dir] [json-file]
#   project-dir  defaults to .
#   json-file    optional pre-computed JSON from detect-stack.sh

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo "sync-skill-state: jq is required but not installed" >&2
  exit 1
fi

PROJECT_DIR="${1:-.}"
JSON_FILE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Get skill data ---
if [ -n "$JSON_FILE" ] && [ -f "$JSON_FILE" ]; then
  STACK_JSON=$(cat "$JSON_FILE")
else
  STACK_JSON=$(bash "$SCRIPT_DIR/detect-stack.sh" "$PROJECT_DIR" 2>/dev/null) || {
    echo "sync-skill-state: detect-stack.sh failed" >&2
    exit 1
  }
fi

# Validate no error key
if echo "$STACK_JSON" | jq -e '.error' &>/dev/null; then
  echo "sync-skill-state: detect-stack.sh returned error" >&2
  exit 1
fi

# --- Extract fields with jq ---
INSTALLED=$(echo "$STACK_JSON" | jq -r '
  [.installed.global[], .installed.project[], .installed.agents[]]
  | unique | join(", ")
  | if . == "" then "None detected" else . end
')

SUGGESTED=$(echo "$STACK_JSON" | jq -r '
  .suggestions | join(", ")
  | if . == "" then "None" else . end
')

DETECTED=$(echo "$STACK_JSON" | jq -r '
  .detected_stack | join(", ")
  | if . == "" then "(none)" else . end
')

FIND_SKILLS=$(echo "$STACK_JSON" | jq -r '
  if .find_skills_available then "yes" else "no" end
')

# --- Update STATE.md ---
STATE_FILE="$PROJECT_DIR/.vbw-planning/STATE.md"

if [ -f "$STATE_FILE" ]; then
  STATE_TMP=$(mktemp)

  # emit_skills_block: print the fresh ### Skills block (called from awk)
  # Uses individual -v args to avoid multiline string issues in awk
  _AWK_SKILLS_EMIT='
    function emit_skills(inst, sugg, det, fs) {
      print "### Skills"
      print "**Installed:** " inst
      print "**Suggested:** " sugg
      print "**Stack detected:** " det
      print "**Registry available:** " fs
    }
  '

  if grep -q '### Skills' "$STATE_FILE"; then
    # Replace existing ### Skills section
    awk -v inst="$INSTALLED" -v sugg="$SUGGESTED" -v det="$DETECTED" -v fs="$FIND_SKILLS" \
      "$_AWK_SKILLS_EMIT"'
      /^### Skills/ { replacing=1; emit_skills(inst, sugg, det, fs); next }
      replacing && /^###[# ]/ { replacing=0 }
      replacing && /^## / { replacing=0 }
      !replacing { print }
    ' "$STATE_FILE" > "$STATE_TMP"
    mv "$STATE_TMP" "$STATE_FILE"
  elif grep -q '## Decisions' "$STATE_FILE" || grep -q '## Key Decisions' "$STATE_FILE"; then
    # Inject ### Skills at end of Decisions section
    awk -v inst="$INSTALLED" -v sugg="$SUGGESTED" -v det="$DETECTED" -v fs="$FIND_SKILLS" \
      "$_AWK_SKILLS_EMIT"'
      BEGIN { injected=0; in_decisions=0 }
      /^## (Key )?Decisions/ { in_decisions=1; print; next }
      in_decisions && /^## / {
        if (!injected) {
          print ""
          emit_skills(inst, sugg, det, fs)
          print ""
          injected=1
        }
        in_decisions=0
        print
        next
      }
      { print }
      END {
        if (in_decisions && !injected) {
          print ""
          emit_skills(inst, sugg, det, fs)
        }
      }
    ' "$STATE_FILE" > "$STATE_TMP"
    mv "$STATE_TMP" "$STATE_FILE"
  fi
  # If neither ### Skills nor ## Decisions: no-op
fi

# --- Update CLAUDE.md ---
CLAUDE_FILE="$PROJECT_DIR/CLAUDE.md"

if [ -f "$CLAUDE_FILE" ] && grep -q '## Installed Skills' "$CLAUDE_FILE"; then
  CLAUDE_TMP=$(mktemp)

  # Build skill name list for CLAUDE.md
  if [ "$INSTALLED" = "None detected" ]; then
    CLAUDE_SKILLS="_(No skills installed)_"
  else
    CLAUDE_SKILLS="$INSTALLED"
  fi

  awk -v skills="$CLAUDE_SKILLS" '
    /^## Installed Skills/ { print; print ""; print skills; replacing=1; next }
    replacing && /^## / { replacing=0 }
    !replacing { print }
  ' "$CLAUDE_FILE" > "$CLAUDE_TMP"
  mv "$CLAUDE_TMP" "$CLAUDE_FILE"
fi

# --- Summary output ---
INSTALLED_COUNT=$(echo "$STACK_JSON" | jq '[.installed.global[], .installed.project[], .installed.agents[]] | unique | length')
echo "skills_synced=true"
echo "installed_count=${INSTALLED_COUNT}"
