#!/bin/bash
set -u
# normalize-plan-filenames.sh — Rename type-first plan artifacts to canonical format
#
# Usage: bash normalize-plan-filenames.sh <phase-or-remediation-round-dir>
#
# Phase directories rename:
#   PLAN-{NN}.md          → {NN}-PLAN.md
#   PLAN-{NN}-SUMMARY.md  → {NN}-SUMMARY.md
#   SUMMARY-{NN}.md       → {NN}-SUMMARY.md
#   CONTEXT-{NN}.md       → {NN}-CONTEXT.md
# Remediation round directories rename:
#   PLAN-R{RR}.md         → R{RR}-PLAN.md
#   PLAN-{RR}.md          → R{RR}-PLAN.md
#
# Skips if target already exists. Exit 0 always (best-effort).

PHASE_DIR="${1:-}"
if [ -z "$PHASE_DIR" ] || [ ! -d "$PHASE_DIR" ]; then
  # Warn if it looks like an unexpanded template placeholder (e.g., "{phase_dir}")
  case "$PHASE_DIR" in
    *\{*\}*) echo "normalize-plan-filenames: skipped — path looks like unexpanded placeholder: $PHASE_DIR" >&2 ;;
  esac
  exit 0
fi

# Strip trailing slash for consistent path joining
PHASE_DIR="${PHASE_DIR%/}"
PHASE_DIR_BASE=$(basename "$PHASE_DIR")

# Remediation round directories use round-scoped names (R01-PLAN.md), not
# phase-scoped names (01-PLAN.md). The containing round directory is the source
# of truth for the canonical round token so QA/UAT/legacy round paths all share
# the same normalization contract.
ROUND_PLAN_TOKEN=""
case "$PHASE_DIR" in
  */remediation/qa/round-[0-9]*|remediation/qa/round-[0-9]*|*/remediation/uat/round-[0-9]*|remediation/uat/round-[0-9]*|*/remediation/round-[0-9]*|remediation/round-[0-9]*)
    ROUND_RAW=$(echo "$PHASE_DIR_BASE" | sed -n 's/^round-\([0-9][0-9]*\)$/\1/p')
    if [ -n "$ROUND_RAW" ]; then
      ROUND_PLAN_TOKEN=$(printf "R%02d" "$((10#$ROUND_RAW))")
    fi
    ;;
esac

if [ -n "$ROUND_PLAN_TOKEN" ]; then
  # Pattern: PLAN-RNN.md or PLAN-NN.md → RNN-PLAN.md, where RNN is derived
  # from the containing remediation round directory.
  for f in "$PHASE_DIR"/[Pp][Ll][Aa][Nn]-[Rr][0-9]*.[mM][dD] "$PHASE_DIR"/[Pp][Ll][Aa][Nn]-[0-9]*.[mM][dD]; do
    [ -f "$f" ] || continue
    [ ! -L "$f" ] || continue  # skip symlinks
    BASENAME=$(basename "$f")
    if ! echo "$BASENAME" | grep -qiE '^PLAN-R?[0-9]+\.(md|MD)$'; then
      echo "skipped: $BASENAME (unknown remediation round plan form)" >&2
      continue
    fi

    TARGET="$PHASE_DIR/${ROUND_PLAN_TOKEN}-PLAN.md"
    if [ -f "$TARGET" ]; then
      echo "skipped: $BASENAME (target $(basename "$TARGET") already exists)" >&2
      continue
    fi
    mv "$f" "$TARGET"
    echo "renamed: $BASENAME -> $(basename "$TARGET")"
  done

  exit 0
fi

