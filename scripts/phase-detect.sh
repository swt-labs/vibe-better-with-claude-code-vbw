#!/bin/bash
set -u
trap 'exit 0' EXIT
# Pre-compute all project state for implement.md and other commands.
# Output: key=value pairs on stdout, one per line. Exit 0 always.

PLANNING_DIR=".vbw-planning"

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
  echo "active_milestone=none"
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
  echo "config_effort=balanced"
  echo "config_autonomy=standard"
  echo "config_auto_commit=true"
  echo "config_planning_tracking=manual"
  echo "config_auto_push=never"
  echo "config_verification_tier=standard"
  echo "config_prefer_teams=always"
  echo "config_max_tasks_per_plan=5"
  echo "config_context_compiler=true"
  echo "has_codebase_map=false"
  echo "brownfield=false"
  echo "execution_state=none"
  exit 0
fi

# --- Project existence ---
PROJECT_EXISTS=false
if [ -f "$PLANNING_DIR/PROJECT.md" ]; then
  if ! grep -q '{project-description}' "$PLANNING_DIR/PROJECT.md" 2>/dev/null; then
    PROJECT_EXISTS=true
  fi
fi
echo "project_exists=$PROJECT_EXISTS"

# --- Active milestone resolution ---
ACTIVE_MILESTONE="none"
ACTIVE_MILESTONE_ERROR=false
PHASES_DIR="$PLANNING_DIR/phases"

if [ -f "$PLANNING_DIR/ACTIVE" ]; then
  SLUG=$(cat "$PLANNING_DIR/ACTIVE" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$SLUG" ]; then
    CANDIDATE="$PLANNING_DIR/milestones/$SLUG/phases"
    if [ -d "$CANDIDATE" ]; then
      ACTIVE_MILESTONE="$SLUG"
      PHASES_DIR="$CANDIDATE"
    else
      ACTIVE_MILESTONE_ERROR=true
      # Fall back to default phases dir
    fi
  fi
fi
echo "active_milestone=$ACTIVE_MILESTONE"
echo "active_milestone_error=$ACTIVE_MILESTONE_ERROR"
echo "phases_dir=$PHASES_DIR"

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
  PHASE_DIRS=$(ls -d "$PHASES_DIR"/*/ 2>/dev/null | (sort -V 2>/dev/null || awk -F/ '{n=$(NF-1); gsub(/[^0-9].*/,"",n); print (n+0)"\t"$0}' | sort -n | cut -f2-))

  for DIR in $PHASE_DIRS; do
    PHASE_COUNT=$((PHASE_COUNT + 1))
  done

  if [ "$PHASE_COUNT" -eq 0 ]; then
    NEXT_PHASE_STATE="no_phases"
  else
    # Priority override: unresolved UAT issues should route first for no-arg /vbw:vibe.
    # Guard: only consider phases that have at least one PLAN and one SUMMARY (i.e., executed).
    for DIR in $PHASE_DIRS; do
      DIRNAME=$(basename "$DIR")
      NUM=$(echo "$DIRNAME" | sed 's/^\([0-9]*\).*/\1/')

      # Skip phases without execution artifacts — a UAT file in a never-executed phase is orphaned/stale.
      # Also skip mid-execution phases (SUMMARY < PLAN) — UAT from a prior run is stale until re-execution completes.
      DIR_PLANS=$(ls "$DIR"[0-9]*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
      DIR_SUMMARIES=$(ls "$DIR"[0-9]*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')
      if [ "$DIR_PLANS" -eq 0 ] || [ "$DIR_SUMMARIES" -lt "$DIR_PLANS" ]; then
        continue
      fi

      UAT_FILE=$(ls "$DIR"[0-9]*-UAT.md 2>/dev/null | sort | tail -1 || true)
      if [ -f "$UAT_FILE" ]; then
        UAT_STATUS=$(grep -m1 '^status:' "$UAT_FILE" 2>/dev/null | sed 's/status:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' || true)
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
      for DIR in $PHASE_DIRS; do
        DIRNAME=$(basename "$DIR")
        # Extract numeric prefix (e.g., "01" from "01-context-diet")
        NUM=$(echo "$DIRNAME" | sed 's/^\([0-9]*\).*/\1/')

        # Count PLAN and SUMMARY files
        P_COUNT=$(ls "$DIR"[0-9]*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
        S_COUNT=$(ls "$DIR"[0-9]*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')

        if [ "$P_COUNT" -eq 0 ]; then
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
