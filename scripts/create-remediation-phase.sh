#!/usr/bin/env bash
set -euo pipefail

# create-remediation-phase.sh — create an active remediation phase from archived milestone UAT
#
# Usage:
#   create-remediation-phase.sh PLANNING_DIR MILESTONE_PHASE_DIR
#
# Output (stdout):
#   phase=<NN>
#   phase_dir=<path>
#   source_uat=<path|none>

PLANNING_DIR="${1:-}"
MILESTONE_PHASE_DIR="${2:-}"

if [[ -z "$PLANNING_DIR" || -z "$MILESTONE_PHASE_DIR" ]]; then
  echo "Usage: create-remediation-phase.sh PLANNING_DIR MILESTONE_PHASE_DIR" >&2
  exit 1
fi

if [[ ! -d "$PLANNING_DIR" ]]; then
  echo "Error: planning dir not found: $PLANNING_DIR" >&2
  exit 1
fi

if [[ ! -d "$MILESTONE_PHASE_DIR" ]]; then
  echo "Error: milestone phase dir not found: $MILESTONE_PHASE_DIR" >&2
  exit 1
fi

# Idempotency: if this milestone phase already maps to a previously created
# remediation phase dir, return that mapping instead of creating duplicates.
EXISTING_MARKER_FILE="$MILESTONE_PHASE_DIR/.remediated"
if [[ -f "$EXISTING_MARKER_FILE" ]]; then
  EXISTING_TARGET_DIR=$(head -n1 "$EXISTING_MARKER_FILE" 2>/dev/null || true)
  if [[ -n "$EXISTING_TARGET_DIR" && -d "$EXISTING_TARGET_DIR" ]]; then
    EXISTING_PHASE=$(basename "$EXISTING_TARGET_DIR" | sed 's/-.*//')
    EXISTING_SOURCE_UAT=$(ls -1 "$EXISTING_TARGET_DIR"/[0-9]*-SOURCE-UAT.md 2>/dev/null | sort | tail -1 || true)
    if [[ -n "$EXISTING_SOURCE_UAT" && -f "$EXISTING_SOURCE_UAT" ]]; then
      EXISTING_SOURCE_UAT_OUT="$EXISTING_SOURCE_UAT"
    else
      EXISTING_SOURCE_UAT_OUT="none"
    fi
    echo "phase=${EXISTING_PHASE}"
    echo "phase_dir=${EXISTING_TARGET_DIR}"
    echo "source_uat=${EXISTING_SOURCE_UAT_OUT}"
    exit 0
  fi
fi

PHASES_DIR="$PLANNING_DIR/phases"
mkdir -p "$PHASES_DIR"

# Determine next phase number from existing active phases.
MAX_PHASE=0
for d in "$PHASES_DIR"/*/; do
  [[ -d "$d" ]] || continue
  base=$(basename "$d")
  num=$(echo "$base" | sed 's/[^0-9].*//')
  [[ -n "$num" ]] || continue
  # Force base-10 to avoid octal interpretation for leading zeroes.
  n=$((10#$num))
  if [[ "$n" -gt "$MAX_PHASE" ]]; then
    MAX_PHASE="$n"
  fi
done

NEXT_PHASE=$((MAX_PHASE + 1))
NEXT_PHASE_PADDED=$(printf "%02d" "$NEXT_PHASE")

SOURCE_PHASE_SLUG=$(basename "$MILESTONE_PHASE_DIR" | sed 's/^[0-9]*-//')
SOURCE_MILESTONE_SLUG=$(basename "$(dirname "$(dirname "$MILESTONE_PHASE_DIR")")")
RAW_SLUG="remediate-${SOURCE_MILESTONE_SLUG}-${SOURCE_PHASE_SLUG}"
PHASE_SLUG=$(echo "$RAW_SLUG" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')

if [ ${#PHASE_SLUG} -gt 60 ]; then
  PHASE_SLUG_TRUNC=$(printf '%s' "$PHASE_SLUG" | cut -c1-60 | sed 's/-$//')
  PHASE_SLUG_WORD_SAFE=$(printf '%s' "$PHASE_SLUG_TRUNC" | sed 's/-[^-]*$//')
  if [[ -n "$PHASE_SLUG_WORD_SAFE" && "$PHASE_SLUG_WORD_SAFE" != "$PHASE_SLUG_TRUNC" ]]; then
    PHASE_SLUG="$PHASE_SLUG_WORD_SAFE"
  else
    PHASE_SLUG="$PHASE_SLUG_TRUNC"
  fi
fi

TARGET_PHASE_DIR="$PHASES_DIR/${NEXT_PHASE_PADDED}-${PHASE_SLUG}"
mkdir -p "$TARGET_PHASE_DIR"

SOURCE_UAT=$(ls -1 "$MILESTONE_PHASE_DIR"/[0-9]*-UAT.md 2>/dev/null | sort | tail -1 || true)

cat > "$TARGET_PHASE_DIR/${NEXT_PHASE_PADDED}-CONTEXT.md" <<EOF
---
phase: ${NEXT_PHASE_PADDED}
title: Milestone UAT remediation
source_milestone: ${SOURCE_MILESTONE_SLUG}
source_phase: $(basename "$MILESTONE_PHASE_DIR")
---

This phase remediates unresolved UAT issues from archived milestone \`${SOURCE_MILESTONE_SLUG}\` (phase \`$(basename "$MILESTONE_PHASE_DIR")\`).

Use the attached source UAT report to drive plan creation and execution.
EOF

if [[ -n "$SOURCE_UAT" && -f "$SOURCE_UAT" ]]; then
  cp "$SOURCE_UAT" "$TARGET_PHASE_DIR/${NEXT_PHASE_PADDED}-SOURCE-UAT.md"
  SOURCE_UAT_OUT="$TARGET_PHASE_DIR/${NEXT_PHASE_PADDED}-SOURCE-UAT.md"
else
  SOURCE_UAT_OUT="none"
fi

# Mark the source milestone phase as remediated so phase-detect.sh
# won't trigger repeated milestone UAT recovery for the same issues.
echo "${TARGET_PHASE_DIR}" > "$MILESTONE_PHASE_DIR/.remediated"

echo "phase=${NEXT_PHASE_PADDED}"
echo "phase_dir=${TARGET_PHASE_DIR}"
echo "source_uat=${SOURCE_UAT_OUT}"

exit 0
