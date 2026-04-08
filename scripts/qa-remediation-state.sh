#!/usr/bin/env bash
# qa-remediation-state.sh — Track QA remediation chain progress on disk.
#
# Persists the current stage of the plan → execute → verify chain so that
# the orchestrator can resume correctly after compaction or session restart.
#
# Usage:
#   qa-remediation-state.sh get         <phase-dir>   → prints current stage + metadata
#   qa-remediation-state.sh advance     <phase-dir>   → advances to next stage
#   qa-remediation-state.sh reset       <phase-dir>   → removes state file
#   qa-remediation-state.sh init        <phase-dir>   → initializes for QA remediation
#   qa-remediation-state.sh needs-round <phase-dir>   → starts a new remediation round
#
# Stages: plan → execute → verify → done
#   (no research/discuss — VERIFICATION.md failures are the input)
#
# Remediation artifacts live in {phase-dir}/remediation/qa/round-{RR}/ with
# R{RR}-PLAN.md, R{RR}-SUMMARY.md naming.
# State file: {phase-dir}/remediation/qa/.qa-remediation-stage (key=value pairs).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CMD="${1:-}"
PHASE_DIR="${2:-}"

if [ -z "$CMD" ] || [ -z "$PHASE_DIR" ]; then
  echo "Usage: qa-remediation-state.sh <get|get-or-init|advance|reset|init|needs-round> <phase-dir>" >&2
  exit 1
fi

