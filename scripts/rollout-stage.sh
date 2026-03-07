#!/usr/bin/env bash
set -u

# rollout-stage.sh [check|advance|status] [--stage=N] [--dry-run]
# Manages optional flag rollout through 3 stages based on completed phase count.
# Stage 1 (observability): metrics -- threshold 0
# Stage 2 (optimization): (graduated, no rollout-managed flags remain) -- threshold 2
# Stage 3 (full): validation_gates, smart_routing, snapshot_resume, event_recovery, monorepo_routing -- threshold 5
# Exit 0 always -- rollout must never block execution.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLANNING_DIR=".vbw-planning"
CONFIG_PATH="${PLANNING_DIR}/config.json"
EVENTS_FILE="${PLANNING_DIR}/.events/event-log.jsonl"
STAGES_PATH="${SCRIPT_DIR}/../config/rollout-stages.json"
DEFAULTS_PATH="${SCRIPT_DIR}/../config/defaults.json"

legacy_flag_name() {
  case "$1" in
    token_budgets) echo "v2_token_budgets" ;;
    two_phase_completion) echo "v2_two_phase_completion" ;;
    metrics) echo "v3_metrics" ;;
    smart_routing) echo "v3_smart_routing" ;;
    validation_gates) echo "v3_validation_gates" ;;
    snapshot_resume) echo "v3_snapshot_resume" ;;
    lease_locks) echo "v3_lease_locks" ;;
    event_recovery) echo "v3_event_recovery" ;;
    monorepo_routing) echo "v3_monorepo_routing" ;;
    *) echo "" ;;
  esac
}

default_flag_value() {
  local flag="$1"
  if [ -f "$DEFAULTS_PATH" ]; then
    jq -r --arg f "$flag" 'if .[$f] == null then "false" else (.[$f] | tostring) end' "$DEFAULTS_PATH" 2>/dev/null || echo "false"
  else
    echo "false"
  fi
}

resolve_flag_value() {
  local flag="$1"
  local legacy_flag
  local default_val

  legacy_flag=$(legacy_flag_name "$flag")
  default_val=$(default_flag_value "$flag")

  jq -r --arg n "$flag" --arg o "$legacy_flag" --arg d "$default_val" '
    if .[$n] != null then .[$n]
    elif ($o != "" and .[$o] != null) then .[$o]
    elif $d == "true" then true
    else false
    end
  ' "$CONFIG_PATH" 2>/dev/null || echo "$default_val"
}

# --- Argument parsing ---
ACTION="check"
FORCE_STAGE=""
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    check|advance|status)
      ACTION="$arg"
      ;;
    --stage=*)
      FORCE_STAGE="${arg#--stage=}"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --help|-h)
      echo "Usage: rollout-stage.sh [check|advance|status] [--stage=N] [--dry-run]"
      echo ""
      echo "Actions:"
      echo "  check    Report current stage without modifying anything (default)"
      echo "  advance  Enable flags for the next eligible stage"
      echo "  status   Show all flags and their current values"
      echo ""
      echo "Options:"
      echo "  --stage=N   Force a specific stage (1, 2, or 3)"
      echo "  --dry-run   Show what would change without writing"
      exit 0
      ;;
  esac
done

# --- Prerequisites check ---
if [ ! -f "$CONFIG_PATH" ]; then
  echo '{"error":"config.json not found","action":"'"$ACTION"'"}' 2>/dev/null || true
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo '{"error":"jq not found","action":"'"$ACTION"'"}' 2>/dev/null || true
  exit 0
fi

if [ ! -f "$STAGES_PATH" ]; then
  echo '{"error":"rollout-stages.json not found","action":"'"$ACTION"'"}' 2>/dev/null || true
  exit 0
fi

# --- Count completed phases ---
COMPLETED_PHASES=0
REQUIRE_CLEAN=$(jq -r 'if .advancement.require_clean_phases == null then true else .advancement.require_clean_phases end' "$STAGES_PATH" 2>/dev/null || echo "true")
COUNT_EVENT=$(jq -r '.advancement.count_event // "phase_end"' "$STAGES_PATH" 2>/dev/null || echo "phase_end")

if [ -f "$EVENTS_FILE" ]; then
  if [ "$REQUIRE_CLEAN" = "true" ]; then
    COMPLETED_PHASES=$(jq -s "[.[] | select(.event == \"${COUNT_EVENT}\") | select(.data.error == null)] | length" "$EVENTS_FILE" 2>/dev/null || echo "0")
  else
    COMPLETED_PHASES=$(jq -s "[.[] | select(.event == \"${COUNT_EVENT}\")] | length" "$EVENTS_FILE" 2>/dev/null || echo "0")
  fi
