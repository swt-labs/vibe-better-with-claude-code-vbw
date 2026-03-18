#!/usr/bin/env bash
set -euo pipefail

# compile-context.sh <phase-number> <role> [phases-dir] [plan-path]
# Produces .context-{role}.md in the phase directory with role-specific context.
# Exit 0 on success, exit 1 when phase directory not found.

if [ $# -lt 2 ]; then
  echo "Usage: compile-context.sh <phase-number> <role> [phases-dir]" >&2
  exit 1
fi

PHASE="$1"
ROLE="$2"
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
PHASES_DIR="${3:-${PLANNING_DIR}/phases}"
PLAN_PATH="${4:-}"

# Milestone path guard: refuse to compile context for archived milestone directories.
# Execution must happen in active phases (.vbw-planning/phases/), not archived milestones.
case "$PHASES_DIR" in
  */.vbw-planning/milestones/*|.vbw-planning/milestones/*)
    echo "Error: refusing to compile context for archived milestone path: $PHASES_DIR" >&2
    echo "Execution must target active phases in .vbw-planning/phases/" >&2
    exit 1
    ;;
esac

# --- Update context index entry (REQ-04) ---
# Writes/updates an entry in .vbw-planning/.cache/context-index.json
# Fail-silent: index is a non-critical debugging/introspection tool
update_context_index() {
  local cache_key="$1" context_path="$2" role="$3" phase="$4"
  local index_path="${PLANNING_DIR}/.cache/context-index.json"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

  mkdir -p "$(dirname "$index_path")" 2>/dev/null || return 0

  # Create index file if it doesn't exist
  if [ ! -f "$index_path" ]; then
    echo '{"entries":{}}' > "$index_path" 2>/dev/null || return 0
  fi

  # Upsert entry using jq (atomic via temp file)
  local tmp
  tmp=$(mktemp 2>/dev/null) || return 0
  if jq --arg key "$cache_key" \
       --arg path "$context_path" \
       --arg role "$role" \
       --arg phase "$phase" \
       --arg ts "$timestamp" \
       '.entries[$key] = {path: $path, role: $role, phase: $phase, timestamp: $ts}' \
       "$index_path" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$index_path" 2>/dev/null || rm -f "$tmp"
  else
    rm -f "$tmp"
  fi
}

# Strip leading zeros for ROADMAP matching (ROADMAP uses "Phase 2:", not "Phase 02:")
PHASE_NUM=$(echo "$PHASE" | sed 's/^0*//')
if [ -z "$PHASE_NUM" ]; then PHASE_NUM="0"; fi

# --- Find phase directory (with zero-pad normalization) ---
PHASE_DIR=$(find "$PHASES_DIR" -maxdepth 1 -type d -name "${PHASE}-*" 2>/dev/null | head -1)

# --- Resolve per-plan research file (prefer {NN}-{MM}-RESEARCH.md, fall back to {NN}-RESEARCH.md) ---
resolve_research_file() {
  local phase_dir="$1" plan_path="$2"
  # If plan path provided, try per-plan research first
  if [ -n "$plan_path" ] && [ -f "$plan_path" ]; then
    local plan_basename
    plan_basename=$(basename "$plan_path" .md)
    # Extract {NN}-{MM} prefix from plan filename like "03-12-PLAN.md" -> "03-12"
    local plan_prefix
    plan_prefix=$(echo "$plan_basename" | sed 's/-PLAN$//')
    local per_plan_research="${phase_dir}/${plan_prefix}-RESEARCH.md"
    if [ -f "$per_plan_research" ]; then
      echo "$per_plan_research"
      return
    fi
  fi
  # Fall back to any *-RESEARCH.md (legacy single-file or first per-plan match)
  find "$phase_dir" -maxdepth 1 -name "*-RESEARCH.md" -print -quit 2>/dev/null || true
}
if [ -z "$PHASE_DIR" ]; then
  # Try zero-padded version: "1" -> "01"
  PADDED=$(printf "%02d" "$PHASE" 2>/dev/null || echo "$PHASE")
  PHASE_DIR=$(find "$PHASES_DIR" -maxdepth 1 -type d -name "${PADDED}-*" 2>/dev/null | head -1)
fi
if [ -z "$PHASE_DIR" ]; then
  echo "Phase ${PHASE} directory not found" >&2
  exit 1
fi

# --- Extract phase metadata from ROADMAP.md ---
ROADMAP="$PLANNING_DIR/ROADMAP.md"

PHASE_SECTION=""
PHASE_GOAL="Not available"
PHASE_REQS="Not available"
PHASE_SUCCESS="Not available"

if [ -f "$ROADMAP" ]; then
  PHASE_SECTION=$(sed -n "/^## Phase ${PHASE_NUM}:/,/^## Phase [0-9]/p" "$ROADMAP" 2>/dev/null | sed '$d') || true
  if [ -n "$PHASE_SECTION" ]; then
    PHASE_GOAL=$(echo "$PHASE_SECTION" | grep '^\*\*Goal:\*\*' 2>/dev/null | sed 's/\*\*Goal:\*\* *//' ) || PHASE_GOAL="Not available"
    PHASE_REQS=$(echo "$PHASE_SECTION" | grep '^\*\*Reqs:\*\*' 2>/dev/null | sed 's/\*\*Reqs:\*\* *//' ) || PHASE_REQS="Not available"
    PHASE_SUCCESS=$(echo "$PHASE_SECTION" | grep '^\*\*Success:\*\*' 2>/dev/null | sed 's/\*\*Success:\*\* *//' ) || PHASE_SUCCESS="Not available"
  fi
fi

# --- Build REQ grep pattern from comma-separated REQ IDs ---
REQ_PATTERN=""
if [ "$PHASE_REQS" != "Not available" ] && [ -n "$PHASE_REQS" ]; then
  REQ_PATTERN=$(echo "$PHASE_REQS" | tr ',' '\n' | sed 's/^ *//' | sed 's/ *$//' | paste -sd '|' -) || true
fi

# --- V3: Context cache check (REQ-07) ---
V3_CACHE_ENABLED=true
CACHE_HASH=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${PLANNING_DIR}/config.json"

V3_DELTA_ENABLED=true
V3_METRICS_ENABLED=true
START_TIME=""

if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  V3_METRICS_ENABLED=$(jq -r 'if .metrics != null then .metrics elif .v3_metrics != null then .v3_metrics else true end' "$CONFIG_PATH" 2>/dev/null || echo "true")
fi

ROLLING_SUMMARY=false
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  # Legacy fallback: honor v3_rolling_summary if unprefixed key missing (pre-migration brownfield)
  ROLLING_SUMMARY=$(jq -r 'if .rolling_summary != null then .rolling_summary elif .v3_rolling_summary != null then .v3_rolling_summary else false end' "$CONFIG_PATH" 2>/dev/null || echo "false")
fi

ROLLING_CONTEXT_PATH="${PLANNING_DIR}/ROLLING-CONTEXT.md"
ROLLING_CONTEXT_SECTION=""
if [ "$ROLLING_SUMMARY" = "true" ] && [ "$PHASE_NUM" -gt 1 ] 2>/dev/null && [ -f "$ROLLING_CONTEXT_PATH" ]; then
  ROLLING_CONTEXT_SECTION=$(cat "$ROLLING_CONTEXT_PATH" 2>/dev/null || true)
fi

# Record start time for metrics
if [ "$V3_METRICS_ENABLED" = "true" ]; then
  START_TIME=$(date +%s 2>/dev/null || echo "0")
fi

if [ "$V3_CACHE_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/cache-context.sh" ]; then
  CACHE_RESULT=$(bash "${SCRIPT_DIR}/cache-context.sh" "$PHASE" "$ROLE" "$CONFIG_PATH" "$PLAN_PATH" 2>/dev/null || echo "miss nohash")
  CACHE_STATUS=$(echo "$CACHE_RESULT" | cut -d' ' -f1)
  CACHE_HASH=$(echo "$CACHE_RESULT" | cut -d' ' -f2)

  if [ "$CACHE_STATUS" = "hit" ]; then
    CACHED_PATH=$(echo "$CACHE_RESULT" | cut -d' ' -f3)
    OUTPUT_PATH="${PHASE_DIR}/.context-${ROLE}.md"
    if cp "$CACHED_PATH" "$OUTPUT_PATH" 2>/dev/null; then
      update_context_index "$CACHE_HASH" "$CACHED_PATH" "$ROLE" "$PHASE"
      if [ "$V3_METRICS_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
        bash "${SCRIPT_DIR}/collect-metrics.sh" cache_hit "$PHASE" "role=${ROLE}" 2>/dev/null || true
      fi
      echo "$OUTPUT_PATH"
      exit 0
    else
      echo "V3 fallback: cache copy failed for ${ROLE}, compiling fresh" >&2
    fi
  fi
elif [ "$V3_CACHE_ENABLED" = "true" ]; then
  echo "V3 fallback: cache-context.sh not found, skipping cache" >&2
fi

# --- Codebase mapping hint helper ---
# Usage: emit_codebase_mapping_hint <priority_files...>
# Emits a "Codebase Map Available" section listing available mapping docs
# and guidance to read priority files first. Only emits if META.md exists
# and at least one of the scanned files exists.
emit_codebase_mapping_hint() {
  local priority_files=("$@")
  if [ ! -f "$PLANNING_DIR/codebase/META.md" ]; then
    return
  fi

  # Scan for all key mapping files
  local MAP_FILES=""
  for doc in ARCHITECTURE CONCERNS PATTERNS DEPENDENCIES STRUCTURE CONVENTIONS TESTING STACK; do
    if [ -f "$PLANNING_DIR/codebase/${doc}.md" ]; then
      MAP_FILES="${MAP_FILES} ${doc}"
    fi
  done

  if [ -z "$MAP_FILES" ]; then
    return
  fi

  echo ""
  echo "### Codebase Map Available"
  echo "Codebase mapping exists in \`.vbw-planning/codebase/\`. Key files:"
  for doc in $MAP_FILES; do
    echo "- \`${doc}.md\`"
  done
  echo ""

  # Build guidance from priority files that exist
  local GUIDANCE_FILES=""
  for pfile in "${priority_files[@]}"; do
    if [ -f "$PLANNING_DIR/codebase/${pfile}.md" ]; then
      if [ -z "$GUIDANCE_FILES" ]; then
        GUIDANCE_FILES="${pfile}.md"
      else
        GUIDANCE_FILES="${GUIDANCE_FILES}, ${pfile}.md"
      fi
    fi
  done
  # Convert to natural language: "A and B" for 2 items, "A, B, and C" for 3+
  local comma_count
  comma_count=$(echo "$GUIDANCE_FILES" | tr -cd ',' | wc -c | tr -d ' ')
  if [ "$comma_count" -eq 1 ]; then
    GUIDANCE_FILES=$(echo "$GUIDANCE_FILES" | sed 's/, / and /')
  elif [ "$comma_count" -gt 1 ]; then
    GUIDANCE_FILES=$(echo "$GUIDANCE_FILES" | sed 's/\(.*\), /\1, and /')
  fi
  if [ -n "$GUIDANCE_FILES" ]; then
    echo "Read ${GUIDANCE_FILES} first to bootstrap codebase understanding."
  fi
}

# --- Role-specific output ---
case "$ROLE" in
  lead)
    {
      echo "## Phase ${PHASE} Context (Compiled)"
      if [ -n "$ROLLING_CONTEXT_SECTION" ]; then
        echo ""
        echo "### Prior Phase Context (Rolling Summary)"
        echo "$ROLLING_CONTEXT_SECTION"
        echo ""
      fi
      echo ""
      echo "### Goal"
      echo "$PHASE_GOAL"
      echo ""
      echo "### Success Criteria"
      echo "$PHASE_SUCCESS"
      echo ""
      echo "### Requirements (${PHASE_REQS})"
      if [ -n "$REQ_PATTERN" ] && [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
        grep -E "($REQ_PATTERN)" "$PLANNING_DIR/REQUIREMENTS.md" 2>/dev/null || echo "No matching requirements found"
      else
        echo "No matching requirements found"
      fi
      echo ""
      # Count total reqs for awareness
      TOTAL_REQS=$(grep -c '^\- \[' "$PLANNING_DIR/REQUIREMENTS.md" 2>/dev/null) || TOTAL_REQS=0
      MATCHED_REQS=0
      if [ "$PHASE_REQS" != "Not available" ] && [ -n "$PHASE_REQS" ]; then
        MATCHED_REQS=$(echo "$PHASE_REQS" | tr ',' '\n' | wc -l | tr -d ' ')
      fi
      OTHERS=$((TOTAL_REQS - MATCHED_REQS))
      if [ "$OTHERS" -gt 0 ]; then
        echo "(${OTHERS} other requirements exist for other phases -- not shown)"
      fi
      echo ""
      echo "### Active Decisions"
      if [ -f "$PLANNING_DIR/STATE.md" ]; then
        DECISIONS=$(sed -n '/^## Key Decisions/,/^## [A-Z]/p' "$PLANNING_DIR/STATE.md" 2>/dev/null | sed '$d' | tail -n +2) || true
        if [ -n "$DECISIONS" ]; then
          echo "$DECISIONS"
        else
          echo "None"
        fi
      else
        echo "None"
      fi
      # --- V3: Include RESEARCH.md if present (per-plan preferred) ---
      RESEARCH_FILE=$(resolve_research_file "$PHASE_DIR" "$PLAN_PATH")
      if [ -n "$RESEARCH_FILE" ] && [ -f "$RESEARCH_FILE" ]; then
        echo ""
        echo "### Research Findings"
        cat "$RESEARCH_FILE"
      else
        # --- Codebase mapping hint only when no research exists (issue #80) ---
        # When research exists, the Scout already analyzed the codebase;
        # the mapping hint would trigger redundant reads.
        emit_codebase_mapping_hint ARCHITECTURE CONCERNS STRUCTURE
      fi
    } > "${PHASE_DIR}/.context-lead.md"
    ;;

  dev)
    {
      echo "## Phase ${PHASE} Context"
      if [ -n "$ROLLING_CONTEXT_SECTION" ]; then
        echo ""
        echo "### Prior Phase Context (Rolling Summary)"
        echo "$ROLLING_CONTEXT_SECTION"
        echo ""
      fi
      echo ""
      echo "### Goal"
      echo "$PHASE_GOAL"
      if [ -f "$PLANNING_DIR/conventions.json" ] && command -v jq &>/dev/null; then
        CONVENTIONS=$(jq -r '.conventions[] | "- [\(.tag)] \(.rule)"' "$PLANNING_DIR/conventions.json" 2>/dev/null) || true
        if [ -n "$CONVENTIONS" ]; then
          echo ""
          echo "### Conventions"
          echo "$CONVENTIONS"
        fi
      fi
      # --- Codebase mapping hint (issue #78) ---
      emit_codebase_mapping_hint CONVENTIONS PATTERNS STRUCTURE DEPENDENCIES
      # --- V3: Delta context (REQ-06) ---
      if [ "$V3_DELTA_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/delta-files.sh" ]; then
        DELTA_FILES=$(bash "${SCRIPT_DIR}/delta-files.sh" "$PHASE_DIR" "$PLAN_PATH" 2>/dev/null || true)
        if [ -n "$DELTA_FILES" ]; then
          echo ""
          echo "### Changed Files (Delta)"
          echo "$DELTA_FILES" | while IFS= read -r f; do
            echo "- \`$f\`"
          done
          # --- V3: Code Slices (REQ-08) ---
          echo ""
          echo "### Code Slices"
          echo "$DELTA_FILES" | while IFS= read -r f; do
            [ -z "$f" ] && continue
            if [ -f "$f" ]; then
              LINES=$(wc -l < "$f" 2>/dev/null | tr -d ' ' || echo "0")
              if [ "$LINES" -le 50 ]; then
                echo ""
                echo "#### \`$f\` (${LINES} lines)"
                echo '```'
                cat "$f" 2>/dev/null || true
                echo '```'
              else
                echo ""
                echo "#### \`$f\` (${LINES} lines, first 30 shown)"
                echo '```'
                head -30 "$f" 2>/dev/null || true
                echo '```'
              fi
            fi
          done
        fi
        # Include active plan content for focused context
        if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
          echo ""
          echo "### Active Plan"
          cat "$PLAN_PATH"
        fi
      fi
      # --- V3: Include RESEARCH.md if present (per-plan preferred) ---
      RESEARCH_FILE=$(resolve_research_file "$PHASE_DIR" "$PLAN_PATH")
      if [ -n "$RESEARCH_FILE" ] && [ -f "$RESEARCH_FILE" ]; then
        echo ""
        echo "### Research Findings"
        cat "$RESEARCH_FILE"
      fi
    } > "${PHASE_DIR}/.context-dev.md"
    ;;

  qa)
    {
      echo "## Phase ${PHASE} Verification Context"
      if [ -n "$ROLLING_CONTEXT_SECTION" ]; then
        echo ""
        echo "### Prior Phase Context (Rolling Summary)"
        echo "$ROLLING_CONTEXT_SECTION"
        echo ""
      fi
      echo ""
      echo "### Goal"
      echo "$PHASE_GOAL"
      echo ""
      echo "### Success Criteria"
      echo "$PHASE_SUCCESS"
      echo ""
      echo "### Requirements to Verify"
      if [ -n "$REQ_PATTERN" ] && [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
        grep -E "($REQ_PATTERN)" "$PLANNING_DIR/REQUIREMENTS.md" 2>/dev/null || echo "No matching requirements found"
      else
        echo "No matching requirements found"
      fi
      if [ -f "$PLANNING_DIR/conventions.json" ] && command -v jq &>/dev/null; then
        CONVENTIONS=$(jq -r '.conventions[] | "- [\(.tag)] \(.rule)"' "$PLANNING_DIR/conventions.json" 2>/dev/null) || true
        if [ -n "$CONVENTIONS" ]; then
          echo ""
          echo "### Conventions to Check"
          echo "$CONVENTIONS"
        fi
      fi
      # --- Codebase mapping hint (issue #79) ---
      emit_codebase_mapping_hint TESTING CONCERNS ARCHITECTURE
    } > "${PHASE_DIR}/.context-qa.md"
    ;;

  scout)
    {
      echo "## Phase ${PHASE} Research Context"
      if [ -n "$ROLLING_CONTEXT_SECTION" ]; then
        echo ""
        echo "### Prior Phase Context (Rolling Summary)"
        echo "$ROLLING_CONTEXT_SECTION"
        echo ""
      fi
      echo ""
      echo "### Goal"
      echo "$PHASE_GOAL"
      echo ""
      echo "### Success Criteria"
      echo "$PHASE_SUCCESS"
      echo ""
      echo "### Requirements (${PHASE_REQS})"
      if [ -n "$REQ_PATTERN" ] && [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
        grep -E "($REQ_PATTERN)" "$PLANNING_DIR/REQUIREMENTS.md" 2>/dev/null || echo "No matching requirements found"
      else
        echo "No matching requirements found"
      fi
      if [ -f "$PLANNING_DIR/conventions.json" ] && command -v jq &>/dev/null; then
        CONVENTIONS=$(jq -r '.conventions[] | "- [\(.tag)] \(.rule)"' "$PLANNING_DIR/conventions.json" 2>/dev/null) || true
        if [ -n "$CONVENTIONS" ]; then
          echo ""
          echo "### Conventions"
          echo "$CONVENTIONS"
        fi
      fi
      # --- V3: Include RESEARCH.md if present (per-plan preferred) ---
      RESEARCH_FILE=$(resolve_research_file "$PHASE_DIR" "$PLAN_PATH")
      if [ -n "$RESEARCH_FILE" ] && [ -f "$RESEARCH_FILE" ]; then
        echo ""
        echo "### Research Findings"
        cat "$RESEARCH_FILE"
      fi
      # --- V3: Delta file list (read-only, no code slices) ---
      if [ "$V3_DELTA_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/delta-files.sh" ]; then
        DELTA_FILES=$(bash "${SCRIPT_DIR}/delta-files.sh" "$PHASE_DIR" "$PLAN_PATH" 2>/dev/null || true)
        if [ -n "$DELTA_FILES" ]; then
          echo ""
          echo "### Changed Files (Delta)"
          echo "$DELTA_FILES" | while IFS= read -r f; do
            echo "- \`$f\`"
          done
        fi
      fi
    } > "${PHASE_DIR}/.context-scout.md"
    ;;

  debugger)
    {
      echo "## Phase ${PHASE} Debug Context"
      if [ -n "$ROLLING_CONTEXT_SECTION" ]; then
        echo ""
        echo "### Prior Phase Context (Rolling Summary)"
        echo "$ROLLING_CONTEXT_SECTION"
        echo ""
      fi
      echo ""
      echo "### Goal"
      echo "$PHASE_GOAL"
      echo ""
      echo "### Success Criteria"
      echo "$PHASE_SUCCESS"
      echo ""
      echo "### Recent Activity"
      if [ -f "$PLANNING_DIR/STATE.md" ]; then
        ACTIVITY=$(sed -n '/^## Activity/,/^## [A-Z]/p' "$PLANNING_DIR/STATE.md" 2>/dev/null | sed '$d' | tail -n +2) || true
        if [ -n "$ACTIVITY" ]; then
          echo "$ACTIVITY"
        else
          echo "None"
        fi
      else
        echo "None"
      fi
      if [ -f "$PLANNING_DIR/conventions.json" ] && command -v jq &>/dev/null; then
        CONVENTIONS=$(jq -r '.conventions[] | "- [\(.tag)] \(.rule)"' "$PLANNING_DIR/conventions.json" 2>/dev/null) || true
        if [ -n "$CONVENTIONS" ]; then
          echo ""
          echo "### Conventions"
          echo "$CONVENTIONS"
        fi
      fi
      # --- Codebase mapping hint (issue #75) ---
      emit_codebase_mapping_hint ARCHITECTURE CONCERNS PATTERNS DEPENDENCIES
      # --- V3: Include RESEARCH.md if present (per-plan preferred) ---
      RESEARCH_FILE=$(resolve_research_file "$PHASE_DIR" "$PLAN_PATH")
      if [ -n "$RESEARCH_FILE" ] && [ -f "$RESEARCH_FILE" ]; then
        echo ""
        echo "### Research Findings"
        cat "$RESEARCH_FILE"
      fi
      # --- V3: Delta context with code slices (debugger needs code for diagnosis) ---
      if [ "$V3_DELTA_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/delta-files.sh" ]; then
        DELTA_FILES=$(bash "${SCRIPT_DIR}/delta-files.sh" "$PHASE_DIR" "$PLAN_PATH" 2>/dev/null || true)
        if [ -n "$DELTA_FILES" ]; then
          echo ""
          echo "### Changed Files (Delta)"
          echo "$DELTA_FILES" | while IFS= read -r f; do
            echo "- \`$f\`"
          done
          echo ""
          echo "### Code Slices"
          echo "$DELTA_FILES" | while IFS= read -r f; do
            [ -z "$f" ] && continue
            if [ -f "$f" ]; then
              LINES=$(wc -l < "$f" 2>/dev/null | tr -d ' ' || echo "0")
              if [ "$LINES" -le 50 ]; then
                echo ""
                echo "#### \`$f\` (${LINES} lines)"
                echo '```'
                cat "$f" 2>/dev/null || true
                echo '```'
              else
                echo ""
                echo "#### \`$f\` (${LINES} lines, first 30 shown)"
                echo '```'
                head -30 "$f" 2>/dev/null || true
                echo '```'
              fi
            fi
          done
        fi
      fi
    } > "${PHASE_DIR}/.context-debugger.md"
    ;;

  architect)
    {
      echo "## Phase ${PHASE} Architecture Context"
      if [ -n "$ROLLING_CONTEXT_SECTION" ]; then
        echo ""
        echo "### Prior Phase Context (Rolling Summary)"
        echo "$ROLLING_CONTEXT_SECTION"
        echo ""
      fi
      echo ""
      echo "### Goal"
      echo "$PHASE_GOAL"
      echo ""
      echo "### Success Criteria"
      echo "$PHASE_SUCCESS"
      echo ""
      echo "### Full Requirements"
      if [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
        cat "$PLANNING_DIR/REQUIREMENTS.md"
      else
        echo "No requirements file found"
      fi
      if [ -f "$PLANNING_DIR/conventions.json" ] && command -v jq &>/dev/null; then
        CONVENTIONS=$(jq -r '.conventions[] | "- [\(.tag)] \(.rule)"' "$PLANNING_DIR/conventions.json" 2>/dev/null) || true
        if [ -n "$CONVENTIONS" ]; then
          echo ""
          echo "### Conventions"
          echo "$CONVENTIONS"
        fi
      fi
      # --- Codebase mapping hint (issue #81) ---
      emit_codebase_mapping_hint ARCHITECTURE STACK
      # --- V3: Include RESEARCH.md if present (per-plan preferred) ---
      RESEARCH_FILE=$(resolve_research_file "$PHASE_DIR" "$PLAN_PATH")
      if [ -n "$RESEARCH_FILE" ] && [ -f "$RESEARCH_FILE" ]; then
        echo ""
        echo "### Research Findings"
        cat "$RESEARCH_FILE"
      fi
    } > "${PHASE_DIR}/.context-architect.md"
    ;;

  *)
    echo "Unknown role: $ROLE. Valid roles: lead, dev, qa, scout, debugger, architect" >&2
    exit 1
    ;;
