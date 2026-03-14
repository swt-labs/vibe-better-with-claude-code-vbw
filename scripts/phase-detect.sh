#!/bin/bash
set -u
trap 'exit 0' EXIT
# Pre-compute all project state for implement.md and other commands.
# Output: key=value pairs on stdout, one per line. Exit 0 always.

PLANNING_DIR=".vbw-planning"

# Source shared UAT helpers (extract_status_value, latest_non_source_uat)
_SCRIPT_DIR_PD="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=uat-utils.sh
. "$_SCRIPT_DIR_PD/uat-utils.sh"
# shellcheck source=summary-utils.sh
. "$_SCRIPT_DIR_PD/summary-utils.sh"

list_child_dirs_sorted() {
  local parent="$1"
  [ -d "$parent" ] || return 0

  find "$parent" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
    (sort -V 2>/dev/null || awk -F/ '{n=$NF; gsub(/[^0-9].*/,"",n); if (n == "") n=0; print (n+0)"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f2-)
}

# --- jq availability ---
JQ_AVAILABLE=false
if command -v jq &>/dev/null; then
  JQ_AVAILABLE=true
fi
echo "jq_available=$JQ_AVAILABLE"

# --- Planning directory ---
if [ -d "$PLANNING_DIR" ]; then
  echo "planning_dir_exists=true"
else
  echo "planning_dir_exists=false"
  echo "project_exists=false"
  echo "phases_dir=none"
  echo "phase_count=0"
  echo "next_phase=none"
  echo "next_phase_slug=none"
  echo "next_phase_state=no_phases"
  echo "next_phase_plans=0"
  echo "next_phase_summaries=0"
  echo "uat_issues_phase=none"
  echo "uat_issues_slug=none"
  echo "uat_issues_major_or_higher=false"
  echo "uat_issues_phases="
  echo "uat_issues_count=0"
  echo "uat_round_count=0"
  echo "has_shipped_milestones=false"
  echo "needs_milestone_rename=false"
  echo "milestone_uat_issues=false"
  echo "milestone_uat_phase=none"
  echo "milestone_uat_slug=none"
  echo "milestone_uat_major_or_higher=false"
  echo "milestone_uat_phase_dir=none"
  echo "milestone_uat_count=0"
  echo "milestone_uat_phase_dirs="
  echo "config_effort=balanced"
  echo "config_autonomy=standard"
  echo "config_auto_commit=true"
  echo "config_planning_tracking=manual"
  echo "config_auto_push=never"
  echo "config_verification_tier=standard"
  echo "config_prefer_teams=auto"
  echo "config_max_tasks_per_plan=5"
  echo "config_context_compiler=true"
  echo "config_require_phase_discussion=false"
  echo "config_auto_uat=false"
  echo "has_unverified_phases=false"
  echo "first_unverified_phase="
  echo "first_unverified_slug="
  echo "has_codebase_map=false"
  echo "brownfield=false"
  echo "execution_state=none"
  exit 0
fi

# --- Rename legacy milestones/default (brownfield hardening) ---
# SessionStart normally performs this migration, but hooks can be unavailable
# in some local-dev setups. Running it here keeps command routing grounded in
# canonical milestone slugs even when SessionStart didn't run.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$PLANNING_DIR/milestones/default" ] && [ -f "$SCRIPT_DIR/rename-default-milestone.sh" ]; then
  bash "$SCRIPT_DIR/rename-default-milestone.sh" "$PLANNING_DIR" 2>/dev/null || true
fi

# --- Project existence ---
PROJECT_EXISTS=false
if [ -f "$PLANNING_DIR/PROJECT.md" ]; then
  if ! grep -q '{project-description}' "$PLANNING_DIR/PROJECT.md" 2>/dev/null; then
    PROJECT_EXISTS=true
  fi
fi
echo "project_exists=$PROJECT_EXISTS"

# --- Root-canonical phases (no ACTIVE indirection) ---
PHASES_DIR="$PLANNING_DIR/phases"
echo "phases_dir=$PHASES_DIR"

# --- Shipped milestones detection ---
HAS_SHIPPED_MILESTONES=false
NEEDS_MILESTONE_RENAME=false
MILESTONE_SCAN_DIRS=()
if [ -d "$PLANNING_DIR/milestones" ]; then
  MILESTONE_DIRS=()
  while IFS= read -r _ms_dir; do
    [ -n "$_ms_dir" ] || continue
    MILESTONE_DIRS+=("${_ms_dir%/}/")
  done < <(list_child_dirs_sorted "$PLANNING_DIR/milestones")

  if [ ${#MILESTONE_DIRS[@]} -gt 0 ]; then
  for _ms_dir in "${MILESTONE_DIRS[@]}"; do
    [ -d "$_ms_dir" ] || continue

    # Canonical archived milestone marker
    if [ -f "${_ms_dir}SHIPPED.md" ]; then
      HAS_SHIPPED_MILESTONES=true
      MILESTONE_SCAN_DIRS+=("$_ms_dir")
      continue
    fi

    # Brownfield fallback: legacy milestones may be missing SHIPPED.md but still
    # contain archived phase artifacts. Treat as shipped for recovery scanning.
    if [ -d "${_ms_dir}phases" ] && ls -d "${_ms_dir}phases"/*/ >/dev/null 2>&1; then
      HAS_SHIPPED_MILESTONES=true
      MILESTONE_SCAN_DIRS+=("$_ms_dir")
    fi
  done
  fi  # end MILESTONE_DIRS length check
  [ -d "$PLANNING_DIR/milestones/default" ] && NEEDS_MILESTONE_RENAME=true
fi
echo "has_shipped_milestones=$HAS_SHIPPED_MILESTONES"
echo "needs_milestone_rename=$NEEDS_MILESTONE_RENAME"

# --- Early config read: require_phase_discussion (needed before phase scanning) ---
CFG_REQUIRE_PHASE_DISCUSSION="false"
CONFIG_FILE_EARLY="$PLANNING_DIR/config.json"
if [ "$JQ_AVAILABLE" = true ] && [ -f "$CONFIG_FILE_EARLY" ]; then
  _rpd=$(jq -r 'if .require_phase_discussion == null then false else .require_phase_discussion end' "$CONFIG_FILE_EARLY" 2>/dev/null) || true
  [ -n "${_rpd:-}" ] && CFG_REQUIRE_PHASE_DISCUSSION="$_rpd"
fi

# --- Phase scanning ---
PHASE_COUNT=0
NEXT_PHASE="none"
NEXT_PHASE_SLUG="none"
NEXT_PHASE_STATE="no_phases"
NEXT_PHASE_PLANS=0
NEXT_PHASE_SUMMARIES=0
UAT_ISSUES_PHASE="none"
UAT_ISSUES_SLUG="none"
UAT_ISSUES_MAJOR_OR_HIGHER=false
UAT_ISSUES_PHASES=""
UAT_ISSUES_COUNT=0
UAT_ROUND_COUNT=0

if [ -d "$PHASES_DIR" ]; then
  # Collect phase directories in numeric order (prevents 100 sorting before 11)
  # Fallback: extract numeric prefix from basename for systems without sort -V
  PHASE_DIRS=()
  while IFS= read -r _phase_dir; do
    [ -n "$_phase_dir" ] || continue
    PHASE_DIRS+=("${_phase_dir%/}/")
  done < <(list_child_dirs_sorted "$PHASES_DIR")

  # Count only canonical (numeric-prefixed) directories
  PHASE_COUNT=0
  for _dir in ${PHASE_DIRS[@]+"${PHASE_DIRS[@]}"}; do
    _bname=$(basename "$_dir")
    _num=$(echo "$_bname" | sed 's/^\([0-9]*\).*/\1/')
    if [ -n "$_num" ] && echo "$_num" | grep -qE '^[0-9]+$'; then
      PHASE_COUNT=$((PHASE_COUNT + 1))
    fi
  done

  if [ "$PHASE_COUNT" -eq 0 ]; then
    NEXT_PHASE_STATE="no_phases"
  elif [ ${#PHASE_DIRS[@]} -gt 0 ]; then
    # Priority override: unresolved UAT issues should route first for no-arg /vbw:vibe.
    # Guard: only consider phases that have at least one PLAN and one SUMMARY (i.e., executed).
    for DIR in "${PHASE_DIRS[@]}"; do
      DIRNAME=$(basename "$DIR")
      NUM=$(echo "$DIRNAME" | sed 's/^\([0-9]*\).*/\1/')

      # Skip non-canonical dirs whose basename doesn't start with digits
      if [ -z "$NUM" ] || ! echo "$NUM" | grep -qE '^[0-9]+$'; then
        continue
      fi

      # Skip phases without execution artifacts — a UAT file in a never-executed phase is orphaned/stale.
      # Also skip mid-execution phases (SUMMARY < PLAN) — UAT from a prior run is stale until re-execution completes.
      DIR_PLANS=$(find "$DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
      DIR_SUMMARIES=$(count_complete_summaries "$DIR")
      if [ "$DIR_PLANS" -eq 0 ] || [ "$DIR_SUMMARIES" -lt "$DIR_PLANS" ]; then
        continue
      fi

      UAT_FILE=$(current_uat "$DIR")
      if [ -f "$UAT_FILE" ]; then
        UAT_STATUS=$(extract_status_value "$UAT_FILE")
        if [ "$UAT_STATUS" = "issues_found" ]; then
          # First match becomes the priority routing target
          if [ "$UAT_ISSUES_PHASE" = "none" ]; then
            UAT_ISSUES_PHASE="$NUM"
            UAT_ISSUES_SLUG="$DIRNAME"
          fi

          # Accumulate all phases with issues
          UAT_ISSUES_COUNT=$((UAT_ISSUES_COUNT + 1))
          UAT_ISSUES_PHASES="${UAT_ISSUES_PHASES:+${UAT_ISSUES_PHASES},}$NUM"

          UAT_CRITICAL=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*critical' "$UAT_FILE" || true)
          UAT_MAJOR=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*major' "$UAT_FILE" || true)
          UAT_MINOR=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*minor' "$UAT_FILE" || true)
          UAT_TAGGED=$((UAT_CRITICAL + UAT_MAJOR + UAT_MINOR))

          # Brownfield-safe: if severity is absent, treat as major+ to avoid accidental quick-fix routing.
          if [ "$UAT_CRITICAL" -gt 0 ] || [ "$UAT_MAJOR" -gt 0 ] || [ "$UAT_TAGGED" -eq 0 ]; then
            UAT_ISSUES_MAJOR_OR_HIGHER=true
          fi
        fi
      fi
    done

    if [ "$UAT_ISSUES_PHASE" != "none" ]; then
      # Before routing to UAT remediation, check if any earlier phase has
      # pending work (incomplete execution or unplanned). Mid-execution phases
      # are skipped by the UAT scan (SUMMARIES < PLANS), so they become
      # invisible when a later phase has UAT issues. Fix: scan for the first
      # incomplete phase before the UAT issues phase and route there instead.
      _EARLIER_INCOMPLETE=false
      for _ei_dir in "${PHASE_DIRS[@]}"; do
        _ei_name=$(basename "$_ei_dir")
        _ei_num=$(echo "$_ei_name" | sed 's/^\([0-9]*\).*/\1/')
        [ -n "$_ei_num" ] && echo "$_ei_num" | grep -qE '^[0-9]+$' || continue
        # Stop once we reach or pass the UAT issues phase
        if [ "$_ei_num" -ge "$UAT_ISSUES_PHASE" ] 2>/dev/null; then
          break
        fi
        _ei_plans=$(find "$_ei_dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
        _ei_summaries=$(count_complete_summaries "$_ei_dir")
        if [ "$_ei_plans" -eq 0 ]; then
          # Mirror the discussion gate from the normal scan
          if [ "$CFG_REQUIRE_PHASE_DISCUSSION" = true ]; then
            _ei_contexts=$(find "$_ei_dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | wc -l | tr -d ' ')
            if [ "$_ei_contexts" -eq 0 ]; then
              NEXT_PHASE="$_ei_num"
              NEXT_PHASE_SLUG="$_ei_name"
              NEXT_PHASE_STATE="needs_discussion"
              NEXT_PHASE_PLANS="$_ei_plans"
              NEXT_PHASE_SUMMARIES="$_ei_summaries"
              _EARLIER_INCOMPLETE=true
              break
            fi
          fi
          NEXT_PHASE="$_ei_num"
          NEXT_PHASE_SLUG="$_ei_name"
          NEXT_PHASE_STATE="needs_plan_and_execute"
          NEXT_PHASE_PLANS="$_ei_plans"
          NEXT_PHASE_SUMMARIES="$_ei_summaries"
          _EARLIER_INCOMPLETE=true
          break
        elif [ "$_ei_summaries" -lt "$_ei_plans" ]; then
          NEXT_PHASE="$_ei_num"
          NEXT_PHASE_SLUG="$_ei_name"
          NEXT_PHASE_STATE="needs_execute"
          NEXT_PHASE_PLANS="$_ei_plans"
          NEXT_PHASE_SUMMARIES="$_ei_summaries"
          _EARLIER_INCOMPLETE=true
          break
        fi
      done

      if [ "$_EARLIER_INCOMPLETE" = false ]; then
        TARGET_DIR="$PHASES_DIR/$UAT_ISSUES_SLUG/"
        NEXT_PHASE="$UAT_ISSUES_PHASE"
        NEXT_PHASE_SLUG="$UAT_ISSUES_SLUG"
        # Compute UAT round count for display
        UAT_ROUND_COUNT=$(count_uat_rounds "$TARGET_DIR" "$UAT_ISSUES_PHASE")
        # Check if remediation is complete (stage=done) → needs re-verification
        _rem_stage="none"
        if [ -f "${TARGET_DIR}remediation/.uat-remediation-stage" ]; then
          # New round-dir state file (key=value format)
          _rem_stage=$(grep '^stage=' "${TARGET_DIR}remediation/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
          _rem_stage="${_rem_stage:-none}"
        elif [ -f "${TARGET_DIR}.uat-remediation-stage" ]; then
          # Legacy state file (single word)
          _rem_stage=$(tr -d '[:space:]' < "${TARGET_DIR}.uat-remediation-stage")
        fi
        # Pre-compute plan/summary counts (needed for state routing AND stale-stage reconciliation)
        NEXT_PHASE_PLANS=$(find "$TARGET_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
        NEXT_PHASE_SUMMARIES=$(count_complete_summaries "$TARGET_DIR")
        # Reconcile stale remediation stage: if execution already completed
        # (all plans have SUMMARY with status:complete) but the stage was never
        # advanced (session crash/kill/compaction), auto-advance to "done" so the
        # orchestrator routes to re-verification instead of re-execution.
        # Also check round-dir summaries for the new layout.
        # Scope to current round only — previous rounds' artifacts must not
        # inflate totals and cause premature execute→done auto-advance.
        _total_plans="$NEXT_PHASE_PLANS"
        _total_summaries="$NEXT_PHASE_SUMMARIES"
        # Read current round for scoped counting
        _cur_rr="01"
        if [ -f "${TARGET_DIR}remediation/.uat-remediation-stage" ]; then
          _cr_val=$(grep '^round=' "${TARGET_DIR}remediation/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
          _cur_rr="${_cr_val:-01}"
        fi
        # Count round-dir plans/summaries for current round only
        _rd_plans=$(find "$TARGET_DIR" -path "*/remediation/round-${_cur_rr}/R${_cur_rr}-PLAN.md" 2>/dev/null | wc -l | tr -d ' ')
        _rd_summaries=$(find "$TARGET_DIR" -path "*/remediation/round-${_cur_rr}/R${_cur_rr}-SUMMARY.md" 2>/dev/null | wc -l | tr -d ' ')
        _total_plans=$(( _total_plans + _rd_plans ))
        _total_summaries=$(( _total_summaries + _rd_summaries ))
        if [ "$_rem_stage" = "execute" ] && [ "$_total_plans" -gt 0 ] && [ "$_total_summaries" -ge "$_total_plans" ]; then
          # Write to whichever state file location exists
          if [ -f "${TARGET_DIR}remediation/.uat-remediation-stage" ]; then
            _cur_round=$(grep '^round=' "${TARGET_DIR}remediation/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
            _cur_layout=$(grep '^layout=' "${TARGET_DIR}remediation/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
            printf 'stage=done\nround=%s\nlayout=%s\n' "${_cur_round:-01}" "${_cur_layout:-round-dir}" > "${TARGET_DIR}remediation/.uat-remediation-stage"
          else
            echo "done" > "${TARGET_DIR}.uat-remediation-stage"
          fi
          _rem_stage="done"
        fi
        if [ "$_rem_stage" = "done" ] || [ "$_rem_stage" = "verify" ]; then
          NEXT_PHASE_STATE="needs_reverification"
        else
          NEXT_PHASE_STATE="needs_uat_remediation"
        fi
      fi
    else
      ALL_DONE=true
      if [ ${#PHASE_DIRS[@]} -gt 0 ]; then
      for DIR in "${PHASE_DIRS[@]}"; do
        DIRNAME=$(basename "$DIR")
        # Extract numeric prefix (e.g., "01" from "01-context-diet")
        NUM=$(echo "$DIRNAME" | sed 's/^\([0-9]*\).*/\1/')

        # Skip non-canonical dirs whose basename doesn't start with digits
        if [ -z "$NUM" ] || ! echo "$NUM" | grep -qE '^[0-9]+$'; then
          continue
        fi

        # Count PLAN and SUMMARY files
        P_COUNT=$(find "$DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
        S_COUNT=$(count_complete_summaries "$DIR")

        if [ "$P_COUNT" -eq 0 ]; then
          # Check if discussion is required before planning
          if [ "$CFG_REQUIRE_PHASE_DISCUSSION" = true ]; then
            # Check for CONTEXT.md (canonical phase-prefixed pattern only)
            C_COUNT=$(find "$DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | wc -l | tr -d ' ')
            if [ "$C_COUNT" -eq 0 ]; then
              if [ "$NEXT_PHASE" = "none" ]; then
                NEXT_PHASE="$NUM"
                NEXT_PHASE_SLUG="$DIRNAME"
                NEXT_PHASE_STATE="needs_discussion"
                NEXT_PHASE_PLANS="$P_COUNT"
                NEXT_PHASE_SUMMARIES="$S_COUNT"
              fi
              ALL_DONE=false
              break
            fi
          fi
          # Needs plan and execute
          if [ "$NEXT_PHASE" = "none" ]; then
            NEXT_PHASE="$NUM"
            NEXT_PHASE_SLUG="$DIRNAME"
            NEXT_PHASE_STATE="needs_plan_and_execute"
            NEXT_PHASE_PLANS="$P_COUNT"
            NEXT_PHASE_SUMMARIES="$S_COUNT"
          fi
          ALL_DONE=false
          break
        elif [ "$S_COUNT" -lt "$P_COUNT" ]; then
          # Has plans but not all have summaries — needs execute
          if [ "$NEXT_PHASE" = "none" ]; then
            NEXT_PHASE="$NUM"
            NEXT_PHASE_SLUG="$DIRNAME"
            NEXT_PHASE_STATE="needs_execute"
            NEXT_PHASE_PLANS="$P_COUNT"
            NEXT_PHASE_SUMMARIES="$S_COUNT"
          fi
          ALL_DONE=false
          break
        fi
        # This phase is complete, continue scanning
      done

      fi  # end PHASE_DIRS length check (all_done scan)

      if [ "$ALL_DONE" = true ] && [ "$NEXT_PHASE" = "none" ]; then
        NEXT_PHASE_STATE="all_done"
      fi
    fi
  fi
fi

# --- Unverified phases detection (for auto_uat routing) ---
# A phase is "unverified" if it is fully built (summaries >= plans, plans > 0)
# but has no completed UAT.md (excluding SOURCE-UAT.md which are verbatim copies
# from milestone remediation). A UAT with a non-terminal status (e.g. draft,
# in_progress) is treated as unverified. Terminal statuses: complete, passed,
# issues_found. Scan runs regardless of NEXT_PHASE_STATE so auto_uat can trigger
# mid-milestone (not only at all_done).
HAS_UNVERIFIED_PHASES=false
FIRST_UNVERIFIED_PHASE=""
FIRST_UNVERIFIED_SLUG=""
if [ ${#PHASE_DIRS[@]} -gt 0 ]; then
  for _uv_dir in ${PHASE_DIRS[@]+"${PHASE_DIRS[@]}"}; do
    [ -d "$_uv_dir" ] || continue
    # Count plans and summaries to confirm phase is fully built
    _uv_plans=$(find "$_uv_dir" -maxdepth 1 -name '[0-9]*-PLAN.md' ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')
    [ "$_uv_plans" -gt 0 ] || continue
    _uv_sums=$(count_complete_summaries "$_uv_dir")
    [ "$_uv_sums" -ge "$_uv_plans" ] || continue
    _uv_uat=$(current_uat "$_uv_dir")
    _uv_is_unverified=false
    if [ -z "$_uv_uat" ]; then
      _uv_is_unverified=true
    else
      # UAT file exists — check if it has a terminal status
      _uv_uat_status=$(extract_status_value "$_uv_uat")
      case "$_uv_uat_status" in
        complete|passed|issues_found) ;;  # terminal — phase is verified
        *) _uv_is_unverified=true ;;
      esac
    fi
    if [ "$_uv_is_unverified" = true ]; then
      HAS_UNVERIFIED_PHASES=true
      if [ -z "$FIRST_UNVERIFIED_PHASE" ]; then
        _uv_dirname=$(basename "$_uv_dir")
        FIRST_UNVERIFIED_PHASE=$(echo "$_uv_dirname" | sed 's/^\([0-9]*\).*/\1/')
        FIRST_UNVERIFIED_SLUG="$_uv_dirname"
      fi
      break
    fi
  done
fi

echo "phase_count=$PHASE_COUNT"
echo "next_phase=$NEXT_PHASE"
echo "next_phase_slug=$NEXT_PHASE_SLUG"
echo "next_phase_state=$NEXT_PHASE_STATE"
echo "next_phase_plans=$NEXT_PHASE_PLANS"
echo "next_phase_summaries=$NEXT_PHASE_SUMMARIES"
echo "has_unverified_phases=$HAS_UNVERIFIED_PHASES"
echo "first_unverified_phase=$FIRST_UNVERIFIED_PHASE"
echo "first_unverified_slug=$FIRST_UNVERIFIED_SLUG"
echo "uat_issues_phase=$UAT_ISSUES_PHASE"
echo "uat_issues_slug=$UAT_ISSUES_SLUG"
echo "uat_issues_major_or_higher=$UAT_ISSUES_MAJOR_OR_HIGHER"
echo "uat_issues_phases=$UAT_ISSUES_PHASES"
echo "uat_issues_count=$UAT_ISSUES_COUNT"
echo "uat_round_count=$UAT_ROUND_COUNT"

# --- Misnamed plan file diagnostic ---
# Detect type-first naming (PLAN-01.md instead of 01-PLAN.md) for actionable warnings.
MISNAMED_PLANS=false
if [ ${#PHASE_DIRS[@]} -gt 0 ]; then
  for _mn_dir in ${PHASE_DIRS[@]+"${PHASE_DIRS[@]}"}; do
    [ -d "$_mn_dir" ] || continue
    # Use -iregex for proper multi-digit matching without false positives on compounds like PLAN-01-RESEARCH.md
    if find "$_mn_dir" -maxdepth 1 \( -iname 'PLAN-[0-9].md' -o -iname 'PLAN-[0-9][0-9].md' -o -iname 'PLAN-[0-9]-SUMMARY.md' -o -iname 'PLAN-[0-9][0-9]-SUMMARY.md' -o -iname 'PLAN-[0-9]-CONTEXT.md' -o -iname 'PLAN-[0-9][0-9]-CONTEXT.md' -o -iname 'SUMMARY-[0-9].md' -o -iname 'SUMMARY-[0-9][0-9].md' -o -iname 'CONTEXT-[0-9].md' -o -iname 'CONTEXT-[0-9][0-9].md' -o -iregex '.*/plan-[0-9][0-9][0-9][0-9]*\.md' -o -iregex '.*/plan-[0-9][0-9][0-9][0-9]*-summary\.md' -o -iregex '.*/plan-[0-9][0-9][0-9][0-9]*-context\.md' -o -iregex '.*/summary-[0-9][0-9][0-9][0-9]*\.md' -o -iregex '.*/context-[0-9][0-9][0-9][0-9]*\.md' \) 2>/dev/null | grep -q .; then
      MISNAMED_PLANS=true
      break
    fi
  done
fi
echo "misnamed_plans=$MISNAMED_PLANS"

# --- Brownfield cross-reference: active remediation → milestone phases ---
# Build a set of milestone phase paths already covered by active remediation
# phases. This handles the case where create-remediation-phase.sh wasn't used
# (or ran before. .remediated markers existed), so .remediated files are missing.
REMEDIATED_MS_PATHS=""
if [ -d "$PHASES_DIR" ] && [ ${#PHASE_DIRS[@]} -gt 0 ]; then
  for _rx_dir in ${PHASE_DIRS[@]+"${PHASE_DIRS[@]}"}; do
    [ -d "$_rx_dir" ] || continue
    _rx_ctx=""
    for _rx_f in "$_rx_dir"[0-9]*-CONTEXT.md; do
      [ -f "$_rx_f" ] || continue
      _rx_ctx="$_rx_f"
      break
    done
    [ -f "$_rx_ctx" ] || continue
    _rx_src_ms=$(awk '/^source_milestone:/{gsub(/^source_milestone:[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit}' "$_rx_ctx" 2>/dev/null || true)
    _rx_src_ph=$(awk '/^source_phase:/{gsub(/^source_phase:[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit}' "$_rx_ctx" 2>/dev/null || true)
    if [ -n "$_rx_src_ms" ] && [ -n "$_rx_src_ph" ]; then
      _rx_resolved="$PLANNING_DIR/milestones/$_rx_src_ms/phases/$_rx_src_ph"
      REMEDIATED_MS_PATHS="${REMEDIATED_MS_PATHS:+${REMEDIATED_MS_PATHS}|}$_rx_resolved"
    fi
  done
fi

# --- Milestone UAT scanning (post-archive recovery) ---
# When active phases have no work (all_done or no_phases) and no active UAT remediation,
# scan archived milestones for unresolved UAT issues.
#
# Selection rule (deterministic): scan milestone dirs in version/numeric order,
# and keep the latest milestone that still has unresolved UAT. This preserves
# discoverability when newer milestones are clean but older shipped milestones
# still contain unresolved UAT issues.
MILESTONE_UAT_ISSUES=false
MILESTONE_UAT_PHASE="none"
MILESTONE_UAT_SLUG="none"
MILESTONE_UAT_MAJOR_OR_HIGHER=false
MILESTONE_UAT_PHASE_DIR="none"
MILESTONE_UAT_COUNT=0
MILESTONE_UAT_PHASE_DIRS=""

if [ "$UAT_ISSUES_PHASE" = "none" ] && { [ "$NEXT_PHASE_STATE" = "all_done" ] || [ "$NEXT_PHASE_STATE" = "no_phases" ]; } && [ "$HAS_SHIPPED_MILESTONES" = true ] && [ ${#MILESTONE_SCAN_DIRS[@]} -gt 0 ]; then
  for _ms_dir in "${MILESTONE_SCAN_DIRS[@]}"; do
    [ -d "$_ms_dir" ] || continue
    [ -d "${_ms_dir}phases" ] || continue

    MS_SLUG=$(basename "$_ms_dir")
    MS_PHASE_DIRS=()
    while IFS= read -r _ms_phase_dir; do
      [ -n "$_ms_phase_dir" ] || continue
      MS_PHASE_DIRS+=("${_ms_phase_dir%/}/")
    done < <(list_child_dirs_sorted "${_ms_dir}phases")

    _ms_issue_count=0
    _ms_issue_phase="none"
    _ms_issue_phase_dirs=""
    _ms_issue_major_or_higher=false

    if [ ${#MS_PHASE_DIRS[@]} -gt 0 ]; then
    for _ms_phase_dir in "${MS_PHASE_DIRS[@]}"; do
      [ -d "$_ms_phase_dir" ] || continue
      _ms_dirname=$(basename "$_ms_phase_dir")
      _ms_num=$(echo "$_ms_dirname" | sed 's/^\([0-9]*\).*/\1/')

      # Skip non-canonical dirs whose basename doesn't start with digits
      if [ -z "$_ms_num" ] || ! echo "$_ms_num" | grep -qE '^[0-9]+$'; then
        continue
      fi

      # Skip phases already remediated (marker written by create-remediation-phase.sh)
      [ -f "${_ms_phase_dir}.remediated" ] && continue

      # Skip phases covered by active remediation (brownfield: no .remediated marker)
      _ms_phase_canonical="${_ms_phase_dir%/}"
      if [ -n "$REMEDIATED_MS_PATHS" ] && echo "$REMEDIATED_MS_PATHS" | grep -qF "$_ms_phase_canonical"; then
        continue
      fi

      # Skip phases without execution artifacts
      _ms_plans=$(find "$_ms_phase_dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
      _ms_summaries=$(count_complete_summaries "$_ms_phase_dir")
      if [ "$_ms_plans" -eq 0 ] || [ "$_ms_summaries" -lt "$_ms_plans" ]; then
        continue
      fi

      _ms_uat=$(current_uat "$_ms_phase_dir")
      if [ -f "$_ms_uat" ]; then
        _ms_uat_status=$(extract_status_value "$_ms_uat")
        if [ "$_ms_uat_status" = "issues_found" ]; then
          _ms_issue_count=$((_ms_issue_count + 1))
          # First match becomes the primary (for backward compat)
          if [ "$_ms_issue_phase" = "none" ]; then
            _ms_issue_phase="$_ms_num"
          fi
          _ms_issue_phase_dirs="${_ms_issue_phase_dirs:+${_ms_issue_phase_dirs}|}${_ms_phase_dir%/}"

          _ms_critical=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*critical' "$_ms_uat" || true)
          _ms_major=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*major' "$_ms_uat" || true)
          _ms_minor=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*minor' "$_ms_uat" || true)
          _ms_tagged=$((_ms_critical + _ms_major + _ms_minor))

          if [ "$_ms_critical" -gt 0 ] || [ "$_ms_major" -gt 0 ] || [ "$_ms_tagged" -eq 0 ]; then
            _ms_issue_major_or_higher=true
          fi
        fi
      fi
    done
    fi  # end MS_PHASE_DIRS length check

    if [ "$_ms_issue_count" -gt 0 ]; then
      # Keep scanning: last match wins, so we surface the latest milestone with issues.
      MILESTONE_UAT_ISSUES=true
      MILESTONE_UAT_PHASE="$_ms_issue_phase"
      MILESTONE_UAT_SLUG="$MS_SLUG"
      # Primary phase dir = first match (for backward compat with single-phase consumers)
      MILESTONE_UAT_PHASE_DIR=$(echo "$_ms_issue_phase_dirs" | cut -d'|' -f1)
      MILESTONE_UAT_MAJOR_OR_HIGHER="$_ms_issue_major_or_higher"
      MILESTONE_UAT_COUNT="$_ms_issue_count"
      MILESTONE_UAT_PHASE_DIRS="$_ms_issue_phase_dirs"
    fi
  done
fi

echo "milestone_uat_issues=$MILESTONE_UAT_ISSUES"
echo "milestone_uat_phase=$MILESTONE_UAT_PHASE"
echo "milestone_uat_slug=$MILESTONE_UAT_SLUG"
echo "milestone_uat_major_or_higher=$MILESTONE_UAT_MAJOR_OR_HIGHER"
echo "milestone_uat_phase_dir=$MILESTONE_UAT_PHASE_DIR"
echo "milestone_uat_count=$MILESTONE_UAT_COUNT"
echo "milestone_uat_phase_dirs=$MILESTONE_UAT_PHASE_DIRS"

# --- Config values ---
CONFIG_FILE="$PLANNING_DIR/config.json"

# Defaults (from config/defaults.json)
CFG_EFFORT="balanced"
CFG_AUTONOMY="standard"
CFG_AUTO_COMMIT="true"
CFG_PLANNING_TRACKING="manual"
CFG_AUTO_PUSH="never"
CFG_VERIFICATION_TIER="standard"
CFG_PREFER_TEAMS="auto"
CFG_MAX_TASKS="5"
CFG_COMPACTION="130000"
CFG_CONTEXT_COMPILER="true"
CFG_AUTO_UAT="false"

if [ "$JQ_AVAILABLE" = true ] && [ -f "$CONFIG_FILE" ]; then
  # Single jq call to extract all config values (reduces subprocesses to 1)
  eval "$(jq -r '
    "CFG_EFFORT=\(.effort // "balanced")",
    "CFG_AUTONOMY=\(.autonomy // "standard")",
    "CFG_AUTO_COMMIT=\(if .auto_commit == null then true else .auto_commit end)",
    "CFG_PLANNING_TRACKING=\(.planning_tracking // "manual")",
    "CFG_AUTO_PUSH=\(.auto_push // "never")",
    "CFG_VERIFICATION_TIER=\(.verification_tier // "standard")",
    "CFG_PREFER_TEAMS=\(.prefer_teams // "auto")",
    "CFG_MAX_TASKS=\(.max_tasks_per_plan // 5)",
    "CFG_CONTEXT_COMPILER=\(if .context_compiler == null then true else .context_compiler end)",
    "CFG_COMPACTION=\(.compaction_threshold // 130000)",
    "CFG_AUTO_UAT=\(if .auto_uat == null then false else .auto_uat end)"
  ' "$CONFIG_FILE" 2>/dev/null)" || true
fi

echo "config_effort=$CFG_EFFORT"
echo "config_autonomy=$CFG_AUTONOMY"
echo "config_auto_commit=$CFG_AUTO_COMMIT"
echo "config_planning_tracking=$CFG_PLANNING_TRACKING"
echo "config_auto_push=$CFG_AUTO_PUSH"
echo "config_verification_tier=$CFG_VERIFICATION_TIER"
echo "config_prefer_teams=$CFG_PREFER_TEAMS"
echo "config_max_tasks_per_plan=$CFG_MAX_TASKS"
echo "config_context_compiler=$CFG_CONTEXT_COMPILER"
echo "config_require_phase_discussion=$CFG_REQUIRE_PHASE_DISCUSSION"
echo "config_auto_uat=$CFG_AUTO_UAT"
echo "config_compaction_threshold=$CFG_COMPACTION"

# --- Codebase map status ---
if [ -f "$PLANNING_DIR/codebase/META.md" ]; then
  echo "has_codebase_map=true"
else
  echo "has_codebase_map=false"
fi

# --- Brownfield detection ---
BROWNFIELD=false
if git ls-files . 2>/dev/null | head -1 | grep -q .; then
  BROWNFIELD=true
fi
echo "brownfield=$BROWNFIELD"

# --- Execution state ---
EXEC_STATE_FILE="$PLANNING_DIR/.execution-state.json"
EXEC_STATE="none"
if [ -f "$EXEC_STATE_FILE" ]; then
  if [ "$JQ_AVAILABLE" = true ]; then
    EXEC_STATE=$(jq -r '.status // "none"' "$EXEC_STATE_FILE" 2>/dev/null)
  else
    # Fallback: grep for status field
    EXEC_STATE=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$EXEC_STATE_FILE" 2>/dev/null | head -1 | sed 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    if [ -z "$EXEC_STATE" ]; then
      EXEC_STATE="none"
    fi
  fi
fi
echo "execution_state=$EXEC_STATE"

exit 0
