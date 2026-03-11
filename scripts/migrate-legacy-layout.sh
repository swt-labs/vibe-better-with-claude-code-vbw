#!/usr/bin/env bash
# migrate-legacy-layout.sh — Migrate flat phase directory to wave + round subfolder layout (v2).
#
# Usage: bash migrate-legacy-layout.sh <phase-dir>
#
# Migrates existing projects from flat layout to the v2 structure:
#   1. Calls organize-wave-structure.sh for initial plan → wave dir organization
#   2. Detects flat remediation artifacts and moves into remediation/P{NN}-{RR}-round/ dirs
#   3. Generates remediation/.uat-remediation-stage with stage + round fields
#   4. Removes deprecated files (SOURCE-UAT copies, etc.)
#
# Idempotent: creates .vbw-planning/.layout-v2-migrated marker. Safe to run multiple times.

set -eo pipefail

PHASE_DIR="${1:-}"
if [ -z "$PHASE_DIR" ] || [ ! -d "$PHASE_DIR" ]; then
  echo "Usage: migrate-legacy-layout.sh <phase-dir>" >&2
  exit 1
fi

PHASE_DIR="${PHASE_DIR%/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Extract phase number
PHASE_BASENAME=$(basename "$PHASE_DIR")
PHASE_NUM=$(echo "$PHASE_BASENAME" | sed 's/^\([0-9][0-9]*\).*/\1/')
if [ -z "$PHASE_NUM" ]; then
  echo "migrate-legacy-layout: cannot extract phase number from $PHASE_BASENAME" >&2
  exit 1
fi
PHASE_NUM=$(printf '%02d' "$((10#$PHASE_NUM))")

# Find .vbw-planning root for marker file
VBW_ROOT=""
case "$PHASE_DIR" in
  */.vbw-planning/phases/*)
    VBW_ROOT=$(echo "$PHASE_DIR" | sed 's|\(.*/.vbw-planning\)/.*|\1|')
    ;;
esac

# Check migration marker
if [ -n "$VBW_ROOT" ] && [ -f "$VBW_ROOT/.layout-v2-migrated" ]; then
  # Already migrated — check if this specific phase was included
  if grep -q "$(basename "$PHASE_DIR")" "$VBW_ROOT/.layout-v2-migrated" 2>/dev/null; then
    exit 0
  fi
fi

echo "migrate-legacy-layout: migrating $(basename "$PHASE_DIR")..."

# --- Step 1: Detect and migrate flat remediation artifacts FIRST ---
# Must happen before organize-wave-structure.sh so remediation {NN}-{MM}-PLAN.md
# files don't get incorrectly treated as initial plans.

OLD_STAGE_FILE="$PHASE_DIR/.uat-remediation-stage"
OLD_STAGE=""
if [ -f "$OLD_STAGE_FILE" ]; then
  OLD_STAGE=$(cat "$OLD_STAGE_FILE" | tr -d '[:space:]')
fi

has_remediation=false

# Check for UAT-round files (definitive sign of remediation)
uat_round_files=()
for f in "$PHASE_DIR"/${PHASE_NUM}-UAT-round-*.md "$PHASE_DIR"/${PHASE_NUM}-UAT-round*.md; do
  [ -f "$f" ] || continue
  uat_round_files+=("$f")
done

