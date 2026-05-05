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
if [ -f "$SCRIPT_DIR/lib/vbw-config-root.sh" ]; then
  # shellcheck source=scripts/lib/vbw-config-root.sh
  source "$SCRIPT_DIR/lib/vbw-config-root.sh"
fi

CMD="${1:-}"
PHASE_DIR="${2:-}"

if [ -z "$CMD" ] || [ -z "$PHASE_DIR" ]; then
  echo "Usage: qa-remediation-state.sh <get|get-or-init|advance|reset|init|needs-round> <phase-dir>" >&2
  exit 1
fi

reject_milestone_phase_dir() {
  local phase_dir="$1"

  # Milestone path guard: refuse to operate on archived milestones.
  case "$phase_dir" in
    */.vbw-planning/milestones/*|.vbw-planning/milestones/*)
      echo "Error: refusing to operate on archived milestone path: $phase_dir" >&2
      echo "QA remediation must target active phases in .vbw-planning/phases/" >&2
      exit 1
      ;;
  esac
}

canonicalize_existing_or_parent() {
  local path="$1" parent base parent_real

  if [ -d "$path" ]; then
    (cd "$path" && pwd -P)
    return 0
  fi

  parent=$(dirname "$path")
  base=$(basename "$path")
  if parent_real=$(cd "$parent" 2>/dev/null && pwd -P); then
    printf '%s/%s\n' "$parent_real" "$base"
  else
    printf '%s\n' "$path"
  fi
}

translate_claude_sidechain_phase_candidate() {
  local candidate="$1" sidechain_root="${VBW_CLAUDE_SIDECHAIN_ROOT:-}" host_root="${VBW_CLAUDE_SIDECHAIN_HOST_ROOT:-}" rel_phase_path inferred_host_root

  # Primary: env-var mapping populated by vbw-config-root.sh when the shell CWD is inside a
  # Claude sidechain (e.g. .claude/worktrees/agent-*).
  if [ -n "$sidechain_root" ] && [ -n "$host_root" ] && [ -f "$host_root/.vbw-planning/config.json" ]; then
    case "$candidate" in
      "$sidechain_root"/.vbw-planning/phases/*)
        rel_phase_path="${candidate#"$sidechain_root"/.vbw-planning/phases/}"
        printf '%s/.vbw-planning/phases/%s\n' "$host_root" "$rel_phase_path"
        return 0
        ;;
    esac
  fi

  # Structural fallback: caller is running from the host CWD but passed an absolute sidechain
  # phase path directly (env vars not set because the hook fires only for sidechain CWD).
  # Infer the host root by stripping the /.claude/worktrees/agent-{id}/... suffix.
  case "$candidate" in
    */.claude/worktrees/agent-*/.vbw-planning/phases/*)
      inferred_host_root=$(printf '%s\n' "$candidate" | sed 's|/\.claude/worktrees/agent-[^/]*/.*||')
      if [ -n "$inferred_host_root" ] && [ -f "$inferred_host_root/.vbw-planning/config.json" ]; then
        rel_phase_path=$(printf '%s\n' "$candidate" | sed 's|.*/.claude/worktrees/agent-[^/]*/\.vbw-planning/phases/||')
        printf '%s/.vbw-planning/phases/%s\n' "$inferred_host_root" "$rel_phase_path"
        return 0
      fi
      ;;
  esac

  printf '%s\n' "$candidate"
}

normalize_active_phase_dir_root() {
  local candidate="$1" phase_root suffix phase_slug

  case "$candidate" in
    */.vbw-planning/phases/*)
      phase_root="${candidate%%/.vbw-planning/phases/*}"
      suffix="${candidate#*/.vbw-planning/phases/}"
      phase_slug="${suffix%%/*}"
      if [ -z "$phase_root" ] || [ -z "$phase_slug" ]; then
        echo "Error: QA remediation phase must include an active phase slug: $candidate" >&2
        exit 1
      fi
      printf '%s/.vbw-planning/phases/%s\n' "$phase_root" "$phase_slug"
      ;;
    *)
      printf '%s\n' "$candidate"
      ;;
  esac
}

