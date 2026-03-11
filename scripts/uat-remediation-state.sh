#!/usr/bin/env bash
# uat-remediation-state.sh — Track UAT remediation chain progress on disk.
#
# Persists the current stage of the research → plan → execute → verify → uat chain
# so the orchestrator can resume correctly after compaction or session restart.
#
# Usage:
#   uat-remediation-state.sh get         <phase-dir>             → prints current stage + round
#   uat-remediation-state.sh advance     <phase-dir>             → advances to next stage
#   uat-remediation-state.sh reset       <phase-dir>             → removes state file
#   uat-remediation-state.sh init        <phase-dir> <severity>  → initializes for severity
#   uat-remediation-state.sh get-or-init <phase-dir> <severity>  → returns existing stage or initializes
#
# get-or-init is the preferred entry point for orchestrators:
#   - If a stage file already exists (resume case), returns the persisted stage — no init side effects.
#   - If no stage file exists (first entry), runs full init (CONTEXT pre-seeding, etc.) and returns
#     the stage + ---CONTEXT--- block — identical to calling init directly.
#   - Both paths emit plan metadata after the stage line:
#       round=RR              — zero-padded current round number
#       round_dir=<path>      — path to current round directory
#       research_path=<path>  — path to existing RESEARCH.md in round dir (empty if none)
#       plan_path=<path>      — path to existing PLAN.md in round dir (empty if none)
#     This eliminates Search/Glob tool calls the orchestrator would otherwise need.
#   This eliminates the two-step get→init pattern that wastes a tool call and forces
#   the LLM to reason about the intermediate "none" value.
#
# Stages (major/critical path): research → plan → execute → verify → uat → done
#   After uat with issues: needs-round → creates next round → research
#   (discuss is skipped — the UAT report serves as the scoping document)
# Stages (minor-only path):     fix → done
#
# State file: {phase-dir}/remediation/.uat-remediation-stage
# Format: key=value pairs (stage=X, round=NN)
# Round dirs: {phase-dir}/remediation/P{NN}-{RR}-round/

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
# Legacy location fallback for unmitigated installations
LEGACY_STATE_FILE="$PHASE_DIR/.uat-remediation-stage"

# Major/critical chain order (UAT report serves as discussion — no separate discuss step)
MAJOR_STAGES=("research" "plan" "execute" "verify" "uat" "done")
# Minor-only chain order
MINOR_STAGES=("fix" "done")

# Extract phase number from dir name
PHASE_BASENAME=$(basename "$PHASE_DIR")
PHASE_NUM=$(echo "$PHASE_BASENAME" | sed 's/^\([0-9][0-9]*\).*/\1/')
PHASE_NUM=$(printf '%02d' "$((10#${PHASE_NUM:-0}))")

get_stage() {
  local sf=""
  if [ -f "$STATE_FILE" ]; then
    sf="$STATE_FILE"
  elif [ -f "$LEGACY_STATE_FILE" ]; then
    sf="$LEGACY_STATE_FILE"
  fi

  if [ -z "$sf" ]; then
    echo "none"
    return
  fi

  # New format: key=value pairs
  if grep -q '^stage=' "$sf" 2>/dev/null; then
    grep '^stage=' "$sf" | head -1 | sed 's/^stage=//' | tr -d '[:space:]'
  else
    # Legacy format: single word
    cat "$sf" | tr -d '[:space:]'
  fi
}

