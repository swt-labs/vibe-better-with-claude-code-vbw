#!/bin/bash
set -u
# normalize-plan-filenames.sh — Rename type-first plan artifacts to number-first format
#
# Usage: bash normalize-plan-filenames.sh <phase-dir>
#
# Renames:
#   PLAN-{NN}.md         → {NN}-PLAN.md
#   PLAN-{NN}-SUMMARY.md → {NN}-SUMMARY.md
#   SUMMARY-{NN}.md      → {NN}-SUMMARY.md
#   CONTEXT-{NN}.md      → {NN}-CONTEXT.md
#
# Skips if target already exists. Exit 0 always (best-effort).

PHASE_DIR="${1:-}"
if [ -z "$PHASE_DIR" ] || [ ! -d "$PHASE_DIR" ]; then
  exit 0
fi

# Strip trailing slash for consistent path joining
PHASE_DIR="${PHASE_DIR%/}"

# Pattern: PLAN-NN.md → NN-PLAN.md
for f in "$PHASE_DIR"/PLAN-[0-9]*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  # Extract number: PLAN-01.md → 01, PLAN-02-SUMMARY.md → 02
  NUM=$(echo "$BASENAME" | sed 's/^PLAN-\([0-9]*\).*/\1/')
  [ -z "$NUM" ] && continue
  # Zero-pad to 2 digits
  NUM=$(printf "%02d" "$((10#$NUM))")

  if echo "$BASENAME" | grep -q '^PLAN-[0-9]*-SUMMARY\.md$'; then
    # PLAN-NN-SUMMARY.md → NN-SUMMARY.md
    TARGET="$PHASE_DIR/${NUM}-SUMMARY.md"
  else
    # PLAN-NN.md → NN-PLAN.md
    TARGET="$PHASE_DIR/${NUM}-PLAN.md"
  fi

  if [ -f "$TARGET" ]; then
    echo "skipped: $BASENAME (target $(basename "$TARGET") already exists)" >&2
    continue
  fi
  mv "$f" "$TARGET"
  echo "renamed: $BASENAME -> $(basename "$TARGET")"
done

# Pattern: SUMMARY-NN.md → NN-SUMMARY.md
for f in "$PHASE_DIR"/SUMMARY-[0-9]*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  NUM=$(echo "$BASENAME" | sed 's/^SUMMARY-\([0-9]*\).*/\1/')
  [ -z "$NUM" ] && continue
  NUM=$(printf "%02d" "$((10#$NUM))")
  TARGET="$PHASE_DIR/${NUM}-SUMMARY.md"
  if [ -f "$TARGET" ]; then
    echo "skipped: $BASENAME (target $(basename "$TARGET") already exists)" >&2
    continue
  fi
  mv "$f" "$TARGET"
  echo "renamed: $BASENAME -> $(basename "$TARGET")"
done

# Pattern: CONTEXT-NN.md → NN-CONTEXT.md
for f in "$PHASE_DIR"/CONTEXT-[0-9]*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  NUM=$(echo "$BASENAME" | sed 's/^CONTEXT-\([0-9]*\).*/\1/')
  [ -z "$NUM" ] && continue
  NUM=$(printf "%02d" "$((10#$NUM))")
  TARGET="$PHASE_DIR/${NUM}-CONTEXT.md"
  if [ -f "$TARGET" ]; then
    echo "skipped: $BASENAME (target $(basename "$TARGET") already exists)" >&2
    continue
  fi
  mv "$f" "$TARGET"
  echo "renamed: $BASENAME -> $(basename "$TARGET")"
done

exit 0
