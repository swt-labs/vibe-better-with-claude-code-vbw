#!/usr/bin/env bash
# prepare-reverification.sh — Advance remediation state for re-verification.
#
# Usage: prepare-reverification.sh <phase-dir>
#
# Round-dir layout: Leaves the phase-root UAT in place (it's the permanent
# historical record) and advances state to verify. verify.md writes
# R{RR}-UAT.md in the round directory; current_uat() prioritizes round-dir
# UATs over phase-root ones. Round-dir UATs already in their round directory
# are handled separately (current round advances to next round, stale rounds
# advance to verify).
#
# Flat/legacy layout: Archives UAT to {NN}-UAT-round-{seq}.md and advances to
# the next remediation round (original behavior).
#
# Guards:
#   - Refuses if no UAT.md exists (nothing to archive)
#   - Refuses if UAT status is not issues_found (don't archive a passing UAT)
#
# The flat-layout round file naming ({NN}-UAT-round-{seq}.md) self-excludes from
# all existing UAT globs ([0-9]*-UAT.md, *-UAT.md) because it ends with
# -round-{seq}.md, not -UAT.md.

set -eo pipefail

PHASE_DIR="${1:-}"

if [ -z "$PHASE_DIR" ]; then
  echo "Usage: prepare-reverification.sh <phase-dir>" >&2
  exit 1
fi

if [ ! -d "$PHASE_DIR" ]; then
  echo "Error: phase directory does not exist: $PHASE_DIR" >&2
  exit 1
fi

# Source shared UAT helpers (extract_status_value, latest_non_source_uat)
_SCRIPT_DIR_PR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=uat-utils.sh
. "$_SCRIPT_DIR_PR/uat-utils.sh"

resolve_config_path() {
  local phase_dir="${1%/}"
  local planning_dir

  case "$phase_dir" in
    */.vbw-planning/phases/*)
      planning_dir=$(dirname "$(dirname "$phase_dir")")
      printf '%s/config.json\n' "$planning_dir"
      ;;
    .vbw-planning/phases/*)
      printf '.vbw-planning/config.json\n'
      ;;
    *)
      printf '.vbw-planning/config.json\n'
      ;;
  esac
}

# Find the UAT file
UAT_FILE=$(current_uat "$PHASE_DIR")

if [ -z "$UAT_FILE" ] || [ ! -f "$UAT_FILE" ]; then
  # Idempotent: if UAT was already archived (e.g., vibe.md ran this before
  # routing to verify.md which runs it again), exit 0 with skip marker.
  echo "skipped=already_archived"
  exit 0
fi

# Check UAT status — only archive issues_found
UAT_STATUS=$(extract_status_value "$UAT_FILE")
if [ "$UAT_STATUS" != "issues_found" ]; then
  echo "Error: UAT status is '${UAT_STATUS:-empty}', not 'issues_found' — refusing to archive" >&2
  exit 1
fi

# Check remediation stage — only archive when stage=done
_REM_STAGE="none"
_new_stage_file="${PHASE_DIR%/}/remediation/uat/.uat-remediation-stage"
_legacy_remed_stage_file="${PHASE_DIR%/}/remediation/.uat-remediation-stage"
_stage_file="${PHASE_DIR%/}/.uat-remediation-stage"
_active_stage_file=""
if [ -f "$_new_stage_file" ]; then
  _active_stage_file="$_new_stage_file"
  _REM_STAGE=$(grep '^stage=' "$_new_stage_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  _REM_STAGE="${_REM_STAGE:-none}"
elif [ -f "$_legacy_remed_stage_file" ]; then
  _active_stage_file="$_legacy_remed_stage_file"
  if grep -q '^stage=' "$_legacy_remed_stage_file" 2>/dev/null; then
    _REM_STAGE=$(grep '^stage=' "$_legacy_remed_stage_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  else
    _REM_STAGE=$(tr -d '[:space:]' < "$_legacy_remed_stage_file")
  fi
  _REM_STAGE="${_REM_STAGE:-none}"
elif [ -f "$_stage_file" ]; then
  _active_stage_file="$_stage_file"
  if grep -q '^stage=' "$_stage_file" 2>/dev/null; then
    _REM_STAGE=$(grep '^stage=' "$_stage_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  else
    _REM_STAGE=$(tr -d '[:space:]' < "$_stage_file")
  fi
  _REM_STAGE="${_REM_STAGE:-none}"
fi
if [ "$_REM_STAGE" != "done" ] && [ "$_REM_STAGE" != "verify" ]; then
  echo "Error: remediation stage is '${_REM_STAGE}', not 'done' or 'verify' — remediation still in progress" >&2
  exit 1
fi

# Extract phase number from UAT filename (e.g., "01" from "01-UAT.md")
UAT_BASENAME=$(basename "$UAT_FILE")
PHASE_NUM=$(echo "$UAT_BASENAME" | sed 's/^\([0-9]*\).*/\1/')

# Normalize phase dir path
case "$PHASE_DIR" in
  */) ;;
  *) PHASE_DIR="$PHASE_DIR/" ;;