canonicalize_phase_dir() {
  local raw_phase_dir="$1" candidate phase_root

  if type find_vbw_root >/dev/null 2>&1; then
    find_vbw_root "$SCRIPT_DIR" >/dev/null 2>&1 || true
  fi

  case "$raw_phase_dir" in
    /*) candidate="$raw_phase_dir" ;;
    *)  candidate="${VBW_CONFIG_ROOT:-$(pwd -P)}/$raw_phase_dir" ;;
  esac

  candidate=$(canonicalize_existing_or_parent "$candidate")
  candidate=$(translate_claude_sidechain_phase_candidate "$candidate")
  candidate=$(canonicalize_existing_or_parent "$candidate")
  candidate=$(normalize_active_phase_dir_root "$candidate")
  candidate=$(canonicalize_existing_or_parent "$candidate")
  reject_milestone_phase_dir "$candidate"

  case "$candidate" in
    */.vbw-planning/phases/*) ;;
    *)
      echo "Error: QA remediation phase must be under active .vbw-planning/phases/: $candidate" >&2
      echo "QA remediation must target active phases, not archived milestones or arbitrary directories." >&2
      exit 1
      ;;
  esac

  phase_root="${candidate%%/.vbw-planning/phases/*}"
  if [ -z "$phase_root" ] || [ "$phase_root" = "$candidate" ]; then
    echo "Error: unable to determine VBW root from phase path: $candidate" >&2
    exit 1
  fi

  export VBW_CONFIG_ROOT="$phase_root"
  export VBW_PLANNING_DIR="$phase_root/.vbw-planning"
  printf '%s\n' "$candidate"
}

reject_milestone_phase_dir "$PHASE_DIR"
PHASE_DIR=$(canonicalize_phase_dir "$PHASE_DIR")

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

phase_number() {
  local base phase
  base=$(basename "${PHASE_DIR%/}")
  phase=$(printf '%s' "$base" | sed 's/^\([0-9]*\).*/\1/')
  phase="${phase:-01}"
  if ! [[ "$phase" =~ ^[0-9]+$ ]]; then
    phase="01"
  fi
  printf '%02d' "$((10#$phase))"
}

