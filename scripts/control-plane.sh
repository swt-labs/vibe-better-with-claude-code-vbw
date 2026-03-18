#!/usr/bin/env bash
set -u

# control-plane.sh <action> <phase> <plan> <task> [options...]
# Lightweight dispatcher that orchestrates enforcement scripts into a sequenced flow.
# Actions: pre-task, post-task, compile, full
# Sequences: contract -> lease -> gate -> context (in that order)
# No-op (exit 0) when all relevant feature flags are OFF.
# Delegates to existing scripts — does not reimplement their logic.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
CONFIG_PATH="${PLANNING_DIR}/config.json"

# --- Usage ---
usage() {
  cat <<EOF
Usage: control-plane.sh <action> <phase> <plan> <task> [options...]

Actions:
  pre-task   Contract + lease acquire + gate checks (per-task)
  post-task  Gate checks + lease release (per-task)
  compile    Context compilation + token budget (per-plan)
  full       Contract + context compilation (per-plan)

Options:
  --plan-path=PATH        Path to plan file
  --role=ROLE             Agent role (dev, lead, qa, scout, etc.)
  --phase-dir=DIR         Phase directory path
  --task-id=ID            Task identifier (e.g., 1-1-T1)
  --claimed-files=F,...   Comma-separated files to lock
EOF
  exit 0
}

# --- Argument parsing ---
if [ $# -lt 1 ]; then
  usage
fi

ACTION="$1"
PHASE="${2:-0}"
PLAN="${3:-0}"
TASK="${4:-0}"
shift
[ $# -ge 1 ] && shift
[ $# -ge 1 ] && shift
[ $# -ge 1 ] && shift

PLAN_PATH=""
ROLE="dev"
PHASE_DIR=""
TASK_ID=""
CLAIMED_FILES=""

for arg in "$@"; do
  case "$arg" in
    --plan-path=*)   PLAN_PATH="${arg#--plan-path=}" ;;
    --role=*)        ROLE="${arg#--role=}" ;;
    --phase-dir=*)   PHASE_DIR="${arg#--phase-dir=}" ;;
    --task-id=*)     TASK_ID="${arg#--task-id=}" ;;
    --claimed-files=*) CLAIMED_FILES="${arg#--claimed-files=}" ;;
  esac
done

# --- Config / flag resolution ---
CONTEXT_COMPILER=false
TOKEN_BUDGETS=true

if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  CONTEXT_COMPILER=$(jq -r 'if .context_compiler == null then true else .context_compiler end' "$CONFIG_PATH" 2>/dev/null || echo "true")
  TOKEN_BUDGETS=$(jq -r 'if .token_budgets != null then .token_budgets elif .v2_token_budgets != null then .v2_token_budgets else true end' "$CONFIG_PATH" 2>/dev/null || echo "true")
fi

# --- No-op check (REQ-C1) ---
# If all flags relevant to the chosen action are false, exit 0 immediately.
# Note: v2_hard_contracts, v2_hard_gates are now always-on (graduated)
# Token budgets and context compiler are config-gated.
check_noop() {
  case "$ACTION" in
    pre-task)
      # Contract and gates are always-on — pre-task is never a noop
      return 1
      ;;
    post-task)
      # Gates are always-on
      return 1
      ;;
    compile)
      [ "$CONTEXT_COMPILER" != "true" ] && [ "$TOKEN_BUDGETS" != "true" ] && return 0
      ;;
    full)
      # Contract is always-on — full is never a noop
      return 1
      ;;
  esac
  return 1
}

# --- Result tracking ---
STEPS_JSON="[]"

record_step() {
  local name="$1" status="$2" detail="${3:-}"
  STEPS_JSON=$(echo "$STEPS_JSON" | jq --arg n "$name" --arg s "$status" --arg d "$detail" \
    '. + [{"name": $n, "status": $s, "detail": $d}]' 2>/dev/null) || true
}

