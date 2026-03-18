#!/usr/bin/env bash
set -u

# validate-contract.sh <mode> <contract-path> <task-number> [modified-files...]
# Validates a task against its contract sidecar.
#
# mode: start (verify contract exists, task in range, hash integrity)
#       end   (check modified files against allowed_paths + forbidden_paths)
#
# Hard contract validation (v2_hard_contracts, graduated): hard stop — exit 2 on violation

if [ $# -lt 3 ]; then
  echo "Usage: validate-contract.sh <start|end> <contract-path> <task-number> [files...]" >&2
  exit 0
fi

MODE="$1"
CONTRACT_PATH="$2"
TASK_NUM="$3"
shift 3

# shellcheck disable=SC2034 # PLANNING_DIR used by convention across VBW scripts
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate contract file exists
if [ ! -f "$CONTRACT_PATH" ]; then
  echo "V2 contract: contract file not found: $CONTRACT_PATH" >&2
  exit 2
fi

# Read contract fields
TASK_COUNT=$(jq -r '.task_count // 0' "$CONTRACT_PATH" 2>/dev/null) || TASK_COUNT=0
PHASE=$(jq -r '.phase // 0' "$CONTRACT_PATH" 2>/dev/null) || PHASE=0

emit_violation() {
  local violation_type="$1"
  local detail="$2"
  if [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
    bash "${SCRIPT_DIR}/collect-metrics.sh" scope_violation "$PHASE" \
      "type=${violation_type}" "task=${TASK_NUM}" "detail=${detail}" 2>/dev/null || true
  fi
  echo "V2 contract violation (${violation_type}): ${detail}" >&2
}

case "$MODE" in
  start)
    # Verify task number is within plan range
    if [ "$TASK_NUM" -gt "$TASK_COUNT" ] 2>/dev/null || [ "$TASK_NUM" -lt 1 ] 2>/dev/null; then
      emit_violation "task_range" "Task ${TASK_NUM} outside contract range 1-${TASK_COUNT}"
      exit 2
    fi

    # Verify contract hash integrity
    STORED_HASH=$(jq -r '.contract_hash // ""' "$CONTRACT_PATH" 2>/dev/null) || STORED_HASH=""
    if [ -n "$STORED_HASH" ]; then
      # Recompute hash from contract body (excluding contract_hash field)
      COMPUTED_HASH=$(jq 'del(.contract_hash)' "$CONTRACT_PATH" 2>/dev/null | shasum -a 256 | cut -d' ' -f1) || COMPUTED_HASH=""
      if [ "$STORED_HASH" != "$COMPUTED_HASH" ]; then
        emit_violation "hash_mismatch" "Contract hash mismatch: stored=${STORED_HASH:0:16}... computed=${COMPUTED_HASH:0:16}..."
        exit 2
      fi
    fi
    ;;

  end)
    # Read allowed paths
    ALLOWED=$(jq -r '.allowed_paths[]' "$CONTRACT_PATH" 2>/dev/null) || ALLOWED=""

    # Read forbidden paths
    FORBIDDEN=$(jq -r '.forbidden_paths[]' "$CONTRACT_PATH" 2>/dev/null) || FORBIDDEN=""

    for FILE in "$@"; do
      [ -z "$FILE" ] && continue
      # Normalize: strip leading ./
      NORM_FILE="${FILE#./}"

      # Check forbidden paths first (hard stop)
      if [ -n "$FORBIDDEN" ]; then
        while IFS= read -r forbidden; do
          [ -z "$forbidden" ] && continue
          NORM_FORBIDDEN="${forbidden#./}"
          NORM_FORBIDDEN="${NORM_FORBIDDEN%/}"
          # Exact match or prefix match (directory patterns)
          if [ "$NORM_FILE" = "$NORM_FORBIDDEN" ] || [[ "$NORM_FILE" == "$NORM_FORBIDDEN"/* ]]; then
            emit_violation "forbidden_path" "${NORM_FILE} matches forbidden path ${NORM_FORBIDDEN}"
            exit 2
          fi
        done <<< "$FORBIDDEN"
      fi

      # Check allowed paths
      FOUND=false
      while IFS= read -r allowed; do
        [ -z "$allowed" ] && continue
        NORM_ALLOWED="${allowed#./}"
        if [ "$NORM_FILE" = "$NORM_ALLOWED" ]; then
          FOUND=true
          break
        fi
      done <<< "$ALLOWED"

      if [ "$FOUND" = "false" ]; then
        emit_violation "out_of_scope" "${NORM_FILE} not in allowed_paths"
        exit 2
      fi
    done
    ;;

  *)
    echo "Unknown mode: $MODE. Valid: start, end" >&2
    ;;
esac

exit 0
