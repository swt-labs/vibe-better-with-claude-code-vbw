#!/usr/bin/env bash
# suggest-next.sh — Context-aware Next Up suggestions (ADP-03)
#
# Usage: suggest-next.sh <command> [result] [phase-number]
#   command: the VBW command that just ran (implement, qa, plan, execute, fix, etc.)
#   result:  optional outcome (pass, fail, partial, complete, skipped)
#   phase-number: optional phase hint for phase-scoped suggestions (used by verify)
#
# Output: Formatted ➜ Next Up block with 2-3 contextual suggestions.
# Called by commands during their output step.
#
# Context detection (all from disk, no extra args needed):
#   - Phase state: next unplanned/unbuilt phase, all-done
#   - Plan count: number of PLAN.md files in active phase
#   - Effort level: from config.json
#   - Deviations: summed from SUMMARY.md frontmatter in active phase
#   - Failing plans: SUMMARY.md files with status != complete
#   - Map staleness: percentage from META.md git hash comparison
#   - Phase name: human-readable slug from directory name

set -eo pipefail

CMD="${1:-}"
RESULT="${2:-}"
TARGET_PHASE_ARG="${3:-}"
PLANNING_DIR=".vbw-planning"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source shared UAT helpers (extract_status_value → aliased as read_status_field, latest_non_source_uat)
# shellcheck source=uat-utils.sh
. "$SCRIPT_DIR/uat-utils.sh"
# Alias for backward compat within this script
read_status_field() { extract_status_value "$@"; }

