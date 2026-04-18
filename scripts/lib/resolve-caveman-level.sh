#!/usr/bin/env bash
# resolve-caveman-level.sh — sourced helper, not standalone
# Resolves effective caveman level for 'auto' mode using .context-usage data.
# Usage: source this file, then call resolve_caveman_level "$caveman_style" "$planning_dir"
# Returns: sets RESOLVED_CAVEMAN_LEVEL to none/lite/full/ultra

# shellcheck disable=SC2034  # RESOLVED_CAVEMAN_LEVEL is read by callers that source this file
resolve_caveman_level() {
  local style="${1:-none}"
  local planning_dir="${2:-.vbw-planning}"

  # Passthrough for non-auto values
  if [[ "$style" != "auto" ]]; then
    RESOLVED_CAVEMAN_LEVEL="$style"
    return 0
  fi

  # Auto mode: read .context-usage to determine pressure level
  local usage_file="${planning_dir}/.context-usage"

  if [[ ! -f "$usage_file" ]]; then
    RESOLVED_CAVEMAN_LEVEL="none"
    return 0
  fi

  # Supported formats:
  #   session_id|used_pct|context_window_size  (3-field)
  #   used_pct|context_window_size              (legacy 2-field)
  local used_pct field_count
  field_count=$(awk -F'|' '{print NF}' "$usage_file" 2>/dev/null)

  if [[ "$field_count" == "3" ]]; then
    used_pct=$(awk -F'|' '{print $2}' "$usage_file" 2>/dev/null)
  elif [[ "$field_count" == "2" ]]; then
    used_pct=$(awk -F'|' '{print $1}' "$usage_file" 2>/dev/null)
  else
    RESOLVED_CAVEMAN_LEVEL="none"
    return 0
  fi

  # Validate numeric
  if [[ -z "$used_pct" ]] || ! [[ "$used_pct" =~ ^[0-9]+$ ]]; then
    RESOLVED_CAVEMAN_LEVEL="none"
    return 0
  fi

  # Map percentage to level
  if (( used_pct >= 85 )); then
    RESOLVED_CAVEMAN_LEVEL="ultra"
  elif (( used_pct >= 70 )); then
    RESOLVED_CAVEMAN_LEVEL="full"
  elif (( used_pct >= 50 )); then
    RESOLVED_CAVEMAN_LEVEL="lite"
  else
    RESOLVED_CAVEMAN_LEVEL="none"
  fi

  return 0
}
