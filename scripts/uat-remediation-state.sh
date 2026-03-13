#!/usr/bin/env bash
# uat-remediation-state.sh — Track UAT remediation chain progress on disk.
#
# Persists the current stage of the research → plan → execute chain so that
# the orchestrator can resume correctly after compaction or session restart.
#
# Usage:
#   uat-remediation-state.sh get         <phase-dir>             → prints current stage
#   uat-remediation-state.sh advance     <phase-dir>             → advances to next stage
#   uat-remediation-state.sh reset       <phase-dir>             → removes state file
#   uat-remediation-state.sh init        <phase-dir> <severity>  → initializes for severity
#   uat-remediation-state.sh get-or-init <phase-dir> <severity>  → returns existing stage or initializes
#   uat-remediation-state.sh needs-round <phase-dir>             → starts a new remediation round
#
# get-or-init is the preferred entry point for orchestrators:
#   - If a stage file already exists (resume case), returns the persisted stage — no init side effects.
#   - If no stage file exists (first entry), runs full init (CONTEXT pre-seeding, etc.) and returns
#     the stage + ---CONTEXT--- block — identical to calling init directly.
#   - Both paths emit plan metadata after the stage line:
#       round=RR              — zero-padded current round number
#       round_dir=<path>      — path to the current round directory
#       research_path=<path>  — path to existing RESEARCH.md (empty if none)
#       plan_path=<path>      — path to existing PLAN.md (empty if none)
#     Stage-aware: for plan/execute stages, uses file presence to find
#     the correct working state (handles session-death-before-advance).
#     This eliminates Search/Glob tool calls the orchestrator would otherwise need.
#   This eliminates the two-step get→init pattern that wastes a tool call and forces
#   the LLM to reason about the intermediate "none" value.
#
# Stages (major/critical path): research → plan → execute → done
#   (discuss is skipped — the UAT report serves as the scoping document)
# Stages (minor-only path):     fix → done
#
# Remediation artifacts live in {phase-dir}/remediation/round-{RR}/ with
# R{RR}-RESEARCH.md, R{RR}-PLAN.md, R{RR}-SUMMARY.md, R{RR}-UAT.md naming.
# State file: {phase-dir}/remediation/.uat-remediation-stage (key=value pairs).
#   layout=round-dir  — artifacts in round dir only (fresh init / needs-round)
#   layout=legacy     — phase-root artifacts are current round (migrated from old format)
# Legacy fallback: reads {phase-dir}/.uat-remediation-stage (single word) for
# projects bootstrapped before round-dir support.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/uat-utils.sh" ]; then
  source "$SCRIPT_DIR/uat-utils.sh"
fi

CMD="${1:-}"
PHASE_DIR="${2:-}"
SEVERITY_ARG="${3:-}"

if [ -z "$CMD" ] || [ -z "$PHASE_DIR" ]; then
  echo "Usage: uat-remediation-state.sh <get|advance|reset|init> <phase-dir> [severity]" >&2
  exit 1
fi

