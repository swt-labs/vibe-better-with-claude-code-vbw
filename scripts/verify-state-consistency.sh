#!/usr/bin/env bash
set -u

# verify-state-consistency.sh — Cross-file state consistency verification.
#
# Checks that STATE.md, ROADMAP.md, PROJECT.md, .execution-state.json, and
# the phase filesystem agree with each other. Designed for three integration
# points:
#   - Archive (--mode archive): hard gate, exit 2 on any failure
#   - Phase completion / session start (--mode advisory): exit 0 always
#
# Usage: verify-state-consistency.sh [planning_dir] [--mode archive|advisory]
# Output: JSON object on stdout with per-check pass/fail and a verdict.
# Exit codes:
#   0 — all pass, or advisory mode (regardless of failures)
#   2 — archive mode AND at least one check failed

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Source shared utilities ------------------------------------------------
# shellcheck source=lib/vbw-config-root.sh
. "$SCRIPT_DIR/lib/vbw-config-root.sh"

if [ -f "$SCRIPT_DIR/lib/summary-status.sh" ]; then
  # shellcheck source=lib/summary-status.sh
  . "$SCRIPT_DIR/lib/summary-status.sh"
fi

if [ -f "$SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  . "$SCRIPT_DIR/summary-utils.sh"
fi

if [ -f "$SCRIPT_DIR/phase-state-utils.sh" ]; then
  # shellcheck source=phase-state-utils.sh
  . "$SCRIPT_DIR/phase-state-utils.sh"
fi

# --- Argument parsing -------------------------------------------------------
MODE="advisory"
PLANNING_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      shift
      MODE="${1:-advisory}"
      ;;
    --mode=*)
      MODE="${1#--mode=}"
      ;;
    -*)
      # unknown flag — ignore
      ;;
    *)
      if [ -z "$PLANNING_DIR" ]; then
        PLANNING_DIR="$1"
      fi
      ;;
  esac
  shift
done

# Resolve planning dir from workspace root if not provided
if [ -z "$PLANNING_DIR" ]; then
  find_vbw_root "$SCRIPT_DIR" 2>/dev/null || true
  PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
fi

# Make absolute
case "$PLANNING_DIR" in
  /*) ;; # already absolute
  *)  PLANNING_DIR="$(pwd)/$PLANNING_DIR" ;;
esac

# --- Early exit: no project state -------------------------------------------
if [ ! -d "$PLANNING_DIR" ] || [ ! -f "$PLANNING_DIR/STATE.md" ]; then
  jq -n --arg mode "$MODE" '{verdict:"skip",mode:$mode,reason:"no project state",checks:{},failed_checks:[]}'
  exit 0
fi

PHASES_DIR="$PLANNING_DIR/phases"
STATE_FILE="$PLANNING_DIR/STATE.md"
ROADMAP_FILE="$PLANNING_DIR/ROADMAP.md"
PROJECT_FILE="$PLANNING_DIR/PROJECT.md"
EXEC_STATE_FILE="$PLANNING_DIR/.execution-state.json"

# --- Check result accumulators -----------------------------------------------
# Each check sets check_NAME_pass (true/false) and check_NAME_detail (string).
# Checks that can't parse their input degrade to "skip" (pass=true, detail explains).
check_state_vs_filesystem_pass=true
check_state_vs_filesystem_detail="ok"
check_roadmap_vs_summaries_pass=true
check_roadmap_vs_summaries_detail="ok"
check_exec_state_vs_filesystem_pass=true
check_exec_state_vs_filesystem_detail="ok"
check_state_vs_roadmap_pass=true
check_state_vs_roadmap_detail="ok"
check_project_vs_state_pass=true
check_project_vs_state_detail="ok"

# --- Helper: parse STATE.md phase line ---------------------------------------
# Extracts "N of M" from "Phase: N of M (...)" — tolerates missing parenthesized name.
parse_state_phase() {
  local state_file="$1"
  STATE_PHASE_CURRENT=""
  STATE_PHASE_TOTAL=""
  local phase_line
  phase_line=$(grep -m1 '^Phase:' "$state_file" 2>/dev/null || true)
  if [ -z "$phase_line" ]; then
    return 1
  fi
  STATE_PHASE_CURRENT=$(echo "$phase_line" | sed -n 's/^Phase:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
  STATE_PHASE_TOTAL=$(echo "$phase_line" | sed -n 's/^Phase:[[:space:]]*[0-9][0-9]*[[:space:]]*of[[:space:]]*\([0-9][0-9]*\).*/\1/p')
  if [ -z "$STATE_PHASE_CURRENT" ] || [ -z "$STATE_PHASE_TOTAL" ]; then
    return 1
  fi
  return 0
}

