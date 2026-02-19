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

if [ -d "$PLANNING_DIR" ]; then

  # Resolve phases directory (milestone-aware)
  PHASES_DIR="$PLANNING_DIR/phases"
  if [ -f "$PLANNING_DIR/ACTIVE" ]; then
    ACTIVE=$(tr -d '[:space:]' < "$PLANNING_DIR/ACTIVE")
    if [ -d "$PLANNING_DIR/milestones/$ACTIVE/phases" ]; then
      PHASES_DIR="$PLANNING_DIR/milestones/$ACTIVE/phases"
    fi
  fi

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
  fi

  # Scan phases
  if [ -d "$PHASES_DIR" ]; then
    # Sort phase dirs numerically (prevents 100 sorting before 11)
    # Fallback: extract numeric prefix from basename for systems without sort -V
    phase_dirs_sorted=$(ls -d "$PHASES_DIR"/*/ 2>/dev/null | (sort -V 2>/dev/null || awk -F/ '{n=$(NF-1); gsub(/[^0-9].*/,"",n); print (n+0)"\t"$0}' | sort -n | cut -f2-))
    for dir in $phase_dirs_sorted; do
      [ -d "$dir" ] || continue
      phase_count=$((phase_count + 1))
      phase_num=$(basename "$dir" | sed 's/[^0-9].*//')
      phase_slug=$(basename "$dir" | sed 's/^[0-9]*-//')

      plans=$(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
      summaries=$(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-SUMMARY.md' 2>/dev/null | wc -l | tr -d ' ')

      if [ "$plans" -eq 0 ] && [ -z "$next_unplanned" ]; then
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

    # If no unplanned/unbuilt, use the last phase (most recently completed)
    if [ -z "$active_phase_dir" ] && [ -n "$last_phase_dir" ]; then
      active_phase_dir="$last_phase_dir"
      active_phase_num="$last_phase_num"
      active_phase_name="$last_phase_name"
      active_phase_plans="$last_phase_plans"
    fi

    # All done if phases exist and nothing is unplanned/unbuilt
    if [ "$phase_count" -gt 0 ] && [ -z "$next_unplanned" ] && [ -z "$next_unbuilt" ]; then
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
        d=$(grep -m1 '^deviations:' "$sf" 2>/dev/null | sed 's/deviations:[[:space:]]*//' || true)
        case "$d" in
          0|"[]"|"") ;;  # zero deviations
          [0-9]*) deviation_count=$((deviation_count + d)) ;;
          *) deviation_count=$((deviation_count + 1)) ;;  # non-empty, non-numeric = at least 1
        esac
        # Check for failed/partial status
        s=$(grep -m1 '^status:' "$sf" 2>/dev/null | sed 's/status:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' || true)
        if [ "$s" = "failed" ] || [ "$s" = "partial" ]; then
          plan_id=$(basename "$sf" | sed 's/-SUMMARY.md//')
          failing_plan_ids="${failing_plan_ids:+$failing_plan_ids }$plan_id"
        fi
      done

      # Check for completed UAT in active phase
      for uf in "$active_phase_dir"/*-UAT.md; do
        [ -f "$uf" ] || continue
        us=$(grep -m1 '^status:' "$uf" 2>/dev/null | sed 's/status:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' || true)
        if [ "$us" = "complete" ]; then
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
    for dir in $(ls -d "$PHASES_DIR"/*/ 2>/dev/null | (sort -V 2>/dev/null || awk -F/ '{n=$(NF-1); gsub(/[^0-9].*/,"",n); print (n+0)"\t"$0}' | sort -n | cut -f2-)); do
      [ -d "$dir" ] || continue
      # Guard: skip phases without execution artifacts (matching phase-detect.sh)
      _plans=$(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
      _summaries=$(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-SUMMARY.md' 2>/dev/null | wc -l | tr -d ' ')
      if [ "$_plans" -eq 0 ] || [ "$_summaries" -lt "$_plans" ]; then
        continue
      fi
      _uat=$(ls -1 "$dir"[0-9]*-UAT.md 2>/dev/null | sort | tail -1 || true)
      if [ -f "$_uat" ]; then
        _us=$(grep -m1 '^status:' "$_uat" 2>/dev/null | sed 's/status:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' || true)
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
    verify_target_uat=$(ls -1 "$verify_target_phase_dir"/[0-9]*-UAT.md 2>/dev/null | sort | tail -1 || true)
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
        # Suggest UAT for cautious/standard autonomy when no UAT exists
        if [ "$has_uat" = false ] && { [ "$cfg_autonomy" = "cautious" ] || [ "$cfg_autonomy" = "standard" ]; }; then
          suggest "/vbw:verify -- Walk through changes before continuing"
        fi
        if [ "$all_done" = true ]; then
          if [ "$deviation_count" -eq 0 ]; then
            suggest "/vbw:vibe --archive -- All phases complete, zero deviations"
          else
            suggest "/vbw:vibe --archive -- Archive completed work ($deviation_count deviation(s) logged)"
            suggest "/vbw:qa -- Review before archiving"
          fi
        elif [ -n "$next_unbuilt" ] || [ -n "$next_unplanned" ]; then
          target="${next_unbuilt:-$next_unplanned}"
          if [ -n "$active_phase_name" ] && [ "$target" != "$active_phase_num" ]; then
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
        # Suggest UAT for cautious/standard autonomy when no UAT exists
        if [ "$has_uat" = false ] && { [ "$cfg_autonomy" = "cautious" ] || [ "$cfg_autonomy" = "standard" ]; }; then
          suggest "/vbw:verify -- Walk through changes manually"
        fi
        if [ "$all_done" = true ]; then
          if [ "$deviation_count" -eq 0 ]; then
            suggest "/vbw:vibe --archive -- All phases complete, zero deviations"
          else
            suggest "/vbw:vibe --archive -- Archive completed work ($deviation_count deviation(s) logged)"
          fi
        else
          target="${next_unbuilt:-$next_unplanned}"
          if [ -n "$target" ]; then
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
          suggest "/vbw:vibe --archive -- All verified, ready to ship"
        else
          suggest "/vbw:vibe -- Continue to next phase"
        fi
        ;;
      issues_found)
        if [ "$uat_major_or_higher" = true ]; then
          if [ -n "$verify_target_phase" ]; then
            suggest "/vbw:vibe -- Continue UAT remediation for Phase $verify_target_phase"
          else
            suggest "/vbw:vibe -- Continue UAT remediation from the latest report"
          fi
          suggest "/vbw:verify --resume -- Continue testing after changes"
        else
          suggest "/vbw:fix -- Fix the issues found during UAT"
          suggest "/vbw:verify --resume -- Continue testing after fix"
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
    if [ "$all_done" = true ]; then
      if [ "$deviation_count" -eq 0 ]; then
        suggest "/vbw:vibe --archive -- All phases complete, zero deviations"
      else
        suggest "/vbw:vibe --archive -- Archive completed work"
      fi
    elif [ -n "$next_unbuilt" ] || [ -n "$next_unplanned" ]; then
      target="${next_unbuilt:-$next_unplanned}"
      for dir in "$PHASES_DIR"/*/; do
        [ -d "$dir" ] || continue
        pn=$(basename "$dir" | sed 's/[^0-9].*//')
        if [ "$pn" = "$target" ]; then
          tname=$(basename "$dir" | sed 's/^[0-9]*-//')
          suggest "/vbw:vibe -- Continue Phase $target: $(fmt_phase_name "$tname")"
          break
        fi
      done
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
    suggest "/vbw:vibe -- Continue building"
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
