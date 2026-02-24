#!/usr/bin/env bash
# prepare-reverification.sh — Archive old UAT and reset remediation stage for re-verification.
#
# Usage: prepare-reverification.sh <phase-dir>
#
# Archives the current UAT.md to {NN}-UAT-round-{seq}.md, removes
# .uat-remediation-stage, and outputs the archive details for logging.
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

# Reuse extract_status_value pattern from phase-detect.sh
extract_status_value() {
  local file="$1"
  awk '
    BEGIN { in_fm = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && tolower($0) ~ /^[[:space:]]*status[[:space:]]*:/ {
      value = $0
      sub(/^[^:]*:[[:space:]]*/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      print tolower(value)
      exit
    }
  ' "$file" 2>/dev/null || true
}

# Find latest non-SOURCE UAT (same pattern as phase-detect.sh)
latest_non_source_uat() {
  local dir="$1"
  local f
  local latest=""

  case "$dir" in
    */) ;;
    *) dir="$dir/" ;;
  esac

  for f in "${dir}"[0-9]*-UAT.md; do
    [ -f "$f" ] || continue
    case "$f" in
      *SOURCE-UAT.md) continue ;;
    esac
    latest="$f"
  done

  if [ -n "$latest" ]; then
    printf '%s\n' "$latest"
  fi
  return 0
}

# Find the UAT file
UAT_FILE=$(latest_non_source_uat "$PHASE_DIR")

if [ -z "$UAT_FILE" ] || [ ! -f "$UAT_FILE" ]; then
  echo "Error: no UAT.md found in $PHASE_DIR — nothing to archive" >&2
  exit 1
fi

# Check UAT status — only archive issues_found
UAT_STATUS=$(extract_status_value "$UAT_FILE")
if [ "$UAT_STATUS" != "issues_found" ]; then
  echo "Error: UAT status is '${UAT_STATUS:-empty}', not 'issues_found' — refusing to archive" >&2
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

# Find next round sequence number
MAX_ROUND=0
for rf in "${PHASE_DIR}${PHASE_NUM}"-UAT-round-*.md; do
  [ -f "$rf" ] || continue
  # Extract round number from filename
  round_num=$(basename "$rf" | sed "s/^${PHASE_NUM}-UAT-round-0*\([0-9]*\)\.md$/\1/")
  if [ -n "$round_num" ] && echo "$round_num" | grep -qE '^[0-9]+$'; then
    if [ "$round_num" -gt "$MAX_ROUND" ] 2>/dev/null; then
      MAX_ROUND="$round_num"
    fi
  fi
done

NEXT_ROUND=$((MAX_ROUND + 1))
ROUND_PADDED=$(printf '%02d' "$NEXT_ROUND")
ROUND_FILE="${PHASE_NUM}-UAT-round-${ROUND_PADDED}.md"

# Archive: rename UAT to round file
mv "$UAT_FILE" "${PHASE_DIR}${ROUND_FILE}"

# Reset remediation stage
rm -f "${PHASE_DIR}.uat-remediation-stage"

# Output for logging
echo "archived=$UAT_BASENAME"
echo "round_file=$ROUND_FILE"
echo "phase=$PHASE_NUM"

exit 0
