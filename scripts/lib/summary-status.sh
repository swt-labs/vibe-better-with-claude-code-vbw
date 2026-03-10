#!/bin/bash
# summary-status.sh — Shared SUMMARY.md status enum, parser, and completion helpers
#
# Canonical status contract:
#   Valid terminal statuses: complete, partial, failed
#   "pending", "completed", "in_progress", etc. are NOT valid
#   SUMMARY.md must only be created with a valid terminal status
#
# Usage: source this file from any script that needs to check plan completion.
#   source "$CLAUDE_PLUGIN_ROOT/scripts/lib/summary-status.sh"

# Guard against double-sourcing
[ -n "${_VBW_SUMMARY_STATUS_LOADED:-}" ] && return 0
_VBW_SUMMARY_STATUS_LOADED=1

# Returns 0 if status is a valid terminal status, 1 otherwise
is_valid_summary_status() {
  local status="$1"
  case "$status" in
    complete|partial|failed) return 0 ;;
    *) return 1 ;;
  esac
}

# Returns 0 if status represents plan completion for progression purposes, 1 otherwise.
# "failed" is terminal but NOT a completion status — the plan was attempted but did not
# succeed, so it should not count toward phase progression.
is_completion_status() {
  local status="$1"
  case "$status" in
    complete|partial) return 0 ;;
    *) return 1 ;;
  esac
}

# Extract status from a SUMMARY.md file's YAML frontmatter.
# Outputs the lowercased status string on stdout, or empty string if not found.
# Exit code: 0 if valid terminal status found, 1 otherwise.
extract_summary_status() {
  local file="$1"
  [ ! -f "$file" ] && echo "" && return 1
  local status=""
  local in_fm=0
  while IFS= read -r line; do
    if [ "$line" = "---" ]; then
      if [ "$in_fm" -eq 0 ]; then in_fm=1; continue; else break; fi
    fi
    if [ "$in_fm" -eq 1 ]; then
      case "$line" in
        status:*)
          status=$(echo "$line" | cut -d: -f2- | sed 's/^ *//' | tr '[:upper:]' '[:lower:]')
          ;;
      esac
    fi
  done < "$file"
  echo "$status"
  is_valid_summary_status "$status"
}

# Check if a SUMMARY.md file represents a completed plan.
# Combines existence check + status validation for progression purposes.
# Returns 0 if file exists AND has a completion status (complete|partial), 1 otherwise.
is_plan_completed() {
  local summary_file="$1"
  [ ! -f "$summary_file" ] && return 1
  local status
  status=$(extract_summary_status "$summary_file")
  is_completion_status "$status"
}

# Check if a SUMMARY.md file has any valid terminal status (including failed).
# Use this when you need to know "was this plan finalized?" rather than
# "did this plan succeed?" For phase progression, use is_plan_completed instead.
is_plan_finalized() {
  local summary_file="$1"
  [ ! -f "$summary_file" ] && return 1
  local status
  status=$(extract_summary_status "$summary_file")
  is_valid_summary_status "$status"
}

# Count completed SUMMARY.md files in a phase directory.
# Only counts files with valid completion statuses (complete|partial).
count_completed_summaries() {
  local phase_dir="$1"
  local count=0
  local sf
  for sf in "$phase_dir"/*-SUMMARY.md; do
    [ ! -f "$sf" ] && continue
    if is_plan_completed "$sf"; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}

# Count finalized SUMMARY.md files in a phase directory.
# Counts files with any valid terminal status (complete|partial|failed).
count_finalized_summaries() {
  local phase_dir="$1"
  local count=0
  local sf
  for sf in "$phase_dir"/*-SUMMARY.md; do
    [ ! -f "$sf" ] && continue
    if is_plan_finalized "$sf"; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}