# Source shared summary-status helpers for status-aware SUMMARY detection
if [ -f "$SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  . "$SCRIPT_DIR/summary-utils.sh"
else
  # Safe default: report zero completions when helpers unavailable
  count_complete_summaries() { echo "0"; }
fi

list_child_dirs_sorted() {
  local parent="$1"
  [ -d "$parent" ] || return 0

  find "$parent" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
    (sort -V 2>/dev/null || awk -F/ '{n=$NF; gsub(/[^0-9].*/,"",n); if (n == "") n=0; print (n+0)"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f2-)
}

# --- State detection ---
has_project=false
phase_count=0
next_unplanned=""
next_unbuilt=""
all_done=false
last_qa_result=""
map_exists=false

# Contextual state (ADP-03)
effort="balanced"
active_phase_dir=""
active_phase_num=""
active_phase_name=""
active_phase_plans=0
deviation_count=0
failing_plan_ids=""
map_staleness=-1
cfg_autonomy="standard"
has_uat=false
uat_major_or_higher=false
verify_target_phase=""
verify_target_phase_dir=""
verify_target_uat=""
milestone_uat_issues=false
milestone_uat_phase="none"
milestone_uat_slug="none"
milestone_uat_count=0
current_uat_issues_phase=""
current_uat_issues_slug=""
current_uat_issues_label=""
current_uat_major_or_higher=false
current_uat_round_count=0
cfg_require_phase_discussion=false
next_undiscussed=""
next_preseeded=""
cfg_auto_uat=false
has_unverified_phases=false
first_unverified_phase=""
first_unverified_slug=""
next_phase_state=""
pd_next_phase=""

read_deviations_field() {
  local file="$1"
  awk '
    BEGIN { in_fm = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && tolower($0) ~ /^[[:space:]]*deviations[[:space:]]*:/ {
      value = $0
      sub(/^[^:]*:[[:space:]]*/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$file" 2>/dev/null || true
}

if [ -d "$PLANNING_DIR" ]; then

  # Canonical post-archive UAT recovery state from phase-detect.sh
  _pd_out=$(bash "$SCRIPT_DIR/phase-detect.sh" 2>/dev/null || true)
  if [ -n "$_pd_out" ]; then
    _pd_milestone_uat=$(echo "$_pd_out" | grep -m1 '^milestone_uat_issues=' | sed 's/^[^=]*=//' || true)
    _pd_milestone_phase=$(echo "$_pd_out" | grep -m1 '^milestone_uat_phase=' | sed 's/^[^=]*=//' || true)
    _pd_milestone_slug=$(echo "$_pd_out" | grep -m1 '^milestone_uat_slug=' | sed 's/^[^=]*=//' || true)
    _pd_milestone_count=$(echo "$_pd_out" | grep -m1 '^milestone_uat_count=' | sed 's/^[^=]*=//' || true)

    [ -n "${_pd_milestone_uat:-}" ] && milestone_uat_issues="$_pd_milestone_uat"
    [ -n "${_pd_milestone_phase:-}" ] && milestone_uat_phase="$_pd_milestone_phase"
    [ -n "${_pd_milestone_slug:-}" ] && milestone_uat_slug="$_pd_milestone_slug"
    [ -n "${_pd_milestone_count:-}" ] && milestone_uat_count="$_pd_milestone_count"

    _pd_require_discuss=$(echo "$_pd_out" | grep -m1 '^config_require_phase_discussion=' | sed 's/^[^=]*=//' || true)
    [ -n "${_pd_require_discuss:-}" ] && cfg_require_phase_discussion="$_pd_require_discuss"

    # Unverified phases (for mid-milestone auto_uat suppression)
    _pd_has_unverified=$(echo "$_pd_out" | grep -m1 '^has_unverified_phases=' | sed 's/^[^=]*=//' || true)
    [ "${_pd_has_unverified:-}" = "true" ] && has_unverified_phases=true

    # First unverified phase details
    _pd_first_unverified_phase=$(echo "$_pd_out" | grep -m1 '^first_unverified_phase=' | sed 's/^[^=]*=//' || true)
    _pd_first_unverified_slug=$(echo "$_pd_out" | grep -m1 '^first_unverified_slug=' | sed 's/^[^=]*=//' || true)
    [ -n "${_pd_first_unverified_phase:-}" ] && first_unverified_phase="$_pd_first_unverified_phase"
    [ -n "${_pd_first_unverified_slug:-}" ] && first_unverified_slug="$_pd_first_unverified_slug"

    # Next phase state (for reverification routing)
    _pd_next_phase_state=$(echo "$_pd_out" | grep -m1 '^next_phase_state=' | sed 's/^[^=]*=//' || true)
    [ -n "${_pd_next_phase_state:-}" ] && next_phase_state="$_pd_next_phase_state"

    # Next phase number (for reverification suggestions)
    _pd_next_phase=$(echo "$_pd_out" | grep -m1 '^next_phase=' | sed 's/^[^=]*=//' || true)
    [ -n "${_pd_next_phase:-}" ] && pd_next_phase="$_pd_next_phase"

    # Current-phase UAT issues (distinct from archived milestone UAT)
    _pd_uat_phase=$(echo "$_pd_out" | grep -m1 '^uat_issues_phase=' | sed 's/^[^=]*=//' || true)
    _pd_uat_slug=$(echo "$_pd_out" | grep -m1 '^uat_issues_slug=' | sed 's/^[^=]*=//' || true)
    _pd_uat_major=$(echo "$_pd_out" | grep -m1 '^uat_issues_major_or_higher=' | sed 's/^[^=]*=//' || true)
    _pd_uat_round_count=$(echo "$_pd_out" | grep -m1 '^uat_round_count=' | sed 's/^[^=]*=//' || true)
    if [ -n "${_pd_uat_phase:-}" ] && [ "$_pd_uat_phase" != "none" ]; then
      current_uat_issues_phase="$_pd_uat_phase"
      current_uat_issues_slug="${_pd_uat_slug:-}"
      [ "${_pd_uat_major:-}" = "true" ] && current_uat_major_or_higher=true
      [ -n "${_pd_uat_round_count:-}" ] && current_uat_round_count="$_pd_uat_round_count"
    fi

    # Build human-readable phase label: "Phase N (slug-name)" or just "Phase N"
    # Append "— Round Y" when archived round files exist (Y = count + 1)
    if [ -n "$current_uat_issues_phase" ] && [ -n "$current_uat_issues_slug" ]; then
      current_uat_issues_label="Phase $current_uat_issues_phase ($current_uat_issues_slug)"
    elif [ -n "$current_uat_issues_phase" ]; then
      current_uat_issues_label="Phase $current_uat_issues_phase"
    else
      current_uat_issues_label=""
    fi
    if [ -n "$current_uat_issues_label" ] && [ "$current_uat_round_count" -gt 0 ] 2>/dev/null; then
      _display_round=$((current_uat_round_count + 1))
      current_uat_issues_label="$current_uat_issues_label — Round $_display_round"
    fi
  fi

  # Root-canonical phases directory (no ACTIVE indirection)
  PHASES_DIR="$PLANNING_DIR/phases"

  # Check PROJECT.md exists and isn't template
  if [ -f "$PLANNING_DIR/PROJECT.md" ] && ! grep -q '{project-name}' "$PLANNING_DIR/PROJECT.md" 2>/dev/null; then
    has_project=true
  fi

  # Read effort from config
  if [ -f "$PLANNING_DIR/config.json" ] && command -v jq >/dev/null 2>&1; then
    # Auto-migrate: add model_profile if missing
    if ! jq -e '.model_profile' "$PLANNING_DIR/config.json" >/dev/null 2>&1; then
      TMP=$(mktemp)
      jq '. + {model_profile: "quality", model_overrides: {}}' "$PLANNING_DIR/config.json" > "$TMP" && mv "$TMP" "$PLANNING_DIR/config.json"
    fi
    e=$(jq -r '.effort // "balanced"' "$PLANNING_DIR/config.json" 2>/dev/null)
    [ -n "$e" ] && [ "$e" != "null" ] && effort="$e"
    a=$(jq -r '.autonomy // "standard"' "$PLANNING_DIR/config.json" 2>/dev/null)
    [ -n "$a" ] && [ "$a" != "null" ] && cfg_autonomy="$a"
    au=$(jq -r '.auto_uat // "false"' "$PLANNING_DIR/config.json" 2>/dev/null)
    [ "$au" = "true" ] && cfg_auto_uat=true
  fi

  # Scan phases
  if [ -d "$PHASES_DIR" ]; then
    # Sort phase dirs numerically (prevents 100 sorting before 11)
    SN_PHASE_DIRS=()
    while IFS= read -r _sn_dir; do
      [ -n "$_sn_dir" ] || continue
      SN_PHASE_DIRS+=("${_sn_dir%/}/")
    done < <(list_child_dirs_sorted "$PHASES_DIR")

    last_phase_dir=""
    last_phase_num=""
    last_phase_name=""
    last_phase_plans=0

    if [ ${#SN_PHASE_DIRS[@]} -gt 0 ]; then
    for dir in "${SN_PHASE_DIRS[@]}"; do
      [ -d "$dir" ] || continue
      phase_num=$(basename "$dir" | sed 's/[^0-9].*//')
      # Skip non-canonical dirs without numeric prefix
      if [ -z "$phase_num" ] || ! echo "$phase_num" | grep -qE '^[0-9]+$'; then
        continue
      fi
      phase_count=$((phase_count + 1))
      phase_slug=$(basename "$dir" | sed 's/^[0-9]*-//')

      plans=$(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
      summaries=$(count_complete_summaries "$dir")

      if [ "$plans" -eq 0 ] && [ -z "$next_unplanned" ]; then
        # Track first undiscussed phase (for require_phase_discussion suggestions)
        if [ "$cfg_require_phase_discussion" = "true" ] && [ -z "$next_undiscussed" ]; then
          context_files=$(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | wc -l | tr -d ' ')
          if [ "$context_files" -eq 0 ]; then
            next_undiscussed="$phase_num"
          elif [ -z "$next_preseeded" ]; then
            # Check ALL context files (sorted) for pre_seeded: true to avoid
            # order-dependent detection when multiple CONTEXT.md files exist.
            while IFS= read -r ctx_file; do
              [ -n "$ctx_file" ] || continue
              if awk '
              BEGIN { in_fm=0; found=0 }
              NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
              in_fm && /^---[[:space:]]*$/ { exit }
              in_fm && /^pre_seeded[[:space:]]*:[[:space:]]*"?true"?[[:space:]]*$/ { found=1; exit }
              END { exit !found }
            ' "$ctx_file" 2>/dev/null; then
                next_preseeded="$phase_num"
                break
              fi
            done < <(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | sort)
          fi
        fi
        next_unplanned="$phase_num"
        active_phase_dir="$dir"
        active_phase_num="$phase_num"
        active_phase_name="$phase_slug"
        active_phase_plans=0
      elif [ "$plans" -gt 0 ] && [ "$summaries" -lt "$plans" ] && [ -z "$next_unbuilt" ]; then
        next_unbuilt="$phase_num"
        active_phase_dir="$dir"
        active_phase_num="$phase_num"
        active_phase_name="$phase_slug"
        active_phase_plans="$plans"
      fi

      # Track the last phase as fallback active phase
      last_phase_dir="$dir"
      last_phase_num="$phase_num"
      last_phase_name="$phase_slug"
      last_phase_plans="$plans"
    done
    fi  # end SN_PHASE_DIRS length check

    # If no unplanned/unbuilt, use the last phase (most recently completed)
    if [ -z "$active_phase_dir" ] && [ -n "$last_phase_dir" ]; then
      active_phase_dir="$last_phase_dir"
      active_phase_num="$last_phase_num"
      active_phase_name="$last_phase_name"
      active_phase_plans="$last_phase_plans"
    fi

    # All done if phases exist, nothing is unplanned/unbuilt, and no current-phase UAT issues
    if [ "$phase_count" -gt 0 ] && [ -z "$next_unplanned" ] && [ -z "$next_unbuilt" ] && [ -z "$current_uat_issues_phase" ]; then
      all_done=true
    fi

    # Find most recent QA result
    for dir in "$PHASES_DIR"/*/; do
      [ -d "$dir" ] || continue
      for vf in "$dir"/*-VERIFICATION.md; do
        [ -f "$vf" ] || continue
        r=$(grep -m1 '^result:' "$vf" 2>/dev/null | sed 's/result:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' || true)
        [ -n "$r" ] && last_qa_result="$r"
      done
    done

    # Count deviations and find failing plans in active phase
    if [ -n "$active_phase_dir" ] && [ -d "$active_phase_dir" ]; then
      for sf in "$active_phase_dir"/*-SUMMARY.md; do
        [ -f "$sf" ] || continue
        # Extract deviations count from frontmatter
        d=$(read_deviations_field "$sf")
        case "$d" in
          0|"[]"|"") ;;  # zero deviations
          [0-9]*) deviation_count=$((deviation_count + d)) ;;
          *) deviation_count=$((deviation_count + 1)) ;;  # non-empty, non-numeric = at least 1
        esac
        # Check for failed/partial status
        s=$(read_status_field "$sf")
        if [ "$s" = "failed" ] || [ "$s" = "partial" ]; then
          plan_id=$(basename "$sf" | sed 's/-SUMMARY.md//')
          failing_plan_ids="${failing_plan_ids:+$failing_plan_ids }$plan_id"
        fi
      done

      # Check for completed UAT in active phase (exclude SOURCE-UAT copies)
      for uf in "$active_phase_dir"/*-UAT.md; do
        [ -f "$uf" ] || continue
        case "$uf" in
          *SOURCE-UAT.md) continue ;;
        esac
        us=$(read_status_field "$uf")
        if [ "$us" = "complete" ] || [ "$us" = "passed" ]; then
          has_uat=true
        fi
      done
    fi
  fi

  # Check map staleness (not just existence)
  if [ -d "$PLANNING_DIR/codebase" ]; then
    map_exists=true
    META="$PLANNING_DIR/codebase/META.md"
    if [ -f "$META" ] && git rev-parse --git-dir >/dev/null 2>&1; then
      git_hash=$(grep '^git_hash:' "$META" 2>/dev/null | awk '{print $2}' || true)
      file_count=$(grep '^file_count:' "$META" 2>/dev/null | awk '{print $2}' || true)
      if [ -n "$git_hash" ] && [ -n "$file_count" ] && [ "$file_count" -gt 0 ] 2>/dev/null; then
        if git cat-file -e "$git_hash" 2>/dev/null; then
          changed=$(git diff --name-only "$git_hash"..HEAD 2>/dev/null | wc -l | tr -d ' ')
          map_staleness=$((changed * 100 / file_count))
        else
          map_staleness=100
        fi
      fi
    fi
  fi
fi

# Use explicit result if provided, fall back to detected QA result
effective_result="${RESULT:-$last_qa_result}"

# Verify issues_found routing: inspect target UAT severities to choose fix vs re-plan guidance.
# - major/critical (or unknown severity shape): route to discuss+plan
# - minor-only: route to quick fix
if [ "$CMD" = "verify" ] && [ "$effective_result" = "issues_found" ] && [ -d "${PHASES_DIR:-}" ]; then
  verify_target_phase="$TARGET_PHASE_ARG"

  # Normalize explicit arg: strip leading zeros for comparison (user may pass "3" for phase "03")
  if [ -n "$verify_target_phase" ]; then
    verify_target_phase=$(echo "$verify_target_phase" | sed 's/^0*//')
    [ -z "$verify_target_phase" ] && verify_target_phase="0"
  fi

  if [ -n "$verify_target_phase" ]; then
    # Explicit phase arg — find the matching directory
    for dir in "$PHASES_DIR"/*/; do
      [ -d "$dir" ] || continue
      pn=$(basename "$dir" | sed 's/[^0-9].*//' | sed 's/^0*//')
      [ -z "$pn" ] && pn="0"
      if [ "$pn" = "$verify_target_phase" ]; then
        verify_target_phase_dir="$dir"
        break
      fi
    done
  else
    # No phase arg — find the first phase with UAT issues (numeric order, matching phase-detect.sh)
    SN_VERIFY_DIRS=()
    while IFS= read -r _sv_dir; do
      [ -n "$_sv_dir" ] || continue
      SN_VERIFY_DIRS+=("${_sv_dir%/}/")
    done < <(list_child_dirs_sorted "$PHASES_DIR")

    for dir in ${SN_VERIFY_DIRS[@]+"${SN_VERIFY_DIRS[@]}"}; do
      [ -d "$dir" ] || continue
      # Guard: skip phases without execution artifacts (matching phase-detect.sh)
      _plans=$(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
      _summaries=$(count_complete_summaries "$dir")
      if [ "$_plans" -eq 0 ] || [ "$_summaries" -lt "$_plans" ]; then
        continue
      fi
      _uat=$(latest_non_source_uat "$dir")
      if [ -f "$_uat" ]; then
        _us=$(read_status_field "$_uat")
        if [ "$_us" = "issues_found" ]; then
          verify_target_phase_dir="$dir"
          verify_target_phase=$(basename "$dir" | sed 's/[^0-9].*//' | sed 's/^0*//')
          [ -z "$verify_target_phase" ] && verify_target_phase="0"
          break
        fi
      fi
    done
    # No fallback — if no phase has issues_found, leave verify_target_phase empty
    # so the output section can show generic guidance instead of false remediation.
  fi

  if [ -n "$verify_target_phase_dir" ]; then
    verify_target_uat=$(latest_non_source_uat "$verify_target_phase_dir")
  fi

  if [ -f "$verify_target_uat" ]; then
    uat_critical=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*critical' "$verify_target_uat" || true)
    uat_major=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*major' "$verify_target_uat" || true)
    uat_minor=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*minor' "$verify_target_uat" || true)
    tagged_severities=$((uat_critical + uat_major + uat_minor))

    # Brownfield-safe default: older UAT formats may omit severity lines.
    if [ "$uat_critical" -gt 0 ] || [ "$uat_major" -gt 0 ] || [ "$tagged_severities" -eq 0 ]; then
      uat_major_or_higher=true
    fi
  else
    # If UAT file isn't locatable but a target was identified, choose safer escalation.
    # If no target was identified at all (no-arg scan found nothing), leave uat_major_or_higher=false
    # so the output shows generic fix guidance rather than false remediation.
    if [ -n "$verify_target_phase_dir" ]; then
      uat_major_or_higher=true
    fi
  fi
fi

# Format phase name for display (replace hyphens with spaces)
fmt_phase_name() {
  echo "$1" | tr '-' ' '
}

# --- Output ---
echo "➜ Next Up"

suggest() {
  echo "  $1"
}

suggest_milestone_recovery() {
  if [ "$milestone_uat_issues" = true ]; then
    if [ "$milestone_uat_slug" != "none" ] && [ "${milestone_uat_count:-0}" -gt 1 ] 2>/dev/null; then
      suggest "/vbw:vibe -- Milestone UAT recovery pending (${milestone_uat_slug}, ${milestone_uat_count} phase(s))"
    elif [ "$milestone_uat_slug" != "none" ] && [ "$milestone_uat_phase" != "none" ]; then
      suggest "/vbw:vibe -- Milestone UAT recovery pending (${milestone_uat_slug}, Phase ${milestone_uat_phase})"
    else
      suggest "/vbw:vibe -- Milestone UAT recovery pending"
    fi
    return 0
  fi
  return 1
}

case "$CMD" in
  init)
    suggest "/vbw:vibe -- Define your project and start building"
    ;;

  vibe|implement|execute)
    case "$effective_result" in
      fail)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/vbw:fix -- Fix plan $first_fail (failed verification)"
        else
          suggest "/vbw:fix -- Fix the failing checks"
        fi
        suggest "/vbw:qa -- Re-run verification after fixing"
        ;;
      partial)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/vbw:fix -- Fix plan $first_fail (partial failure)"
        else
          suggest "/vbw:fix -- Address partial failures"
        fi
        if [ "$all_done" != true ]; then
          suggest "/vbw:vibe -- Continue to next phase"
        fi
        ;;
      *)
        # Suggest UAT verification when:
        # 1. Active phase is fully built (plans>0), has no UAT, no known issues, AND (auto_uat or cautious/standard)
        # 2. auto_uat=true AND some completed phase is unverified (cross-phase)
        # Skip when current phase already has UAT issues (remediation takes priority)
        if [ -z "$current_uat_issues_phase" ] && \
           { { [ "$has_uat" = false ] && [ "$active_phase_plans" -gt 0 ] && { [ "$cfg_auto_uat" = true ] || [ "$cfg_autonomy" = "cautious" ] || [ "$cfg_autonomy" = "standard" ]; }; } \
             || { [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; }; }; then
          if [ -n "$first_unverified_phase" ]; then
            _uv_label="$first_unverified_phase"
            [ -n "$first_unverified_slug" ] && _uv_label="$first_unverified_phase ($(fmt_phase_name "${first_unverified_slug#*-}"))"
            suggest "/vbw:verify $first_unverified_phase -- Walk through $_uv_label changes before continuing"
          else
            suggest "/vbw:verify -- Walk through changes before continuing"
          fi
        fi
        if [ "$all_done" = true ] || [ "$next_phase_state" = "needs_reverification" ]; then
          if [ "$next_phase_state" = "needs_reverification" ]; then
            suggest "/vbw:vibe -- Re-verify Phase ${pd_next_phase:-} after remediation"
          elif ! suggest_milestone_recovery; then
            if [ "$deviation_count" -eq 0 ]; then
              suggest "/vbw:vibe --archive -- All phases complete, zero deviations"
            else
              suggest "/vbw:vibe --archive -- Archive completed work ($deviation_count deviation(s) logged)"
              suggest "/vbw:qa -- Review before archiving"
            fi
          elif [ "$deviation_count" -gt 0 ]; then
            suggest "/vbw:qa -- Review remediation scope before resuming new work"
          else
            :
          fi
        elif [ -n "$current_uat_issues_phase" ]; then
          if [ "$current_uat_major_or_higher" = true ]; then
            suggest "/vbw:vibe -- Remediate UAT issues for $current_uat_issues_label"
          else
            suggest "/vbw:fix -- Fix minor UAT issues in $current_uat_issues_label"
          fi
        elif { [ -n "$next_unbuilt" ] || [ -n "$next_unplanned" ]; } && ! { [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; }; then
          target="${next_unbuilt:-$next_unplanned}"
          # If next phase needs discussion, suggest discuss (suppress continue)
          if [ -n "$next_undiscussed" ] && [ "$next_undiscussed" = "$target" ]; then
            suggest "/vbw:discuss $target -- Discuss phase before planning"
          elif [ -n "$next_preseeded" ] && [ "$next_preseeded" = "$target" ]; then
            for dir in "$PHASES_DIR"/*/; do
              [ -d "$dir" ] || continue
              pn=$(basename "$dir" | sed 's/[^0-9].*//')
              if [ "$pn" = "$target" ]; then
                tname=$(basename "$dir" | sed 's/^[0-9]*-//')
                suggest "/vbw:vibe -- Plan Phase $target: $(fmt_phase_name "$tname") (discussion pre-seeded from UAT)"
                break
              fi
            done
          elif [ -n "$active_phase_name" ] && [ "$target" != "$active_phase_num" ]; then
            for dir in "$PHASES_DIR"/*/; do
              [ -d "$dir" ] || continue
              pn=$(basename "$dir" | sed 's/[^0-9].*//')
              if [ "$pn" = "$target" ]; then
                tname=$(basename "$dir" | sed 's/^[0-9]*-//')
                suggest "/vbw:vibe -- Continue to Phase $target: $(fmt_phase_name "$tname")"
                break
              fi
            done
          else
            suggest "/vbw:vibe -- Continue to next phase"
          fi
        fi
        if [ "$RESULT" = "skipped" ]; then
          suggest "/vbw:qa -- Verify completed work"
        fi
        ;;
    esac
    ;;

  plan)
    if [ "$active_phase_plans" -gt 0 ]; then
      suggest "/vbw:vibe -- Execute $active_phase_plans plans ($effort effort)"
    else
      suggest "/vbw:vibe -- Execute the planned phase"
    fi
    ;;

  qa)
    case "$effective_result" in
      pass)
        # Suggest UAT verification when:
        # 1. Active phase is fully built (plans>0), has no UAT, no known issues, AND (auto_uat or cautious/standard)
        # 2. auto_uat=true AND some completed phase is unverified (cross-phase)
        # Skip when current phase already has UAT issues (remediation takes priority)
        if [ -z "$current_uat_issues_phase" ] && \
           { { [ "$has_uat" = false ] && [ "$active_phase_plans" -gt 0 ] && { [ "$cfg_auto_uat" = true ] || [ "$cfg_autonomy" = "cautious" ] || [ "$cfg_autonomy" = "standard" ]; }; } \
             || { [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; }; }; then
          if [ -n "$first_unverified_phase" ]; then
            _uv_label="$first_unverified_phase"
            [ -n "$first_unverified_slug" ] && _uv_label="$first_unverified_phase ($(fmt_phase_name "${first_unverified_slug#*-}"))"
            suggest "/vbw:verify $first_unverified_phase -- Walk through $_uv_label changes manually"
          else
            suggest "/vbw:verify -- Walk through changes manually"
          fi
        fi
        if [ "$all_done" = true ] || [ "$next_phase_state" = "needs_reverification" ]; then
          if [ "$next_phase_state" = "needs_reverification" ]; then
            suggest "/vbw:vibe -- Re-verify Phase ${pd_next_phase:-} after remediation"
          elif ! suggest_milestone_recovery; then
            if [ "$deviation_count" -eq 0 ]; then
              suggest "/vbw:vibe --archive -- All phases complete, zero deviations"
            else
              suggest "/vbw:vibe --archive -- Archive completed work ($deviation_count deviation(s) logged)"
            fi
          else
            :
          fi
        elif [ -n "$current_uat_issues_phase" ]; then
          if [ "$current_uat_major_or_higher" = true ]; then
            suggest "/vbw:vibe -- Remediate UAT issues for $current_uat_issues_label"
          else
            suggest "/vbw:fix -- Fix minor UAT issues in $current_uat_issues_label"
          fi
        elif { [ -n "${next_unbuilt:-}" ] || [ -n "${next_unplanned:-}" ]; } && ! { [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; }; then
          target="${next_unbuilt:-$next_unplanned}"
          if [ -n "$next_undiscussed" ] && [ -n "$target" ] && [ "$next_undiscussed" = "$target" ]; then
            suggest "/vbw:discuss $target -- Discuss phase before planning"
          elif [ -n "$next_preseeded" ] && [ -n "$target" ] && [ "$next_preseeded" = "$target" ]; then
            for dir in "$PHASES_DIR"/*/; do
              [ -d "$dir" ] || continue
              pn=$(basename "$dir" | sed 's/[^0-9].*//')
              if [ "$pn" = "$target" ]; then
                tname=$(basename "$dir" | sed 's/^[0-9]*-//')
                suggest "/vbw:vibe -- Plan Phase $target: $(fmt_phase_name "$tname") (discussion pre-seeded from UAT)"
                break
              fi
            done
          elif [ -n "$target" ]; then
            for dir in "$PHASES_DIR"/*/; do
              [ -d "$dir" ] || continue
              pn=$(basename "$dir" | sed 's/[^0-9].*//')
              if [ "$pn" = "$target" ]; then
                tname=$(basename "$dir" | sed 's/^[0-9]*-//')
                suggest "/vbw:vibe -- Continue to Phase $target: $(fmt_phase_name "$tname")"
                break
              fi
            done
          else
            suggest "/vbw:vibe -- Continue to next phase"
          fi
        fi
        ;;
      fail)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/vbw:fix -- Fix plan $first_fail (failed QA)"
        else
          suggest "/vbw:fix -- Fix the failing checks"
        fi
        ;;
      partial)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/vbw:fix -- Fix plan $first_fail (partial failure)"
        else
          suggest "/vbw:fix -- Address partial failures"
        fi
        suggest "/vbw:vibe -- Continue despite warnings"
        ;;
      *)
        suggest "/vbw:vibe -- Continue building"
        ;;
    esac
    ;;

  fix)
    suggest "/vbw:qa -- Verify the fix"
    suggest "/vbw:vibe -- Continue building"
    ;;

  verify)
    case "$effective_result" in
      pass)
        if [ "$all_done" = true ]; then
          if ! suggest_milestone_recovery; then
            suggest "/vbw:vibe --archive -- All verified, ready to ship"
          fi
        else
          suggest "/vbw:vibe -- Continue to next phase"
        fi
        ;;
      issues_found)
        if [ "$uat_major_or_higher" = true ]; then
          if [ -n "$verify_target_phase" ]; then
            suggest "/vbw:vibe -- Remediate UAT issues for Phase $verify_target_phase"
          else
            suggest "/vbw:vibe -- Remediate UAT issues from the latest report"
          fi
        else
          suggest "/vbw:fix -- Fix minor issues found during UAT"
        fi
        ;;
      *)
        suggest "/vbw:vibe -- Continue building"
        ;;
    esac
    ;;

  debug)
    suggest "/vbw:fix -- Apply the fix"
    suggest "/vbw:vibe -- Continue building"
    ;;

  config)
    if [ "$has_project" = true ]; then
      suggest "/vbw:status -- View project state"
    else
      suggest "/vbw:vibe -- Define your project and start building"
    fi
    ;;

  archive)
    suggest "/vbw:vibe -- Start new work"
    ;;

  status)
    if [ "$next_phase_state" = "needs_reverification" ]; then
      suggest "/vbw:vibe -- Re-verify Phase ${pd_next_phase:-} after remediation"
    elif [ "$all_done" = true ]; then
      if ! suggest_milestone_recovery; then
        if [ "$deviation_count" -eq 0 ]; then
          suggest "/vbw:vibe --archive -- All phases complete, zero deviations"
        else
          suggest "/vbw:vibe --archive -- Archive completed work"
        fi
      else
        :
      fi
    elif [ -n "$current_uat_issues_phase" ]; then
      if [ "$current_uat_major_or_higher" = true ]; then
        suggest "/vbw:vibe -- Remediate UAT issues for $current_uat_issues_label"
      else
        suggest "/vbw:fix -- Fix minor UAT issues in $current_uat_issues_label"
      fi
    elif [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; then
      if [ -n "$first_unverified_phase" ]; then
        _uv_label="$first_unverified_phase"
        [ -n "$first_unverified_slug" ] && _uv_label="$first_unverified_phase ($(fmt_phase_name "${first_unverified_slug#*-}"))"
        suggest "/vbw:verify $first_unverified_phase -- Verify $_uv_label before continuing"
      else
        suggest "/vbw:verify -- Verify completed phases before continuing"
      fi
    elif [ -n "$next_unbuilt" ] || [ -n "$next_unplanned" ]; then
      target="${next_unbuilt:-$next_unplanned}"
      # If next phase needs discussion, suggest discuss (suppress continue)
      if [ -n "$next_undiscussed" ] && [ "$next_undiscussed" = "$target" ]; then
        suggest "/vbw:discuss $target -- Discuss phase before planning"
      elif [ -n "$next_preseeded" ] && [ "$next_preseeded" = "$target" ]; then
        for dir in "$PHASES_DIR"/*/; do
          [ -d "$dir" ] || continue
          pn=$(basename "$dir" | sed 's/[^0-9].*//')
          if [ "$pn" = "$target" ]; then
            tname=$(basename "$dir" | sed 's/^[0-9]*-//')
            suggest "/vbw:vibe -- Plan Phase $target: $(fmt_phase_name "$tname") (discussion pre-seeded from UAT)"
            break
          fi
        done
      else
        for dir in "$PHASES_DIR"/*/; do
          [ -d "$dir" ] || continue
          pn=$(basename "$dir" | sed 's/[^0-9].*//')
          if [ "$pn" = "$target" ]; then
            tname=$(basename "$dir" | sed 's/^[0-9]*-//')
            suggest "/vbw:vibe -- Continue Phase $target: $(fmt_phase_name "$tname")"
            break
          fi
        done
      fi
    else
      suggest "/vbw:vibe -- Start building"
    fi
    ;;

  map)
    suggest "/vbw:vibe -- Start building"
    suggest "/vbw:status -- View project state"
    ;;

  discuss|assumptions)
    suggest "/vbw:vibe --plan -- Plan this phase"
    suggest "/vbw:vibe -- Plan and execute in one flow"
    ;;

  resume)
    if [ "$next_phase_state" = "needs_reverification" ]; then
      suggest "/vbw:vibe -- Re-verify Phase ${pd_next_phase:-} after remediation"
    elif [ -n "$current_uat_issues_phase" ]; then
      if [ "$current_uat_major_or_higher" = true ]; then
        suggest "/vbw:vibe -- Remediate UAT issues for $current_uat_issues_label"
      else
        suggest "/vbw:fix -- Fix minor UAT issues in $current_uat_issues_label"
      fi
    elif [ "$all_done" = true ]; then
      if ! suggest_milestone_recovery; then
        if [ "$deviation_count" -eq 0 ]; then
          suggest "/vbw:vibe --archive -- All phases complete, zero deviations"
        else
          suggest "/vbw:vibe --archive -- Archive completed work ($deviation_count deviation(s) logged)"
        fi
      fi
    elif [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; then
      if [ -n "$first_unverified_phase" ]; then
        _uv_label="$first_unverified_phase"
        [ -n "$first_unverified_slug" ] && _uv_label="$first_unverified_phase ($(fmt_phase_name "${first_unverified_slug#*-}"))"
        suggest "/vbw:verify $first_unverified_phase -- Verify $_uv_label before continuing"
      else
        suggest "/vbw:verify -- Verify completed phases before continuing"
      fi
    elif [ -n "$next_unbuilt" ] || [ -n "$next_unplanned" ]; then
      target="${next_unbuilt:-$next_unplanned}"
      if [ -n "$next_undiscussed" ] && [ "$next_undiscussed" = "$target" ]; then
        suggest "/vbw:discuss $target -- Discuss phase before planning"
      elif [ -n "$next_preseeded" ] && [ "$next_preseeded" = "$target" ]; then
        for dir in "$PHASES_DIR"/*/; do
          [ -d "$dir" ] || continue
          pn=$(basename "$dir" | sed 's/[^0-9].*//')
          if [ "$pn" = "$target" ]; then
            tname=$(basename "$dir" | sed 's/^[0-9]*-//')
            suggest "/vbw:vibe -- Plan Phase $target: $(fmt_phase_name "$tname") (discussion pre-seeded from UAT)"
            break
          fi
        done
      else
        for dir in "$PHASES_DIR"/*/; do
          [ -d "$dir" ] || continue
          pn=$(basename "$dir" | sed 's/[^0-9].*//')
          if [ "$pn" = "$target" ]; then
            tname=$(basename "$dir" | sed 's/^[0-9]*-//')
            suggest "/vbw:vibe -- Continue Phase $target: $(fmt_phase_name "$tname")"
            break
          fi
        done
      fi
    else
      suggest "/vbw:vibe -- Continue building"
    fi
    suggest "/vbw:status -- View current progress"
    ;;

  *)
    # Fallback for help, whats-new, update, etc.
    if [ "$has_project" = true ]; then
      suggest "/vbw:vibe -- Continue building"
      suggest "/vbw:status -- View project progress"
    else
      suggest "/vbw:vibe -- Start a new project"
    fi
    ;;
esac

# Map staleness hint (skip for map/init/help commands)
case "$CMD" in
  map|init|help|update|whats-new|uninstall) ;;
  *)
    if [ "$has_project" = true ] && [ "$phase_count" -gt 0 ]; then
      if [ "$map_exists" = false ]; then
        suggest "/vbw:map -- Map your codebase for better planning"
      elif [ "$map_staleness" -gt 30 ]; then
        suggest "/vbw:map --incremental -- Codebase map is ${map_staleness}% stale"
      fi
    fi
    ;;
esac