esac

# --- V3: Cache the compiled result ---
if [ "$V3_CACHE_ENABLED" = "true" ] && [ -n "$CACHE_HASH" ] && [ "$CACHE_HASH" != "nohash" ]; then
  CACHE_DIR="${PLANNING_DIR}/.cache/context"
  if mkdir -p "$CACHE_DIR" 2>/dev/null; then
    cp "${PHASE_DIR}/.context-${ROLE}.md" "${CACHE_DIR}/${CACHE_HASH}.md" 2>/dev/null || echo "V3 fallback: cache write failed for ${ROLE}" >&2
    update_context_index "$CACHE_HASH" "${CACHE_DIR}/${CACHE_HASH}.md" "$ROLE" "$PHASE"
  else
    echo "V3 fallback: could not create cache dir" >&2
  fi
fi

# --- V3: Emit compile_context metric ---
if [ "$V3_METRICS_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
  END_TIME=$(date +%s 2>/dev/null || echo "0")
  DURATION_MS=$(( (END_TIME - ${START_TIME:-0}) * 1000 ))
  DELTA_COUNT=0
  if [ "$V3_DELTA_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/delta-files.sh" ]; then
    DELTA_COUNT=$(bash "${SCRIPT_DIR}/delta-files.sh" "$PHASE_DIR" "$PLAN_PATH" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  fi
  bash "${SCRIPT_DIR}/collect-metrics.sh" compile_context "$PHASE" "role=${ROLE}" "duration_ms=${DURATION_MS}" "delta_files=${DELTA_COUNT}" "cache=miss" 2>/dev/null || true
fi

echo "${PHASE_DIR}/.context-${ROLE}.md"
