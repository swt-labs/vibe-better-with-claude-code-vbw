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
# Scans both flat root and wave subdirs (P*-*-wave/).
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
  for f in "$dir"/P*-*-wave/*-SUMMARY.md; do
    [ -f "$f" ] || continue
    if is_summary_complete "$f"; then
      count=$((count + 1))
    fi
  done
  for f in "$dir"/remediation/P*-*-round/*-SUMMARY.md; do
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
# Scans both flat root and wave subdirs (P*-*-wave/).
count_done_summaries() {
  local dir="$1"
  local count=0
  local f st
  for f in "$dir"/*-SUMMARY.md; do
    [ -f "$f" ] || continue
    st=$(tr -d '\r' < "$f" 2>/dev/null | sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' | head -1 | tr -d '[:space:]')
    case "$st" in complete|completed|partial) count=$((count + 1)) ;; esac
  done
  for f in "$dir"/P*-*-wave/*-SUMMARY.md; do
    [ -f "$f" ] || continue
    st=$(tr -d '\r' < "$f" 2>/dev/null | sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' | head -1 | tr -d '[:space:]')
    case "$st" in complete|completed|partial) count=$((count + 1)) ;; esac
  done
  for f in "$dir"/remediation/P*-*-round/*-SUMMARY.md; do
    [ -f "$f" ] || continue
    st=$(tr -d '\r' < "$f" 2>/dev/null | sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' | head -1 | tr -d '[:space:]')
    case "$st" in complete|completed|partial) count=$((count + 1)) ;; esac
  done
  echo "$count"
}

# count_terminal_summaries DIR
# Returns count of SUMMARY.md files with any terminal status in DIR.
# Scans both flat root and wave subdirs (P*-*-wave/).
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
  for f in "$dir"/P*-*-wave/*-SUMMARY.md; do
    [ -f "$f" ] || continue
    if is_summary_terminal "$f"; then
      count=$((count + 1))
    fi
  done
  for f in "$dir"/remediation/P*-*-round/*-SUMMARY.md; do
    [ -f "$f" ] || continue
    if is_summary_terminal "$f"; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}

# count_phase_plans DIR
# Returns count of PLAN.md files in DIR, scanning flat root
# (legacy [0-9]*-PLAN.md), wave subdirs (P*-*-wave/*-PLAN.md),
# and remediation round dirs (remediation/P*-*-round/*-PLAN.md).
count_phase_plans() {
  local dir="$1"
  local count=0
  count=$(( $(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l) + \
            $(find "$dir" -path '*/P*-*-wave/*-PLAN.md' ! -name '.*' 2>/dev/null | wc -l) + \
            $(find "$dir" -path '*/remediation/P*-*-round/*-PLAN.md' ! -name '.*' 2>/dev/null | wc -l) ))
  echo "$count" | tr -d ' '
}

# count_phase_contexts DIR
# Returns count of CONTEXT.md files in DIR, scanning both flat root
# (legacy [0-9]*-CONTEXT.md) and wave subdirs (P*-*-wave/*-CONTEXT.md).
count_phase_contexts() {
  local dir="$1"
  local count=0
  count=$(( $(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | wc -l) + \
            $(find "$dir" -path '*/P*-*-wave/*-CONTEXT.md' ! -name '.*' 2>/dev/null | wc -l) ))
  echo "$count" | tr -d ' '
}

# Also count P-prefix CONTEXT at phase root (e.g., P01-CONTEXT.md from do_init)
# count_phase_contexts_any DIR
# Broader: includes P{NN}-CONTEXT.md at root level too.
count_phase_contexts_any() {
  local dir="$1"
  local count=0
  count=$(( $(find "$dir" -maxdepth 1 ! -name '.*' \( -name '[0-9]*-CONTEXT.md' -o -name 'P[0-9]*-CONTEXT.md' \) 2>/dev/null | wc -l) + \
            $(find "$dir" -path '*/P*-*-wave/*-CONTEXT.md' ! -name '.*' 2>/dev/null | wc -l) ))
  echo "$count" | tr -d ' '
}
