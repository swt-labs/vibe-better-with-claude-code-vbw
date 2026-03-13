#!/usr/bin/env bash
# uat-utils.sh — Shared UAT helper functions for phase-detect, suggest-next,
# and prepare-reverification. Source this file; do not execute directly.
#
# Functions:
#   extract_status_value <file>   — Extract status value from YAML frontmatter
#                                   with body-level fallback for brownfield files.
#   latest_non_source_uat <dir>   — Find the latest canonical UAT file in a phase
#                                   directory, excluding SOURCE-UAT.md copies.
#   current_uat <dir>             — Find the active UAT file (round-dir first,
#                                   then phase-root fallback).
#   count_uat_rounds <dir> <num>  — Count existing {num}-UAT-round-*.md files
#                                   in a phase directory. Returns max round number.

# Guard: prevent accidental direct execution
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Error: uat-utils.sh must be sourced, not executed directly" >&2
  exit 1
fi

# extract_status_value — Extract 'status:' value from a markdown file.
#
# Priority: YAML frontmatter (between --- delimiters at file start).
# Fallback: first unindented 'status:' line in the body. The body fallback
# requires the line to start at column 0 (no leading whitespace) to avoid
# matching indented prose, markdown list items, or table rows that happen
# to contain 'status:'.
extract_status_value() {
  local file="$1"
  local result
  # Try frontmatter first
  result=$(awk '
    BEGIN { in_fm = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && tolower($0) ~ /^[[:space:]]*status[[:space:]]*:/ {
      value = $0
      sub(/^[^:]*:[[:space:]]*/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      gsub(/^[\"]/,  "", value); gsub(/[\"]/,  "", value)
      gsub(/^'"'"'/, "", value); gsub(/'"'"'$/, "", value)
      print tolower(value)
      exit
    }
  ' "$file" 2>/dev/null || true)
  # Fallback: scan body for unindented status: line (brownfield/manual UATs)
  # Only accept known status values to avoid matching prose like "Status: The system works"
  if [ -z "$result" ]; then
    result=$(awk '
      tolower($0) ~ /^status[[:space:]]*:/ {
        value = $0
        sub(/^[^:]*:[[:space:]]*/, "", value)
        gsub(/[[:space:]]+$/, "", value)
        v = tolower(value)
        if (v == "issues_found" || v == "complete" || v == "passed" || v == "in_progress" || v == "pending" || v == "failed" || v == "aborted") {
          print v
          exit
        }
      }
    ' "$file" 2>/dev/null || true)
  fi
  printf '%s' "$result"
}

# latest_non_source_uat — Find the latest [0-9]*-UAT.md file in a directory,
# excluding SOURCE-UAT.md files (verbatim copies from milestone remediation).
#
# Compares numeric prefixes to handle both zero-padded (01, 02) and unpadded
# (1, 2, 10) numbering correctly. Returns empty string (and exit 0) if no
# matching file exists.
latest_non_source_uat() {
  local dir="$1"
  local latest=""
  local latest_num=-1

  case "$dir" in
    */) ;;
    *) dir="$dir/" ;;
  esac

  for f in "${dir}"[0-9]*-UAT.md; do
    [ -f "$f" ] || continue
    case "$f" in *SOURCE-UAT.md) continue ;; esac
    # Extract numeric prefix from basename (e.g., "01" from "01-UAT.md")
    local bname num
    bname=$(basename "$f")
    num=$(echo "$bname" | sed 's/^\([0-9]*\).*/\1/' | sed 's/^0*//')
    num=${num:-0}
    if [ "$num" -gt "$latest_num" ] 2>/dev/null; then
      latest_num=$num
      latest="$f"
    fi
  done

  if [ -n "$latest" ]; then
    printf '%s\n' "$latest"
  fi
  return 0
}

# count_uat_rounds — Count remediation rounds in both flat and round-dir layouts.
#
# Flat layout: scans for {phase_num}-UAT-round-*.md files at phase root.
# Round-dir layout: scans for remediation/round-*/R*-UAT.md files.
# Returns the maximum round number found across both locations (0 if none).
count_uat_rounds() {
  local dir="$1"
  local phase_num="$2"
  local max_round=0

  case "$dir" in
    */) ;;
    *) dir="$dir/" ;;
  esac

  # Flat layout: {phase_num}-UAT-round-{NN}.md
  for rf in "${dir}${phase_num}"-UAT-round-*.md; do
    [ -f "$rf" ] || continue
    local round_num
    round_num=$(basename "$rf" | sed "s/^${phase_num}-UAT-round-0*\\([0-9]*\\)\\.md$/\\1/")
    if [ -n "$round_num" ] && echo "$round_num" | grep -qE '^[0-9]+$'; then
      if [ "$round_num" -gt "$max_round" ] 2>/dev/null; then
        max_round="$round_num"
      fi
    fi
  done

  # Round-dir layout: remediation/round-{NN}/R{NN}-UAT.md
  for rf in "${dir}"remediation/round-*/R*-UAT.md; do
    [ -f "$rf" ] || continue
    local rr_num
    rr_num=$(basename "$rf" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
    if [ -n "$rr_num" ] && echo "$rr_num" | grep -qE '^[0-9]+$'; then
      if [ "$rr_num" -gt "$max_round" ] 2>/dev/null; then
        max_round="$rr_num"
      fi
    fi
  done

  printf '%d' "$max_round"
}

# extract_round_issue_ids — Extract test IDs that had "Result: issue" in a
# UAT round file. Prints one ID per line. Works on both archived round files
# (flat layout) and round-dir UAT files (R{RR}-UAT.md).
extract_round_issue_ids() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    /^### [PD][0-9]/ {
      id = $2
      sub(/:$/, "", id)
      has_issue = 0
      next
    }
    /^- \*\*Result:\*\*[[:space:]]*issue/ {
      print id
    }
  ' "$file"
}