esac

# Detect layout from remediation state file (before round counting — round-dir
# layout uses a completely different archival strategy)
_LAYOUT="flat"
if [ -n "$_active_stage_file" ] && [ -f "$_active_stage_file" ]; then
  _layout_val=$(grep '^layout=' "$_active_stage_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  if [ "$_layout_val" = "round-dir" ]; then
    _LAYOUT="round-dir"
  fi
fi

CONFIG_PATH=$(resolve_config_path "$PHASE_DIR")
CURRENT_ROUND=$(bash "$_SCRIPT_DIR_PR/uat-remediation-state.sh" current-round "${PHASE_DIR%/}" 2>/dev/null) || {
  echo "Error: could not resolve current UAT remediation round for ${PHASE_DIR%/}" >&2
  exit 1
}
CURRENT_ROUND="${CURRENT_ROUND:-01}"
CURRENT_ROUND_NUM=$(echo "$CURRENT_ROUND" | sed 's/^0*//')
CURRENT_ROUND_NUM="${CURRENT_ROUND_NUM:-1}"

# For round-dir UATs already in their round directory, skip mv archival
case "$UAT_FILE" in
  */remediation/uat/round-*/R*-UAT.md)
    # Extract round number from the UAT filename (e.g., R01 → 1, R02 → 2)
    _uat_round_raw=$(basename "$UAT_FILE" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
    _uat_round="${_uat_round_raw:-0}"
    PHASE_NUM=$(basename "${PHASE_DIR%/}" | sed 's/^\([0-9]*\).*/\1/')
    if [ "$_uat_round" = "$CURRENT_ROUND_NUM" ]; then
      _cap_decision=$(bash "$_SCRIPT_DIR_PR/resolve-uat-remediation-round-limit.sh" --next-round-decision "$CONFIG_PATH" "$CURRENT_ROUND" 2>/dev/null) || {
        echo "Error: could not resolve UAT remediation round cap for current round $CURRENT_ROUND" >&2
        exit 1
      }
      _cap_reached=$(printf '%s\n' "$_cap_decision" | awk -F= '/^cap_reached=/{print $2; exit}')
      case "${_cap_reached:-}" in
        true)
          echo "skipped=cap_reached"
          echo "phase=$PHASE_NUM"
          echo "layout=$_LAYOUT"
          printf '%s\n' "$_cap_decision"
          exit 0
          ;;
        false) ;; # continue to advance
        *)
          echo "Error: malformed round-limit helper output — missing or invalid cap_reached key" >&2
          exit 1
          ;;
      esac

      # Current round's UAT has issues — advance to next round
      bash "$_SCRIPT_DIR_PR/uat-remediation-state.sh" needs-round "${PHASE_DIR%/}" >/dev/null
      rm -f "${PHASE_DIR}.uat-remediation-stage"
      if git rev-parse --git-dir >/dev/null 2>&1; then
        git add "${PHASE_DIR}remediation/uat/.uat-remediation-stage" 2>/dev/null || true
        git rm -f --quiet "${PHASE_DIR}.uat-remediation-stage" 2>/dev/null || true
      fi
      echo "archived=in-round-dir"
      echo "round_file=$UAT_BASENAME"
      echo "phase=$PHASE_NUM"
      echo "layout=$_LAYOUT"
    else
      # Stale UAT from a previous round — current round has no UAT yet.
      # Don't archive or advance rounds; move stage to verify so the
      # orchestrator writes a fresh UAT for the current round.
      if [ "$_REM_STAGE" = "done" ]; then
        bash "$_SCRIPT_DIR_PR/uat-remediation-state.sh" advance "${PHASE_DIR%/}" >/dev/null
      fi
      echo "skipped=ready_for_verify"
      echo "phase=$PHASE_NUM"
      echo "layout=$_LAYOUT"
    fi
    exit 0
    ;;
