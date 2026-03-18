#!/usr/bin/env bash
set -u

# token-budget.sh <role> [file] [contract-path] [task-number]
# Enforces character-based budgets on context content.
#
# Budget resolution order (v2_token_budgets=true):
#   1. Per-task: contract metadata -> complexity score -> tier multiplier -> role base * multiplier
#   2. Per-role: token-budgets.json .budgets[role].max_chars
#   3. No budget (pass through): role not in budgets or max_chars=0
#
# Input: file path as arg, or stdin if no file.
# Output: truncated content within budget (stdout).
# Logs overage to metrics (v3_metrics graduated).
# Exit: 0 always (budget enforcement must never block).

# shellcheck disable=SC2034 # PLANNING_DIR used by convention across VBW scripts
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUDGETS_PATH="${SCRIPT_DIR}/../config/token-budgets.json"

if [ $# -lt 1 ]; then
  # No role — pass through
  cat 2>/dev/null
  exit 0
fi

ROLE="$1"
shift

# Read content from file arg or stdin
CONTENT=""
if [ $# -ge 1 ] && [ -f "$1" ]; then
  CONTENT=$(cat "$1" 2>/dev/null) || CONTENT=""
  shift
else
  CONTENT=$(cat 2>/dev/null) || CONTENT=""
fi

# Optional contract metadata for per-task budgets
CONTRACT_PATH="${1:-}"

# Check token_budgets flag — if disabled, pass through
# Legacy fallback: honor v2_token_budgets if unprefixed key missing (pre-migration brownfield)
CONFIG_PATH="$PLANNING_DIR/config.json"
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  TOKEN_BUDGETS=$(jq -r 'if .token_budgets != null then .token_budgets elif .v2_token_budgets != null then .v2_token_budgets else true end' "$CONFIG_PATH" 2>/dev/null || echo "true")
  if [ "$TOKEN_BUDGETS" != "true" ]; then
    echo "$CONTENT"
    exit 0
  fi
fi

# If no budget definitions exist, pass through
if [ ! -f "$BUDGETS_PATH" ]; then
  echo "$CONTENT"
  exit 0
fi

# Compute per-task budget from contract metadata and complexity tiers
compute_task_budget() {
  local contract_path="$1"
  local role="$2"
  local budgets_path="$3"

  # Check per_task_budget_enabled
  local enabled
  enabled=$(jq -r '.task_complexity.per_task_budget_enabled // false' "$budgets_path" 2>/dev/null) || enabled="false"
  [ "$enabled" != "true" ] && return 1

  # Read contract metadata
  [ ! -f "$contract_path" ] && return 1
  local must_haves_count allowed_paths_count depends_on_count
  must_haves_count=$(jq '.must_haves | length' "$contract_path" 2>/dev/null) || must_haves_count=0
  allowed_paths_count=$(jq '.allowed_paths | length' "$contract_path" 2>/dev/null) || allowed_paths_count=0
  depends_on_count=$(jq '.depends_on | length' "$contract_path" 2>/dev/null) || depends_on_count=0

  # Read weights
  local mh_w files_w dep_w
  mh_w=$(jq -r '.task_complexity.must_haves_weight // 1' "$budgets_path" 2>/dev/null) || mh_w=1
  files_w=$(jq -r '.task_complexity.files_weight // 2' "$budgets_path" 2>/dev/null) || files_w=2
  dep_w=$(jq -r '.task_complexity.dependency_weight // 3' "$budgets_path" 2>/dev/null) || dep_w=3

  # Compute complexity score
  local score
  score=$(( (must_haves_count * mh_w) + (allowed_paths_count * files_w) + (depends_on_count * dep_w) ))

  # Find matching tier
  local multiplier
  multiplier=$(jq -r --argjson s "$score" '
    .task_complexity.tiers
    | map(select(.min_score <= $s and .max_score >= $s))
    | .[0].multiplier // 1.0
  ' "$budgets_path" 2>/dev/null) || multiplier="1.0"

  # Get base role budget (chars)
  local base_budget
  base_budget=$(jq -r --arg r "$role" '.budgets[$r].max_chars // 0' "$budgets_path" 2>/dev/null) || base_budget=0
  [ "$base_budget" -eq 0 ] 2>/dev/null && return 1

  # Compute task budget (integer arithmetic via awk for float multiply)
  local task_budget
  task_budget=$(awk "BEGIN {printf \"%.0f\", $base_budget * $multiplier}") || return 1

  echo "$task_budget"
  return 0
}

# Load budget: per-task from contract, or per-role fallback
MAX_CHARS=0
BUDGET_SOURCE="role"
if [ -n "$CONTRACT_PATH" ] && [ -f "$CONTRACT_PATH" ] && [ -f "$BUDGETS_PATH" ]; then
  TASK_BUDGET=$(compute_task_budget "$CONTRACT_PATH" "$ROLE" "$BUDGETS_PATH" 2>/dev/null) || TASK_BUDGET=""
  if [ -n "$TASK_BUDGET" ] && [ "$TASK_BUDGET" -gt 0 ] 2>/dev/null; then
    MAX_CHARS="$TASK_BUDGET"
    BUDGET_SOURCE="task"
  fi
fi

# Fallback to per-role budget
if [ "$MAX_CHARS" -eq 0 ] && [ -f "$BUDGETS_PATH" ]; then
  MAX_CHARS=$(jq -r --arg r "$ROLE" '.budgets[$r].max_chars // 0' "$BUDGETS_PATH" 2>/dev/null || echo "0")
fi

# No budget defined — pass through
if [ "$MAX_CHARS" -eq 0 ] || [ "$MAX_CHARS" = "0" ]; then
  echo "$CONTENT"
  exit 0
fi

# Count characters
CHAR_COUNT=${#CONTENT}

if [ "$CHAR_COUNT" -le "$MAX_CHARS" ]; then
  # Within budget
  echo "$CONTENT"
  exit 0
fi

# Truncate using head strategy (preserve goal/criteria at the top)
STRATEGY=$(jq -r '.truncation_strategy // "head"' "$BUDGETS_PATH" 2>/dev/null || echo "head")
OVERAGE=$((CHAR_COUNT - MAX_CHARS))

case "$STRATEGY" in
  head)
    # Keep first MAX_CHARS characters (preserves goal/criteria)
    printf '%s' "$CONTENT" | head -c "$MAX_CHARS"
    echo
    ;;
  tail)
    # Keep last MAX_CHARS characters
    printf '%s' "$CONTENT" | tail -c "$MAX_CHARS"
    echo
    ;;
  *)
    printf '%s' "$CONTENT" | head -c "$MAX_CHARS"
    echo
    ;;
esac

# Log overage to metrics (v3_metrics graduated)
if [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
  bash "${SCRIPT_DIR}/collect-metrics.sh" token_overage 0 \
    "role=${ROLE}" "chars_total=${CHAR_COUNT}" "chars_max=${MAX_CHARS}" \
    "chars_truncated=${OVERAGE}" "budget_source=${BUDGET_SOURCE}" 2>/dev/null || true
fi

# Output truncation notice to stderr
echo "[token-budget] ${ROLE}: truncated ${OVERAGE} chars (${CHAR_COUNT} -> ${MAX_CHARS})" >&2
