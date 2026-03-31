#!/usr/bin/env bash
set -euo pipefail

# resolve-verification-path.sh — Canonical resolver for QA VERIFICATION.md inputs.
#
# Usage:
#   bash resolve-verification-path.sh <phase|current|authoritative|plan-input> <phase-dir>
#
# Modes:
#   phase      → phase-level VERIFICATION path (prefers {NN}-VERIFICATION.md,
#                falls back to brownfield plain VERIFICATION.md, else returns the
#                canonical numbered path)
#   current    → verification artifact for the current QA verification pass
#                (current round R{RR}-VERIFICATION.md only while stage=verify
#                or after stage=done, else phase-level fallback)
#   authoritative → QA result downstream UAT consumers should trust
#                (round VERIFICATION only after remediation reaches stage=done,
#                else phase-level fallback)
#   plan-input → verification artifact to plan remediation from (the nearest
#                earlier remediation verification that still contains unresolved
#                FAIL rows; if no earlier round still has FAIL rows, fall back
#                to the phase-level verification. Missing prior-round artifacts
#                still fail closed.)

MODE="${1:-}"
PHASE_DIR="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="${PHASE_DIR%/}/remediation/qa/.qa-remediation-stage"

if [ -z "$MODE" ] || [ -z "$PHASE_DIR" ]; then
  echo "usage: resolve-verification-path.sh <phase|current|authoritative|plan-input> <phase-dir>" >&2
  exit 1
fi

case "$MODE" in
  phase|current|authoritative|plan-input) ;;
  *)
    echo "error: unknown mode: $MODE" >&2
    exit 1
    ;;
esac

if [ ! -d "$PHASE_DIR" ]; then
  echo "error: phase-dir does not exist: $PHASE_DIR" >&2
  exit 1
fi

phase_level_path() {
  local canonical_name canonical_path base phase_num phase_prefix wave_files

  canonical_name=$(bash "$SCRIPT_DIR/resolve-artifact-path.sh" verification "$PHASE_DIR" 2>/dev/null || true)
  if [ -n "$canonical_name" ]; then
    canonical_path="$PHASE_DIR/$canonical_name"
    if [ -f "$canonical_path" ]; then
      echo "$canonical_path"
      return 0
    fi
    phase_prefix="${canonical_name%-VERIFICATION.md}"
  else
    phase_prefix=""
  fi

  if [ -z "$phase_prefix" ]; then
    base=$(basename "${PHASE_DIR%/}")
    phase_num=$(echo "$base" | sed 's/^\([0-9]*\).*/\1/')
    if [ -n "$phase_num" ] && [[ "$phase_num" =~ ^[0-9]+$ ]]; then
      phase_prefix=$(printf '%02d' "$((10#$phase_num))")
    fi
  fi

  if [ -f "$PHASE_DIR/VERIFICATION.md" ]; then
    echo "$PHASE_DIR/VERIFICATION.md"
    return 0
  fi

  if [ -n "$phase_prefix" ]; then
    wave_files=$(ls -1 "$PHASE_DIR/${phase_prefix}-VERIFICATION-wave"*.md 2>/dev/null | (sort -V 2>/dev/null || sort) || true)
    if [ -n "$wave_files" ]; then
      printf '%s\n' "$wave_files" | tail -1
      return 0
    fi
  fi

  if [ -n "$canonical_name" ]; then
    echo "$PHASE_DIR/$canonical_name"
    return 0
  fi

  base=$(basename "${PHASE_DIR%/}")
  phase_num=$(echo "$base" | sed 's/^\([0-9]*\).*/\1/')
  phase_num="${phase_num:-01}"
  if ! [[ "$phase_num" =~ ^[0-9]+$ ]]; then
    phase_num="01"
  fi
  phase_num=$(printf '%02d' "$((10#$phase_num))")
  echo "$PHASE_DIR/${phase_num}-VERIFICATION.md"
}

read_round() {
  local round
  round=$(grep '^round=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  round="${round:-01}"
  if ! [[ "$round" =~ ^[0-9]+$ ]]; then
    round="01"
  fi
  printf '%02d' "$((10#$round))"
}

read_stage() {
  local stage
  stage=$(grep '^stage=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  stage="${stage:-none}"
  case "$stage" in
    plan|execute|verify|done) echo "$stage" ;;
    *) echo "none" ;;
  esac
}

verification_has_fail_rows() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || return 1
  awk -F'|' '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    !/^\|/ { header_found = 0; next }
    /^\|/ {
      if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
      if (!header_found) {
        status_col = 0
        for (i = 2; i < NF; i++) {
          cell = trim($i)
          if (cell == "Status") status_col = i
        }
        if (status_col > 0) header_found = 1
        next
      }
      if (status_col > 0) {
        status = trim($(status_col))
        gsub(/\*+/, "", status)
        status = trim(status)
        if (status == "FAIL") {
          found = 1
          exit
        }
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$file_path" 2>/dev/null
}

phase_path=$(phase_level_path)

case "$MODE" in
  phase)
    echo "$phase_path"
    ;;
  current)
    if [ -f "$STATE_FILE" ]; then
      stage=$(read_stage)
      case "$stage" in
        verify|done)
          round=$(read_round)
          round_path="$PHASE_DIR/remediation/qa/round-${round}/R${round}-VERIFICATION.md"
          if [ -f "$round_path" ]; then
            echo "$round_path"
            exit 0
          fi
          if [ "$stage" = "done" ]; then
            echo "$round_path"
            exit 0
          fi
          ;;
      esac
    fi
    echo "$phase_path"
    ;;
  authoritative)
    if [ -f "$STATE_FILE" ]; then
      stage=$(read_stage)
      if [ "$stage" = "done" ]; then
        round=$(read_round)
        round_path="$PHASE_DIR/remediation/qa/round-${round}/R${round}-VERIFICATION.md"
        if [ -f "$round_path" ]; then
          echo "$round_path"
        else
          echo "$round_path"
        fi
        exit 0
      fi
    fi
    echo "$phase_path"
    ;;
  plan-input)
    if [ -f "$STATE_FILE" ]; then
      round=$(read_round)
      if [ "$((10#$round))" -gt 1 ]; then
        prev_round=$(printf '%02d' "$((10#$round - 1))")
        prev_path="$PHASE_DIR/remediation/qa/round-${prev_round}/R${prev_round}-VERIFICATION.md"
        if [ ! -f "$prev_path" ]; then
          exit 0
        fi

        search_round=$((10#$prev_round))
        while [ "$search_round" -gt 0 ] 2>/dev/null; do
          candidate_round=$(printf '%02d' "$search_round")
          candidate_path="$PHASE_DIR/remediation/qa/round-${candidate_round}/R${candidate_round}-VERIFICATION.md"
          if [ ! -f "$candidate_path" ]; then
            exit 0
          fi
          if verification_has_fail_rows "$candidate_path"; then
            echo "$candidate_path"
            exit 0
          fi
          search_round=$((search_round - 1))
        done

        if verification_has_fail_rows "$phase_path"; then
          echo "$phase_path"
        fi
        exit 0
      fi
    fi
    if verification_has_fail_rows "$phase_path"; then
      echo "$phase_path"
    fi
    ;;
esac