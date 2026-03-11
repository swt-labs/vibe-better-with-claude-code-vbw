#!/usr/bin/env bash
# organize-wave-structure.sh — Organize flat plan files into wave subfolders with P-prefix naming.
#
# Usage: bash organize-wave-structure.sh <phase-dir>
#
# Reads flat {MM}-PLAN.md files written by Lead, parses `wave:` from YAML frontmatter,
# creates P{NN}-{WW}-wave/ subfolders, and moves plans + summaries into them with
# P-prefix naming: P{NN}-W{WW}-{MM}-PLAN.md, P{NN}-W{WW}-{MM}-SUMMARY.md.
#
# Also renames phase-root files to P-prefix:
#   {NN}-CONTEXT.md    → P{NN}-CONTEXT.md
#   {NN}-RESEARCH.md   → P{NN}-RESEARCH.md
#   {NN}-VERIFICATION.md → P{NN}-VERIFICATION.md
#   {NN}-UAT.md        → P{NN}-UAT.md
#
# Idempotent: detects already-organized files and skips. Exit 0 always (best-effort).

set -u

PHASE_DIR="${1:-}"
if [ -z "$PHASE_DIR" ] || [ ! -d "$PHASE_DIR" ]; then
  case "$PHASE_DIR" in
    *\{*\}*) echo "organize-wave-structure: skipped — path looks like unexpanded placeholder: $PHASE_DIR" >&2 ;;
  esac
  exit 0
fi

PHASE_DIR="${PHASE_DIR%/}"

# Extract phase number (NN) from directory name like "03-slug"
PHASE_BASENAME=$(basename "$PHASE_DIR")
PHASE_NUM=$(echo "$PHASE_BASENAME" | sed 's/^\([0-9][0-9]*\).*/\1/')
if [ -z "$PHASE_NUM" ]; then
  echo "organize-wave-structure: cannot extract phase number from $PHASE_BASENAME" >&2
  exit 0
fi
# Zero-pad to 2 digits
PHASE_NUM=$(printf '%02d' "$((10#$PHASE_NUM))")

# --- Phase-root P-prefix renaming ---

rename_if_needed() {
  local old="$1" new="$2"
  if [ -f "$old" ] && [ ! -f "$new" ]; then
    mv "$old" "$new"
    echo "renamed: $(basename "$old") -> $(basename "$new")"
  fi
}

rename_if_needed "$PHASE_DIR/${PHASE_NUM}-CONTEXT.md" "$PHASE_DIR/P${PHASE_NUM}-CONTEXT.md"
rename_if_needed "$PHASE_DIR/${PHASE_NUM}-RESEARCH.md" "$PHASE_DIR/P${PHASE_NUM}-RESEARCH.md"
rename_if_needed "$PHASE_DIR/${PHASE_NUM}-VERIFICATION.md" "$PHASE_DIR/P${PHASE_NUM}-VERIFICATION.md"
rename_if_needed "$PHASE_DIR/${PHASE_NUM}-UAT.md" "$PHASE_DIR/P${PHASE_NUM}-UAT.md"

# --- Parse wave frontmatter from flat plan files ---