relative_to_phase() {
  local target="${1:-}"
  case "$target" in
    "$PHASE_DIR"/*) printf '%s' "${target#"$PHASE_DIR/"}" ;;
    *) printf '%s' "$(basename "$target")" ;;
  esac
}

new_issue_object() {
  local test_name="$1"
  local file_path="$2"
  local error_msg="$3"
  local source_path="$4"
  local round="$5"

  jq -cn \
    --arg test "$test_name" \
    --arg file "$file_path" \
    --arg error "$error_msg" \
    --arg source_path "$source_path" \
    --argjson round "$round" \
    '{
      test: $test,
      file: $file,
      error: $error,
      first_seen_in: $source_path,
      last_seen_in: $source_path,
      first_seen_round: $round,
      last_seen_round: $round,
      times_seen: 1
    }'
}

extract_pre_existing_issues_json_from_verification() {
  local verification_file="$1"
  local source_rel="$2"
  local round="$3"
  local tmp_json
  tmp_json=$(mktemp)

  awk -F'|' -v source_rel="$source_rel" -v round="$round" '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    /^## Pre-existing Issues/ { found=1; next }
    found && /^## / { exit }
    found && /^\|/ {
      if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
      test = trim($2)
      file = trim($3)
      err = trim($4)
      if (tolower(test) == "test" && tolower(file) == "file") next
      if (test == "") next
      print test "\t" file "\t" err
    }
  ' "$verification_file" 2>/dev/null | while IFS=$'\t' read -r test_name file_path error_msg; do
    [ -n "$test_name" ] || continue
    new_issue_object "$test_name" "$file_path" "$error_msg" "$source_rel" "$round"
  done > "$tmp_json"

  jq -s 'map(select(type == "object")) | unique_by(.test, .file, .error) | sort_by(.test, .file, .error)' "$tmp_json"
  rm -f "$tmp_json"
}

write_known_issue_snapshot() {
  local snapshot_path="$1"
  local issues_json="$2"
  local issue_count tmp_file
  issue_count=$(printf '%s' "$issues_json" | jq 'length' 2>/dev/null || echo 0)
  if [ "$issue_count" -eq 0 ] 2>/dev/null; then
    rm -f "$snapshot_path"
    echo 0
    return 0
  fi

  mkdir -p "$(dirname "$snapshot_path")"
  tmp_file=$(mktemp "${snapshot_path}.tmp.XXXXXX")
  jq -n \
    --arg phase "$(phase_number)" \
    --argjson issues "$issues_json" '
      {
        schema_version: 1,
        phase: $phase,
        issues: ($issues | sort_by(.test, .file, .error))
      }
    ' > "$tmp_file"
  mv "$tmp_file" "$snapshot_path"
  echo "$issue_count"
}

materialize_round_known_issues_snapshot() {
  local round_dir="$1"
  local round="$2"
  local live_registry_path="$3"
  local live_registry_status="$4"
  local source_verification_path="$5"
  local phase_verification_path="$6"
  local current_round_verification_path="$7"
  local snapshot_path="$round_dir/R${round}-KNOWN-ISSUES.json"
  local issues_json='[]'
  local source_rel=""
  local issue_count="0"

  if [ -f "$snapshot_path" ] && jq -e 'type == "object" and (.issues | type == "array")' "$snapshot_path" >/dev/null 2>&1; then
    issue_count=$(jq '.issues | length' "$snapshot_path" 2>/dev/null || echo 0)
    printf 'snapshot_path=%s\n' "$snapshot_path"
    printf 'snapshot_count=%s\n' "$issue_count"
    return 0
  fi

  if [ "$live_registry_status" = "present" ] && [ -f "$live_registry_path" ]; then
    issues_json=$(jq -c '.issues // []' "$live_registry_path" 2>/dev/null || echo '[]')
  elif [ -n "$source_verification_path" ] && [ -f "$source_verification_path" ]; then
    source_rel=$(relative_to_phase "$source_verification_path")
    issues_json=$(extract_pre_existing_issues_json_from_verification "$source_verification_path" "$source_rel" 0)
  elif [ "$round" = "01" ] && [ ! -f "$current_round_verification_path" ] && [ -n "$phase_verification_path" ] && [ -f "$phase_verification_path" ]; then
    source_rel=$(relative_to_phase "$phase_verification_path")
    issues_json=$(extract_pre_existing_issues_json_from_verification "$phase_verification_path" "$source_rel" 0)
  fi

  issue_count=$(write_known_issue_snapshot "$snapshot_path" "$issues_json")
  printf 'snapshot_path=%s\n' "$snapshot_path"
  printf 'snapshot_count=%s\n' "$issue_count"
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
  local phase_verification_path phase_pre_existing_issue_count current_round_verification_path
  local known_issues_meta input_mode snapshot_meta
  round=$(canonicalize_round "$(get_round)")
  round_dir="$PHASE_DIR/remediation/qa/round-${round}"
  current_round_verification_path="$round_dir/R${round}-VERIFICATION.md"
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

  snapshot_meta=$(materialize_round_known_issues_snapshot \
    "$round_dir" \
    "$round" \
    "$known_issues_path" \
    "$known_issues_status" \
    "$source_verification_path" \
    "$phase_verification_path" \
    "$current_round_verification_path")
  known_issues_path=$(printf '%s\n' "$snapshot_meta" | awk -F= '/^snapshot_path=/{print $2; exit}')
  known_issues_count=$(printf '%s\n' "$snapshot_meta" | awk -F= '/^snapshot_count=/{print $2; exit}')
  if [ -n "$known_issues_path" ] && [ -f "$known_issues_path" ] && [ "$known_issues_count" -gt 0 ] 2>/dev/null; then
    known_issues_status="present"
  else
    known_issues_status="missing"
  fi

  input_mode="none"
  if [ "${source_fail_count:-0}" -gt 0 ] 2>/dev/null && [ "${known_issues_count:-0}" -gt 0 ] 2>/dev/null; then
    input_mode="both"
  elif [ "${source_fail_count:-0}" -gt 0 ] 2>/dev/null; then
    input_mode="verification"
  elif [ "${known_issues_count:-0}" -gt 0 ] 2>/dev/null; then
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
