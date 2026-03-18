#!/bin/bash
set -u
# Update the Phase: total in STATE.md after phase add/insert/remove.
# Usage: update-phase-total.sh <planning_root> [--inserted N | --removed N]
#   --inserted N: a phase was inserted at position N (adjust current if >= N)
#   --removed N:  a phase was removed at position N (adjust current if > N)
# Always recalculates total from filesystem.

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

# Update STATE.md
tmp="${state_md}.tmp.$$"
sed "s/^Phase: .*/${replacement}/" "$state_md" > "$tmp" 2>/dev/null && \
  mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