emit_result() {
  local exit_code="${1:-0}"
  # Include context_path and contract_path in output when available
  if [ -n "$CONTEXT_PATH_OUT" ] || [ -n "$CONTRACT_PATH_OUT" ]; then
    local ctx_json="${CONTEXT_PATH_OUT:-null}"
    local ctr_json="${CONTRACT_PATH_OUT:-null}"
    [ "$ctx_json" != "null" ] && ctx_json="\"$ctx_json\""
    [ "$ctr_json" != "null" ] && ctr_json="\"$ctr_json\""
    jq -n --arg action "$ACTION" --argjson steps "$STEPS_JSON" \
      --argjson ctx "$ctx_json" --argjson ctr "$ctr_json" \
      '{"action": $action, "steps": $steps, "context_path": $ctx, "contract_path": $ctr}' 2>/dev/null \
      || echo "{\"action\":\"${ACTION}\",\"steps\":[]}"
  else
    jq -n --arg action "$ACTION" --argjson steps "$STEPS_JSON" \
      '{"action": $action, "steps": $steps}' 2>/dev/null \
      || echo "{\"action\":\"${ACTION}\",\"steps\":[]}"
  fi
  exit "$exit_code"
}

# --- Step functions ---
CONTRACT_PATH_OUT=""

step_contract() {
  # v2_hard_contracts is now always enabled (graduated)
  if [ -z "$PLAN_PATH" ] || [ ! -f "$PLAN_PATH" ]; then
    record_step "contract" "skip" "no plan file"
    return 0
  fi
  local result
  result=$(bash "$SCRIPT_DIR/generate-contract.sh" "$PLAN_PATH" 2>/dev/null) || {
    record_step "contract" "fail" "generate-contract.sh error"
    echo "control-plane: contract generation failed" >&2
    return 0
  }
  if [ -n "$result" ]; then
    CONTRACT_PATH_OUT="$result"
    record_step "contract" "pass" "$result"
  else
    record_step "contract" "skip" "no output from generate-contract.sh"
  fi
  return 0
}

step_lease_acquire() {
  local tid="${TASK_ID:-${PHASE}-${PLAN}-T${TASK}}"
  local files_args=""
  if [ -n "$CLAIMED_FILES" ]; then
    files_args=$(echo "$CLAIMED_FILES" | tr ',' ' ')
  fi
  local result
  result=$(bash "$SCRIPT_DIR/lease-lock.sh" acquire "$tid" --ttl=300 $files_args 2>/dev/null) || {
    record_step "lease_acquire" "fail" "lease-lock.sh error"
    echo "control-plane: lease acquisition failed" >&2
    return 0
  }
  if [ "$result" = "conflict_blocked" ]; then
    # Retry once after 2s delay (per plan: auto-repair on lease conflict)
    sleep 2
    result=$(bash "$SCRIPT_DIR/lease-lock.sh" acquire "$tid" --ttl=300 $files_args 2>/dev/null) || result="error"
    if [ "$result" = "conflict_blocked" ] || [ "$result" = "error" ]; then
      record_step "lease_acquire" "fail" "conflict blocked after retry"
      return 1
    fi
  fi
  record_step "lease_acquire" "pass" "$result"
  return 0
}

step_gate() {
  local gate_type="$1"
  # v2_hard_gates is now always enabled (graduated)
  local contract="${CONTRACT_PATH_OUT:-}"
  if [ -z "$contract" ]; then
    # Try to find contract from phase/plan
    contract="${PLANNING_DIR}/.contracts/${PHASE}-${PLAN}.json"
  fi
  local result exit_code
  result=$(bash "$SCRIPT_DIR/hard-gate.sh" "$gate_type" "$PHASE" "$PLAN" "$TASK" "$contract" 2>/dev/null) || true
  exit_code=$?
  local gate_result
  gate_result=$(echo "$result" | jq -r '.result // "unknown"' 2>/dev/null) || gate_result="unknown"

  if [ "$gate_result" = "fail" ]; then
    # Attempt auto-repair
    local repair_result
    repair_result=$(bash "$SCRIPT_DIR/auto-repair.sh" "$gate_type" "$PHASE" "$PLAN" "$TASK" "$contract" 2>/dev/null) || true
    local repaired
    repaired=$(echo "$repair_result" | jq -r '.repaired // false' 2>/dev/null) || repaired="false"
    if [ "$repaired" = "true" ]; then
      record_step "gate_${gate_type}" "pass" "repaired"
      return 0
    else
      record_step "gate_${gate_type}" "fail" "gate failed, repair failed"
      return 1
    fi
  fi
  record_step "gate_${gate_type}" "pass" "$gate_result"
  return 0
}

