#!/usr/bin/env bash
# compile-rolling-summary.sh — Roll up completed phase SUMMARY.md files into a condensed digest.
# Usage: compile-rolling-summary.sh [phases-dir] [output-path]
# Fail-open: uses set -u but NOT set -e. Exits 0 on any error.

set -u

PHASES_DIR="${1:-.vbw-planning/phases}"
OUTPUT_PATH="${2:-.vbw-planning/ROLLING-CONTEXT.md}"

# ── T1: Discover SUMMARY.md files ─────────────────────────────────────────────

SUMMARY_FILES=""

if [ -d "$PHASES_DIR" ]; then
  # Sort by path for phase order
  while IFS= read -r f; do
    # Extract status from YAML frontmatter (between first two --- delimiters)
    STATUS=$(sed -n '/^---$/,/^---$/p' "$f" 2>/dev/null | grep '^status:' | head -1 | sed 's/^status:[[:space:]]*//' | tr -d '"' || true)
    if [ "$STATUS" = "complete" ] || [ "$STATUS" = "completed" ]; then
      SUMMARY_FILES="${SUMMARY_FILES}${f}
"
    fi
  done < <(find "$PHASES_DIR" -maxdepth 4 -name "*-SUMMARY.md" 2>/dev/null | sort)
fi

# Remove trailing newline
SUMMARY_FILES="${SUMMARY_FILES%
}"

# Count total SUMMARY.md files (including incomplete ones) to detect single-phase no-op
TOTAL_COUNT=0
if [ -d "$PHASES_DIR" ]; then
  TOTAL_COUNT=$(find "$PHASES_DIR" -maxdepth 4 -name "*-SUMMARY.md" 2>/dev/null | wc -l | tr -d ' ')
fi

# ── Single-phase no-op ─────────────────────────────────────────────────────────
# If only one SUMMARY.md total (regardless of status), no "prior" context to roll up.
if [ "$TOTAL_COUNT" -le 1 ]; then
  TMPFILE=$(mktemp 2>/dev/null) || TMPFILE="${OUTPUT_PATH}.tmp"
  {
    echo "# Rolling Context"
    echo "No prior completed phases."
  } > "$TMPFILE" || { echo "WARNING: write failed" >&2; exit 0; }
  mv "$TMPFILE" "$OUTPUT_PATH" 2>/dev/null || { echo "WARNING: mv failed" >&2; exit 0; }
  echo "$OUTPUT_PATH"
  exit 0
fi

# ── Zero accepted (completed) paths ───────────────────────────────────────────
if [ -z "$SUMMARY_FILES" ]; then
  TMPFILE=$(mktemp 2>/dev/null) || TMPFILE="${OUTPUT_PATH}.tmp"
  {
    echo "# Rolling Context"
    echo "No prior completed phases."
  } > "$TMPFILE" || { echo "WARNING: write failed" >&2; exit 0; }
  mv "$TMPFILE" "$OUTPUT_PATH" 2>/dev/null || { echo "WARNING: mv failed" >&2; exit 0; }
  echo "$OUTPUT_PATH"
  exit 0
fi

# ── T2: Extract frontmatter and body from each completed SUMMARY.md ────────────

CONTEXT_LINES=""
ACCEPTED_COUNT=0

while IFS= read -r SUMMARY_FILE; do
  [ -z "$SUMMARY_FILE" ] && continue
  [ -f "$SUMMARY_FILE" ] || continue

  # Extract frontmatter fields (wrapped in subshell with || true for malformed files)
  FM_PHASE=$(sed -n '/^---$/,/^---$/p' "$SUMMARY_FILE" 2>/dev/null | grep '^phase:' | head -1 | sed 's/^phase:[[:space:]]*//' | tr -d '"' || true)
  FM_PLAN=$(sed -n '/^---$/,/^---$/p' "$SUMMARY_FILE" 2>/dev/null | grep '^plan:' | head -1 | sed 's/^plan:[[:space:]]*//' | tr -d '"' || true)
  FM_TITLE=$(sed -n '/^---$/,/^---$/p' "$SUMMARY_FILE" 2>/dev/null | grep '^title:' | head -1 | sed 's/^title:[[:space:]]*//' | tr -d '"' || true)
  FM_DEVIATIONS=$(sed -n '/^---$/,/^---$/p' "$SUMMARY_FILE" 2>/dev/null | grep '^deviations:' | head -1 | sed 's/^deviations:[[:space:]]*//' | tr -d '"' || true)
  FM_COMMITS=$(sed -n '/^---$/,/^---$/p' "$SUMMARY_FILE" 2>/dev/null | grep '^commit_hashes:' | head -1 | sed 's/^commit_hashes:[[:space:]]*//' | tr -d '[]"' | cut -d',' -f1 | tr -d ' ' || true)

  # Defaults
  FM_PHASE="${FM_PHASE:-?}"
  FM_PLAN="${FM_PLAN:-?}"
  FM_TITLE="${FM_TITLE:-Untitled}"
  FM_DEVIATIONS="${FM_DEVIATIONS:-0}"
  FM_COMMITS="${FM_COMMITS:-none}"

  # Extract ## What Was Built — first 3 non-empty lines after heading
  WHAT_BUILT=$(awk '/^## What Was Built/{found=1; count=0; next} found && /^## /{exit} found && NF>0{print; count++; if(count>=3) exit}' "$SUMMARY_FILE" 2>/dev/null | head -3 || true)
  BUILT_LINE1=$(echo "$WHAT_BUILT" | sed -n '1p' | sed 's/^[[:space:]]*//' | sed 's/^[-*] //' || true)
  [ -z "$BUILT_LINE1" ] && BUILT_LINE1="(no details)"

  # Extract ## Files Modified — lines starting with "- " (up to 5)
  FILES_LIST=$(awk '/^## Files Modified/{found=1; next} found && /^## /{exit} found && /^- /{print}' "$SUMMARY_FILE" 2>/dev/null | head -5 | sed 's/^- //' | tr '\n' ',' | sed 's/,$//' || true)
  [ -z "$FILES_LIST" ] && FILES_LIST="(none listed)"

  # Build entry block
  ENTRY="## Phase ${FM_PHASE} Plan ${FM_PLAN}: ${FM_TITLE}
Built: ${BUILT_LINE1}
Files: ${FILES_LIST}
Deviations: ${FM_DEVIATIONS}
Commit: ${FM_COMMITS}"

  if [ -n "$CONTEXT_LINES" ]; then
    CONTEXT_LINES="${CONTEXT_LINES}
${ENTRY}"
  else
    CONTEXT_LINES="$ENTRY"
  fi

  ACCEPTED_COUNT=$((ACCEPTED_COUNT + 1))
done <<EOF
$SUMMARY_FILES
EOF

# ── T3: Assemble and write output with 200-line cap ───────────────────────────

TMPFILE=$(mktemp 2>/dev/null) || TMPFILE="${OUTPUT_PATH}.tmp"

{
  echo "# Rolling Context"
  echo "Compiled from ${ACCEPTED_COUNT} completed phase plan(s). Cap: 200 lines."
  echo ""
  printf '%s\n' "$CONTEXT_LINES"
} | head -200 > "$TMPFILE" 2>/dev/null || { echo "WARNING: write to tmpfile failed" >&2; exit 0; }

mv "$TMPFILE" "$OUTPUT_PATH" 2>/dev/null || { echo "WARNING: mv to output failed" >&2; exit 0; }

echo "$OUTPUT_PATH"
exit 0
