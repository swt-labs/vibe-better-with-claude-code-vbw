#!/usr/bin/env bash
# uat-utils.sh — Shared UAT helper functions for phase-detect, suggest-next,
# and prepare-reverification. Source this file; do not execute directly.
#
# Functions:
#   extract_status_value <file>   — Extract status value from YAML frontmatter
#                                   with body-level fallback for brownfield files.
#   latest_non_source_uat <dir>   — Find the latest canonical UAT file in a phase
#                                   directory, excluding SOURCE-UAT.md copies.
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

# count_uat_rounds — Count archived UAT round files in a phase directory.
#
# Scans for {phase_num}-UAT-round-*.md files, extracts the numeric round
# suffix from each, and prints the maximum round number found (0 if none).
# This is the single source of truth for round semantics — display round
# is count + 1 when active issues exist.
count_uat_rounds() {
  local dir="$1"
  local phase_num="$2"
  local max_round=0

  case "$dir" in
    */) ;;
    *) dir="$dir/" ;;
  esac

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

  printf '%d' "$max_round"
}

# extract_round_issue_ids — Extract test IDs that had "Result: issue" in a
# UAT round file. Prints one ID per line. Works on both archived round files
# and active UAT files.
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