# --- Helper: parse STATE.md project name -------------------------------------
parse_state_project_name() {
  local state_file="$1"
  STATE_PROJECT_NAME=""
  STATE_PROJECT_NAME=$(grep -m1 '^\*\*Project:\*\*' "$state_file" 2>/dev/null | sed 's/.*\*\*Project:\*\*[[:space:]]*//' || true)
}

# --- Helper: find active phase dir (first incomplete phase) ------------------
find_active_phase_position() {
  local phases_dir="$1"
  ACTIVE_PHASE_POS=""
  [ -d "$phases_dir" ] || return 1
  local idx=0 dir plans complete
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    idx=$((idx + 1))
    plans=$(count_phase_plans "$dir")
    complete=$(count_complete_summaries "$dir")
    if [ "$plans" -eq 0 ] || [ "$complete" -lt "$plans" ]; then
      ACTIVE_PHASE_POS="$idx"
      return 0
    fi
  done < <(list_canonical_phase_dirs "$phases_dir")
  # All phases complete — active is last+1 or last
  ACTIVE_PHASE_POS="$idx"
  return 0
}

# =============================================================================
# CHECK 1: STATE.md ↔ filesystem (phase number and total)
# =============================================================================
run_check_state_vs_filesystem() {
  if ! parse_state_phase "$STATE_FILE"; then
    check_state_vs_filesystem_detail="skip: could not parse Phase line from STATE.md"
    return
  fi

  if [ ! -d "$PHASES_DIR" ]; then
    check_state_vs_filesystem_detail="skip: no phases directory"
    return
  fi

  local fs_total
  fs_total=$(list_canonical_phase_dirs "$PHASES_DIR" | wc -l | tr -d ' ')

  local details=""
  if [ "$STATE_PHASE_TOTAL" != "$fs_total" ]; then
    details="phase total mismatch: STATE.md says $STATE_PHASE_TOTAL, filesystem has $fs_total"
    check_state_vs_filesystem_pass=false
  fi

  find_active_phase_position "$PHASES_DIR"
  if [ -n "$ACTIVE_PHASE_POS" ] && [ "$STATE_PHASE_CURRENT" != "$ACTIVE_PHASE_POS" ]; then
    local msg="active phase mismatch: STATE.md says phase $STATE_PHASE_CURRENT, filesystem active is $ACTIVE_PHASE_POS"
    if [ -n "$details" ]; then
      details="$details; $msg"
    else
      details="$msg"
    fi
    check_state_vs_filesystem_pass=false
  fi

  if [ "$check_state_vs_filesystem_pass" = "false" ]; then
    check_state_vs_filesystem_detail="$details"
  fi
}