fi

# --- Determine current stage ---
CURRENT_STAGE=0
CURRENT_LABEL=""
NEXT_STAGE=""
NEXT_THRESHOLD=""
ELIGIBLE_STAGES="[]"

STAGE_COUNT=$(jq '.stages | length' "$STAGES_PATH" 2>/dev/null || echo "0")

ELIGIBLE_LIST=""
for i in $(seq 0 $((STAGE_COUNT - 1))); do
  STAGE_NUM=$(jq -r ".stages[$i].stage" "$STAGES_PATH" 2>/dev/null || echo "0")
  THRESHOLD=$(jq -r ".stages[$i].phases_required" "$STAGES_PATH" 2>/dev/null || echo "999")
  LABEL=$(jq -r ".stages[$i].label" "$STAGES_PATH" 2>/dev/null || echo "")

  if [ "$COMPLETED_PHASES" -ge "$THRESHOLD" ]; then
    CURRENT_STAGE=$STAGE_NUM
    CURRENT_LABEL="$LABEL"
    if [ -n "$ELIGIBLE_LIST" ]; then
      ELIGIBLE_LIST="${ELIGIBLE_LIST},${STAGE_NUM}"
    else
      ELIGIBLE_LIST="${STAGE_NUM}"
    fi
  else
    if [ -z "$NEXT_STAGE" ]; then
      NEXT_STAGE=$STAGE_NUM
      NEXT_THRESHOLD=$THRESHOLD
    fi
  fi
done

ELIGIBLE_STAGES="[${ELIGIBLE_LIST}]"

# --- Action: check ---
if [ "$ACTION" = "check" ]; then
  NEXT_JSON="null"
  [ -n "$NEXT_STAGE" ] && NEXT_JSON=$NEXT_STAGE
  jq -n \
    --argjson current "$CURRENT_STAGE" \
    --argjson phases "$COMPLETED_PHASES" \
    --argjson eligible "$ELIGIBLE_STAGES" \
    --argjson next "$NEXT_JSON" \
    '{current_stage: $current, completed_phases: $phases, eligible_stages: $eligible, next_stage: $next}' 2>/dev/null \
    || echo "{\"current_stage\":${CURRENT_STAGE},\"completed_phases\":${COMPLETED_PHASES}}"
  exit 0
fi

# --- Action: advance ---
if [ "$ACTION" = "advance" ]; then
  TARGET_STAGE=$CURRENT_STAGE
  if [ -n "$FORCE_STAGE" ]; then
    TARGET_STAGE=$FORCE_STAGE
  fi

  if [ "$TARGET_STAGE" -eq 0 ]; then
    TARGET_STAGE=1
  fi

  # Collect flags for target stage and all prior stages
  ALL_FLAGS="[]"
  for i in $(seq 0 $((STAGE_COUNT - 1))); do
    STAGE_NUM=$(jq -r ".stages[$i].stage" "$STAGES_PATH" 2>/dev/null || echo "0")
    if [ "$STAGE_NUM" -le "$TARGET_STAGE" ]; then
      STAGE_FLAGS=$(jq ".stages[$i].flags" "$STAGES_PATH" 2>/dev/null || echo "[]")
      ALL_FLAGS=$(echo "$ALL_FLAGS" | jq --argjson sf "$STAGE_FLAGS" '. + $sf' 2>/dev/null || echo "$ALL_FLAGS")
    fi
  done

  # Check current config and build change list
  FLAGS_TO_ENABLE="[]"
  FLAGS_ALREADY="[]"
  FLAG_COUNT=$(echo "$ALL_FLAGS" | jq 'length' 2>/dev/null || echo "0")

  for i in $(seq 0 $((FLAG_COUNT - 1))); do
    FLAG=$(echo "$ALL_FLAGS" | jq -r ".[$i]" 2>/dev/null || echo "")
    [ -z "$FLAG" ] && continue
    CURRENT_VAL=$(resolve_flag_value "$FLAG")
    if [ "$CURRENT_VAL" = "true" ]; then
      FLAGS_ALREADY=$(echo "$FLAGS_ALREADY" | jq --arg f "$FLAG" '. + [$f]' 2>/dev/null || echo "$FLAGS_ALREADY")
    else
      FLAGS_TO_ENABLE=$(echo "$FLAGS_TO_ENABLE" | jq --arg f "$FLAG" '. + [$f]' 2>/dev/null || echo "$FLAGS_TO_ENABLE")
    fi
  done

  # Dry-run mode
  if [ "$DRY_RUN" = "true" ]; then
    jq -n \
      --arg action "advance" \
      --argjson stage "$TARGET_STAGE" \
      --argjson flags_enabled "$FLAGS_TO_ENABLE" \
      --argjson flags_already "$FLAGS_ALREADY" \
      --argjson dry_run true \
      '{action: $action, stage: $stage, flags_enabled: $flags_enabled, flags_already_enabled: $flags_already, dry_run: $dry_run}' 2>/dev/null \
      || echo '{"action":"advance","dry_run":true}'
    exit 0
  fi

  # Apply changes
  ENABLE_COUNT=$(echo "$FLAGS_TO_ENABLE" | jq 'length' 2>/dev/null || echo "0")
  if [ "$ENABLE_COUNT" -gt 0 ]; then
    jq --argjson flags "$FLAGS_TO_ENABLE" '
      reduce $flags[] as $f (.; .[$f] = true)
    ' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
  fi

  jq -n \
    --arg action "advance" \
    --argjson stage "$TARGET_STAGE" \
    --argjson flags_enabled "$FLAGS_TO_ENABLE" \
    --argjson flags_already "$FLAGS_ALREADY" \
    --argjson dry_run false \
    '{action: $action, stage: $stage, flags_enabled: $flags_enabled, flags_already_enabled: $flags_already, dry_run: $dry_run}' 2>/dev/null \
    || echo '{"action":"advance","dry_run":false}'
  exit 0
