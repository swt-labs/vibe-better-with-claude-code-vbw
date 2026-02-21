#!/bin/bash
set -u
trap 'exit 0' EXIT
# Pre-compute all project state for implement.md and other commands.
# Output: key=value pairs on stdout, one per line. Exit 0 always.

PLANNING_DIR=".vbw-planning"

list_child_dirs_sorted() {
  local parent="$1"
  [ -d "$parent" ] || return 0

  find "$parent" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
    (sort -V 2>/dev/null || awk -F/ '{n=$NF; gsub(/[^0-9].*/,"",n); if (n == "") n=0; print (n+0)"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f2-)
}

extract_status_value() {
  local file="$1"
  awk '
    {
      line = $0
      if (tolower(line) ~ /^[[:space:]]*status[[:space:]]*:/) {
        value = line
        sub(/^[^:]*:[[:space:]]*/, "", value)
        gsub(/[[:space:]]+$/, "", value)
        print tolower(value)
        exit
      }
    }
  ' "$file" 2>/dev/null || true
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
  echo "config_prefer_teams=always"
  echo "config_max_tasks_per_plan=5"
  echo "config_context_compiler=true"
  echo "config_require_phase_discussion=false"
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
      DIR_PLANS=$(ls "$DIR"[0-9]*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
      DIR_SUMMARIES=$(ls "$DIR"[0-9]*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')
      if [ "$DIR_PLANS" -eq 0 ] || [ "$DIR_SUMMARIES" -lt "$DIR_PLANS" ]; then
        continue
      fi

      UAT_FILE=$(ls "$DIR"[0-9]*-UAT.md 2>/dev/null | grep -v 'SOURCE-UAT\.md$' | sort | tail -1 || true)
      if [ -f "$UAT_FILE" ]; then
        UAT_STATUS=$(extract_status_value "$UAT_FILE")
        if [ "$UAT_STATUS" = "issues_found" ]; then
          UAT_ISSUES_PHASE="$NUM"
          UAT_ISSUES_SLUG="$DIRNAME"

          UAT_CRITICAL=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*critical' "$UAT_FILE" || true)
          UAT_MAJOR=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*major' "$UAT_FILE" || true)
          UAT_MINOR=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*minor' "$UAT_FILE" || true)
          UAT_TAGGED=$((UAT_CRITICAL + UAT_MAJOR + UAT_MINOR))

          # Brownfield-safe: if severity is absent, treat as major+ to avoid accidental quick-fix routing.
          if [ "$UAT_CRITICAL" -gt 0 ] || [ "$UAT_MAJOR" -gt 0 ] || [ "$UAT_TAGGED" -eq 0 ]; then
            UAT_ISSUES_MAJOR_OR_HIGHER=true
          fi
          break
        fi
      fi
    done

    if [ "$UAT_ISSUES_PHASE" != "none" ]; then
      TARGET_DIR="$PHASES_DIR/$UAT_ISSUES_SLUG/"
      NEXT_PHASE="$UAT_ISSUES_PHASE"
      NEXT_PHASE_SLUG="$UAT_ISSUES_SLUG"
      NEXT_PHASE_STATE="needs_uat_remediation"
      NEXT_PHASE_PLANS=$(ls "$TARGET_DIR"[0-9]*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
      NEXT_PHASE_SUMMARIES=$(ls "$TARGET_DIR"[0-9]*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')
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
        P_COUNT=$(ls "$DIR"[0-9]*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
        S_COUNT=$(ls "$DIR"[0-9]*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')

        if [ "$P_COUNT" -eq 0 ]; then
          # Check if discussion is required before planning
          if [ "$CFG_REQUIRE_PHASE_DISCUSSION" = true ]; then
            # Check for CONTEXT.md (canonical phase-prefixed pattern only)
            C_COUNT=$(ls "$DIR"[0-9]*-CONTEXT.md 2>/dev/null | wc -l | tr -d ' ')
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

echo "phase_count=$PHASE_COUNT"
echo "next_phase=$NEXT_PHASE"
echo "next_phase_slug=$NEXT_PHASE_SLUG"
echo "next_phase_state=$NEXT_PHASE_STATE"
echo "next_phase_plans=$NEXT_PHASE_PLANS"
echo "next_phase_summaries=$NEXT_PHASE_SUMMARIES"
echo "uat_issues_phase=$UAT_ISSUES_PHASE"
echo "uat_issues_slug=$UAT_ISSUES_SLUG"
echo "uat_issues_major_or_higher=$UAT_ISSUES_MAJOR_OR_HIGHER"

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

      # Skip phases without execution artifacts
      _ms_plans=$(ls "$_ms_phase_dir"[0-9]*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
      _ms_summaries=$(ls "$_ms_phase_dir"[0-9]*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')
      if [ "$_ms_plans" -eq 0 ] || [ "$_ms_summaries" -lt "$_ms_plans" ]; then
        continue
      fi

      _ms_uat=$(ls "$_ms_phase_dir"[0-9]*-UAT.md 2>/dev/null | grep -v 'SOURCE-UAT\.md$' | sort | tail -1 || true)
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
CFG_PREFER_TEAMS="always"
CFG_MAX_TASKS="5"
CFG_COMPACTION="130000"
CFG_CONTEXT_COMPILER="true"

if [ "$JQ_AVAILABLE" = true ] && [ -f "$CONFIG_FILE" ]; then
  # Single jq call to extract all config values (reduces subprocesses to 1)
  eval "$(jq -r '
    "CFG_EFFORT=\(.effort // "balanced")",
    "CFG_AUTONOMY=\(.autonomy // "standard")",
    "CFG_AUTO_COMMIT=\(if .auto_commit == null then true else .auto_commit end)",
    "CFG_PLANNING_TRACKING=\(.planning_tracking // "manual")",
    "CFG_AUTO_PUSH=\(.auto_push // "never")",
    "CFG_VERIFICATION_TIER=\(.verification_tier // "standard")",
    "CFG_PREFER_TEAMS=\(.prefer_teams // "always")",
    "CFG_MAX_TASKS=\(.max_tasks_per_plan // 5)",
    "CFG_CONTEXT_COMPILER=\(if .context_compiler == null then true else .context_compiler end)",
    "CFG_COMPACTION=\(.compaction_threshold // 130000)"
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