# =============================================================================
# CHECK 2: ROADMAP.md ↔ SUMMARY.md (completion markers)
# =============================================================================
run_check_roadmap_vs_summaries() {
  if [ ! -f "$ROADMAP_FILE" ]; then
    check_roadmap_vs_summaries_detail="skip: no ROADMAP.md"
    return
  fi

  if [ ! -d "$PHASES_DIR" ]; then
    check_roadmap_vs_summaries_detail="skip: no phases directory"
    return
  fi

  local mismatches=""
  local phase_num checked plans complete phase_dir

  while IFS= read -r line; do
    phase_num=$(echo "$line" | sed -n 's/^- \[.\] Phase \([0-9][0-9]*\):.*/\1/p')
    [ -n "$phase_num" ] || continue
    checked=false
    if echo "$line" | grep -q '^\- \[x\]'; then
      checked=true
    fi

    # Find phase dir with matching number
    phase_dir=""
    local d d_num
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      d_num=$(basename "$d" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
      # Remove leading zeros for comparison (sed, not arithmetic — avoids octal for 08/09)
      d_num=$(printf '%s' "$d_num" | sed 's/^0*//')
      d_num=${d_num:-0}
      if [ "$d_num" -eq "$phase_num" ]; then
        phase_dir="$d"
        break
      fi
    done < <(list_canonical_phase_dirs "$PHASES_DIR")

    if [ -z "$phase_dir" ]; then
      continue  # phase dir not found — skip this entry
    fi

    plans=$(count_phase_plans "$phase_dir")
    complete=$(count_complete_summaries "$phase_dir")

    # Marked complete in roadmap but not all plans done
    if [ "$checked" = "true" ] && { [ "$plans" -eq 0 ] || [ "$complete" -lt "$plans" ]; }; then
      mismatches="${mismatches:+$mismatches, }phase $phase_num marked [x] but incomplete ($complete/$plans done)"
    fi

    # Not marked complete but all plans are done
    if [ "$checked" = "false" ] && [ "$plans" -gt 0 ] && [ "$complete" -ge "$plans" ]; then
      mismatches="${mismatches:+$mismatches, }phase $phase_num marked [ ] but all plans complete ($complete/$plans)"
    fi
  done < <(grep -E '^\- \[(x| )\] Phase [0-9]+:' "$ROADMAP_FILE" 2>/dev/null || true)

  if [ -n "$mismatches" ]; then
    check_roadmap_vs_summaries_pass=false
    check_roadmap_vs_summaries_detail="$mismatches"
  fi
}

# =============================================================================
# CHECK 3: .execution-state.json ↔ filesystem
# =============================================================================
run_check_exec_state_vs_filesystem() {
  if [ ! -f "$EXEC_STATE_FILE" ]; then
    check_exec_state_vs_filesystem_detail="skip: no .execution-state.json"
    return
  fi

  # Validate JSON
  if ! jq empty "$EXEC_STATE_FILE" 2>/dev/null; then
    check_exec_state_vs_filesystem_detail="skip: .execution-state.json is not valid JSON"
    return
  fi

  local es_phase es_status
  es_phase=$(jq -r '.phase // empty' "$EXEC_STATE_FILE" 2>/dev/null || true)
  es_status=$(jq -r '.status // empty' "$EXEC_STATE_FILE" 2>/dev/null || true)

  if [ -z "$es_phase" ] || [ -z "$es_status" ]; then
    check_exec_state_vs_filesystem_detail="skip: .execution-state.json missing phase or status"
    return
  fi

  if [ ! -d "$PHASES_DIR" ]; then
    check_exec_state_vs_filesystem_detail="skip: no phases directory"
    return
  fi

  local details=""

  # Find phase dir matching es_phase number
  local target_dir="" d d_num
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    d_num=$(basename "$d" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
    d_num=$(printf '%s' "$d_num" | sed 's/^0*//')
    d_num=${d_num:-0}
    if [ "$d_num" -eq "$es_phase" ]; then
      target_dir="$d"
      break
    fi
  done < <(list_canonical_phase_dirs "$PHASES_DIR")

  if [ -z "$target_dir" ]; then
    details="phase dir for phase $es_phase not found on filesystem"
    check_exec_state_vs_filesystem_pass=false
    check_exec_state_vs_filesystem_detail="$details"
    return
  fi

  # Status coherence: complete but incomplete plans
  local plans complete
  plans=$(count_phase_plans "$target_dir")
  complete=$(count_complete_summaries "$target_dir")

  if [ "$es_status" = "complete" ] && [ "$plans" -gt 0 ] && [ "$complete" -lt "$plans" ]; then
    details="status is 'complete' but phase $es_phase has incomplete plans ($complete/$plans)"
    check_exec_state_vs_filesystem_pass=false
  fi

  if [ "$es_status" = "running" ] && [ "$plans" -eq 0 ]; then
    local msg="status is 'running' but phase $es_phase has no plans"
    if [ -n "$details" ]; then
      details="$details; $msg"
    else
      details="$msg"
    fi
    check_exec_state_vs_filesystem_pass=false
  fi

  # Per-plan status verification
  local plan_count plan_id plan_status plan_mismatches=""
  plan_count=$(jq -r '.plans | length // 0' "$EXEC_STATE_FILE" 2>/dev/null || echo 0)

  local i=0
  while [ "$i" -lt "$plan_count" ]; do
    plan_id=$(jq -r ".plans[$i].id // empty" "$EXEC_STATE_FILE" 2>/dev/null || true)
    plan_status=$(jq -r ".plans[$i].status // empty" "$EXEC_STATE_FILE" 2>/dev/null || true)

    if [ -n "$plan_id" ] && [ -n "$plan_status" ]; then
      case "$plan_status" in
        complete|partial|failed)
          # Check that a SUMMARY.md exists for this plan
          local summary_found=false summary_file
          for summary_file in "$target_dir/${plan_id}-SUMMARY.md" "$target_dir/SUMMARY.md"; do
            if [ -f "$summary_file" ]; then
              summary_found=true
              break
            fi
          done
          if [ "$summary_found" = "false" ]; then
            plan_mismatches="${plan_mismatches:+$plan_mismatches, }plan '$plan_id' status=$plan_status but no SUMMARY.md found"
          fi
          ;;
      esac
    fi
    i=$((i + 1))
  done

  if [ -n "$plan_mismatches" ]; then
    if [ -n "$details" ]; then
      details="$details; $plan_mismatches"
    else
      details="$plan_mismatches"
    fi
    check_exec_state_vs_filesystem_pass=false
  fi

  if [ "$check_exec_state_vs_filesystem_pass" = "false" ]; then
    check_exec_state_vs_filesystem_detail="$details"
  fi
}

# =============================================================================
# CHECK 4: STATE.md ↔ ROADMAP.md (phase count)
# =============================================================================
run_check_state_vs_roadmap() {
  if ! parse_state_phase "$STATE_FILE"; then
    check_state_vs_roadmap_detail="skip: could not parse Phase line from STATE.md"
    return
  fi

  if [ ! -f "$ROADMAP_FILE" ]; then
    check_state_vs_roadmap_detail="skip: no ROADMAP.md"
    return
  fi

  local roadmap_checklist_count roadmap_section_count
  roadmap_checklist_count=$(grep -cE '^\- \[.\] Phase [0-9]+:' "$ROADMAP_FILE" 2>/dev/null || echo 0)
  roadmap_section_count=$(grep -cE '^### Phase [0-9]+:' "$ROADMAP_FILE" 2>/dev/null || echo 0)

  local details="" failed=false

  if [ "$STATE_PHASE_TOTAL" != "$roadmap_checklist_count" ]; then
    details="STATE.md total=$STATE_PHASE_TOTAL vs ROADMAP checklist count=$roadmap_checklist_count"
    failed=true
  fi

  if [ "$roadmap_section_count" -gt 0 ] && [ "$STATE_PHASE_TOTAL" != "$roadmap_section_count" ]; then
    local msg="STATE.md total=$STATE_PHASE_TOTAL vs ROADMAP section count=$roadmap_section_count"
    if [ -n "$details" ]; then
      details="$details; $msg"
    else
      details="$msg"
    fi
    failed=true
  fi

  if [ "$roadmap_checklist_count" != "$roadmap_section_count" ] && [ "$roadmap_section_count" -gt 0 ]; then
    local msg="ROADMAP checklist count=$roadmap_checklist_count vs ROADMAP section count=$roadmap_section_count"
    if [ -n "$details" ]; then
      details="$details; $msg"
    else
      details="$msg"
    fi
    failed=true
  fi

  if [ "$failed" = "true" ]; then
    check_state_vs_roadmap_pass=false
    check_state_vs_roadmap_detail="$details"
  fi
}

# =============================================================================
# CHECK 5: PROJECT.md ↔ STATE.md (project name)
# =============================================================================
run_check_project_vs_state() {
  if [ ! -f "$PROJECT_FILE" ]; then
    check_project_vs_state_detail="skip: no PROJECT.md"
    return
  fi

  local project_name state_name
  project_name=$(sed -n '1s/^# //p' "$PROJECT_FILE" 2>/dev/null || true)
  parse_state_project_name "$STATE_FILE"
  state_name="$STATE_PROJECT_NAME"

  if [ -z "$project_name" ]; then
    check_project_vs_state_detail="skip: could not parse project name from PROJECT.md"
    return
  fi

  if [ -z "$state_name" ]; then
    check_project_vs_state_detail="skip: could not parse project name from STATE.md"
    return
  fi

  if [ "$project_name" != "$state_name" ]; then
    check_project_vs_state_pass=false
    check_project_vs_state_detail="PROJECT.md='$project_name' vs STATE.md='$state_name'"
  fi
}

# --- Run all checks ----------------------------------------------------------
run_check_state_vs_filesystem
run_check_roadmap_vs_summaries
run_check_exec_state_vs_filesystem
run_check_state_vs_roadmap
run_check_project_vs_state

# --- Assemble failed_checks list ---------------------------------------------
FAILED_CHECKS=""
if [ "$check_state_vs_filesystem_pass" = "false" ]; then
  FAILED_CHECKS="${FAILED_CHECKS:+$FAILED_CHECKS,}\"state_vs_filesystem\""
fi
if [ "$check_roadmap_vs_summaries_pass" = "false" ]; then
  FAILED_CHECKS="${FAILED_CHECKS:+$FAILED_CHECKS,}\"roadmap_vs_summaries\""
fi
if [ "$check_exec_state_vs_filesystem_pass" = "false" ]; then
  FAILED_CHECKS="${FAILED_CHECKS:+$FAILED_CHECKS,}\"exec_state_vs_filesystem\""
fi
if [ "$check_state_vs_roadmap_pass" = "false" ]; then
  FAILED_CHECKS="${FAILED_CHECKS:+$FAILED_CHECKS,}\"state_vs_roadmap\""
fi
if [ "$check_project_vs_state_pass" = "false" ]; then
  FAILED_CHECKS="${FAILED_CHECKS:+$FAILED_CHECKS,}\"project_vs_state\""
fi

# --- Determine verdict -------------------------------------------------------
VERDICT="pass"
if [ -n "$FAILED_CHECKS" ]; then
  VERDICT="fail"
fi

# --- Output JSON --------------------------------------------------------------
jq -n \
  --arg verdict "$VERDICT" \
  --arg mode "$MODE" \
  --argjson c1_pass "$check_state_vs_filesystem_pass" \
  --arg c1_detail "$check_state_vs_filesystem_detail" \
  --argjson c2_pass "$check_roadmap_vs_summaries_pass" \
  --arg c2_detail "$check_roadmap_vs_summaries_detail" \
  --argjson c3_pass "$check_exec_state_vs_filesystem_pass" \
  --arg c3_detail "$check_exec_state_vs_filesystem_detail" \
  --argjson c4_pass "$check_state_vs_roadmap_pass" \
  --arg c4_detail "$check_state_vs_roadmap_detail" \
  --argjson c5_pass "$check_project_vs_state_pass" \
  --arg c5_detail "$check_project_vs_state_detail" \
  --argjson failed "[$FAILED_CHECKS]" \
  '{
    verdict: $verdict,
    mode: $mode,
    checks: {
      state_vs_filesystem: {pass: $c1_pass, detail: $c1_detail},
      roadmap_vs_summaries: {pass: $c2_pass, detail: $c2_detail},
      exec_state_vs_filesystem: {pass: $c3_pass, detail: $c3_detail},
      state_vs_roadmap: {pass: $c4_pass, detail: $c4_detail},
      project_vs_state: {pass: $c5_pass, detail: $c5_detail}
    },
    failed_checks: $failed
  }'

# --- Exit code ----------------------------------------------------------------
if [ "$VERDICT" = "fail" ] && [ "$MODE" = "archive" ]; then
  exit 2
fi
exit 0
