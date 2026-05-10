#!/usr/bin/env bash
# extract-uat-resume.sh — Extract UAT resume metadata from a phase directory.
# Usage: extract-uat-resume.sh <phase-dir>
#
# Outputs compact resume metadata so the LLM doesn't need to scan-parse
# the UAT file to find the resume point.
#
# Output formats:
#   uat_resume=none                           — no UAT file exists
#   uat_resume=all_done uat_completed=N uat_total=N — all tests have results
#   uat_resume=<test-id> uat_completed=N uat_total=N — resume at <test-id>
#     uat_resume_scenario=...                 — active product checkpoint scenario, when present
#     uat_resume_expected=...                 — active product checkpoint expected result, when present
#     uat_resume_deviation=...                — active summary-deviation review text, when present
#     uat_resume_source_plan=...              — active summary-deviation source plan, when present
#     uat_resume_source_summary=...           — active summary-deviation source summary, when present
#     uat_resume_deviation_signature=...      — active summary-deviation identity, when present

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared UAT helpers if available
if [ -f "$SCRIPT_DIR/uat-utils.sh" ]; then
  # shellcheck source=uat-utils.sh
  source "$SCRIPT_DIR/uat-utils.sh"
fi

PHASE_DIR="${1:?Usage: extract-uat-resume.sh <phase-dir>}"

if [ ! -d "$PHASE_DIR" ]; then
  echo "uat_resume=none"
  exit 0
fi

# Round-aware guard: when remediation state indicates a current round,
# check ONLY that round's UAT file. Do NOT fall back to previous rounds —
# stale resume data (e.g. all_done from round 01) would cause the model to
# STOP instead of generating fresh tests for round 02.
_state_file=""
if [ -f "${PHASE_DIR%/}/remediation/uat/.uat-remediation-stage" ]; then
  _state_file="${PHASE_DIR%/}/remediation/uat/.uat-remediation-stage"
elif [ -f "${PHASE_DIR%/}/remediation/.uat-remediation-stage" ]; then
  _state_file="${PHASE_DIR%/}/remediation/.uat-remediation-stage"
elif [ -f "${PHASE_DIR%/}/.uat-remediation-stage" ]; then
  _state_file="${PHASE_DIR%/}/.uat-remediation-stage"
fi
if [ -f "$_state_file" ]; then
  _layout=$(grep '^layout=' "$_state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  _round=$(grep '^round=' "$_state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  case "$_state_file" in
    */remediation/.uat-remediation-stage|*/.uat-remediation-stage)
      _layout="${_layout:-legacy}"
      _round="${_round:-01}"
      ;;
  esac
  if [ -n "$_round" ]; then
    _rr=$(printf '%02d' "$_round" 2>/dev/null) || _rr="$_round"
    case "${_layout:-round-dir}" in
      round-dir)
        _round_uat="${PHASE_DIR%/}/remediation/uat/round-${_rr}/R${_rr}-UAT.md"
        ;;
      legacy)
        _round_uat="${PHASE_DIR%/}/remediation/round-${_rr}/R${_rr}-UAT.md"
        ;;
      *)
        _round_uat=""
        ;;
    esac
    if [ -n "$_round_uat" ]; then
      if [ -f "$_round_uat" ]; then
        UAT_FILE="$_round_uat"
      else
        # Current round has no UAT yet — new round, not stale data
        echo "uat_resume=none"
        exit 0
      fi
    fi
  fi
fi

# Find the active UAT file (round-dir first, then phase-root fallback)
# Skipped when the round-dir guard above already resolved UAT_FILE.
if [ -z "${UAT_FILE:-}" ]; then
  if type current_uat &>/dev/null; then
    UAT_FILE=$(current_uat "$PHASE_DIR")
  elif type latest_non_source_uat &>/dev/null; then
    UAT_FILE=$(latest_non_source_uat "$PHASE_DIR")
  else
    UAT_FILE=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-UAT.md' ! -name '*SOURCE-UAT.md' 2>/dev/null | sort | tail -1)
  fi
fi

if [ -z "$UAT_FILE" ] || [ ! -f "$UAT_FILE" ]; then
  echo "uat_resume=none"
  exit 0
fi