# Extract wave number from YAML frontmatter.
# Returns wave number or empty string if not found.
extract_wave() {
  local file="$1"
  awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^wave[[:space:]]*:/ {
      gsub(/^wave[[:space:]]*:[[:space:]]*/, "")
      gsub(/[[:space:]]*$/, "")
      gsub(/"/, "")
      print
      exit
    }
  ' "$file"
}

# Collect flat plan files (not already in wave dirs) and parse wave/plan data.
# Uses indexed arrays for Bash 3.2 compatibility (no associative arrays).
# Only processes {MM}-PLAN.md (single-number prefix from Lead).
# Skips {NN}-{MM}-PLAN.md (two-number prefix = remediation plans).
plan_files=()
plan_waves=()
plan_nums=()

for f in "$PHASE_DIR"/[0-9]*-PLAN.md; do
  [ -f "$f" ] || continue
  [ ! -L "$f" ] || continue

  bn=$(basename "$f")
  plan_mm=""
  # Only handle {MM}-PLAN.md (single number prefix from Lead agent)
  if echo "$bn" | grep -qE '^[0-9]+-PLAN\.md$'; then
    plan_mm=$(echo "$bn" | sed 's/^\([0-9]*\)-PLAN\.md$/\1/')
  else
    # Skip {NN}-{MM}-PLAN.md patterns (remediation plans)
    continue
  fi
  [ -z "$plan_mm" ] && continue
  plan_mm=$(printf '%02d' "$((10#$plan_mm))")

  wave=$(extract_wave "$f")
  if [ -z "$wave" ]; then
    wave="1"
  fi
  # Validate wave is numeric (F9: non-numeric values like "TBD" cause arithmetic errors)
  if ! echo "$wave" | grep -qE '^[0-9]+$'; then
    echo "organize-wave-structure: WARNING: non-numeric wave value '$wave' in $(basename "$f"), defaulting to 1" >&2
    wave="1"
  fi
  wave=$(printf '%02d' "$((10#$wave))")

  plan_files+=("$f")
  plan_waves+=("$wave")
  plan_nums+=("$plan_mm")
done

# If no flat plan files, nothing to organize
if [ ${#plan_files[@]} -eq 0 ]; then
  exit 0
fi

# --- Create wave directories and move files ---

idx=0
for f in "${plan_files[@]}"; do
  wave="${plan_waves[$idx]}"
  plan_mm="${plan_nums[$idx]}"
  idx=$((idx + 1))

  wave_dir="$PHASE_DIR/P${PHASE_NUM}-${wave}-wave"
  mkdir -p "$wave_dir"

  # Move plan
  target_plan="$wave_dir/P${PHASE_NUM}-W${wave}-${plan_mm}-PLAN.md"
  if [ ! -f "$target_plan" ]; then
    if ! mv "$f" "$target_plan" 2>/dev/null; then
      echo "organize-wave-structure: WARNING: failed to move $(basename "$f") to $wave_dir/" >&2
    else
      echo "organized: $(basename "$f") -> P${PHASE_NUM}-${wave}-wave/$(basename "$target_plan")"
    fi
  fi

  # Move matching summary if it exists
  old_summary="$PHASE_DIR/${plan_mm}-SUMMARY.md"
  old_summary2="$PHASE_DIR/${PHASE_NUM}-${plan_mm}-SUMMARY.md"
  target_summary="$wave_dir/P${PHASE_NUM}-W${wave}-${plan_mm}-SUMMARY.md"

  if [ -f "$old_summary" ] && [ ! -f "$target_summary" ]; then
    if ! mv "$old_summary" "$target_summary" 2>/dev/null; then
      echo "organize-wave-structure: WARNING: failed to move $(basename "$old_summary")" >&2
    else
      echo "organized: $(basename "$old_summary") -> P${PHASE_NUM}-${wave}-wave/$(basename "$target_summary")"
    fi
  elif [ -f "$old_summary2" ] && [ ! -f "$target_summary" ]; then
    if ! mv "$old_summary2" "$target_summary" 2>/dev/null; then
      echo "organize-wave-structure: WARNING: failed to move $(basename "$old_summary2")" >&2
    else
      echo "organized: $(basename "$old_summary2") -> P${PHASE_NUM}-${wave}-wave/$(basename "$target_summary")"
    fi
  fi
done

# --- Move wave-level verification files ---
# Check for existing per-wave verification files that might need renaming.
# Current format: {NN}-VERIFICATION-P{MM}[-P{MM2}].md → wave dir P{NN}-W{WW}-VERIFICATION.md
# This is handled when verification files are written, not retroactively.

exit 0
