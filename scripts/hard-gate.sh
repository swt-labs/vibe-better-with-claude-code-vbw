#!/usr/bin/env bash
set -u

# hard-gate.sh <gate_type> <phase> <plan> <task> <contract_path>
# Runs a single hard gate check. Returns JSON result.
# Gate types: contract_compliance, protected_file, required_checks,
#             commit_hygiene, artifact_persistence, verification_threshold
#
# Output: JSON {gate, result, evidence, ts}
# Exit: 0 on pass, 2 on fail (when v2_hard_gates=true)
# AUTONOMY INDEPENDENCE (V2 spec line 162):
# Gates fire regardless of the autonomy config value. YOLO/full autonomy
# skips interactive prompts and confirmation gates, but hard gates (file
# integrity, contract compliance, commit hygiene) always execute. The
# autonomy value is included in gate output for observability only.

if [ $# -lt 5 ]; then
  echo '{"gate":"unknown","result":"error","evidence":"insufficient arguments","ts":"unknown"}'
  exit 0
fi

GATE_TYPE="$1"
PHASE="$2"
PLAN="$3"
TASK="$4"
CONTRACT_PATH="$5"

PLANNING_DIR=".vbw-planning"
CONFIG_PATH="${PLANNING_DIR}/config.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AUTONOMY="unknown"
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  AUTONOMY=$(jq -r '.autonomy // "unknown"' "$CONFIG_PATH" 2>/dev/null || echo "unknown")
fi

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

emit_result() {
  local result="$1"
  local evidence="$2"
  local event_type="gate_passed"
  [ "$result" = "fail" ] && event_type="gate_failed"

  # Log event
  if [ -f "${SCRIPT_DIR}/log-event.sh" ]; then
    bash "${SCRIPT_DIR}/log-event.sh" "$event_type" "$PHASE" "$PLAN" \
      "gate=${GATE_TYPE}" "task=${TASK}" "evidence=${evidence}" 2>/dev/null || true
  fi

  # Log metric
  if [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
    bash "${SCRIPT_DIR}/collect-metrics.sh" "gate_${result}" "$PHASE" "$PLAN" \
      "gate=${GATE_TYPE}" "task=${TASK}" 2>/dev/null || true
  fi

  echo "{\"gate\":\"${GATE_TYPE}\",\"result\":\"${result}\",\"evidence\":\"${evidence}\",\"autonomy\":\"${AUTONOMY}\",\"ts\":\"${TS}\"}"
}

case "$GATE_TYPE" in
  contract_compliance)
    # Verify contract hash integrity + task in range
    if [ ! -f "$CONTRACT_PATH" ]; then
      emit_result "fail" "contract file not found"
      exit 2
    fi

    # Hash check
    STORED_HASH=$(jq -r '.contract_hash // ""' "$CONTRACT_PATH" 2>/dev/null) || STORED_HASH=""
    if [ -n "$STORED_HASH" ]; then
      COMPUTED_HASH=$(jq 'del(.contract_hash)' "$CONTRACT_PATH" 2>/dev/null | shasum -a 256 | cut -d' ' -f1) || COMPUTED_HASH=""
      if [ "$STORED_HASH" != "$COMPUTED_HASH" ]; then
        emit_result "fail" "contract hash mismatch"
        exit 2
      fi
    fi

    # Task range check
    TASK_COUNT=$(jq -r '.task_count // 0' "$CONTRACT_PATH" 2>/dev/null) || TASK_COUNT=0
    if [ "$TASK" -gt "$TASK_COUNT" ] 2>/dev/null || [ "$TASK" -lt 1 ] 2>/dev/null; then
      emit_result "fail" "task ${TASK} outside range 1-${TASK_COUNT}"
      exit 2
    fi

    emit_result "pass" "hash verified, task in range"
    ;;

  protected_file)
    # Check if any modified files are in forbidden_paths
    if [ ! -f "$CONTRACT_PATH" ]; then
      emit_result "pass" "no contract, fail-open"
      exit 0
    fi

    FORBIDDEN=$(jq -r '.forbidden_paths[]' "$CONTRACT_PATH" 2>/dev/null) || FORBIDDEN=""
    if [ -z "$FORBIDDEN" ]; then
      emit_result "pass" "no forbidden paths defined"
      exit 0
    fi

    # Check git staged files against forbidden paths
    STAGED=$(git diff --cached --name-only 2>/dev/null) || STAGED=""
    BLOCKED=""
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      while IFS= read -r forbidden; do
        [ -z "$forbidden" ] && continue
        if [ "$file" = "$forbidden" ] || [[ "$file" == "$forbidden"/* ]]; then
          BLOCKED="${BLOCKED}${file} "
        fi
      done <<< "$FORBIDDEN"
    done <<< "$STAGED"

    if [ -n "$BLOCKED" ]; then
      emit_result "fail" "forbidden files staged: ${BLOCKED}"
      exit 2
    fi

    emit_result "pass" "no forbidden files staged"
    ;;

  required_checks)
    # Run verification_checks from contract
    if [ ! -f "$CONTRACT_PATH" ]; then
      emit_result "pass" "no contract, fail-open"
      exit 0
    fi

    CHECKS=$(jq -r '.verification_checks[]' "$CONTRACT_PATH" 2>/dev/null) || CHECKS=""
    if [ -z "$CHECKS" ]; then
      emit_result "pass" "no verification checks defined"
      exit 0
    fi

    FAILED_CHECKS=""
    while IFS= read -r check; do
      [ -z "$check" ] && continue
      if ! eval "$check" >/dev/null 2>&1; then
        FAILED_CHECKS="${FAILED_CHECKS}${check}; "
      fi
    done <<< "$CHECKS"

    if [ -n "$FAILED_CHECKS" ]; then
      emit_result "fail" "checks failed: ${FAILED_CHECKS}"
      exit 2
    fi

    emit_result "pass" "all verification checks passed"
    ;;

  commit_hygiene)
    # Validate last commit message format
    LAST_MSG=$(git log -1 --format=%s 2>/dev/null) || LAST_MSG=""
    if [ -z "$LAST_MSG" ]; then
      emit_result "pass" "no commits to check"
      exit 0
    fi

    # Check conventional commit format: type(scope): description
    if echo "$LAST_MSG" | grep -qE '^(feat|fix|test|refactor|perf|docs|style|chore)\(.+\): .+'; then
      emit_result "pass" "commit format valid"
    else
      emit_result "fail" "commit format invalid: ${LAST_MSG}"
      exit 2
    fi
    ;;

  artifact_persistence)
    # Verify SUMMARY.md exists for completed plans
    PHASES_DIR="${PLANNING_DIR}/phases"
    [ ! -d "$PHASES_DIR" ] && { emit_result "pass" "no phases dir"; exit 0; }

    PHASE_DIR=$(ls -d "${PHASES_DIR}/${PHASE}-"* 2>/dev/null | head -1)
    [ -z "$PHASE_DIR" ] && { emit_result "pass" "phase dir not found"; exit 0; }

    # Check all plans up to current have SUMMARY.md
    MISSING=""
    for plan_file in "$PHASE_DIR"/*-PLAN.md; do
      [ ! -f "$plan_file" ] && continue
      PLAN_NUM=$(basename "$plan_file" | sed 's/^[0-9]*-\([0-9]*\)-.*/\1/')
      # Only check plans before the current one
      if [ "$PLAN_NUM" -lt "$PLAN" ] 2>/dev/null; then
        SUMMARY_FILE="${plan_file%-PLAN.md}-SUMMARY.md"
        if [ ! -f "$SUMMARY_FILE" ]; then
          MISSING="${MISSING}plan-${PLAN_NUM} "
        fi
      fi
    done

    if [ -n "$MISSING" ]; then
      emit_result "fail" "missing SUMMARY.md for: ${MISSING}"
      exit 2
    fi

    emit_result "pass" "all prior plan artifacts present"
    ;;

  verification_threshold)
    # Check QA pass rate meets threshold
    PHASES_DIR="${PLANNING_DIR}/phases"
    PHASE_DIR=$(ls -d "${PHASES_DIR}/${PHASE}-"* 2>/dev/null | head -1)
    [ -z "$PHASE_DIR" ] && { emit_result "pass" "phase dir not found"; exit 0; }

    # Prefer final phase verification artifact over wave files.
    # Selection order:
    # 1) <phasePrefix>-VERIFICATION.md (authoritative final)
    # 2) Latest <phasePrefix>-VERIFICATION-waveN.md
    # 3) Brownfield fallback: VERIFICATION.md
    # 4) Legacy fallback: first *-VERIFICATION*.md
    VERIFICATION_FILE=""
    PHASE_BASENAME=$(basename "$PHASE_DIR")
    PHASE_PREFIX="${PHASE_BASENAME%%-*}"

    # 1) Final deterministic phase verification file
    if [ -f "$PHASE_DIR/${PHASE_PREFIX}-VERIFICATION.md" ]; then
      VERIFICATION_FILE="$PHASE_DIR/${PHASE_PREFIX}-VERIFICATION.md"
    fi

    # 2) Latest wave verification (if final file absent)
    if [ -z "$VERIFICATION_FILE" ]; then
      WAVE_FILES=$(ls -1 "$PHASE_DIR/${PHASE_PREFIX}-VERIFICATION-wave"*.md 2>/dev/null | (sort -V 2>/dev/null || sort))
      if [ -n "$WAVE_FILES" ]; then
        VERIFICATION_FILE=$(printf '%s\n' "$WAVE_FILES" | tail -1)
      fi
    fi

    # 3) Brownfield fallback: non-prefixed VERIFICATION.md
    if [ -z "$VERIFICATION_FILE" ] && [ -f "$PHASE_DIR/VERIFICATION.md" ]; then
      VERIFICATION_FILE="$PHASE_DIR/VERIFICATION.md"
    fi

    # 4) Legacy fallback: any prefixed verification artifact
    if [ -z "$VERIFICATION_FILE" ]; then
      for vf in "$PHASE_DIR"/*-VERIFICATION*.md; do
        [ -f "$vf" ] && VERIFICATION_FILE="$vf" && break
      done
    fi

    if [ -z "$VERIFICATION_FILE" ]; then
      # No verification file — check config for verification_tier
      TIER=$(jq -r '.verification_tier // "standard"' "$CONFIG_PATH" 2>/dev/null || echo "standard")
      if [ "$TIER" = "quick" ] || [ "$TIER" = "skip" ]; then
        emit_result "pass" "verification not required (tier=${TIER})"
        exit 0
      fi
      emit_result "fail" "VERIFICATION.md missing (tier=${TIER})"
      exit 2
    fi

    # Check for PASS verdict
    if grep -qi 'PASS\|passed\|all.*pass' "$VERIFICATION_FILE" 2>/dev/null; then
      emit_result "pass" "verification passed"
    elif grep -qi 'FAIL\|failed' "$VERIFICATION_FILE" 2>/dev/null; then
      emit_result "fail" "verification failed"
      exit 2
    else
      emit_result "pass" "verification status unclear, fail-open"
    fi
    ;;

  forbidden_commands)
    # Check if any recently executed commands match forbidden_commands patterns
    if [ ! -f "$CONTRACT_PATH" ]; then
      emit_result "pass" "no contract, fail-open"
      exit 0
    fi

    FORBIDDEN_COUNT=$(jq -r '.forbidden_commands | length // 0' "$CONTRACT_PATH" 2>/dev/null) || FORBIDDEN_COUNT=0
    if [ "$FORBIDDEN_COUNT" -eq 0 ]; then
      emit_result "pass" "no forbidden commands defined"
      exit 0
    fi

    # Check event log for bash_guard_block events in current plan
    EVENT_LOG="${PLANNING_DIR}/.event-log.jsonl"
    if [ ! -f "$EVENT_LOG" ]; then
      emit_result "pass" "no event log, fail-open"
      exit 0
    fi

    # Look for bash_guard_block events (any blocked destructive command is a violation)
    VIOLATIONS=$(grep '"bash_guard_block"' "$EVENT_LOG" 2>/dev/null | tail -5)
    if [ -n "$VIOLATIONS" ]; then
      PREVIEW=$(echo "$VIOLATIONS" | jq -r '.command_preview // "unknown"' 2>/dev/null | head -1)
      emit_result "fail" "destructive command attempted: ${PREVIEW}"
      exit 2
    fi

    emit_result "pass" "no forbidden command violations"
    ;;

  *)
    emit_result "fail" "unknown gate type: ${GATE_TYPE}"
    exit 2
    ;;
esac
