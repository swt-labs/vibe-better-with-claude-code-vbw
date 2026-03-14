#!/usr/bin/env bash
# prepare-reverification.sh — Archive old UAT and advance remediation round for re-verification.
#
# Usage: prepare-reverification.sh <phase-dir>
#
# Archives the current UAT.md to {NN}-UAT-round-{seq}.md, advances the
# remediation state to the next round (stage=research, round incremented),
# and outputs the archive details for logging.
#
# Guards:
#   - Refuses if no UAT.md exists (nothing to archive)
#   - Refuses if UAT status is not issues_found (don't archive a passing UAT)
#
# The round file naming ({NN}-UAT-round-{seq}.md) self-excludes from all
# existing UAT globs ([0-9]*-UAT.md, *-UAT.md) because it ends with
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
_new_stage_file="${PHASE_DIR%/}/remediation/.uat-remediation-stage"
_stage_file="${PHASE_DIR%/}/.uat-remediation-stage"
if [ -f "$_new_stage_file" ]; then
  _REM_STAGE=$(grep '^stage=' "$_new_stage_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  _REM_STAGE="${_REM_STAGE:-none}"
elif [ -f "$_stage_file" ]; then
  _REM_STAGE=$(tr -d '[:space:]' < "$_stage_file")
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

# Find next round sequence number (via shared helper)
MAX_ROUND=$(count_uat_rounds "$PHASE_DIR" "$PHASE_NUM")

NEXT_ROUND=$((MAX_ROUND + 1))
ROUND_PADDED=$(printf '%02d' "$NEXT_ROUND")
ROUND_FILE="${PHASE_NUM}-UAT-round-${ROUND_PADDED}.md"

# Warn if we've been through many rounds — signal the user may want a different approach
if [ "$NEXT_ROUND" -ge 3 ]; then
  echo "reverification_warning=This phase has been through $MAX_ROUND remediation rounds. Consider a different approach if issues persist."
fi

# Detect layout from remediation state file
_LAYOUT="flat"
if [ -f "$_new_stage_file" ]; then
  _layout_val=$(grep '^layout=' "$_new_stage_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  if [ "$_layout_val" = "round-dir" ]; then
    _LAYOUT="round-dir"
  fi
fi

# For round-dir UATs already in their round directory, skip mv archival
case "$UAT_FILE" in
  */remediation/round-*/R*-UAT.md)
    # Extract round number from the UAT filename (e.g., R01 → 1, R02 → 2)
    _uat_round_raw=$(basename "$UAT_FILE" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
    _uat_round="${_uat_round_raw:-0}"
    # Read current round from state file (strip leading zeros for numeric compare)
    _cur_round="1"
    if [ -f "$_new_stage_file" ]; then
      _cr_val=$(grep '^round=' "$_new_stage_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
      _cur_round=$(echo "${_cr_val:-01}" | sed 's/^0*//')
      _cur_round="${_cur_round:-1}"
    fi
    PHASE_NUM=$(basename "${PHASE_DIR%/}" | sed 's/^\([0-9]*\).*/\1/')
    if [ "$_uat_round" = "$_cur_round" ]; then
      # Current round's UAT has issues — advance to next round
      bash "$_SCRIPT_DIR_PR/uat-remediation-state.sh" needs-round "${PHASE_DIR%/}" >/dev/null
      rm -f "${PHASE_DIR}.uat-remediation-stage"
      if git rev-parse --git-dir >/dev/null 2>&1; then
        git add "${PHASE_DIR}remediation/.uat-remediation-stage" 2>/dev/null || true
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

# Archive: rename UAT to round file
mv "$UAT_FILE" "${PHASE_DIR}${ROUND_FILE}"

if [ "$_LAYOUT" = "round-dir" ]; then
  # Round-dir layout: do NOT advance to next round yet.
  # verify.md will write R{RR}-UAT.md into the current round dir, then
  # advance only if re-verification finds issues.
  # Advance done → verify through the proper state machine.
  bash "$_SCRIPT_DIR_PR/uat-remediation-state.sh" advance "${PHASE_DIR%/}" >/dev/null
else
  # Flat/legacy layout: advance remediation to next round (original behavior)
  bash "$_SCRIPT_DIR_PR/uat-remediation-state.sh" needs-round "${PHASE_DIR%/}" >/dev/null
fi

# Clean up legacy state file if present (new-location state file persists with updated round)
rm -f "${PHASE_DIR}.uat-remediation-stage"

# Pre-stage changes in git so boundary commits capture them even if the
# LLM improvises a manual commit instead of using planning-git.sh.
if git rev-parse --git-dir >/dev/null 2>&1; then
  git add "${PHASE_DIR}${ROUND_FILE}" 2>/dev/null || true
  git add "${PHASE_DIR}remediation/.uat-remediation-stage" 2>/dev/null || true
  git rm -f --quiet "${PHASE_DIR}.uat-remediation-stage" 2>/dev/null || true
fi

# Output for logging
echo "archived=$UAT_BASENAME"
echo "round_file=$ROUND_FILE"
echo "phase=$PHASE_NUM"
echo "layout=$_LAYOUT"

exit 0