# Milestone path guard: refuse to init/advance remediation in archived milestones.
# Archived milestones are read-only; remediation must happen in active phases.
case "$PHASE_DIR" in
  */.vbw-planning/milestones/*|.vbw-planning/milestones/*)
    echo "Error: refusing to operate on archived milestone path: $PHASE_DIR" >&2
    echo "Remediation must target active phases in .vbw-planning/phases/" >&2
    echo "Use create-remediation-phase.sh to create active remediation phases from milestone UAT." >&2
    exit 1
    ;;
esac

STATE_FILE="$PHASE_DIR/remediation/.uat-remediation-stage"
LEGACY_STATE_FILE="$PHASE_DIR/.uat-remediation-stage"

# Major/critical chain order (UAT report serves as discussion — no separate discuss step)
MAJOR_STAGES=("research" "plan" "execute" "done")
# Minor-only chain order
MINOR_STAGES=("fix" "done")

get_stage() {
  if [ -f "$STATE_FILE" ]; then
    # New format: key=value pairs — extract stage value
    local _val
    _val=$(grep '^stage=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ -n "$_val" ]; then
      echo "$_val"
    else
      # Fallback: treat as single-word (shouldn't happen, but safe)
      tr -d '[:space:]' < "$STATE_FILE"
    fi
  elif [ -f "$LEGACY_STATE_FILE" ]; then
    # Legacy format: single word file at phase root
    cat "$LEGACY_STATE_FILE" | tr -d '[:space:]'
  else
    echo "none"
  fi
}

get_round() {
  if [ -f "$STATE_FILE" ]; then
    local _val
    _val=$(grep '^round=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    echo "${_val:-01}"
  else
    echo "01"
  fi
}

get_layout() {
  # Returns "legacy" when phase-root artifacts belong to the current round
  # (migrated from legacy single-word state file), "round-dir" otherwise.
  # Only legacy layout enables fallback to phase-root plan/research files.
  if [ -f "$STATE_FILE" ]; then
    local _val
    _val=$(grep '^layout=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    echo "${_val:-round-dir}"
  else
    # Legacy state file at phase root — artifacts are at phase root
    echo "legacy"
  fi
}

get_round_dir() {
  local round
  round=$(get_round)
  echo "$PHASE_DIR/remediation/round-${round}"
}

next_stage() {
  local current="$1"
  local -a stages

  # Determine which chain we're on based on current stage
  case "$current" in
    research|plan|execute) stages=("${MAJOR_STAGES[@]}") ;;
    fix)                  stages=("${MINOR_STAGES[@]}") ;;
    done)                 echo "verify"; return 0 ;;
    verify)               echo "verify"; return 0 ;;
    *)                    echo "done"; return 0 ;;
  esac

  local found=false
  for s in "${stages[@]}"; do
    if [ "$found" = true ]; then
      echo "$s"
      return 0
    fi
    if [ "$s" = "$current" ]; then
      found=true
    fi
  done

  # If current stage not found in chain, return done
  echo "done"
}

do_init() {
  local severity="$1"
  local initial_stage
  case "$severity" in
    major|critical) initial_stage="research" ;;
    minor)          initial_stage="fix" ;;
    *)              initial_stage="research" ;;
  esac

  # Create remediation directory and first round dir
  mkdir -p "$PHASE_DIR/remediation/round-01"

  # Write key=value state file (layout=round-dir: fresh round, no legacy fallback)
  printf 'stage=%s\nround=01\nlayout=round-dir\n' "$initial_stage" > "$STATE_FILE"

  # Remove legacy state file if it exists (migrated to new location)
  rm -f "$LEGACY_STATE_FILE"

  echo "$initial_stage"

  # Pre-seed the phase CONTEXT.md with UAT report content so the
  # require_phase_discussion gate sees pre_seeded: true and skips
  # discussion naturally — matching how milestone-level remediation
  # works via create-remediation-phase.sh.
  #
  # Appends UAT issues to the existing CONTEXT (preserving original
  # discussion context) and adds pre_seeded: true to frontmatter.
  #
  # Sets _init_context_file for emit_init_context() to use.
  local context_file uat_file uat_content _already_seeded
  _init_emit_context=false
  _init_context_file=""

  context_file=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | sort | head -1)
  if type latest_non_source_uat &>/dev/null; then
    uat_file=$(latest_non_source_uat "$PHASE_DIR")
  else
    uat_file=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-UAT.md' ! -name '*SOURCE-UAT.md' 2>/dev/null | sort | tail -1)
  fi

  if [ -n "$uat_file" ] && [ -f "$uat_file" ]; then
    uat_content=$(cat "$uat_file")
    # Normalize quoted numeric values in YAML frontmatter
    # LLM sometimes writes phase: "03" instead of phase: 03
    uat_content=$(printf '%s\n' "$uat_content" | sed -E '/^---[[:space:]]*$/,/^---[[:space:]]*$/{
      s/^([[:space:]]*(phase|round)[[:space:]]*:[[:space:]]*)"([0-9]+)"/\1\3/
    }')

    if [ -n "$context_file" ] && [ -f "$context_file" ]; then
      _already_seeded=false
      if awk '
        BEGIN { in_fm=0; found=0 }
        NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
        in_fm && /^---[[:space:]]*$/ { exit }
        in_fm && /^pre_seeded[[:space:]]*:[[:space:]]*"?true"?[[:space:]]*$/ { found=1; exit }
        END { exit !found }
      ' "$context_file" 2>/dev/null; then
        _already_seeded=true
      fi

      if [ "$_already_seeded" = true ]; then
        awk '/^## UAT Remediation Issues[[:space:]]*$/ { exit } { print }' \
          "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
        {
          echo "## UAT Remediation Issues"
          echo ""
          printf '%s\n' "$uat_content"
        } >> "$context_file"
        _init_emit_context=true
        _init_context_file="$context_file"
      else
        if head -1 "$context_file" | grep -q '^---[[:space:]]*$'; then
          awk '
            NR==1 && /^---[[:space:]]*$/ { print; next }
            !inserted && /^---[[:space:]]*$/ { print "pre_seeded: true"; inserted=1 }
            { print }
          ' "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
        else
          {
            echo "---"
            echo "pre_seeded: true"
            echo "---"
            echo ""
            cat "$context_file"
          } > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
        fi

        {
          echo ""
          echo "---"
          echo ""
          echo "## UAT Remediation Issues"
          echo ""
          printf '%s\n' "$uat_content"
        } >> "$context_file"
        _init_emit_context=true
        _init_context_file="$context_file"
      fi
    else
      local phase_basename phase_num
      phase_basename=$(basename "$PHASE_DIR")
      phase_num=$(echo "$phase_basename" | sed 's/[^0-9].*//')
      context_file="$PHASE_DIR/${phase_num}-CONTEXT.md"

      {
        echo "---"
        echo "pre_seeded: true"
        echo "---"
        echo ""
        echo "# Phase ${phase_num}: UAT Remediation — Context"
        echo ""
        echo "## UAT Remediation Issues"
        echo ""
        printf '%s\n' "$uat_content"
      } > "$context_file"
      _init_emit_context=true
      _init_context_file="$context_file"
    fi
  fi
}

