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
  normalize_roadmap_phase_num
  roadmap_checklist_phase_num_from_line
  roadmap_phase_dir_prefix_num
  roadmap_numbering_scheme
  roadmap_phase_num_for_dir
  roadmap_phase_dir_for_num
  roadmap_checklist_phase_nums
  roadmap_checklist_count
  roadmap_checklist_has_duplicate_phase_nums
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
  local tmp line line_num marker scheme

  [ -f "$roadmap_file" ] || return 0
  if roadmap_checklist_has_duplicate_phase_nums "$roadmap_file"; then
    return 0
  fi
  scheme=$(roadmap_numbering_scheme "$roadmap_file" "$PHASES_DIR")
  [ "$scheme" != "unknown" ] || return 0

  tmp="${roadmap_file}.tmp-checklist.$$.${RANDOM:-0}"
  : > "$tmp" 2>/dev/null || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    if line_num=$(roadmap_checklist_phase_num_from_line "$line"); then
      if marker=$(desired_roadmap_marker_for_phase_num "$scheme" "$line_num"); then
        line="- [${marker}]${line:5}"
      fi
    fi
    printf '%s\n' "$line" >> "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 0; }
  done < "$roadmap_file"

  [ -s "$tmp" ] && mv "$tmp" "$roadmap_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

phase_dir_array_index() {
  local wanted="$1" idx=0 candidate

  for candidate in "${phase_dirs[@]}"; do
    if [ "${candidate%/}" = "${wanted%/}" ]; then
      printf '%s\n' "$idx"
      return 0
    fi
    idx=$((idx + 1))
  done

  return 1
}

existing_phase_status_line() {
  local state_file="$1" phase_num="$2"

  grep -E "^- \*\*Phase 0*${phase_num}([ :]|\()" "$state_file" 2>/dev/null | head -1
}

append_phase_status_for_dir_index() {
  local out_file="$1" display_num="$2" dir_index="$3"
  local name label

  name=${names[$dir_index]}
  label=${labels[$dir_index]}
  printf -- '- **Phase %s (%s):** %s\n' "$display_num" "$name" "$label" >> "$out_file" 2>/dev/null || true
}

append_missing_phase_status() {
  local out_file="$1" phase_num="$2"
  local existing

  existing=$(existing_phase_status_line "$STATE_FILE" "$phase_num" || true)
  if [ -n "$existing" ]; then
    printf '%s\n' "$existing" >> "$out_file" 2>/dev/null || true
  else
    printf -- '- **Phase %s (Missing phase directory):** Unknown (missing phase directory)\n' "$phase_num" >> "$out_file" 2>/dev/null || true
  fi
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

ROADMAP_FILE="$PLANNING_DIR/ROADMAP.md"
numbering_scheme="ordinal"
roadmap_total=0
if [ -f "$ROADMAP_FILE" ]; then
  numbering_scheme=$(roadmap_numbering_scheme "$ROADMAP_FILE" "$PHASES_DIR")
  if type phase_state_log_numbering_warnings >/dev/null 2>&1; then
    phase_state_log_numbering_warnings "$PLANNING_DIR" "$ROADMAP_FILE" "$PHASES_DIR" "$numbering_scheme"
  fi
  if [ "$numbering_scheme" = "unknown" ]; then
    quiet_json "skipped" "ROADMAP checklist numbering scheme is mixed or unresolvable"
    exit 0
  fi
  roadmap_total=$(roadmap_checklist_count "$ROADMAP_FILE")
fi

active_display_idx="$active_idx"
display_total="$TOTAL"
if [ "$numbering_scheme" = "prefix" ] && [ "${roadmap_total:-0}" -gt 0 ]; then
  active_display_idx=$(roadmap_phase_num_for_dir "prefix" "${phase_dirs[$array_idx]}" "$PHASES_DIR")
  [ -n "$active_display_idx" ] || active_display_idx="$active_idx"
  display_total="$roadmap_total"
fi

phase_line="Phase: ${active_display_idx} of ${display_total} (${active_name})"
plans_line="Plans: ${active_terminal_count}/${active_plan_count}"
progress_line="Progress: ${progress}%"
status_line="Status: ${active_status}"

status_lines_file="${STATE_FILE}.phase-status.$$.${RANDOM:-0}"
: > "$status_lines_file" 2>/dev/null || exit 0
if [ "$numbering_scheme" = "prefix" ] && [ "${roadmap_total:-0}" -gt 0 ]; then
  while IFS= read -r roadmap_phase_num; do
    [ -n "$roadmap_phase_num" ] || continue
    roadmap_phase_dir=$(roadmap_phase_dir_for_num "prefix" "$PHASES_DIR" "$roadmap_phase_num" 2>/dev/null || true)
    if [ -n "$roadmap_phase_dir" ] && dir_index=$(phase_dir_array_index "$roadmap_phase_dir"); then
      append_phase_status_for_dir_index "$status_lines_file" "$roadmap_phase_num" "$dir_index"
    else
      append_missing_phase_status "$status_lines_file" "$roadmap_phase_num"
    fi
  done < <(roadmap_checklist_phase_nums "$ROADMAP_FILE")
else
  idx=0
  for phase_dir in "${phase_dirs[@]}"; do
    idx=$((idx + 1))
    case "$numbering_scheme" in
      prefix)
        display_num=$(roadmap_phase_num_for_dir "prefix" "$phase_dir" "$PHASES_DIR")
        [ -n "$display_num" ] || display_num="$idx"
        ;;
      *)
        display_num="$idx"
        ;;
    esac
    append_phase_status_for_dir_index "$status_lines_file" "$display_num" "$((idx - 1))"
  done
fi

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
