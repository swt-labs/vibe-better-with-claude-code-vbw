#!/usr/bin/env bash
set -u

# two-phase-complete.sh <task_id> <phase> <plan> <contract_path> [evidence...]
# V2 two-phase completion protocol:
#   1. Emit task_completed_candidate with evidence
#   2. Validate must_haves + verification_checks from contract
#   3. Emit task_completed_confirmed on pass, task_completion_rejected on fail
# Output: JSON {result: "confirmed"|"rejected", checks_passed: N, checks_total: N, errors: [...]}
# Exit: 0 on confirmed, 2 on rejected, 0 when flag off

# shellcheck disable=SC2034 # PLANNING_DIR used by convention across VBW scripts
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 4 ]; then
  echo '{"result":"error","errors":["usage: two-phase-complete.sh <task_id> <phase> <plan> <contract_path> [evidence...]"]}'
  exit 0
fi

TASK_ID="$1"
PHASE="$2"
PLAN="$3"
CONTRACT_PATH="$4"
shift 4

# Check two_phase_completion flag — if disabled, skip
CONFIG_PATH="$PLANNING_DIR/config.json"
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  TWO_PHASE=$(jq -r 'if .two_phase_completion != null then .two_phase_completion elif .v2_two_phase_completion != null then .v2_two_phase_completion else true end' "$CONFIG_PATH" 2>/dev/null || echo "true")
  if [ "$TWO_PHASE" != "true" ]; then
    echo '{"result":"skipped","reason":"two_phase_completion=false"}'
    exit 0
  fi
fi

# Collect evidence from remaining args; extract files_modified if present
EVIDENCE=""
FILES_MODIFIED=""
for arg in "$@"; do
  case "$arg" in
    files_modified=*)
      FILES_MODIFIED="${arg#files_modified=}"
      ;;
  esac
  if [ -n "$EVIDENCE" ]; then
    EVIDENCE="${EVIDENCE}, ${arg}"
  else
    EVIDENCE="$arg"
  fi
done

# Phase 1: Emit task_completed_candidate
if [ -f "${SCRIPT_DIR}/log-event.sh" ]; then
  bash "${SCRIPT_DIR}/log-event.sh" "task_completed_candidate" "$PHASE" "$PLAN" \
    "task_id=${TASK_ID}" "evidence=${EVIDENCE:-none}" 2>/dev/null || true
fi

# Phase 2: Validate must_haves + verification_checks from contract
ERRORS="[]"
CHECKS_PASSED=0
CHECKS_TOTAL=0

add_error() {
  ERRORS=$(echo "$ERRORS" | jq --arg e "$1" '. + [$e]' 2>/dev/null || echo "[\"$1\"]")
}

if [ ! -f "$CONTRACT_PATH" ]; then
  add_error "contract file not found: ${CONTRACT_PATH}"
  CHECKS_TOTAL=1
else
  # Check must_haves: require non-empty evidence (REQ-03)
  MUST_HAVES=$(jq -r '.must_haves // [] | .[]' "$CONTRACT_PATH" 2>/dev/null) || MUST_HAVES=""
  if [ -n "$MUST_HAVES" ]; then
    while IFS= read -r mh; do
      [ -z "$mh" ] && continue
      CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
      if [ -z "$EVIDENCE" ] || [ "$EVIDENCE" = "none" ]; then
        add_error "no evidence provided for must_have: ${mh}"
      else
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
      fi
    done <<< "$MUST_HAVES"
  fi

  # Validate files_modified against allowed_paths (REQ-03)
  if [ -n "$FILES_MODIFIED" ]; then
    ALLOWED_PATHS=$(jq -r '.allowed_paths // [] | .[]' "$CONTRACT_PATH" 2>/dev/null) || ALLOWED_PATHS=""
    if [ -n "$ALLOWED_PATHS" ]; then
      IFS=',' read -ra FM_ARRAY <<< "$FILES_MODIFIED"
      for fmod in "${FM_ARRAY[@]}"; do
        [ -z "$fmod" ] && continue
        CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
        IN_SCOPE=false
        while IFS= read -r allowed; do
          [ -z "$allowed" ] && continue
          case "$fmod" in
            "$allowed"|"$allowed"/*) IN_SCOPE=true; break ;;
          esac
        done <<< "$ALLOWED_PATHS"
        if [ "$IN_SCOPE" = "true" ]; then
          CHECKS_PASSED=$((CHECKS_PASSED + 1))
        else
          add_error "files_modified outside allowed_paths: ${fmod}"
        fi
      done
    fi
  fi

  # Run verification_checks: each is a shell command that must exit 0
  VERIFICATION_CHECKS=$(jq -r '.verification_checks // [] | .[]' "$CONTRACT_PATH" 2>/dev/null) || VERIFICATION_CHECKS=""
  if [ -n "$VERIFICATION_CHECKS" ]; then
    while IFS= read -r check; do
      [ -z "$check" ] && continue
      CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
      if eval "$check" >/dev/null 2>&1; then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
      else
        add_error "verification check failed: ${check}"
      fi
    done <<< "$VERIFICATION_CHECKS"
  fi
fi

# Phase 3: Emit result
ERROR_COUNT=$(echo "$ERRORS" | jq 'length' 2>/dev/null || echo "0")

if [ "$ERROR_COUNT" -eq 0 ] || [ "$ERROR_COUNT" = "0" ]; then
  # Emit task_completed_confirmed
  if [ -f "${SCRIPT_DIR}/log-event.sh" ]; then
    bash "${SCRIPT_DIR}/log-event.sh" "task_completed_confirmed" "$PHASE" "$PLAN" \
      "task_id=${TASK_ID}" "checks_passed=${CHECKS_PASSED}" "checks_total=${CHECKS_TOTAL}" 2>/dev/null || true
  fi

  jq -n --argjson passed "$CHECKS_PASSED" --argjson total "$CHECKS_TOTAL" \
    '{result: "confirmed", checks_passed: $passed, checks_total: $total, errors: []}'
  exit 0
else
  # Emit task_completion_rejected
  if [ -f "${SCRIPT_DIR}/log-event.sh" ]; then
    bash "${SCRIPT_DIR}/log-event.sh" "task_completion_rejected" "$PHASE" "$PLAN" \
      "task_id=${TASK_ID}" "checks_passed=${CHECKS_PASSED}" "checks_total=${CHECKS_TOTAL}" \
      "error_count=${ERROR_COUNT}" 2>/dev/null || true
  fi

  jq -n --argjson passed "$CHECKS_PASSED" --argjson total "$CHECKS_TOTAL" --argjson errors "$ERRORS" \
    '{result: "rejected", checks_passed: $passed, checks_total: $total, errors: $errors}'
  exit 2
fi