esac

# --- Phase-root UAT handling depends on layout ---

if [ "$_LAYOUT" = "round-dir" ]; then
  # Round-dir layout: the phase-root UAT is the ORIGINAL document that found
  # issues and triggered remediation. Leave it in place — it serves as the
  # permanent historical record. verify.md writes R{RR}-UAT.md in the round
  # dir, and current_uat() prioritizes round-dir UATs over phase-root ones.
  # Just advance state done → verify.
  if [ "$_REM_STAGE" = "done" ]; then
    bash "$_SCRIPT_DIR_PR/uat-remediation-state.sh" advance "${PHASE_DIR%/}" >/dev/null
  fi

  rm -f "${PHASE_DIR}.uat-remediation-stage"

  if git rev-parse --git-dir >/dev/null 2>&1; then
    git add "${PHASE_DIR}remediation/uat/.uat-remediation-stage" 2>/dev/null || true
    git rm -f --quiet "${PHASE_DIR}.uat-remediation-stage" 2>/dev/null || true
  fi

  echo "archived=kept"
  echo "phase=$PHASE_NUM"
  echo "layout=$_LAYOUT"
  exit 0
fi

# Flat/legacy layout: archive to numbered round file
MAX_ROUND=$(count_uat_rounds "$PHASE_DIR" "$PHASE_NUM")

_cap_decision=$(bash "$_SCRIPT_DIR_PR/resolve-uat-remediation-round-limit.sh" --next-round-decision "$CONFIG_PATH" "$CURRENT_ROUND" 2>/dev/null) || {
  echo "Error: could not resolve UAT remediation round cap for current round $CURRENT_ROUND" >&2
  exit 1
}
_cap_reached=$(printf '%s\n' "$_cap_decision" | awk -F= '/^cap_reached=/{print $2; exit}')
case "${_cap_reached:-}" in
  true)
    echo "skipped=cap_reached"
    echo "phase=$PHASE_NUM"
    echo "layout=$_LAYOUT"
    printf '%s\n' "$_cap_decision"
    exit 0
    ;;
  false) ;; # continue to advance
  *)
    echo "Error: malformed round-limit helper output — missing or invalid cap_reached key" >&2
    exit 1
    ;;
esac

NEXT_ROUND=$((MAX_ROUND + 1))
ROUND_PADDED=$(printf '%02d' "$NEXT_ROUND")
ROUND_FILE="${PHASE_NUM}-UAT-round-${ROUND_PADDED}.md"

# Warn if we've been through many rounds — signal the user may want a different approach
if [ "$NEXT_ROUND" -ge 3 ]; then
  echo "reverification_warning=This phase has been through $MAX_ROUND UAT remediation rounds. Consider a different approach if issues persist."
fi

mv "$UAT_FILE" "${PHASE_DIR}${ROUND_FILE}"
mkdir -p "${PHASE_DIR}remediation/uat"
printf 'stage=%s\nround=%s\nlayout=round-dir\n' "$_REM_STAGE" "$CURRENT_ROUND" > "$_new_stage_file"
rm -f "$_legacy_remed_stage_file" "${PHASE_DIR}.uat-remediation-stage"
bash "$_SCRIPT_DIR_PR/uat-remediation-state.sh" needs-round "${PHASE_DIR%/}" >/dev/null

# Clean up legacy state file if present (new-location state file persists with updated round)
rm -f "${PHASE_DIR}.uat-remediation-stage"

# Pre-stage changes in git so boundary commits capture them even if the
# LLM improvises a manual commit instead of using planning-git.sh.
if git rev-parse --git-dir >/dev/null 2>&1; then
  git add "${PHASE_DIR}${ROUND_FILE}" 2>/dev/null || true
  git add "${PHASE_DIR}remediation/uat/.uat-remediation-stage" 2>/dev/null || true
  git rm -f --quiet "${PHASE_DIR}.uat-remediation-stage" 2>/dev/null || true
fi

# Output for logging
echo "archived=$UAT_BASENAME"
echo "round_file=$ROUND_FILE"
echo "phase=$PHASE_NUM"
echo "layout=$_LAYOUT"

exit 0
