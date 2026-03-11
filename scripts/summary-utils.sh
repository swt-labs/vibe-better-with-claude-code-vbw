#!/bin/bash
# summary-utils.sh -- shared helpers for status-aware SUMMARY.md checking
# Source this from scripts that need status-based completion detection.
# All functions are portable bash (3.2+), no external dependencies beyond sed.

# list_phase_plan_files DIR
# Emits PLAN.md files for a phase directory across flat root, wave subdirs,
# and remediation round dirs.
list_phase_plan_files() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  { find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null; \
    find "$dir" -maxdepth 2 -path '*/P*-*-wave/*-PLAN.md' ! -name '.*' 2>/dev/null; \
    find "$dir" -maxdepth 3 -path '*/remediation/P*-*-round/*-PLAN.md' ! -name '.*' 2>/dev/null; } | sort
}

# list_phase_summary_files DIR
# Emits SUMMARY.md files for a phase directory across flat root, wave subdirs,
# and remediation round dirs.
list_phase_summary_files() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  { find "$dir" -maxdepth 1 ! -name '.*' -name '*-SUMMARY.md' 2>/dev/null; \
    find "$dir" -maxdepth 2 -path '*/P*-*-wave/*-SUMMARY.md' ! -name '.*' 2>/dev/null; \
    find "$dir" -maxdepth 3 -path '*/remediation/P*-*-round/*-SUMMARY.md' ! -name '.*' 2>/dev/null; } | sort
}

# frontmatter_scalar_value FILE KEY
# Reads a simple scalar from YAML frontmatter and strips surrounding quotes.
frontmatter_scalar_value() {
  local f="$1"
  local key="$2"
  [ -f "$f" ] || return 0
  awk -v key="$key" '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^[^[:space:]]/ && $0 ~ "^" key ":[[:space:]]*" {
      line = $0
      sub("^" key ":[[:space:]]*", "", line)
      print line
      exit
    }
  ' "$f" 2>/dev/null | sed "s/^[\"']//; s/[\"']$//" || true
}

# plan_contract_numbers FILE
# Emits "<phase>|<plan>" for a PLAN.md file, preferring frontmatter phase/plan
# so migrated remediation files keep their original plan ordinal.
plan_contract_numbers() {
  local plan_file="$1"
  local basename phase plan
  basename=$(basename "$plan_file" 2>/dev/null) || basename="$plan_file"

  phase=$(frontmatter_scalar_value "$plan_file" phase)
  plan=$(frontmatter_scalar_value "$plan_file" plan)

  if [ -z "$phase" ]; then
    case "$basename" in
      P[0-9]*-R[0-9]*-*|P[0-9]*-W[0-9]*-*) phase=$(echo "$basename" | sed 's/^P\([0-9]*\)-.*/\1/') ;;
      *) phase=$(echo "$basename" | sed 's/^\([0-9]*\)-.*/\1/') ;;
    esac
  fi

  if [ -z "$plan" ]; then
    case "$basename" in
      P[0-9]*-R[0-9]*-*) plan=$(echo "$basename" | sed 's/^P[0-9]*-R\([0-9]*\)-.*/\1/') ;;
      P[0-9]*-W[0-9]*-*) plan=$(echo "$basename" | sed 's/^P[0-9]*-W[0-9]*-\([0-9]*\)-.*/\1/') ;;
      *) plan=$(echo "$basename" | sed 's/^[0-9]*-\([0-9]*\)-.*/\1/') ;;
    esac
  fi

  printf '%s|%s\n' "$phase" "$plan"
}

# summary_status_value FILE_PATH
# Emits the normalized status from SUMMARY frontmatter, or nothing if absent.
summary_status_value() {
  local f="$1"
  [ -f "$f" ] || return 1
  tr -d '\r' < "$f" 2>/dev/null | sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' | head -1 | tr -d '[:space:]'
}

# is_summary_complete FILE_PATH
# Returns 0 if SUMMARY exists and has terminal-complete status, 1 otherwise.
# "complete" and "completed" are both accepted as terminal-complete.
# "partial" and "failed" are terminal but NOT complete.
is_summary_complete() {
  local f="$1"
  [ -f "$f" ] || return 1
  local status
  status=$(summary_status_value "$f")
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
  status=$(summary_status_value "$f")
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
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if is_summary_complete "$f"; then
      count=$((count + 1))
    fi
  done < <(list_phase_summary_files "$dir")
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
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    st=$(summary_status_value "$f")
    case "$st" in complete|completed|partial) count=$((count + 1)) ;; esac
  done < <(list_phase_summary_files "$dir")
  echo "$count"
}

# count_terminal_summaries DIR
# Returns count of SUMMARY.md files with any terminal status in DIR.
# Scans both flat root and wave subdirs (P*-*-wave/).
count_terminal_summaries() {
  local dir="$1"
  local count=0
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if is_summary_terminal "$f"; then
      count=$((count + 1))
    fi
  done < <(list_phase_summary_files "$dir")
  echo "$count"
}

# count_phase_plans DIR
# Returns count of PLAN.md files in DIR, scanning flat root
# (legacy [0-9]*-PLAN.md), wave subdirs (P*-*-wave/*-PLAN.md),
# and remediation round dirs (remediation/P*-*-round/*-PLAN.md).
count_phase_plans() {
  local dir="$1"
  list_phase_plan_files "$dir" | wc -l | tr -d ' '
}

# count_phase_contexts DIR
# Returns count of CONTEXT.md files in DIR, scanning both flat root
# (legacy [0-9]*-CONTEXT.md) and wave subdirs (P*-*-wave/*-CONTEXT.md).
count_phase_contexts() {
  local dir="$1"
  local count=0
  count=$(( $(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | wc -l) + \
            $(find "$dir" -maxdepth 2 -path '*/P*-*-wave/*-CONTEXT.md' ! -name '.*' 2>/dev/null | wc -l) ))
  echo "$count" | tr -d ' '
}

# Also count P-prefix CONTEXT at phase root (e.g., P01-CONTEXT.md from do_init)
# count_phase_contexts_any DIR
# Broader: includes P{NN}-CONTEXT.md at root level too.
count_phase_contexts_any() {
  local dir="$1"
  local count=0
  count=$(( $(find "$dir" -maxdepth 1 ! -name '.*' \( -name '[0-9]*-CONTEXT.md' -o -name 'P[0-9]*-CONTEXT.md' \) 2>/dev/null | wc -l) + \
            $(find "$dir" -maxdepth 2 -path '*/P*-*-wave/*-CONTEXT.md' ! -name '.*' 2>/dev/null | wc -l) ))
  echo "$count" | tr -d ' '
}