# Parse all test entries: count total, find first without a result, and emit
# deterministic prompt-critical context for the active checkpoint.
awk '
  BEGIN {
    total=0
    completed=0
    first_incomplete=""
    cur_id=""
    cur_has_result=0
    last_field=""
  }

  function trim(v) {
    gsub(/\r/, "", v)
    sub(/^[[:space:]]+/, "", v)
    sub(/[[:space:]]+$/, "", v)
    return v
  }

  function flatten(v) {
    v = trim(v)
    gsub(/[[:space:]][[:space:]]+/, " ", v)
    return v
  }

  function field_value(line) {
    sub(/^- \*\*[^*]+:\*\*[[:space:]]*/, "", line)
    return flatten(line)
  }

  function normalize_result(raw,    val, upper, lower, i, c, pos, lval) {
    val = trim(raw)
    # Strip common decorators while preserving the literal template placeholder
    # {pass|skip|issue}, which must remain incomplete.
    gsub(/^[^a-zA-Z{]+/, "", val)
    gsub(/[^a-zA-Z}]+$/, "", val)

    upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    lower = "abcdefghijklmnopqrstuvwxyz"
    lval = ""
    for (i = 1; i <= length(val); i++) {
      c = substr(val, i, 1)
      pos = index(upper, c)
      if (pos > 0) c = substr(lower, pos, 1)
      lval = lval c
    }
    val = lval

    if (val == "" || val == "{pass|skip|issue}") return ""
    if (val ~ /^pass/) return "pass"
    if (val ~ /^skip/) return "skip"
    if (val ~ /^issue/ || val ~ /^fail/ || val ~ /^partial/) return "issue"
    return ""
  }

  function reset_current() {
    cur_scenario=""
    cur_expected=""
    cur_deviation=""
    cur_source_plan=""
    cur_source_summary=""
    cur_deviation_signature=""
    last_field=""
  }

  function append_to_last(line) {
    line = flatten(line)
    if (line == "" || last_field == "") {
      return
    }
    if (last_field == "scenario") cur_scenario = flatten(cur_scenario " " line)
    else if (last_field == "expected") cur_expected = flatten(cur_expected " " line)
    else if (last_field == "deviation") cur_deviation = flatten(cur_deviation " " line)
    else if (last_field == "source_plan") cur_source_plan = flatten(cur_source_plan " " line)
    else if (last_field == "source_summary") cur_source_summary = flatten(cur_source_summary " " line)
    else if (last_field == "deviation_signature") cur_deviation_signature = flatten(cur_deviation_signature " " line)
  }

  function snapshot_first_incomplete() {
    first_scenario = cur_scenario
    first_expected = cur_expected
    first_deviation = cur_deviation
    first_source_plan = cur_source_plan
    first_source_summary = cur_source_summary
    first_deviation_signature = cur_deviation_signature
  }

  function check_prev() {
    if (cur_id != "" && cur_has_result == 0 && first_incomplete == "") {
      first_incomplete = cur_id
      snapshot_first_incomplete()
    }
  }

  /^### (P[0-9]+(-T[0-9]+)?|PR[0-9]+-T[0-9]+|D[0-9]+)(:|[[:space:]])/ {
    # Before starting new test, check if previous test was incomplete
    check_prev()
    # Extract test ID: "### P01-T2: title" or "### D1: title"
    cur_id = $2
    sub(/:$/, "", cur_id)
    total++
    cur_has_result = 0
    reset_current()
    next
  }
  /^- \*\*Scenario:\*\*/ {
    if (cur_id == "") next
    cur_scenario = field_value($0)
    last_field = "scenario"
    next
  }
  /^- \*\*Expected:\*\*/ {
    if (cur_id == "") next
    cur_expected = field_value($0)
    last_field = "expected"
    next
  }
  /^- \*\*Deviation:\*\*/ {
    if (cur_id == "") next
    cur_deviation = field_value($0)
    last_field = "deviation"
    next
  }
  /^- \*\*Source Plan:\*\*/ {
    if (cur_id == "") next
    cur_source_plan = field_value($0)
    last_field = "source_plan"
    next
  }
  /^- \*\*Source Summary:\*\*/ {
    if (cur_id == "") next
    cur_source_summary = field_value($0)
    last_field = "source_summary"
    next
  }
  /^- \*\*Deviation Signature:\*\*/ {
    if (cur_id == "") next
    cur_deviation_signature = field_value($0)
    last_field = "deviation_signature"
    next
  }
  /^- \*\*Result:\*\*/ {
    if (cur_id == "") next
    val = $0
    sub(/^- \*\*Result:\*\*[[:space:]]*/, "", val)
    if (normalize_result(val) != "") {
      cur_has_result = 1
      completed++
    }
    last_field = ""
    next
  }
  /^- \*\*/ {
    last_field = ""
    next
  }
  /^## / {
    # End of tests section — check last test
    check_prev()
    cur_id = ""
    cur_has_result = 0
    reset_current()
    last_field = ""
    next
  }
  /^[[:space:]]*$/ {
    last_field = ""
    next
  }
  {
    if (cur_id == "") next
    append_to_last($0)
  }
  END {
    # Check last test if file ends without ## section
    check_prev()
    if (total == 0) {
      printf "uat_resume=none\n"
    } else if (completed >= total) {
      printf "uat_resume=all_done uat_completed=%d uat_total=%d\n", completed, total
    } else if (first_incomplete != "") {
      printf "uat_resume=%s uat_completed=%d uat_total=%d\n", first_incomplete, completed, total
      if (first_deviation != "" || first_source_plan != "" || first_source_summary != "" || first_deviation_signature != "") {
        if (first_deviation != "") printf "uat_resume_deviation=%s\n", first_deviation
        if (first_source_plan != "") printf "uat_resume_source_plan=%s\n", first_source_plan
        if (first_source_summary != "") printf "uat_resume_source_summary=%s\n", first_source_summary
        if (first_deviation_signature != "") printf "uat_resume_deviation_signature=%s\n", first_deviation_signature
      } else {
        if (first_scenario != "") printf "uat_resume_scenario=%s\n", first_scenario
        if (first_expected != "") printf "uat_resume_expected=%s\n", first_expected
      }
    } else {
      printf "uat_resume=all_done uat_completed=%d uat_total=%d\n", completed, total
    }
  }
' "$UAT_FILE"
