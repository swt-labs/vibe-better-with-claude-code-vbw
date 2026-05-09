#!/usr/bin/env bash
# uat-utils.sh — Shared UAT helper functions for phase-detect, suggest-next,
# and prepare-reverification. Source this file; do not execute directly.
#
# Functions:
#   normalize_uat_status <value>  — Map LLM-generated UAT status synonyms to
#                                   canonical values (complete, issues_found, etc.).
#   extract_status_value <file>   — Extract status value from YAML frontmatter
#                                   with body-level fallback for brownfield files.
#                                   Applies normalize_uat_status automatically.
#   uat_file_status_class <file>  — Classify a UAT file as complete,
#                                   issues_found, active, or none.
#   current_uat_status_class <dir> — Classify the active UAT for a phase dir.
#   current_uat_blocks_phase_completion <dir>
#                                — True when the active UAT prevents phase
#                                  completion/archive.
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

# normalize_uat_status — Map LLM-generated UAT status synonyms to canonical values.
#
# The UAT template defines: in_progress, complete, issues_found.
# LLMs sometimes write semantically equivalent but non-canonical values
# (e.g., "all_pass", "passed", "verified"). Without normalization, downstream
# consumers (phase-detect, prepare-reverification, state-updater) fail to
# recognize these as terminal statuses, causing mis-routing.
#
# Canonical terminal statuses: complete, issues_found
# Canonical non-terminal: in_progress, pending
normalize_uat_status() {
  local raw="${1:-}"
  case "$raw" in
    all_pass|passed|pass|all_passed|verified|no_issues) echo "complete" ;;
    failed) echo "issues_found" ;;
    *) echo "$raw" ;;
  esac
}

# extract_status_value — Extract 'status:' value from a markdown file.
#
# Priority: YAML frontmatter (between --- delimiters at file start).
# Fallback: first unindented 'status:' line in the body. The body fallback
# requires the line to start at column 0 (no leading whitespace) to avoid
# matching indented prose, markdown list items, or table rows that happen
# to contain 'status:'.
#
# UAT files: the extracted value is passed through normalize_uat_status() to
# map LLM synonyms (all_pass, passed, verified, failed, etc.) to canonical
# values. SUMMARY files use their own extraction path in summary-utils.sh
# which never calls normalize_uat_status(), so these mappings are UAT-only.
_extract_uat_status_value() {
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
        if (v == "issues_found" || v == "complete" || v == "passed" || v == "in_progress" || v == "pending" || v == "failed" || v == "aborted" || v == "all_pass" || v == "all_passed" || v == "pass" || v == "verified" || v == "no_issues") {
          print v
          exit
        }
      }
    ' "$file" 2>/dev/null || true)
  fi
  printf '%s' "$result"
}

extract_status_value() {
  local file="$1" result
  result=$(_extract_uat_status_value "$file")
  result=$(normalize_uat_status "$result")
  printf '%s' "$result"
}

# uat_status_class — Classify a normalized or raw UAT status value.
#
# Completion/archive is allowed only for explicit passing terminal statuses.
# `issues_found` is a terminal UAT result that requires remediation.
# Empty raw input maps to `none`; callers deciding phase completion/archive from
# an artifact must use uat_file_status_class(), current_uat_status_class(), or
# current_uat_blocks_phase_completion() instead. Those file-aware helpers treat
# remediation round UAT files and artifacts with a blank frontmatter `status:`
# key as `active`, while preserving legacy `none` for phase-root files with no
# authoritative status key.
# Unrecognized and non-terminal raw statuses mean active verification is still
# authoritative and must block phase completion when used by file-aware callers.
uat_status_class() {
  local status
  status=$(normalize_uat_status "${1:-}")
  case "$status" in
    "")
      printf '%s\n' "none"
      ;;
    complete)
      printf '%s\n' "complete"
      ;;
    issues_found)
      printf '%s\n' "issues_found"
      ;;
    *)
      printf '%s\n' "active"
      ;;
  esac
}

# uat_file_status_value — Extract and normalize UAT status directly.
#
# This intentionally does not call extract_status_value(), because some callers
# validate behavior when that legacy function is degraded or locally overridden.
# The classification contract must remain tied to the artifact content itself.
uat_file_status_value() {
  local file="$1" result
  [ -f "$file" ] || return 1
  result=$(_extract_uat_status_value "$file")
  result=$(normalize_uat_status "$result")
  printf '%s' "$result"
}