get_round() {
  local sf=""
  if [ -f "$STATE_FILE" ]; then
    sf="$STATE_FILE"
  elif [ -f "$LEGACY_STATE_FILE" ]; then
    sf="$LEGACY_STATE_FILE"
  fi

  if [ -z "$sf" ]; then
    echo "01"
    return
  fi

  if grep -q '^round=' "$sf" 2>/dev/null; then
    grep '^round=' "$sf" | head -1 | sed 's/^round=//' | tr -d '[:space:]'
  else
    # Legacy format: no round info, derive from existing round dirs
    local max_rr=0
    for d in "$PHASE_DIR"/remediation/P${PHASE_NUM}-*-round; do
      [ -d "$d" ] || continue
      local rr=$(basename "$d" | sed "s/^P${PHASE_NUM}-\([0-9]*\)-round$/\1/")
      [ -z "$rr" ] && continue
      local rr_num=$((10#$rr))
      [ "$rr_num" -gt "$max_rr" ] && max_rr=$rr_num
    done
    if [ "$max_rr" -gt 0 ]; then
      printf '%02d' "$max_rr"
    else
      echo "01"
    fi
  fi
}

write_stage_file() {
  local stage="$1"
  local round="$2"
  mkdir -p "$PHASE_DIR/remediation"
  {
    echo "stage=$stage"
    echo "round=$round"
  } > "$STATE_FILE"
  # Remove legacy file if it exists
  rm -f "$LEGACY_STATE_FILE"
}

get_round_dir() {
  local round="$1"
  echo "$PHASE_DIR/remediation/P${PHASE_NUM}-${round}-round"
}

next_stage() {
  local current="$1"
  local -a stages

  # Determine which chain we're on based on current stage
  case "$current" in
    research|plan|execute|verify|uat) stages=("${MAJOR_STAGES[@]}") ;;
    fix)                              stages=("${MINOR_STAGES[@]}") ;;
    done)                 echo "done"; return 0 ;;
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
  local first_round="01"
  local initial_stage

  case "$severity" in
    major|critical) initial_stage="research" ;;
    minor)          initial_stage="fix" ;;
    *)              initial_stage="research" ;;
  esac

  # Create round directory and write stage file
  local round_dir
  round_dir=$(get_round_dir "$first_round")
  mkdir -p "$round_dir"
  write_stage_file "$initial_stage" "$first_round"
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

  # Find CONTEXT file: P-prefix first, then legacy
  context_file=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' \( -name "P${PHASE_NUM}-CONTEXT.md" -o -name '[0-9]*-CONTEXT.md' \) 2>/dev/null | sort | head -1)

  # Find UAT file: prefer latest_non_source_uat if available, fallback to find
  if type latest_non_source_uat &>/dev/null; then
    uat_file=$(latest_non_source_uat "$PHASE_DIR")
  fi
  if [ -z "$uat_file" ]; then
    uat_file=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' \( -name "P${PHASE_NUM}-UAT.md" -o -name '[0-9]*-UAT.md' \) ! -name '*SOURCE-UAT.md' 2>/dev/null | sort | tail -1)
  fi

  if [ -n "$uat_file" ] && [ -f "$uat_file" ]; then
    uat_content=$(cat "$uat_file")

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
      context_file="$PHASE_DIR/P${PHASE_NUM}-CONTEXT.md"

      {
        echo "---"
        echo "pre_seeded: true"
        echo "---"
        echo ""
        echo "# Phase ${PHASE_NUM}: UAT Remediation — Context"
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
  # Emit round info and paths to research/plan files in the current round dir.
  # Output:
  #   round=RR
  #   round_dir=<path>
  #   research_path=<path>   (empty if none)
  #   plan_path=<path>       (empty if none)
  local stage="$1"
  local round research_path="" plan_path=""

  round=$(get_round)
  local round_dir
  round_dir=$(get_round_dir "$round")

  # Look for research file in round dir: P{NN}-R{RR}-RESEARCH.md
  local research_file="${round_dir}/P${PHASE_NUM}-R${round}-RESEARCH.md"
  if [ -f "$research_file" ]; then
    research_path="$research_file"
  fi

  # Look for plan file in round dir: P{NN}-R{RR}-PLAN.md
  local plan_file="${round_dir}/P${PHASE_NUM}-R${round}-PLAN.md"
  if [ -f "$plan_file" ]; then
    plan_path="$plan_file"
  fi

  echo "round=${round}"
  echo "round_dir=${round_dir}"
  echo "research_path=${research_path}"
  echo "plan_path=${plan_path}"
}