step_lease_release() {
  local tid="${TASK_ID:-${PHASE}-${PLAN}-T${TASK}}"
  local result
  result=$(bash "$SCRIPT_DIR/lease-lock.sh" release "$tid" 2>/dev/null) || result="error"
  record_step "lease_release" "pass" "$result"
  return 0
}

CONTEXT_PATH_OUT=""

step_context() {
  if [ "$CONTEXT_COMPILER" != "true" ]; then
    record_step "context" "skip" "context_compiler=false"
    return 0
  fi
  local phases_dir="${PHASE_DIR%/*}"
  [ -z "$phases_dir" ] && phases_dir="${PLANNING_DIR}/phases"
  local result
  result=$(bash "$SCRIPT_DIR/compile-context.sh" "$PHASE" "$ROLE" "$phases_dir" "$PLAN_PATH" 2>/dev/null) || {
    record_step "context" "fail" "compile-context.sh error"
    echo "control-plane: context compilation failed" >&2
    return 0
  }
  if [ -n "$result" ]; then
    CONTEXT_PATH_OUT="$result"
    record_step "context" "pass" "$result"
  else
    record_step "context" "skip" "no output from compile-context.sh"
  fi
  return 0
}

step_token_budget() {
  # token_budgets flag controls budget enforcement
  if [ "$TOKEN_BUDGETS" != "true" ]; then
    record_step "token_budget" "skip" "token_budgets=false"
    return 0
  fi
  # token-budget.sh will pass through if no budget definitions exist
  if [ -z "$CONTEXT_PATH_OUT" ] || [ ! -f "$CONTEXT_PATH_OUT" ]; then
    record_step "token_budget" "skip" "no context file"
    return 0
  fi
  local contract="${CONTRACT_PATH_OUT:-}"
  local tmp
  tmp=$(mktemp 2>/dev/null) || {
    record_step "token_budget" "fail" "could not create temp file"
    return 0
  }
  bash "$SCRIPT_DIR/token-budget.sh" "$ROLE" "$CONTEXT_PATH_OUT" "$contract" "$TASK" > "$tmp" 2>/dev/null || {
    rm -f "$tmp"
    record_step "token_budget" "fail" "token-budget.sh error"
    return 0
  }
  if [ -s "$tmp" ]; then
    mv "$tmp" "$CONTEXT_PATH_OUT" 2>/dev/null || rm -f "$tmp"
    record_step "token_budget" "pass" "budget applied"
  else
    rm -f "$tmp"
    record_step "token_budget" "skip" "empty output"
  fi
  return 0
}

# --- No-op early exit ---
if check_noop; then
  record_step "noop" "skip" "all flags OFF for ${ACTION}"
  emit_result 0
fi

# --- Action dispatch ---
case "$ACTION" in
  pre-task)
    step_contract
    step_lease_acquire || emit_result 1
    step_gate "contract_compliance" || emit_result 1
    step_gate "protected_file" || emit_result 1
    emit_result 0
    ;;

  post-task)
    step_gate "required_checks" || emit_result 1
    step_gate "commit_hygiene" || emit_result 1
    step_lease_release
    emit_result 0
    ;;

  compile)
    step_context
    step_token_budget
    emit_result 0
    ;;

  full)
    step_contract
    step_context
    step_token_budget
    emit_result 0
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    usage
    ;;
esac