# Pattern: PLAN-NN.md → NN-PLAN.md (case-insensitive prefix and extension)
for f in "$PHASE_DIR"/[Pp][Ll][Aa][Nn]-[0-9]*.[mM][dD]; do
  [ -f "$f" ] || continue
  [ ! -L "$f" ] || continue  # skip symlinks
  BASENAME=$(basename "$f")
  # Only handle known forms: PLAN-NN.md, PLAN-NN-SUMMARY.md, PLAN-NN-CONTEXT.md
  if ! echo "$BASENAME" | grep -qiE '^PLAN-[0-9]+\.(md|MD)$|^PLAN-[0-9]+-(SUMMARY|CONTEXT)\.(md|MD)$'; then
    echo "skipped: $BASENAME (unknown compound form)" >&2
    continue
  fi
  # Extract number: PLAN-01.md → 01, PLAN-02-SUMMARY.md → 02 (case-insensitive)
  NUM=$(echo "$BASENAME" | sed 's/^[Pp][Ll][Aa][Nn]-\([0-9]*\).*/\1/')
  [ -z "$NUM" ] && continue
  # Zero-pad to 2 digits
  NUM=$(printf "%02d" "$((10#$NUM))")

  if echo "$BASENAME" | grep -qi '^[Pp][Ll][Aa][Nn]-[0-9]*-[Ss][Uu][Mm][Mm][Aa][Rr][Yy]\.[mM][dD]$'; then
    # PLAN-NN-SUMMARY.md → NN-SUMMARY.md
    TARGET="$PHASE_DIR/${NUM}-SUMMARY.md"
  elif echo "$BASENAME" | grep -qi '^[Pp][Ll][Aa][Nn]-[0-9]*-[Cc][Oo][Nn][Tt][Ee][Xx][Tt]\.[mM][dD]$'; then
    # PLAN-NN-CONTEXT.md → NN-CONTEXT.md
    TARGET="$PHASE_DIR/${NUM}-CONTEXT.md"
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

# Pattern: SUMMARY-NN.md → NN-SUMMARY.md (case-insensitive prefix and extension)
for f in "$PHASE_DIR"/[Ss][Uu][Mm][Mm][Aa][Rr][Yy]-[0-9]*.[mM][dD]; do
  [ -f "$f" ] || continue
  [ ! -L "$f" ] || continue  # skip symlinks
  BASENAME=$(basename "$f")
  # Only handle exact SUMMARY-NN.md (no compound suffixes)
  if ! echo "$BASENAME" | grep -qiE '^SUMMARY-[0-9]+\.(md|MD)$'; then
    echo "skipped: $BASENAME (unknown compound form)" >&2
    continue
  fi
  NUM=$(echo "$BASENAME" | sed 's/^[Ss][Uu][Mm][Mm][Aa][Rr][Yy]-\([0-9]*\).*/\1/')
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

# Pattern: CONTEXT-NN.md → NN-CONTEXT.md (case-insensitive prefix and extension)
for f in "$PHASE_DIR"/[Cc][Oo][Nn][Tt][Ee][Xx][Tt]-[0-9]*.[mM][dD]; do
  [ -f "$f" ] || continue
  [ ! -L "$f" ] || continue  # skip symlinks
  BASENAME=$(basename "$f")
  # Only handle exact CONTEXT-NN.md (no compound suffixes)
  if ! echo "$BASENAME" | grep -qiE '^CONTEXT-[0-9]+\.(md|MD)$'; then
    echo "skipped: $BASENAME (unknown compound form)" >&2
    continue
  fi
  NUM=$(echo "$BASENAME" | sed 's/^[Cc][Oo][Nn][Tt][Ee][Xx][Tt]-\([0-9]*\).*/\1/')
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

# --- Brownfield migration: {NN}-01-RESEARCH.md → {NN}-RESEARCH.md ---
# Plan mode previously created phase-wide research with plan-specific naming.
# Migrate {NN}-01-RESEARCH.md to phase-wide {NN}-RESEARCH.md when:
#   - {NN}-01-RESEARCH.md exists
#   - {NN}-RESEARCH.md does NOT exist
#   - No other per-plan research ({NN}-02-RESEARCH.md, etc.) exists
PHASE_NUM_NRM=$(echo "$PHASE_DIR_BASE" | sed 's/^\([0-9]*\).*/\1/')
if [ -n "$PHASE_NUM_NRM" ]; then
  PHASE_NUM_NRM=$(printf "%02d" "$((10#$PHASE_NUM_NRM))")
  OLD_RESEARCH="$PHASE_DIR/${PHASE_NUM_NRM}-01-RESEARCH.md"
  NEW_RESEARCH="$PHASE_DIR/${PHASE_NUM_NRM}-RESEARCH.md"
  if [ -f "$OLD_RESEARCH" ] && [ ! -f "$NEW_RESEARCH" ]; then
    # Check that no other per-plan research files exist (02+)
    OTHER_RESEARCH=$(find "$PHASE_DIR" -maxdepth 1 -name "${PHASE_NUM_NRM}-[0-9][0-9]*-RESEARCH.md" ! -name "${PHASE_NUM_NRM}-01-RESEARCH.md" 2>/dev/null | head -1)
    if [ -z "$OTHER_RESEARCH" ]; then
      mv "$OLD_RESEARCH" "$NEW_RESEARCH"
      echo "renamed: $(basename "$OLD_RESEARCH") -> $(basename "$NEW_RESEARCH")"
    fi
  fi
fi

exit 0