case "$CMD" in
  get)
    stage=$(get_stage)
    round=$(get_round)
    echo "$stage"
    if [ "$stage" != "none" ]; then
      echo "round=${round}"
    fi
    ;;

  advance)
    current=$(get_stage)
    round=$(get_round)
    if [ "$current" = "none" ] || [ "$current" = "done" ]; then
      echo "done"
    elif [ "$current" = "uat" ]; then
      # After UAT: transition to needs-round (orchestrator will pass uat-has-issues flag)
      # External caller must set needs-round explicitly via write or call get-or-init
      new_stage=$(next_stage "$current")
      write_stage_file "$new_stage" "$round"
      echo "$new_stage"
    else
      new_stage=$(next_stage "$current")
      write_stage_file "$new_stage" "$round"
      echo "$new_stage"
    fi
    ;;

  needs-round)
    # Orchestrator signals UAT found issues — set needs-round for next get-or-init
    round=$(get_round)
    write_stage_file "needs-round" "$round"
    echo "needs-round"
    echo "round=${round}"
    ;;

  reset)
    rm -f "$STATE_FILE" "$LEGACY_STATE_FILE"
    echo "none"
    ;;

  init)
    if [ -z "$SEVERITY_ARG" ]; then
      echo "Usage: uat-remediation-state.sh init <phase-dir> <major|minor>" >&2
      exit 1
    fi
    do_init "$SEVERITY_ARG"
    emit_plan_metadata "$(get_stage)"
    emit_init_context
    ;;

  get-or-init)
    if [ -z "$SEVERITY_ARG" ]; then
      echo "Usage: uat-remediation-state.sh get-or-init <phase-dir> <major|minor>" >&2
      exit 1
    fi
    existing=$(get_stage)
    if [ "$existing" = "needs-round" ]; then
      # UAT had issues — create next round dir and reset to research
      old_round=$(get_round)
      new_round_num=$(( 10#$old_round + 1 ))
      new_round=$(printf '%02d' "$new_round_num")
      round_dir=$(get_round_dir "$new_round")
      mkdir -p "$round_dir"
      write_stage_file "research" "$new_round"
      echo "research"
      emit_plan_metadata "research"
      # Re-seed CONTEXT with latest UAT report for the new round
      _init_emit_context=false
      _init_context_file=""
      # Note: no 'local' here — we're in a case block, not a function
      context_file="" ; uat_file="" ; uat_content=""
      context_file=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' \( -name "P${PHASE_NUM}-CONTEXT.md" -o -name '[0-9]*-CONTEXT.md' \) 2>/dev/null | sort | head -1)
      if type latest_non_source_uat &>/dev/null; then
        uat_file=$(latest_non_source_uat "$PHASE_DIR")
      fi
      if [ -z "$uat_file" ]; then
        uat_file=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' \( -name "P${PHASE_NUM}-UAT.md" -o -name '[0-9]*-UAT.md' \) ! -name '*SOURCE-UAT.md' 2>/dev/null | sort | tail -1)
      fi
      if [ -n "$uat_file" ] && [ -f "$uat_file" ] && [ -n "$context_file" ] && [ -f "$context_file" ]; then
        uat_content=$(cat "$uat_file")
        # Strip old UAT section and append new
        awk '/^## UAT Remediation Issues[[:space:]]*$/ { exit } { print }' \
          "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
        {
          echo "## UAT Remediation Issues"
          echo ""
          printf '%s\n' "$uat_content"
        } >> "$context_file"
        _init_emit_context=true
        _init_context_file="$context_file"
      fi
      emit_init_context
    elif [ "$existing" != "none" ]; then
      echo "$existing"
      emit_plan_metadata "$existing"
    else
      do_init "$SEVERITY_ARG"
      emit_plan_metadata "$(get_stage)"
      emit_init_context
    fi
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    exit 1
    ;;
esac