if [ ${#uat_round_files[@]} -gt 0 ] || [ -f "$OLD_STAGE_FILE" ]; then
  has_remediation=true
fi

# If already has remediation/ dir with round subdirs, skip remediation migration
if [ -d "$PHASE_DIR/remediation" ]; then
  existing_rounds=$(find "$PHASE_DIR/remediation" -maxdepth 1 -type d -name 'P*-round' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$existing_rounds" -gt 0 ]; then
    has_remediation=false
  fi
fi

if [ "$has_remediation" = true ]; then
  echo "migrate-legacy-layout: detected remediation artifacts, organizing..."

  # Determine number of remediation rounds from UAT-round files
  max_round=0
  for f in "${uat_round_files[@]}"; do
    bn=$(basename "$f")
    rr=$(echo "$bn" | sed -n "s/.*UAT-round-*\([0-9][0-9]*\)\.md$/\1/p")
    [ -z "$rr" ] && continue
    rr_num=$((10#$rr))
    if [ "$rr_num" -gt "$max_round" ]; then
      max_round=$rr_num
    fi
  done

  if [ "$max_round" -eq 0 ] && [ -n "$OLD_STAGE" ] && [ "$OLD_STAGE" != "none" ]; then
    max_round=1
  fi

  if [ "$max_round" -gt 0 ]; then
    mkdir -p "$PHASE_DIR/remediation"

    # Count initial plans: only {MM}-PLAN.md (single-number prefix from Lead).
    # Remediation plans are {NN}-{MM}-PLAN.md (two-number prefix).
    initial_plan_count=$(find "$PHASE_DIR" -maxdepth 1 -name '[0-9]*-PLAN.md' ! -name '[0-9]*-[0-9]*-PLAN.md' ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')

    for rr_num in $(seq 1 "$max_round"); do
      rr=$(printf '%02d' "$rr_num")
      round_dir="$PHASE_DIR/remediation/P${PHASE_NUM}-${rr}-round"
      mkdir -p "$round_dir"

      # Compute the plan MM for this round
      plan_mm=$(printf '%02d' $((initial_plan_count + rr_num)))

      # Move remediation research
      old_research="$PHASE_DIR/${PHASE_NUM}-${plan_mm}-RESEARCH.md"
      if [ -f "$old_research" ]; then
        mv "$old_research" "$round_dir/P${PHASE_NUM}-R${rr}-RESEARCH.md"
        echo "migrated: $(basename "$old_research") -> remediation/P${PHASE_NUM}-${rr}-round/P${PHASE_NUM}-R${rr}-RESEARCH.md"
      fi

      # Move remediation plan
      old_plan="$PHASE_DIR/${PHASE_NUM}-${plan_mm}-PLAN.md"
      if [ -f "$old_plan" ]; then
        mv "$old_plan" "$round_dir/P${PHASE_NUM}-R${rr}-PLAN.md"
        echo "migrated: $(basename "$old_plan") -> remediation/P${PHASE_NUM}-${rr}-round/P${PHASE_NUM}-R${rr}-PLAN.md"
      fi

      # Move remediation summary
      old_summary="$PHASE_DIR/${PHASE_NUM}-${plan_mm}-SUMMARY.md"
      if [ -f "$old_summary" ]; then
        mv "$old_summary" "$round_dir/P${PHASE_NUM}-R${rr}-SUMMARY.md"
        echo "migrated: $(basename "$old_summary") -> remediation/P${PHASE_NUM}-${rr}-round/P${PHASE_NUM}-R${rr}-SUMMARY.md"
      fi

      # Move remediation verification
      old_verif="$PHASE_DIR/${PHASE_NUM}-${plan_mm}-VERIFICATION.md"
      if [ -f "$old_verif" ]; then
        mv "$old_verif" "$round_dir/P${PHASE_NUM}-R${rr}-VERIFICATION.md"
        echo "migrated: $(basename "$old_verif") -> remediation/P${PHASE_NUM}-${rr}-round/P${PHASE_NUM}-R${rr}-VERIFICATION.md"
      fi

      # Move UAT-round file
      old_uat=""
      for candidate in "$PHASE_DIR/${PHASE_NUM}-UAT-round-${rr}.md" \
                        "$PHASE_DIR/${PHASE_NUM}-UAT-round-$(printf '%d' "$rr_num").md" \
                        "$PHASE_DIR/${PHASE_NUM}-UAT-round${rr}.md"; do
        if [ -f "$candidate" ]; then
          old_uat="$candidate"
          break
        fi
      done
      if [ -n "$old_uat" ]; then
        mv "$old_uat" "$round_dir/P${PHASE_NUM}-R${rr}-UAT.md"
        echo "migrated: $(basename "$old_uat") -> remediation/P${PHASE_NUM}-${rr}-round/P${PHASE_NUM}-R${rr}-UAT.md"
      fi
    done

    # Move .uat-remediation-stage to remediation/ and add round field
    if [ -f "$OLD_STAGE_FILE" ]; then
      new_stage_file="$PHASE_DIR/remediation/.uat-remediation-stage"
      {
        echo "stage=$OLD_STAGE"
        echo "round=$(printf '%02d' "$max_round")"
      } > "$new_stage_file"
      rm -f "$OLD_STAGE_FILE"
      echo "migrated: .uat-remediation-stage -> remediation/.uat-remediation-stage (stage=$OLD_STAGE round=$(printf '%02d' "$max_round"))"
    fi

    # Remove SOURCE-UAT (initial UAT preserved as P{NN}-UAT.md)
    for src_uat in "$PHASE_DIR/${PHASE_NUM}-SOURCE-UAT.md" "$PHASE_DIR/P${PHASE_NUM}-SOURCE-UAT.md"; do
      if [ -f "$src_uat" ]; then
        rm -f "$src_uat"
        echo "removed: $(basename "$src_uat") (initial UAT preserved as P${PHASE_NUM}-UAT.md)"
      fi
    done
  fi
fi

# --- Step 2: Organize initial plans into wave subfolders ---

ORGANIZE_SCRIPT="$SCRIPT_DIR/organize-wave-structure.sh"
if [ -f "$ORGANIZE_SCRIPT" ]; then
  bash "$ORGANIZE_SCRIPT" "$PHASE_DIR"
fi

# --- Step 3: Record migration marker ---

if [ -n "$VBW_ROOT" ]; then
  echo "$(basename "$PHASE_DIR") migrated $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$VBW_ROOT/.layout-v2-migrated"
fi

echo "migrate-legacy-layout: done"
exit 0