emit_init_context() {
  if [ "$_init_emit_context" = true ] && [ -n "$_init_context_file" ] && [ -f "$_init_context_file" ]; then
    echo "---CONTEXT---"
    cat "$_init_context_file"
  fi
}

emit_plan_metadata() {
  # Emit round-dir metadata for orchestrators.
  # Reports the current round, round directory, and paths to existing
  # research/plan files within the round dir. Legacy phase-root fallback
  # only applies when layout=legacy (migrated from old single-word state file),
  # preventing stale artifacts from previous rounds being returned as current.
  local round round_dir layout research_path="" plan_path=""

  round=$(get_round)
  round_dir=$(get_round_dir)
  layout=$(get_layout)

  # Check for existing research in round dir first, then legacy phase root
  local rr_research="${round_dir}/R${round}-RESEARCH.md"
  if [ -f "$rr_research" ]; then
    research_path="$rr_research"
  elif [ "$layout" = "legacy" ]; then
    # Legacy fallback: per-plan research at phase root (brownfield migration only)
    local phase_basename phase_prefix
    phase_basename=$(basename "$PHASE_DIR")
    phase_prefix=$(echo "$phase_basename" | sed 's/-[^0-9].*//')
    local legacy_per_plan legacy_phase_level
    # Scan for highest per-plan research in phase root
    legacy_per_plan=$(find "$PHASE_DIR" -maxdepth 1 -name "${phase_prefix}-*-RESEARCH.md" ! -name '.*' 2>/dev/null | sort | tail -1)
    legacy_phase_level="${PHASE_DIR}/${phase_prefix}-RESEARCH.md"
    if [ -n "$legacy_per_plan" ] && [ -f "$legacy_per_plan" ]; then
      research_path="$legacy_per_plan"
    elif [ -f "$legacy_phase_level" ]; then
      research_path="$legacy_phase_level"
    fi
  fi

  # Check for existing plan in round dir first, then legacy phase root
  local rr_plan="${round_dir}/R${round}-PLAN.md"
  if [ -f "$rr_plan" ]; then
    plan_path="$rr_plan"
  elif [ "$layout" = "legacy" ]; then
    # Legacy fallback: highest plan file at phase root (brownfield migration only)
    local phase_basename phase_prefix
    phase_basename=$(basename "$PHASE_DIR")
    phase_prefix=$(echo "$phase_basename" | sed 's/-[^0-9].*//')
    local legacy_plan
    legacy_plan=$(find "$PHASE_DIR" -maxdepth 1 -name "${phase_prefix}-*-PLAN.md" ! -name '.*' 2>/dev/null | sort | tail -1)
    if [ -n "$legacy_plan" ] && [ -f "$legacy_plan" ]; then
      plan_path="$legacy_plan"
    fi
  fi

  echo "round=${round}"
  echo "round_dir=${round_dir}"
  echo "research_path=${research_path}"
  echo "plan_path=${plan_path}"
}