uat_file_has_frontmatter_status_key() {
  local file="$1"
  [ -f "$file" ] || return 1
  awk '
    BEGIN { in_fm = 0; found = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && tolower($0) ~ /^[[:space:]]*status[[:space:]]*:/ {
      found = 1
      exit
    }
    END { exit(found ? 0 : 1) }
  ' "$file" 2>/dev/null
}

uat_file_is_remediation_round_uat() {
  case "$1" in
    */remediation/uat/round-*/R*-UAT.md|*/remediation/round-*/R*-UAT.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# uat_file_status_class — Classify a concrete UAT artifact.
#
# Existing remediation round UAT artifacts are authoritative blockers even when
# their status is missing or blank, so they classify as `active`. A blank
# frontmatter `status:` key is also an explicit active blocker. Brownfield
# phase-root UAT files with no authoritative status key remain `none`, preserving
# degraded legacy behavior where ignored prose/body status mentions do not block
# completion by themselves.
uat_file_status_class() {
  local file="$1" status
  [ -f "$file" ] || { printf '%s\n' "none"; return 0; }
  status=$(uat_file_status_value "$file")
  if [ -n "$status" ]; then
    uat_status_class "$status"
  elif uat_file_has_frontmatter_status_key "$file" || uat_file_is_remediation_round_uat "$file"; then
    printf '%s\n' "active"
  else
    printf '%s\n' "none"
  fi
}

uat_status_class_blocks_completion() {
  case "${1:-none}" in
    issues_found|active) return 0 ;;
    *) return 1 ;;
  esac
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
# Round-dir layout: scans for remediation/uat/round-*/R*-UAT.md files.
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

  # Round-dir layout: remediation/uat/round-{NN}/R{NN}-UAT.md
  for rf in "${dir}"remediation/uat/round-*/R*-UAT.md; do
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

# uat_phase_num_for_dir — Extract the numeric phase prefix from a phase dir.
uat_phase_num_for_dir() {
  local phase_dir="$1" phase_basename phase_num

  phase_basename=$(basename "$phase_dir")
  phase_num=$(printf '%s\n' "$phase_basename" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
  printf '%s' "$phase_num"
}

# uat_infer_legacy_current_round — Infer current legacy remediation round.
#
# Legacy single-word or phase-root state predates explicit round-dir metadata.
# When archived UAT rounds exist, the current working round is the next round;
# otherwise it is round 01.
uat_infer_legacy_current_round() {
  local phase_dir="$1" phase_num archived_rounds current_round

  phase_num=$(uat_phase_num_for_dir "$phase_dir")
  if [ -z "$phase_num" ]; then
    echo "01"
    return 0
  fi

  archived_rounds=$(count_uat_rounds "$phase_dir" "$phase_num")
  if [[ "$archived_rounds" =~ ^[0-9]+$ ]] && [ "$archived_rounds" -gt 0 ] 2>/dev/null; then
    current_round=$((archived_rounds + 1))
    printf '%02d\n' "$current_round"
    return 0
  fi

  echo "01"
}

# uat_resolve_legacy_round — Resolve stored legacy metadata to current round.
#
# Stored rounds greater than 1 are explicit and win. Missing, invalid, or stale
# round-01 metadata is inferred from archived UAT artifacts for brownfield
# compatibility.
uat_resolve_legacy_round() {
  local phase_dir="$1" stored_round="${2:-}" stored_num

  stored_num=$(printf '%s\n' "$stored_round" | sed 's/^0*//')
  stored_num="${stored_num:-0}"

  if [ "$stored_num" -gt 1 ] 2>/dev/null; then
    printf '%02d\n' "$stored_num"
    return 0
  fi

  uat_infer_legacy_current_round "$phase_dir"
}

# extract_round_issue_ids — Extract test IDs that had "Result: issue" in a
# UAT round file. Prints one ID per line. Works on both archived round files
# (flat layout) and round-dir UAT files (R{RR}-UAT.md).
extract_round_issue_ids() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    function tolower_str(s,    i, c, out, upper, lower, pos) {
      upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      lower = "abcdefghijklmnopqrstuvwxyz"
      out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        pos = index(upper, c)
        if (pos > 0)
          c = substr(lower, pos, 1)
        out = out c
      }
      return out
    }
    /^### (P[0-9]+(-T[0-9]+)?|PR[0-9]+-T[0-9]+|D[0-9]+)(:|[[:space:]])/ {
      id = $2
      sub(/:$/, "", id)
      has_issue = 0
      next
    }
    /^- \*\*Result:\*\*/ {
      val = $0
      sub(/^- \*\*Result:\*\*[[:space:]]*/, "", val)
      gsub(/[[:space:]]+$/, "", val)
      lval = tolower_str(val)
      if (lval ~ /^(issue|fail|failed|partial)/) {
        print id
      }
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

  # Check remediation state (new location first, then brownfield legacy paths)
  local state_file=""
  if [ -f "${dir}remediation/uat/.uat-remediation-stage" ]; then
    state_file="${dir}remediation/uat/.uat-remediation-stage"
  elif [ -f "${dir}remediation/.uat-remediation-stage" ]; then
    state_file="${dir}remediation/.uat-remediation-stage"
  elif [ -f "${dir}.uat-remediation-stage" ]; then
    state_file="${dir}.uat-remediation-stage"
  fi
  if [ -f "$state_file" ]; then
    local layout round rr
    layout=$(grep '^layout=' "$state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    round=$(grep '^round=' "$state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    case "$state_file" in
      */remediation/.uat-remediation-stage|*/.uat-remediation-stage)
        layout="${layout:-legacy}"
        round="${round:-01}"
        ;;
    esac
    if [ "$layout" = "round-dir" ] && [ -n "$round" ]; then
      rr=$(printf '%02d' "$round" 2>/dev/null) || rr="$round"
      local round_uat="${dir}remediation/uat/round-${rr}/R${rr}-UAT.md"
      if [ -f "$round_uat" ]; then
        printf '%s\n' "$round_uat"
        return 0
      fi
      # Current round's UAT doesn't exist yet (start of new round).
      # Scan all round dirs for the latest existing R{NN}-UAT.md.
      local _prev_best="" _prev_best_num=-1
      for _ruat in "${dir}"remediation/uat/round-*/R*-UAT.md; do
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
    elif [ "$layout" = "legacy" ] && [ -n "$round" ]; then
      rr=$(printf '%02d' "$round" 2>/dev/null) || rr="$round"
      local legacy_round_uat="${dir}remediation/round-${rr}/R${rr}-UAT.md"
      if [ -f "$legacy_round_uat" ]; then
        printf '%s\n' "$legacy_round_uat"
        return 0
      fi
      local _legacy_best="" _legacy_best_num=-1
      for _legacy_uat in "${dir}"remediation/round-*/R*-UAT.md; do
        [ -f "$_legacy_uat" ] || continue
        local _legacy_num
        _legacy_num=$(basename "$_legacy_uat" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
        if [ -n "$_legacy_num" ] && echo "$_legacy_num" | grep -qE '^[0-9]+$'; then
          if [ "$_legacy_num" -gt "$_legacy_best_num" ] 2>/dev/null; then
            _legacy_best_num=$_legacy_num
            _legacy_best="$_legacy_uat"
          fi
        fi
      done
      if [ -n "$_legacy_best" ]; then
        printf '%s\n' "$_legacy_best"
        return 0
      fi
    fi
  fi

  # Fall back to phase-root UAT
  latest_non_source_uat "${dir%/}"
}

current_uat_status_class() {
  local dir="$1" uat_file
  uat_file=$(current_uat "$dir")
  [ -n "$uat_file" ] && [ -f "$uat_file" ] || { printf '%s\n' "none"; return 0; }
  uat_file_status_class "$uat_file"
}

current_uat_blocks_phase_completion() {
  local class
  class=$(current_uat_status_class "$1" 2>/dev/null || printf '%s\n' "none")
  uat_status_class_blocks_completion "$class"
}

current_uat_needs_remediation() {
  [ "$(current_uat_status_class "$1" 2>/dev/null || printf '%s\n' "none")" = "issues_found" ]
}

current_uat_needs_verification() {
  [ "$(current_uat_status_class "$1" 2>/dev/null || printf '%s\n' "none")" = "active" ]
}
