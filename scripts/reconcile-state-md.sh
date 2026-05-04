#!/usr/bin/env bash
# reconcile-state-md.sh — Deterministically reconcile STATE.md current phase
# projection from phase PLAN/SUMMARY/UAT artifacts.
#
# Default mode is intentionally quiet and fail-open so hooks and SessionStart
# can call it without injecting context or breaking Claude Code sessions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P 2>/dev/null || pwd)"
JSON_OUTPUT=false
MODE="planning"
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      JSON_OUTPUT=true
      ;;
    --changed)
      MODE="changed"
      shift
      TARGET="${1:-}"
      ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"
      fi
      ;;
  esac
  shift || break
done

quiet_json() {
  if [ "$JSON_OUTPUT" = true ] && command -v jq >/dev/null 2>&1; then
    jq -n --arg status "$1" --arg detail "${2:-}" '{status:$status,detail:$detail}'
  fi
}

# Source shared helpers. Missing dependencies are a quiet no-op by default.
if [ -f "$SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  . "$SCRIPT_DIR/summary-utils.sh" || { quiet_json "skipped" "summary-utils unavailable"; exit 0; }
fi
if [ -f "$SCRIPT_DIR/phase-state-utils.sh" ]; then
  # shellcheck source=phase-state-utils.sh
  . "$SCRIPT_DIR/phase-state-utils.sh" || { quiet_json "skipped" "phase-state-utils unavailable"; exit 0; }
fi
if [ -f "$SCRIPT_DIR/uat-utils.sh" ]; then
  # shellcheck source=uat-utils.sh
  . "$SCRIPT_DIR/uat-utils.sh" || { quiet_json "skipped" "uat-utils unavailable"; exit 0; }
fi

REQUIRED_FUNCTIONS=(
  list_canonical_phase_dirs
  count_phase_plans
  count_complete_summaries
  count_terminal_summaries
  current_uat
  extract_status_value
  phase_dir_display_name
)
for fn in "${REQUIRED_FUNCTIONS[@]}"; do
  if ! type "$fn" >/dev/null 2>&1; then
    quiet_json "skipped" "missing required function: $fn"
    exit 0
  fi
done

physical_dir() {
  local dir="$1"
  if [ -d "$dir" ]; then
    (cd "$dir" 2>/dev/null && pwd -P 2>/dev/null) || printf '%s\n' "$dir"
  else
    printf '%s\n' "$dir"
  fi
}

resolve_planning_root_from_changed() {
  local changed="$1"
  local dir parent traversals

  [ -n "$changed" ] || return 0

  if [ -d "$changed" ]; then
    dir="$changed"
  elif [ -f "$changed" ]; then
    dir=$(dirname "$changed")
  else
    dir=$(dirname "$changed")
  fi

  dir=$(physical_dir "$dir")
  traversals=0
  while [ -n "$dir" ] && [ "$traversals" -le 10 ]; do
    if [ -f "$dir/STATE.md" ] && [ -d "$dir/phases" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    parent=$(dirname "$dir")
    [ "$parent" = "$dir" ] && break
    dir="$parent"
    traversals=$((traversals + 1))
  done

  return 0
}

resolve_planning_root() {
  local target="$1"

  if [ "$MODE" = "changed" ]; then
    resolve_planning_root_from_changed "$target"
    return 0
  fi

  [ -n "$target" ] || target="${VBW_PLANNING_DIR:-.vbw-planning}"
  if [ -d "$target" ]; then
    physical_dir "$target"
  else
    printf '%s\n' "$target"
  fi
}

phase_has_unresolved_uat() {
  local phase_dir="$1"
  local uat_file status_val

  uat_file=$(current_uat "$phase_dir")
  [ -n "$uat_file" ] && [ -f "$uat_file" ] || return 1
  status_val=$(extract_status_value "$uat_file")
  [ "$status_val" = "issues_found" ]
}

status_label_for_phase() {
  local idx="$1" plan_count="$2" terminal_count="$3" complete_count="$4" unresolved="$5"

  if [ "$unresolved" = true ]; then
    printf '%s\n' "Needs remediation"
  elif [ "$plan_count" -gt 0 ] && [ "$complete_count" -ge "$plan_count" ]; then
    printf '%s\n' "Complete"
  elif [ "$terminal_count" -gt 0 ]; then
    printf '%s\n' "In progress"
  elif [ "$plan_count" -gt 0 ]; then
    printf '%s\n' "Planned"
  elif [ "$idx" -eq 1 ]; then
    printf '%s\n' "Pending planning"
  else
    printf '%s\n' "Pending"
  fi
}

rewrite_current_phase_section() {
  local state_file="$1" phase_line="$2" plans_line="$3" progress_line="$4" status_line="$5"
  local tmp

  tmp="${state_file}.tmp-current.$$.${RANDOM:-0}"
  if grep -q '^## Current Phase$' "$state_file" 2>/dev/null; then
    PHASE_LINE="$phase_line" PLANS_LINE="$plans_line" PROGRESS_LINE="$progress_line" STATUS_LINE="$status_line" awk '
      /^## Current Phase$/ {
        print
        print ENVIRON["PHASE_LINE"]
        print ENVIRON["PLANS_LINE"]
        print ENVIRON["PROGRESS_LINE"]
        print ENVIRON["STATUS_LINE"]
        skip = 1
        next
      }
      skip && /^## / { skip = 0; print ""; print; next }
      skip { next }
      { print }
    ' "$state_file" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && mv "$tmp" "$state_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    PHASE_LINE="$phase_line" PLANS_LINE="$plans_line" PROGRESS_LINE="$progress_line" STATUS_LINE="$status_line" awk '
      !seen_phase && /^Phase:/ { print ENVIRON["PHASE_LINE"]; seen_phase = 1; next }
      !seen_plans && /^Plans:/ { print ENVIRON["PLANS_LINE"]; seen_plans = 1; next }
      !seen_progress && /^Progress:/ { print ENVIRON["PROGRESS_LINE"]; seen_progress = 1; next }
      !seen_status && /^Status:/ { print ENVIRON["STATUS_LINE"]; seen_status = 1; next }
      { print }
    ' "$state_file" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && mv "$tmp" "$state_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  fi
}

rewrite_phase_status_section() {
  local state_file="$1" status_lines_file="$2"
  local tmp

  [ -s "$status_lines_file" ] || return 0
  grep -q '^## Phase Status$' "$state_file" 2>/dev/null || return 0

  tmp="${state_file}.tmp-status.$$.${RANDOM:-0}"
  STATUS_LINES_FILE="$status_lines_file" awk '
    /^## Phase Status$/ {
      print
      while ((getline line < ENVIRON["STATUS_LINES_FILE"]) > 0) print line
      skip = 1
      next
    }
    skip && /^- \*\*Phase [0-9]/ { next }
    skip && /^$/ { skip = 0; print; next }
    skip && /^## / { skip = 0; print ""; print; next }
    skip { next }
    { print }
  ' "$state_file" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && mv "$tmp" "$state_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

desired_roadmap_marker_for_phase_num() {
  local scheme="$1" wanted_num="$2" idx phase_dir candidate_phase_dir plan_count complete_count unresolved
  phase_dir=$(roadmap_phase_dir_for_num "$scheme" "$PHASES_DIR" "$wanted_num") || return 1
  [ -n "$phase_dir" ] || return 1

  idx=0
  for candidate_phase_dir in "${phase_dirs[@]}"; do
    if [ "${candidate_phase_dir%/}" = "${phase_dir%/}" ]; then
      plan_count=${plan_counts[$idx]}
      complete_count=${complete_counts[$idx]}
      unresolved=${unresolved_flags[$idx]}
      if [ "$plan_count" -gt 0 ] && [ "$complete_count" -ge "$plan_count" ] && [ "$unresolved" != true ]; then
        printf '%s\n' "x"
      else
        printf '%s\n' " "
      fi
      return 0
    fi
    idx=$((idx + 1))
  done
  return 1
}

rewrite_roadmap_checklist_projection() {
  local roadmap_file="$1"
  local tmp line raw_num line_num marker scheme

  [ -f "$roadmap_file" ] || return 0
  scheme=$(roadmap_numbering_scheme "$roadmap_file" "$PHASES_DIR")
  [ "$scheme" != "unknown" ] || return 0

  tmp="${roadmap_file}.tmp-checklist.$$.${RANDOM:-0}"
  : > "$tmp" 2>/dev/null || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^-\ \[.\]\ \[?Phase\ ([0-9][0-9]*): ]]; then
      raw_num="${BASH_REMATCH[1]}"
      line_num=$(normalize_roadmap_phase_num "$raw_num")
      if marker=$(desired_roadmap_marker_for_phase_num "$scheme" "$line_num"); then
        line="- [${marker}]${line:5}"
      fi
    fi
    printf '%s\n' "$line" >> "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 0; }
  done < "$roadmap_file"

  [ -s "$tmp" ] && mv "$tmp" "$roadmap_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

PLANNING_DIR=$(resolve_planning_root "$TARGET")
[ -n "$PLANNING_DIR" ] || { quiet_json "skipped" "planning root not found"; exit 0; }

STATE_FILE="$PLANNING_DIR/STATE.md"
PHASES_DIR="$PLANNING_DIR/phases"
[ -f "$STATE_FILE" ] && [ -d "$PHASES_DIR" ] || { quiet_json "skipped" "missing STATE.md or phases directory"; exit 0; }

phase_dirs=()
while IFS= read -r phase_dir; do
  [ -n "$phase_dir" ] || continue
  phase_dirs+=("$phase_dir")
done < <(list_canonical_phase_dirs "$PHASES_DIR")

TOTAL=${#phase_dirs[@]}
[ "$TOTAL" -gt 0 ] || { quiet_json "skipped" "no canonical phases"; exit 0; }

plan_counts=()
terminal_counts=()
complete_counts=()
unresolved_flags=()
names=()
labels=()

active_idx=0
active_unresolved=false
all_done=true
idx=0
for phase_dir in "${phase_dirs[@]}"; do
  idx=$((idx + 1))
  plan_count=$(count_phase_plans "$phase_dir")
  terminal_count=$(count_terminal_summaries "$phase_dir")
  complete_count=$(count_complete_summaries "$phase_dir")
  unresolved=false
  if phase_has_unresolved_uat "$phase_dir"; then
    unresolved=true
  fi

  plan_counts+=("$plan_count")
  terminal_counts+=("$terminal_count")
  complete_counts+=("$complete_count")
  unresolved_flags+=("$unresolved")
  names+=("$(phase_dir_display_name "$phase_dir")")
  labels+=("$(status_label_for_phase "$idx" "$plan_count" "$terminal_count" "$complete_count" "$unresolved")")

  if [ "$active_idx" -eq 0 ]; then
    if [ "$plan_count" -eq 0 ] || [ "$complete_count" -lt "$plan_count" ] || [ "$unresolved" = true ]; then
      active_idx="$idx"
      active_unresolved="$unresolved"
      all_done=false
    fi
  fi
done

if [ "$active_idx" -eq 0 ]; then
  active_idx="$TOTAL"
  all_done=true
  active_unresolved=false
fi

array_idx=$((active_idx - 1))
active_plan_count=${plan_counts[$array_idx]}
active_terminal_count=${terminal_counts[$array_idx]}
active_complete_count=${complete_counts[$array_idx]}
active_name=${names[$array_idx]}

if [ "$active_plan_count" -gt 0 ]; then
  progress=$((active_terminal_count * 100 / active_plan_count))
else
  progress=0
fi

if [ "$all_done" = true ]; then
  active_status="complete"
elif [ "$active_unresolved" = true ]; then
  active_status="needs_remediation"
elif [ "$active_plan_count" -eq 0 ]; then
  active_status="ready"
elif [ "$active_terminal_count" -gt 0 ] && [ "$active_complete_count" -lt "$active_plan_count" ]; then
  active_status="active"
else
  active_status="ready"
fi

phase_line="Phase: ${active_idx} of ${TOTAL} (${active_name})"
plans_line="Plans: ${active_terminal_count}/${active_plan_count}"
progress_line="Progress: ${progress}%"
status_line="Status: ${active_status}"

status_lines_file="${STATE_FILE}.phase-status.$$.${RANDOM:-0}"
: > "$status_lines_file" 2>/dev/null || exit 0
idx=0
for phase_dir in "${phase_dirs[@]}"; do
  idx=$((idx + 1))
  name=${names[$((idx - 1))]}
  label=${labels[$((idx - 1))]}
  printf -- '- **Phase %s (%s):** %s\n' "$idx" "$name" "$label" >> "$status_lines_file" 2>/dev/null || true
done

rewrite_current_phase_section "$STATE_FILE" "$phase_line" "$plans_line" "$progress_line" "$status_line"
rewrite_phase_status_section "$STATE_FILE" "$status_lines_file"
rm -f "$status_lines_file" 2>/dev/null || true
rewrite_roadmap_checklist_projection "$PLANNING_DIR/ROADMAP.md"

if [ "$JSON_OUTPUT" = true ] && command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg status "reconciled" \
    --arg planning_dir "$PLANNING_DIR" \
    --arg phase "$active_idx" \
    --arg total "$TOTAL" \
    --arg phase_status "$active_status" \
    '{status:$status,planning_dir:$planning_dir,phase:($phase|tonumber),total:($total|tonumber),phase_status:$phase_status}'
fi

exit 0