# current_uat — Find the active UAT file, checking round-dir layout first.
#
# If the phase has a round-dir remediation layout with an R{RR}-UAT.md in the
# current round directory, returns that path. Otherwise falls back to
# latest_non_source_uat() (phase-root UAT).
#
# Same contract as latest_non_source_uat: returns a filepath string if found,
# empty string if not, exit 0 always.
current_uat() {
  local dir="$1"

  case "$dir" in
    */) ;;
    *) dir="$dir/" ;;
  esac

  # Check round-dir remediation state
  local state_file="${dir}remediation/.uat-remediation-stage"
  if [ -f "$state_file" ]; then
    local layout round rr
    layout=$(grep '^layout=' "$state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    round=$(grep '^round=' "$state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$layout" = "round-dir" ] && [ -n "$round" ]; then
      rr=$(printf '%02d' "$round" 2>/dev/null) || rr="$round"
      local round_uat="${dir}remediation/round-${rr}/R${rr}-UAT.md"
      if [ -f "$round_uat" ]; then
        printf '%s\n' "$round_uat"
        return 0
      fi
      # Current round's UAT doesn't exist yet (start of new round).
      # Scan all round dirs for the latest existing R{NN}-UAT.md.
      local _prev_best="" _prev_best_num=-1
      for _ruat in "${dir}"remediation/round-*/R*-UAT.md; do
        [ -f "$_ruat" ] || continue
        local _rnum
        _rnum=$(basename "$_ruat" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
        if [ -n "$_rnum" ] && echo "$_rnum" | grep -qE '^[0-9]+$'; then
          if [ "$_rnum" -gt "$_prev_best_num" ] 2>/dev/null; then
            _prev_best_num=$_rnum
            _prev_best="$_ruat"
          fi
        fi
      done
      if [ -n "$_prev_best" ]; then
        printf '%s\n' "$_prev_best"
        return 0
      fi
    fi
  fi

  # Fall back to phase-root UAT
  latest_non_source_uat "${dir%/}"
}
