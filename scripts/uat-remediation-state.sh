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
#
# get-or-init is the preferred entry point for orchestrators:
#   - If a stage file already exists (resume case), returns the persisted stage — no init side effects.
#   - If no stage file exists (first entry), runs full init (CONTEXT pre-seeding, etc.) and returns
#     the stage + ---CONTEXT--- block — identical to calling init directly.
#   This eliminates the two-step get→init pattern that wastes a tool call and forces
#   the LLM to reason about the intermediate "none" value.
#
# Stages (major/critical path): research → plan → execute → done
#   (discuss is skipped — the UAT report serves as the scoping document)
# Stages (minor-only path):     fix → done
#
# The state file is {phase-dir}/.uat-remediation-stage and contains a single word.

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

STATE_FILE="$PHASE_DIR/.uat-remediation-stage"

# Major/critical chain order (UAT report serves as discussion — no separate discuss step)
MAJOR_STAGES=("research" "plan" "execute" "done")
# Minor-only chain order
MINOR_STAGES=("fix" "done")

get_stage() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE" | tr -d '[:space:]'
  else
    echo "none"
  fi
}

next_stage() {
  local current="$1"
  local -a stages

  # Determine which chain we're on based on current stage
  case "$current" in
    research|plan|execute) stages=("${MAJOR_STAGES[@]}") ;;
    fix)                  stages=("${MINOR_STAGES[@]}") ;;
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
  case "$severity" in
    major|critical) echo "research" > "$STATE_FILE"; echo "research" ;;
    minor)          echo "fix" > "$STATE_FILE"; echo "fix" ;;
    *)              echo "research" > "$STATE_FILE"; echo "research" ;;
  esac

  # Pre-seed the phase CONTEXT.md with UAT report content so the
  # require_phase_discussion gate sees pre_seeded: true and skips
  # discussion naturally — matching how milestone-level remediation
  # works via create-remediation-phase.sh.
  #
  # Appends UAT issues to the existing CONTEXT (preserving original
  # discussion context) and adds pre_seeded: true to frontmatter.
  local context_file uat_file uat_content _already_seeded _emit_context=false

  context_file=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | sort | head -1)
  if type latest_non_source_uat &>/dev/null; then
    uat_file=$(latest_non_source_uat "$PHASE_DIR")
  else
    uat_file=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-UAT.md' ! -name '*SOURCE-UAT.md' 2>/dev/null | sort | tail -1)
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
        _emit_context=true
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
        _emit_context=true
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
      _emit_context=true
    fi
  fi

  if [ "$_emit_context" = true ] && [ -n "$context_file" ] && [ -f "$context_file" ]; then
    echo "---CONTEXT---"
    cat "$context_file"
  fi
}

case "$CMD" in
  get)
    get_stage
    ;;

  advance)
    current=$(get_stage)
    if [ "$current" = "none" ] || [ "$current" = "done" ]; then
      echo "done"
    else
      new_stage=$(next_stage "$current")
      echo "$new_stage" > "$STATE_FILE"
      echo "$new_stage"
    fi
    ;;

  reset)
    rm -f "$STATE_FILE"
    echo "none"
    ;;

  init)
    if [ -z "$SEVERITY_ARG" ]; then
      echo "Usage: uat-remediation-state.sh init <phase-dir> <major|minor>" >&2
      exit 1
    fi
    do_init "$SEVERITY_ARG"
    ;;

  get-or-init)
    if [ -z "$SEVERITY_ARG" ]; then
      echo "Usage: uat-remediation-state.sh get-or-init <phase-dir> <major|minor>" >&2
      exit 1
    fi
    existing=$(get_stage)
    if [ "$existing" != "none" ]; then
      echo "$existing"
    else
      do_init "$SEVERITY_ARG"
    fi
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    exit 1
    ;;
esac