fi

# --- Action: status ---
if [ "$ACTION" = "status" ]; then
  echo "# V3 Rollout Status"
  echo ""
  echo "Current stage: ${CURRENT_STAGE} (${CURRENT_LABEL})"
  echo "Completed phases: ${COMPLETED_PHASES}"
  if [ -n "$NEXT_STAGE" ]; then
    echo "Next stage: ${NEXT_STAGE} (requires ${NEXT_THRESHOLD} phases)"
  else
    echo "Next stage: none (all stages unlocked)"
  fi
  echo ""

  echo "## Flag Status"
  echo "| Flag | Stage | Enabled |"
  echo "|------|-------|---------|"

  # Build flag-to-stage mapping and print managed flags
  MANAGED_FLAGS="[]"
  for i in $(seq 0 $((STAGE_COUNT - 1))); do
    STAGE_NUM=$(jq -r ".stages[$i].stage" "$STAGES_PATH" 2>/dev/null || echo "0")
    LABEL=$(jq -r ".stages[$i].label" "$STAGES_PATH" 2>/dev/null || echo "")
    STAGE_FLAGS=$(jq -r ".stages[$i].flags[]" "$STAGES_PATH" 2>/dev/null || echo "")
    for FLAG in $STAGE_FLAGS; do
      VALUE=$(resolve_flag_value "$FLAG")
      echo "| ${FLAG} | ${STAGE_NUM} (${LABEL}) | ${VALUE} |"
      MANAGED_FLAGS=$(echo "$MANAGED_FLAGS" | jq --arg f "$FLAG" '. + [$f]' 2>/dev/null || echo "$MANAGED_FLAGS")
    done
  done

  # Find unmanaged v3_ flags
  ALL_V3_FLAGS=$(jq -r 'keys[] | select(startswith("v3_"))' "$CONFIG_PATH" 2>/dev/null || echo "")
  UNMANAGED=""
  for FLAG in $ALL_V3_FLAGS; do
    IS_MANAGED=$(echo "$MANAGED_FLAGS" | jq --arg f "$FLAG" 'any(. == $f)' 2>/dev/null || echo "false")
    if [ "$IS_MANAGED" = "false" ]; then
      VALUE=$(jq -r ".${FLAG} // false" "$CONFIG_PATH" 2>/dev/null || echo "false")
      if [ -z "$UNMANAGED" ]; then
        UNMANAGED="yes"
        echo ""
        echo "## Unmanaged Flags"
        echo "| Flag | Enabled |"
        echo "|------|---------|"
      fi
      echo "| ${FLAG} | ${VALUE} |"
    fi
  done

  exit 0
fi
