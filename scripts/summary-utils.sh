#!/bin/bash
# summary-utils.sh -- shared helpers for status-aware SUMMARY.md checking
# Source this from scripts that need status-based completion detection.
# All functions are portable bash (3.2+), no external dependencies beyond sed.

# is_summary_complete FILE_PATH
# Returns 0 if SUMMARY exists and has terminal-complete status, 1 otherwise.
# "complete" and "completed" are both accepted as terminal-complete.
# "partial" and "failed" are terminal but NOT complete.
is_summary_complete() {
  local f="$1"
  [ -f "$f" ] || return 1
  local status
  status=$(tr -d '\r' < "$f" 2>/dev/null | sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' | head -1 | tr -d '[:space:]')
  case "$status" in
    complete|completed) return 0 ;;
    *) return 1 ;;
  esac
}

# is_summary_terminal FILE_PATH
# Returns 0 if SUMMARY exists and has any terminal status (complete|completed|partial|failed).
is_summary_terminal() {
  local f="$1"
  [ -f "$f" ] || return 1
  local status
  status=$(tr -d '\r' < "$f" 2>/dev/null | sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' | head -1 | tr -d '[:space:]')
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
  for f in "$dir"/*-SUMMARY.md; do
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
  for f in "$dir"/*-SUMMARY.md; do
    [ -f "$f" ] || continue
    st=$(tr -d '\r' < "$f" 2>/dev/null | sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' | head -1 | tr -d '[:space:]')
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
  for f in "$dir"/*-SUMMARY.md; do
    [ -f "$f" ] || continue
    if is_summary_terminal "$f"; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}