# Milestone path guard: refuse to operate on archived milestones.
case "$PHASE_DIR" in
  */.vbw-planning/milestones/*|.vbw-planning/milestones/*)
    echo "Error: refusing to operate on archived milestone path: $PHASE_DIR" >&2
    echo "QA remediation must target active phases in .vbw-planning/phases/" >&2
    exit 1
    ;;
esac

STATE_FILE="$PHASE_DIR/remediation/qa/.qa-remediation-stage"

# QA remediation stages: plan → execute → verify → done
STAGES=("plan" "execute" "verify" "done")

count_fail_rows_in_verification() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || { echo 0; return; }
  awk -F'|' '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    !/^\|/ { header_found = 0; next }
    /^\|/ {
      if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
      if (!header_found) {
        status_col = 0
        for (i = 2; i < NF; i++) {
          cell = trim($i)
          if (cell == "Status") status_col = i
        }
        if (status_col > 0) header_found = 1
        next
      }
      if (status_col > 0) {
        status = trim($(status_col))
        gsub(/\*+/, "", status)
        status = trim(status)
        if (status == "FAIL") count++
      }
    }
    END { print count + 0 }
  ' "$file_path" 2>/dev/null
}

count_pre_existing_issues_in_verification() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || { echo 0; return; }
  awk -F'|' '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    /^## Pre-existing Issues/ { found = 1; next }
    found && /^## / { exit }
    found && /^\|/ {
      if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
      test = trim($2)
      file = trim($3)
      if (tolower(test) == "test" && tolower(file) == "file") next
      if (test != "") count++
    }
    END { print count + 0 }
  ' "$file_path" 2>/dev/null
}

get_stage() {
  if [ -f "$STATE_FILE" ]; then
    local _val
    local _stage
    _val=$(grep '^stage=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
    _val="${_val:-none}"
    for _stage in "${STAGES[@]}"; do
      if [ "$_stage" = "$_val" ]; then
        echo "$_val"
        return 0
      fi
    done
    echo "none"
  else
    echo "none"
  fi
}

get_round() {
  if [ -f "$STATE_FILE" ]; then
    local _val
    _val=$(grep '^round=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
    echo "${_val:-01}"
  else
    echo "01"
  fi
}

get_round_started_at_commit() {
  if [ -f "$STATE_FILE" ]; then
    local _val
    _val=$(grep '^round_started_at_commit=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]' || true)
    echo "${_val:-}"
  else
    echo ""
  fi
}

capture_round_started_at_commit() {
  git -C "$PHASE_DIR" rev-parse HEAD 2>/dev/null || true
}

write_state() {
  local stage="$1"
  local round="$2"
  local round_started_at_commit="${3:-}"
  printf 'stage=%s\nround=%s\nround_started_at_commit=%s\n' "$stage" "$round" "$round_started_at_commit" > "$STATE_FILE"
}

canonicalize_round() {
  local round="$1"
  round="${round:-01}"
  if ! [[ "$round" =~ ^[0-9]+$ ]]; then
    round="01"
  fi
  printf '%02d' "$((10#$round))"
}

get_round_dir() {
  local round
  round=$(canonicalize_round "$(get_round)")
  echo "$PHASE_DIR/remediation/qa/round-${round}"
}

MAX_ROUNDS=3

validate_stage() {
  local stage="$1"
  for s in "${STAGES[@]}"; do
    [ "$s" = "$stage" ] && return 0
  done
  return 1
}

next_stage() {
  local current="$1"
  if ! validate_stage "$current"; then
    echo "Error: unknown stage: $current" >&2
    return 1
  fi
  local found=false
  for s in "${STAGES[@]}"; do
    if [ "$found" = true ]; then
      echo "$s"
      return 0
    fi
    if [ "$s" = "$current" ]; then
      found=true
    fi
  done
  # At end of chain (done) — stay at done
  echo "done"
}

start_new_round() {
  local current_stage current_round next_round next_round_padded round_started_at_commit
  current_stage=$(get_stage)
  # Only allow new round from verify or done — not from plan/execute
  case "$current_stage" in
    verify|done) ;;
    *)
      echo "Error: needs-round requires stage verify or done, got: $current_stage" >&2
      exit 1
      ;;
  esac
  current_round=$(get_round)
  # Guard: ensure round is numeric
  if ! [[ "$current_round" =~ ^[0-9]+$ ]]; then
    echo "Error: corrupt round value in state file: $current_round" >&2
    exit 1
  fi
  next_round=$(( 10#$current_round + 1 ))
  if [ "$next_round" -gt "$MAX_ROUNDS" ]; then
    echo "Error: max QA remediation rounds ($MAX_ROUNDS) exceeded" >&2
    exit 2
  fi
  next_round_padded=$(printf '%02d' "$next_round")
  mkdir -p "$PHASE_DIR/remediation/qa/round-${next_round_padded}"
  round_started_at_commit=$(capture_round_started_at_commit)
  write_state "plan" "$next_round_padded" "$round_started_at_commit"
  echo "plan"
  emit_metadata
}

emit_metadata() {
  local round round_dir source_verification_path round_started_at_commit
  local source_fail_count known_issues_path known_issues_status known_issues_count
  local phase_verification_path phase_pre_existing_issue_count current_round_verification_path current_stage
  local known_issues_meta input_mode
  round=$(canonicalize_round "$(get_round)")
  round_dir="$PHASE_DIR/remediation/qa/round-${round}"
  current_round_verification_path="$round_dir/R${round}-VERIFICATION.md"
  current_stage=$(get_stage)
  round_started_at_commit=$(get_round_started_at_commit)
  source_verification_path=$(bash "$SCRIPT_DIR/resolve-verification-path.sh" plan-input "$PHASE_DIR" 2>/dev/null || true)
  if [ -n "$source_verification_path" ] && [ ! -f "$source_verification_path" ]; then
    source_verification_path=""
  fi
  source_fail_count=0
  if [ -n "$source_verification_path" ] && [ -f "$source_verification_path" ]; then
    source_fail_count=$(count_fail_rows_in_verification "$source_verification_path")
  fi
  phase_verification_path=$(bash "$SCRIPT_DIR/resolve-verification-path.sh" phase "$PHASE_DIR" 2>/dev/null || true)
  if [ -n "$phase_verification_path" ] && [ ! -f "$phase_verification_path" ]; then
    phase_verification_path=""
  fi
  phase_pre_existing_issue_count=0
  if [ -n "$phase_verification_path" ] && [ -f "$phase_verification_path" ]; then
    phase_pre_existing_issue_count=$(count_pre_existing_issues_in_verification "$phase_verification_path")
  fi
  known_issues_path="$PHASE_DIR/known-issues.json"
  known_issues_status="missing"
  known_issues_count=0
  if [ -f "$SCRIPT_DIR/track-known-issues.sh" ]; then
    known_issues_meta=$(bash "$SCRIPT_DIR/track-known-issues.sh" status "$PHASE_DIR" 2>/dev/null || true)
    known_issues_path=$(printf '%s\n' "$known_issues_meta" | awk -F= '/^known_issues_path=/{print $2; exit}')
    known_issues_status=$(printf '%s\n' "$known_issues_meta" | awk -F= '/^known_issues_status=/{print $2; exit}')
    known_issues_count=$(printf '%s\n' "$known_issues_meta" | awk -F= '/^known_issues_count=/{print $2; exit}')
  fi
  known_issues_path="${known_issues_path:-$PHASE_DIR/known-issues.json}"
  known_issues_status="${known_issues_status:-missing}"
  known_issues_count="${known_issues_count:-0}"
  input_mode="none"
  if [ "${source_fail_count:-0}" -gt 0 ] 2>/dev/null && [ "${known_issues_count:-0}" -gt 0 ] 2>/dev/null; then
    input_mode="both"
  elif [ "${source_fail_count:-0}" -gt 0 ] 2>/dev/null; then
    input_mode="verification"
  elif [ "${known_issues_count:-0}" -gt 0 ] 2>/dev/null; then
    input_mode="known-issues"
  elif [ "${phase_pre_existing_issue_count:-0}" -gt 0 ] 2>/dev/null \
    && { [ "$current_stage" != "done" ] || [ ! -f "$current_round_verification_path" ]; }; then
    input_mode="known-issues"
  fi
  echo "round=${round}"
  echo "round_dir=${round_dir}"
  echo "round_started_at_commit=${round_started_at_commit}"
  echo "source_verification_path=${source_verification_path}"
  echo "source_fail_count=${source_fail_count}"
  echo "known_issues_path=${known_issues_path}"
  echo "known_issues_status=${known_issues_status}"
  echo "known_issues_count=${known_issues_count}"
  echo "phase_pre_existing_issue_count=${phase_pre_existing_issue_count}"
  echo "input_mode=${input_mode}"
  echo "plan_path=${round_dir}/R${round}-PLAN.md"
  echo "summary_path=${round_dir}/R${round}-SUMMARY.md"
  echo "verification_path=${round_dir}/R${round}-VERIFICATION.md"
}

case "$CMD" in
  get)
    stage=$(get_stage)
    echo "$stage"
    if [ "$stage" != "none" ]; then
      emit_metadata
    fi
    ;;

  init)
    # Create remediation directory and first round dir
    round_started_at_commit=$(capture_round_started_at_commit)
    mkdir -p "$PHASE_DIR/remediation/qa/round-01"
    write_state "plan" "01" "$round_started_at_commit"
    echo "plan"
    emit_metadata
    ;;

  advance)
    current=$(get_stage)
    if [ "$current" = "none" ]; then
      echo "Error: no QA remediation in progress" >&2
      exit 1
    fi
    next=$(next_stage "$current")
    round=$(get_round)
    round_started_at_commit=$(get_round_started_at_commit)

    # When advancing from verify, check result:
    # - If verify → done, that means QA passed
    # - The orchestrator reads VERIFICATION.md before calling advance
    write_state "$next" "$round" "$round_started_at_commit"
    echo "$next"
    emit_metadata
    ;;

  needs-round)
    # Start a new remediation round (QA failed again)
    start_new_round
    ;;

  get-or-init)
    stage=$(get_stage)
    if [ "$stage" = "none" ]; then
      round_started_at_commit=$(capture_round_started_at_commit)
      mkdir -p "$PHASE_DIR/remediation/qa/round-01"
      write_state "plan" "01" "$round_started_at_commit"
      echo "plan"
      emit_metadata
    else
      echo "$stage"
      emit_metadata
    fi
    ;;

  reset)
    rm -f "$STATE_FILE"
    echo "none"
    ;;

  *)
    echo "Error: unknown command: $CMD" >&2
    echo "Usage: qa-remediation-state.sh <get|get-or-init|advance|reset|init|needs-round> <phase-dir>" >&2
    exit 1
    ;;
esac
