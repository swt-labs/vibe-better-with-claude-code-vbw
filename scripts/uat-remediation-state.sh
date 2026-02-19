#!/usr/bin/env bash
# uat-remediation-state.sh — Track UAT remediation chain progress on disk.
#
# Persists the current stage of the discuss → plan → execute chain so that
# the orchestrator can resume correctly after compaction or session restart.
#
# Usage:
#   uat-remediation-state.sh get     <phase-dir>             → prints current stage
#   uat-remediation-state.sh advance <phase-dir>             → advances to next stage
#   uat-remediation-state.sh reset   <phase-dir>             → removes state file
#   uat-remediation-state.sh init    <phase-dir> <severity>  → initializes for severity
#
# Stages (major/critical path): discuss → plan → execute → done
# Stages (minor-only path):     fix → done
#
# The state file is {phase-dir}/.uat-remediation-stage and contains a single word.

set -eo pipefail

CMD="${1:-}"
PHASE_DIR="${2:-}"
SEVERITY_ARG="${3:-}"

if [ -z "$CMD" ] || [ -z "$PHASE_DIR" ]; then
  echo "Usage: uat-remediation-state.sh <get|advance|reset|init> <phase-dir> [severity]" >&2
  exit 1
fi

STATE_FILE="$PHASE_DIR/.uat-remediation-stage"

# Major/critical chain order
MAJOR_STAGES=("discuss" "plan" "execute" "done")
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
    discuss|plan|execute) stages=("${MAJOR_STAGES[@]}") ;;
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
    case "$SEVERITY_ARG" in
      major|critical) echo "discuss" > "$STATE_FILE"; echo "discuss" ;;
      minor)          echo "fix" > "$STATE_FILE"; echo "fix" ;;
      *)              echo "discuss" > "$STATE_FILE"; echo "discuss" ;;
    esac
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    exit 1
    ;;
esac