case "$CMD" in
  get)
    get_stage
    ;;

  advance)
    current=$(get_stage)
    if [ "$current" = "none" ] || [ "$current" = "verify" ]; then
      echo "$current"
    else
      new_stage=$(next_stage "$current")
      round=$(get_round)
      layout=$(get_layout)
      mkdir -p "$(dirname "$STATE_FILE")"
      printf 'stage=%s\nround=%s\nlayout=%s\n' "$new_stage" "$round" "$layout" > "$STATE_FILE"
      # Remove legacy state file if we migrated to new location
      [ -f "$LEGACY_STATE_FILE" ] && rm -f "$LEGACY_STATE_FILE"
      echo "$new_stage"
    fi
    ;;

  reset)
    rm -f "$STATE_FILE" "$LEGACY_STATE_FILE"
    echo "none"
    ;;

  needs-round)
    # Start a new remediation round: increment round, create dir, reset to research
    current_round=$(get_round)
    next_round=$(( 10#$current_round + 1 ))
    next_round_padded=$(printf '%02d' "$next_round")
    mkdir -p "$PHASE_DIR/remediation/round-${next_round_padded}"
    printf 'stage=research\nround=%s\nlayout=round-dir\n' "$next_round_padded" > "$STATE_FILE"
    echo "research"
    echo "round=${next_round_padded}"
    echo "round_dir=$PHASE_DIR/remediation/round-${next_round_padded}"
    ;;

  init)
    if [ -z "$SEVERITY_ARG" ]; then
      echo "Usage: uat-remediation-state.sh init <phase-dir> <major|minor>" >&2
      exit 1
    fi
    do_init "$SEVERITY_ARG"
    emit_plan_metadata
    emit_init_context
    ;;

  get-or-init)
    if [ -z "$SEVERITY_ARG" ]; then
      echo "Usage: uat-remediation-state.sh get-or-init <phase-dir> <major|minor>" >&2
      exit 1
    fi
    existing=$(get_stage)
    if [ "$existing" != "none" ]; then
      # If resuming from legacy state file, migrate to new format
      if [ ! -f "$STATE_FILE" ] && [ -f "$LEGACY_STATE_FILE" ]; then
        mkdir -p "$PHASE_DIR/remediation/round-01"
        # layout=legacy: phase-root artifacts are current work (migrated from old format)
        printf 'stage=%s\nround=01\nlayout=legacy\n' "$existing" > "$STATE_FILE"
        rm -f "$LEGACY_STATE_FILE"
      fi
      echo "$existing"
      emit_plan_metadata
    else
      do_init "$SEVERITY_ARG"
      # Init always sets research or fix — read back for stage-aware metadata
      emit_plan_metadata
      emit_init_context
    fi
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    exit 1
    ;;
esac
