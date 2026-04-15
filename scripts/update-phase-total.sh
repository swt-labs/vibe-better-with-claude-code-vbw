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
  # F-06: inline minimal terminal summary parser instead of always returning 0
  count_complete_summaries() {
    local dir="$1" count=0
    for f in "$dir"/*-SUMMARY.md "$dir"/SUMMARY.md; do
      [ -f "$f" ] || continue
      local status
      status=$(tr -d '\r' < "$f" 2>/dev/null | sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' | head -1 | tr -d '[:space:]')
      case "$status" in
        complete|completed) count=$((count + 1)) ;;
      esac
    done
    echo "$count"
  }
  count_terminal_summaries() {
    local dir="$1" count=0
    for f in "$dir"/*-SUMMARY.md "$dir"/SUMMARY.md; do
      [ -f "$f" ] || continue
      local status
      status=$(tr -d '\r' < "$f" 2>/dev/null | sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' | head -1 | tr -d '[:space:]')
      case "$status" in
        complete|completed|partial|failed) count=$((count + 1)) ;;
      esac
    done
    echo "$count"
  }
fi
if [ -f "$SCRIPT_DIR/phase-state-utils.sh" ]; then
  # shellcheck source=phase-state-utils.sh
  source "$SCRIPT_DIR/phase-state-utils.sh"
else
  list_canonical_phase_dirs() {
    local parent="$1"
    [ -d "$parent" ] || return 0
    local dirs=() d base
    for d in "$parent"/*/; do
      [ -d "$d" ] || continue
      base="${d%/}"; base="${base##*/}"
      case "$base" in [0-9]*-*) dirs+=("${d%/}") ;; esac
    done
    [ ${#dirs[@]} -gt 0 ] || return 0
    printf '%s\n' "${dirs[@]}" | sort -V 2>/dev/null || \
      printf '%s\n' "${dirs[@]}" | awk -F/ '{n=$NF; gsub(/[^0-9].*/,"",n); if (n == "") n=0; print (n+0)"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f2-
  }
  count_phase_plans() {
    local dir="$1"
    local count=0
    local f
    for f in "$dir"/[0-9]*-PLAN.md "$dir"/PLAN.md; do
      [ -f "$f" ] && count=$((count + 1))
    done
    echo "$count"
  }
  phase_dir_display_name() {
    local dir="$1"
    basename "$dir" | sed 's/^[0-9]*-//' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1'
  }
  phase_status_label() {
    local dir="$1" phase_idx="$2"
    local plans complete terminal
    plans=$(count_phase_plans "$dir")
    complete=$(count_complete_summaries "$dir")
    terminal=$(count_terminal_summaries "$dir")
    if [ "$plans" -gt 0 ] && [ "$complete" -ge "$plans" ]; then
      echo "Complete"
    elif [ "$terminal" -gt 0 ]; then
      echo "In progress"
    elif [ "$plans" -gt 0 ]; then
      echo "Planned"
    elif [ "$phase_idx" -eq 1 ]; then
      echo "Pending planning"
    else
      echo "Pending"
    fi
  }
fi

planning_root="${1:-.vbw-planning}"
state_md="${planning_root}/STATE.md"
phases_dir="${planning_root}/phases"

[ -f "$state_md" ] || exit 0
[ -d "$phases_dir" ] || exit 0

# Parse optional flags
shift || true
action=""
position=0
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --inserted)
      action="inserted"
      position="${2:-0}"
      shift 2 || break
      ;;
    --removed)
      action="removed"
      position="${2:-0}"
      shift 2 || break
      ;;
    *)
      shift
      ;;
  esac
done

# Validate position is a positive integer when provided
if [ -n "$action" ] && ! echo "$position" | grep -qE '^[1-9][0-9]*$'; then
  exit 0
fi

sorted_dirs_file="${state_md}.dirs.$$"
list_canonical_phase_dirs "$phases_dir" > "$sorted_dirs_file"

total=$(wc -l < "$sorted_dirs_file" | tr -d ' ')

# F-02: handle zero-phase state — remove stale current-phase section and clear
# stale Phase Status bullets so STATE.md no longer claims an active phase.
if [ "$total" -eq 0 ]; then
  if grep -q '^## Current Phase' "$state_md" 2>/dev/null; then
    tmp_current_zero="${state_md}.tmpcurrent.$$"
    awk '
      /^## Current Phase$/ { skip = 1; next }
      skip && /^##/ { skip = 0; print; next }
      skip { next }
      { print }
    ' "$state_md" > "$tmp_current_zero" 2>/dev/null && \
      mv "$tmp_current_zero" "$state_md" 2>/dev/null || rm -f "$tmp_current_zero" 2>/dev/null
  fi
  if grep -q '^## Phase Status' "$state_md" 2>/dev/null; then
    tmp_zero="${state_md}.tmp.$$"
    awk '
      /^## Phase Status$/ { print; skip = 1; next }
      skip && /^- \*\*Phase [0-9]/ { next }
      skip && /^$/ { skip = 0; print; next }
      skip && /^##/ { skip = 0; print; next }
      skip { next }
      { print }
    ' "$state_md" > "$tmp_zero" 2>/dev/null && \
      mv "$tmp_zero" "$state_md" 2>/dev/null || rm -f "$tmp_zero" 2>/dev/null
  fi
  rm -f "$sorted_dirs_file" 2>/dev/null
  exit 0
fi

# Extract current phase number from Phase: line
current_line=$(grep -m1 '^Phase: ' "$state_md" 2>/dev/null)
if [ -z "$current_line" ]; then
  rm -f "$sorted_dirs_file" 2>/dev/null
  exit 0
fi

current=$(echo "$current_line" | sed 's/^Phase: \([0-9]*\).*/\1/')
if [ -z "$current" ]; then
  rm -f "$sorted_dirs_file" 2>/dev/null
  exit 0
fi

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

# F-11: Resolve phase name from sorted position (not filesystem prefix) so
# the Phase: line and Phase Status bullets always agree on numbering.
phase_name=""
phase_dir=$(sed -n "${current}p" "$sorted_dirs_file")
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
  local_name=$(phase_dir_display_name "$dir")
  status_text=$(phase_status_label "$dir" "$phase_idx")
  echo "- **Phase ${phase_idx} (${local_name}):** ${status_text}" >> "$new_status_file"
done < "$sorted_dirs_file"

rm -f "$sorted_dirs_file" 2>/dev/null

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
    skip && /^##/ { skip = 0; print ""; print; next }
    skip { next }
    { print }
  ' "$state_md" > "$tmp2" 2>/dev/null && \
    mv "$tmp2" "$state_md" 2>/dev/null || rm -f "$tmp2" 2>/dev/null
fi
rm -f "$new_status_file" 2>/dev/null
