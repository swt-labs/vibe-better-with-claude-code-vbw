#!/bin/bash
# summary-utils.sh -- shared helpers for status-aware SUMMARY.md checking
# Source this from scripts that need status-based completion detection.
# All functions are portable bash (3.2+) with no external process dependencies
# on the hot path. This keeps summary counting stable under heavily parallel
# BATS runs where frequent fork/exec can intermittently fail.

trim_summary_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

extract_summary_status() {
  local f="$1"
  local line value
  local in_fm=false
  local saw_content=false
  local bom=$'\357\273\277'

  [ -f "$f" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"

    if [ "$saw_content" = false ]; then
      line="${line#"$bom"}"
      value=$(trim_summary_value "$line")
      if [ -z "$value" ]; then
        continue
      fi
      saw_content=true
      if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
        in_fm=true
        continue
      fi
      return 0
    fi

    if [ "$in_fm" = true ]; then
      if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
        return 0
      fi
      if [[ "$line" =~ ^[[:space:]]*status: ]]; then
        value="${line#*:}"
        value=$(trim_summary_value "$value")
        case "$value" in
          \"*\") value="${value#\"}"; value="${value%\"}" ;;
          \'*\') value="${value#\'}"; value="${value%\'}" ;;
        esac
        value=$(trim_summary_value "$value")
        printf '%s\n' "$value"
        return 0
      fi
    fi
  done < "$f"

  return 0
}

# is_summary_complete FILE_PATH
# Returns 0 if SUMMARY exists and has terminal-complete status, 1 otherwise.
# "complete" and "completed" are both accepted as terminal-complete.
# "partial" and "failed" are terminal but NOT complete.
is_summary_complete() {
  local f="$1"
  local status
  [ -f "$f" ] || return 1
  status=$(extract_summary_status "$f")
  case "$status" in
    complete|completed) return 0 ;;
    *) return 1 ;;
  esac
}

# is_summary_terminal FILE_PATH
# Returns 0 if SUMMARY exists and has any terminal status (complete|completed|partial|failed).
is_summary_terminal() {
  local f="$1"
  local status
  [ -f "$f" ] || return 1
  status=$(extract_summary_status "$f")
  case "$status" in
    complete|completed|partial|failed) return 0 ;;
    *) return 1 ;;
  esac
}

# count_complete_summaries DIR
# Returns count of SUMMARY.md files with terminal-complete status in DIR.
count_complete_summaries() {
  local dir="$1"
  local count=0
  local f
  for f in "$dir"/*-SUMMARY.md "$dir"/SUMMARY.md; do
    [ -f "$f" ] || continue
    if is_summary_complete "$f"; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}

# count_done_summaries DIR
# Returns count of SUMMARY.md files considered "done" for reconciliation:
# complete, completed, or partial (matching recover-state.sh's promotion of partial→complete).
count_done_summaries() {
  local dir="$1"
  local count=0
  local f st
  for f in "$dir"/*-SUMMARY.md "$dir"/SUMMARY.md; do
    [ -f "$f" ] || continue
    st=$(extract_summary_status "$f")
    case "$st" in complete|completed|partial) count=$((count + 1)) ;; esac
  done
  echo "$count"
}

# count_terminal_summaries DIR
# Returns count of SUMMARY.md files with any terminal status in DIR.
count_terminal_summaries() {
  local dir="$1"
  local count=0
  local f
  for f in "$dir"/*-SUMMARY.md "$dir"/SUMMARY.md; do
    [ -f "$f" ] || continue
    if is_summary_terminal "$f"; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}
