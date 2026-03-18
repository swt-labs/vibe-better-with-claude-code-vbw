#!/bin/bash
set -u
# Update the Phase: total in STATE.md after phase add/insert/remove.
# Usage: update-phase-total.sh <planning_root> [--inserted N | --removed N]
#   --inserted N: a phase was inserted at position N (adjust current if >= N)
#   --removed N:  a phase was removed at position N (adjust current if > N)
# Always recalculates total from filesystem.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  source "$SCRIPT_DIR/summary-utils.sh"
else
  count_terminal_summaries() { echo "0"; }
fi

planning_root="${1:-.vbw-planning}"
state_md="${planning_root}/STATE.md"
phases_dir="${planning_root}/phases"

[ -f "$state_md" ] || exit 0
[ -d "$phases_dir" ] || exit 0

# Parse optional flag
shift || true
action=""
position=0
if [ "${1:-}" = "--inserted" ] && [ -n "${2:-}" ]; then
  action="inserted"
  position="$2"
elif [ "${1:-}" = "--removed" ] && [ -n "${2:-}" ]; then
  action="removed"
  position="$2"
fi

# Validate position is a positive integer when provided
if [ -n "$action" ] && ! echo "$position" | grep -qE '^[1-9][0-9]*$'; then
  exit 0
fi

# Recalculate total from filesystem
total=$(find "$phases_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
[ "$total" -eq 0 ] && exit 0

# Extract current phase number from Phase: line
current_line=$(grep -m1 '^Phase: ' "$state_md" 2>/dev/null)
[ -z "$current_line" ] && exit 0

current=$(echo "$current_line" | sed 's/^Phase: \([0-9]*\).*/\1/')
[ -z "$current" ] && exit 0

# Adjust current phase number for insert/remove
case "$action" in
  inserted)
    if [ "$current" -ge "$position" ]; then
      current=$((current + 1))
    fi
    ;;
  removed)
    if [ "$current" -gt "$position" ]; then
      current=$((current - 1))
    fi
    ;;
esac

# Clamp current to valid range
[ "$current" -gt "$total" ] && current="$total"
[ "$current" -lt 1 ] && current=1

# Extract slug name from the current phase directory
phase_name=""
phase_dir=$(find "$phases_dir" -mindepth 1 -maxdepth 1 -type d -name "$(printf '%02d' "$current")-*" 2>/dev/null | head -1)
if [ -z "$phase_dir" ]; then
  # Try without zero-padding
  phase_dir=$(find "$phases_dir" -mindepth 1 -maxdepth 1 -type d -name "${current}-*" 2>/dev/null | head -1)
fi
if [ -n "$phase_dir" ]; then
  phase_name=$(basename "$phase_dir" | sed 's/^[0-9]*-//' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
fi

# Build replacement
if [ -n "$phase_name" ]; then
  replacement="Phase: ${current} of ${total} (${phase_name})"
else
  replacement="Phase: ${current} of ${total}"
fi

# Update STATE.md Phase: line
tmp="${state_md}.tmp.$$"
sed "s/^Phase: .*/${replacement}/" "$state_md" > "$tmp" 2>/dev/null && \
  mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null

# Rebuild ## Phase Status section to match current phase directories
new_status_file="${state_md}.newstatus.$$"
phase_idx=0
: > "$new_status_file"
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  phase_idx=$((phase_idx + 1))
  local_name=$(basename "$dir" | sed 's/^[0-9]*-//' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
  # Check for existing plans/summaries to infer status
  local_plans=$(find "$dir" -maxdepth 1 -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
  local_summaries=$(count_terminal_summaries "$dir")
  if [ "$local_plans" -gt 0 ] && [ "$local_summaries" -ge "$local_plans" ]; then
    status_text="Complete"
  elif [ "$local_summaries" -gt 0 ]; then
    status_text="In progress"
  elif [ "$local_plans" -gt 0 ]; then
    status_text="Planned"
  elif [ "$phase_idx" -eq 1 ]; then
    status_text="Pending planning"
  else
    status_text="Pending"
  fi
  echo "- **Phase ${phase_idx} (${local_name}):** ${status_text}" >> "$new_status_file"
done < <(find "$phases_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | (sort -V 2>/dev/null || awk -F/ '{n=$NF; gsub(/[^0-9].*/,"",n); if (n == "") n=0; print (n+0)"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f2-))

# Replace existing ## Phase Status section if present
if [ -s "$new_status_file" ] && grep -q '^## Phase Status' "$state_md" 2>/dev/null; then
  tmp2="${state_md}.tmp2.$$"
  NSF="$new_status_file" awk '
    /^## Phase Status$/ {
      print
      while ((getline line < ENVIRON["NSF"]) > 0) print line
      skip = 1
      next
    }
    skip && /^- \*\*Phase [0-9]/ { next }
    skip && /^$/ { skip = 0; print; next }
    skip && /^##/ { skip = 0; print; next }
    skip { skip = 0; print; next }
    { print }
  ' "$state_md" > "$tmp2" 2>/dev/null && \
    mv "$tmp2" "$state_md" 2>/dev/null || rm -f "$tmp2" 2>/dev/null
fi
rm -f "$new_status_file" 2>/dev/null
