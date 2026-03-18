#!/usr/bin/env bash
set -u

# token-baseline.sh [measure|compare|report] [--phase=N] [--save]
# Computes per-phase token usage from event log data and produces comparison reports.
# Reads from event-log.jsonl and run-metrics.jsonl, stores baselines in .baselines/.
# Exit 0 always — baseline measurement must never block execution.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
EVENTS_FILE="${PLANNING_DIR}/.events/event-log.jsonl"
METRICS_FILE="${PLANNING_DIR}/.metrics/run-metrics.jsonl"
BASELINES_DIR="${PLANNING_DIR}/.baselines"
BASELINE_FILE="${BASELINES_DIR}/token-baseline.json"
BUDGETS_PATH="${SCRIPT_DIR}/../config/token-budgets.json"

# Parse arguments
ACTION="measure"
PHASE_FILTER=""
SAVE_BASELINE=false

for arg in "$@"; do
  case "$arg" in
    measure|compare|report)
      ACTION="$arg"
      ;;
    --phase=*)
      PHASE_FILTER="${arg#--phase=}"
      ;;
    --save)
      SAVE_BASELINE=true
      ;;
  esac
done

# --- Data reading functions ---

count_overages() {
  local phase_filter="${1:-}"
  if [ ! -f "$METRICS_FILE" ]; then
    echo "0"
    return
  fi
  if [ -n "$phase_filter" ]; then
    jq -s "[.[] | select(.event == \"token_overage\") | select(.phase == ${phase_filter})] | length" "$METRICS_FILE" 2>/dev/null || echo "0"
  else
    jq -s '[.[] | select(.event == "token_overage")] | length' "$METRICS_FILE" 2>/dev/null || echo "0"
  fi
}

sum_truncated_chars() {
  local phase_filter="${1:-}"
  if [ ! -f "$METRICS_FILE" ]; then
    echo "0"
    return
  fi
  # Support both old (lines_truncated) and new (chars_truncated) field names
  if [ -n "$phase_filter" ]; then
    jq -s "[.[] | select(.event == \"token_overage\") | select(.phase == ${phase_filter}) | (.data.chars_truncated // .data.lines_truncated // \"0\") | tonumber] | add // 0" "$METRICS_FILE" 2>/dev/null || echo "0"
  else
    jq -s '[.[] | select(.event == "token_overage") | (.data.chars_truncated // .data.lines_truncated // "0") | tonumber] | add // 0' "$METRICS_FILE" 2>/dev/null || echo "0"
  fi
}

count_tasks() {
  local phase_filter="${1:-}"
  if [ ! -f "$EVENTS_FILE" ]; then
    echo "0"
    return
  fi
  if [ -n "$phase_filter" ]; then
    jq -s "[.[] | select(.event == \"task_started\") | select(.phase == ${phase_filter})] | length" "$EVENTS_FILE" 2>/dev/null || echo "0"
  else
    jq -s '[.[] | select(.event == "task_started")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0"
  fi
}

count_escalations_legacy() {
  local phase_filter="${1:-}"
  if [ ! -f "$EVENTS_FILE" ]; then
    echo "0"
    return
  fi
  if [ -n "$phase_filter" ]; then
    jq -s "[.[] | select(.event == \"token_cap_escalated\") | select(.phase == ${phase_filter})] | length" "$EVENTS_FILE" 2>/dev/null || echo "0"
  else
    jq -s '[.[] | select(.event == "token_cap_escalated")] | length' "$EVENTS_FILE" 2>/dev/null || echo "0"
  fi
}

get_phases() {
  local phases=""
  if [ -f "$EVENTS_FILE" ]; then
    phases=$(jq -s '[.[].phase] | unique | sort | .[]' "$EVENTS_FILE" 2>/dev/null || echo "")
  fi
  if [ -f "$METRICS_FILE" ]; then
    local metric_phases
    metric_phases=$(jq -s '[.[].phase] | unique | sort | .[]' "$METRICS_FILE" 2>/dev/null || echo "")
    if [ -n "$metric_phases" ]; then
      if [ -n "$phases" ]; then
        phases=$(printf '%s\n%s' "$phases" "$metric_phases" | sort -n | uniq)
      else
        phases="$metric_phases"
      fi
    fi
  fi
  echo "$phases"
}

# --- Helper: delta direction ---
get_delta_direction() {
  local d="$1"
  if [ "$d" -gt 0 ] 2>/dev/null; then echo "worse"
  elif [ "$d" -lt 0 ] 2>/dev/null; then echo "better"
  else echo "same"
  fi
}

# --- Prerequisites check ---
if [ ! -f "$EVENTS_FILE" ] && [ ! -f "$METRICS_FILE" ]; then
  echo "No event data found yet."
  exit 0
fi

# --- Measure function (reusable) ---
build_measurement() {
  local phase_filter="${1:-}"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

  local phases_json="{}"
  local total_overages=0
  local total_truncated=0
  local total_tasks=0
  local total_escalations=0

  local phase_list
  if [ -n "$phase_filter" ]; then
    phase_list="$phase_filter"
  else
    phase_list=$(get_phases)
  fi

  if [ -n "$phase_list" ]; then
    for phase in $phase_list; do
      local p_overages p_truncated p_tasks p_escalations p_opt
      p_overages=$(count_overages "$phase")
      p_truncated=$(sum_truncated_chars "$phase")
      p_tasks=$(count_tasks "$phase")
      p_escalations=$(count_escalations_legacy "$phase")

      if [ "$p_tasks" -gt 0 ] 2>/dev/null; then
        p_opt=$(awk "BEGIN {printf \"%.3f\", ${p_overages} / ${p_tasks}}")
      else
        p_opt="0"
      fi

      phases_json=$(echo "$phases_json" | jq --argjson p "$phase" \
        --argjson ov "$p_overages" --argjson tr "$p_truncated" \
        --argjson ta "$p_tasks" --argjson es "$p_escalations" \
        --arg opt "$p_opt" \
        '. + {($p | tostring): {overages: $ov, truncated_chars: $tr, tasks: $ta, escalations_legacy: $es, overages_per_task: ($opt | tonumber)}}' 2>/dev/null) || true

      total_overages=$((total_overages + p_overages))
      total_truncated=$((total_truncated + p_truncated))
      total_tasks=$((total_tasks + p_tasks))
      total_escalations=$((total_escalations + p_escalations))
    done
  fi

  local total_opt="0"
  if [ "$total_tasks" -gt 0 ] 2>/dev/null; then
    total_opt=$(awk "BEGIN {printf \"%.3f\", ${total_overages} / ${total_tasks}}")
  fi

  # Budget utilization
  local budget_json="{}"
  if [ -f "$BUDGETS_PATH" ] && [ -f "$METRICS_FILE" ]; then
    local roles
    roles=$(jq -r '.budgets | keys[]' "$BUDGETS_PATH" 2>/dev/null || echo "")
    for role in $roles; do
      local r_total r_max r_pct
      r_total=$(jq -s --arg r "$role" '[.[] | select(.event == "token_overage") | select(.data.role == $r) | (.data.chars_total // .data.lines_total // "0") | tonumber] | add // 0' "$METRICS_FILE" 2>/dev/null || echo "0")
      r_max=$(jq -s --arg r "$role" '[.[] | select(.event == "token_overage") | select(.data.role == $r) | (.data.chars_max // .data.lines_max // "0") | tonumber] | add // 0' "$METRICS_FILE" 2>/dev/null || echo "0")
      if [ "$r_max" -gt 0 ] 2>/dev/null; then
        r_pct=$(awk "BEGIN {printf \"%.0f\", ${r_total} * 100 / ${r_max}}")
      else
        r_pct="0"
      fi
      budget_json=$(echo "$budget_json" | jq --arg r "$role" \
        --argjson t "$r_total" --argjson m "$r_max" --argjson p "$r_pct" \
        '. + {($r): {total_chars: $t, max_chars: $m, utilization_pct: $p}}' 2>/dev/null) || true
    done
  fi

  jq -n \
    --arg ts "$ts" \
    --argjson phases "$phases_json" \
    --argjson ov "$total_overages" \
    --argjson tr "$total_truncated" \
    --argjson ta "$total_tasks" \
    --argjson es "$total_escalations" \
    --arg opt "$total_opt" \
    --argjson budget "$budget_json" \
    '{
      timestamp: $ts,
      phases: $phases,
      totals: {overages: $ov, truncated_chars: $tr, tasks: $ta, escalations_legacy: $es, overages_per_task: ($opt | tonumber)},
      budget_utilization: $budget
    }' 2>/dev/null || echo "{}"
}

# --- Compare function ---
build_comparison() {
  if [ ! -f "$BASELINE_FILE" ]; then
    echo "No baseline found. Run with --save first."
    return
  fi

  local baseline current
  baseline=$(cat "$BASELINE_FILE" 2>/dev/null)
  current=$(build_measurement "$PHASE_FILTER")

  local b_ts b_ov b_tr b_es b_opt
  b_ts=$(echo "$baseline" | jq -r '.timestamp' 2>/dev/null || echo "unknown")
  b_ov=$(echo "$baseline" | jq -r '.totals.overages // 0' 2>/dev/null || echo "0")
  b_tr=$(echo "$baseline" | jq -r '.totals.truncated_chars // .totals.truncated_lines // 0' 2>/dev/null || echo "0")
  b_es=$(echo "$baseline" | jq -r '.totals.escalations_legacy // .totals.escalations // 0' 2>/dev/null || echo "0")
  b_opt=$(echo "$baseline" | jq -r '.totals.overages_per_task // 0' 2>/dev/null || echo "0")

  local c_ts c_ov c_tr c_es c_opt
  c_ts=$(echo "$current" | jq -r '.timestamp' 2>/dev/null || echo "unknown")
  c_ov=$(echo "$current" | jq -r '.totals.overages // 0' 2>/dev/null || echo "0")
  c_tr=$(echo "$current" | jq -r '.totals.truncated_chars // .totals.truncated_lines // 0' 2>/dev/null || echo "0")
  c_es=$(echo "$current" | jq -r '.totals.escalations_legacy // .totals.escalations // 0' 2>/dev/null || echo "0")
  c_opt=$(echo "$current" | jq -r '.totals.overages_per_task // 0' 2>/dev/null || echo "0")

  local d_ov=$((c_ov - b_ov))
  local d_tr=$((c_tr - b_tr))
  local d_es=$((c_es - b_es))
  local d_opt
  d_opt=$(awk "BEGIN {printf \"%.3f\", ${c_opt} - ${b_opt}}")

  local dir_ov dir_tr dir_es dir_opt
  dir_ov=$(get_delta_direction "$d_ov")
  dir_tr=$(get_delta_direction "$d_tr")
  dir_es=$(get_delta_direction "$d_es")
  # For float delta direction
  local d_opt_int
  d_opt_int=$(awk "BEGIN {d = ${c_opt} - ${b_opt}; if (d > 0.0005) print 1; else if (d < -0.0005) print -1; else print 0}")
  dir_opt=$(get_delta_direction "$d_opt_int")

  # Detect phase changes (new/removed phases)
  local phase_changes="{}"
  local baseline_phases current_phases
  baseline_phases=$(echo "$baseline" | jq -r '.phases | keys[]' 2>/dev/null || echo "")
  current_phases=$(echo "$current" | jq -r '.phases | keys[]' 2>/dev/null || echo "")

  for bp in $baseline_phases; do
    if ! echo "$current_phases" | grep -qw "$bp"; then
      phase_changes=$(echo "$phase_changes" | jq --arg p "$bp" '. + {($p): "removed"}' 2>/dev/null) || true
    fi
  done
  for cp in $current_phases; do
    if ! echo "$baseline_phases" | grep -qw "$cp"; then
      phase_changes=$(echo "$phase_changes" | jq --arg p "$cp" '. + {($p): "new"}' 2>/dev/null) || true
    fi
  done

  jq -n \
    --arg b_ts "$b_ts" \
    --arg c_ts "$c_ts" \
    --argjson b_ov "$b_ov" --argjson c_ov "$c_ov" --argjson d_ov "$d_ov" --arg dir_ov "$dir_ov" \
    --argjson b_tr "$b_tr" --argjson c_tr "$c_tr" --argjson d_tr "$d_tr" --arg dir_tr "$dir_tr" \
    --argjson b_es "$b_es" --argjson c_es "$c_es" --argjson d_es "$d_es" --arg dir_es "$dir_es" \
    --arg b_opt "$b_opt" --arg c_opt "$c_opt" --arg d_opt "$d_opt" --arg dir_opt "$dir_opt" \
    --argjson pc "$phase_changes" \
    '{
      baseline_timestamp: $b_ts,
      current_timestamp: $c_ts,
      deltas: {
        overages: {baseline: $b_ov, current: $c_ov, delta: $d_ov, direction: $dir_ov},
        truncated_chars: {baseline: $b_tr, current: $c_tr, delta: $d_tr, direction: $dir_tr},
        escalations_legacy: {baseline: $b_es, current: $c_es, delta: $d_es, direction: $dir_es},
        overages_per_task: {baseline: ($b_opt | tonumber), current: ($c_opt | tonumber), delta: ($d_opt | tonumber), direction: $dir_opt}
      },
      phase_changes: $pc
    }' 2>/dev/null || echo "{}"
}

# --- Report function ---
build_report() {
  local measurement
  measurement=$(build_measurement "$PHASE_FILTER")

  local ts
  ts=$(echo "$measurement" | jq -r '.timestamp' 2>/dev/null || echo "unknown")

  echo "# Token Usage Baseline Report"
  echo ""
  echo "Generated: ${ts}"
  if [ -n "$PHASE_FILTER" ]; then
    echo "Phase filter: ${PHASE_FILTER}"
  fi
  echo ""

  # Per-Phase Summary
  echo "## Per-Phase Summary"
  echo "| Phase | Overages | Chars Truncated | Tasks | Overages/Task |"
  echo "|-------|----------|-----------------|-------|---------------|"

  local phase_keys
  phase_keys=$(echo "$measurement" | jq -r '.phases | keys[] | tonumber' 2>/dev/null | sort -n || echo "")
  local t_ov t_tr t_ta t_opt
  t_ov=$(echo "$measurement" | jq -r '.totals.overages // 0' 2>/dev/null)
  t_tr=$(echo "$measurement" | jq -r '.totals.truncated_chars // .totals.truncated_lines // 0' 2>/dev/null)
  t_ta=$(echo "$measurement" | jq -r '.totals.tasks // 0' 2>/dev/null)
  t_opt=$(echo "$measurement" | jq -r '.totals.overages_per_task // 0' 2>/dev/null)

  for pk in $phase_keys; do
    local p_ov p_tr p_ta p_opt
    p_ov=$(echo "$measurement" | jq -r --arg p "$pk" '.phases[$p].overages // 0' 2>/dev/null)
    p_tr=$(echo "$measurement" | jq -r --arg p "$pk" '.phases[$p].truncated_chars // .phases[$p].truncated_lines // 0' 2>/dev/null)
    p_ta=$(echo "$measurement" | jq -r --arg p "$pk" '.phases[$p].tasks // 0' 2>/dev/null)
    p_opt=$(echo "$measurement" | jq -r --arg p "$pk" '.phases[$p].overages_per_task // 0' 2>/dev/null)
    printf "| %s | %s | %s | %s | %.2f |\n" "$pk" "$p_ov" "$p_tr" "$p_ta" "$p_opt"
  done

  printf "| **Total** | **%s** | **%s** | **%s** | **%.2f** |\n" "$t_ov" "$t_tr" "$t_ta" "$t_opt"
  echo ""

  # Budget Utilization
  echo "## Budget Utilization"
  echo "| Role | Total Chars | Budget Max | Utilization |"
  echo "|------|-------------|-----------|-------------|"

  local budget_roles has_budget_data=false
  budget_roles=$(echo "$measurement" | jq -r '.budget_utilization | keys[]' 2>/dev/null || echo "")
  for role in $budget_roles; do
    local r_t r_m r_p
    r_t=$(echo "$measurement" | jq -r --arg r "$role" '.budget_utilization[$r].total_chars // .budget_utilization[$r].total_lines // 0' 2>/dev/null)
    r_m=$(echo "$measurement" | jq -r --arg r "$role" '.budget_utilization[$r].max_chars // .budget_utilization[$r].max_lines // 0' 2>/dev/null)
    r_p=$(echo "$measurement" | jq -r --arg r "$role" '.budget_utilization[$r].utilization_pct // 0' 2>/dev/null)
    # Only show roles with actual usage data
    if [ "$r_t" -gt 0 ] 2>/dev/null || [ "$r_m" -gt 0 ] 2>/dev/null; then
      echo "| ${role} | ${r_t} | ${r_m} | ${r_p}% |"
      has_budget_data=true
    fi
  done
  if [ "$has_budget_data" = "false" ]; then
    echo "| (no overage data) | - | - | - |"
  fi
  echo ""

  # Comparison section
  if [ -f "$BASELINE_FILE" ]; then
    echo "## Comparison with Baseline"

    local baseline
    baseline=$(cat "$BASELINE_FILE" 2>/dev/null)
    local b_ts
    b_ts=$(echo "$baseline" | jq -r '.timestamp' 2>/dev/null || echo "unknown")
    echo "Baseline from: ${b_ts}"
    echo ""
    echo "| Metric | Baseline | Current | Delta | Direction |"
    echo "|--------|----------|---------|-------|-----------|"

    local b_ov b_tr
    b_ov=$(echo "$baseline" | jq -r '.totals.overages // 0' 2>/dev/null)
    b_tr=$(echo "$baseline" | jq -r '.totals.truncated_chars // .totals.truncated_lines // 0' 2>/dev/null)

    local d_ov=$((t_ov - b_ov))
    local d_tr=$((t_tr - b_tr))

    local sign_ov sign_tr dir_ov dir_tr
    if [ "$d_ov" -gt 0 ] 2>/dev/null; then sign_ov="+${d_ov}"; dir_ov="worse"
    elif [ "$d_ov" -lt 0 ] 2>/dev/null; then sign_ov="${d_ov}"; dir_ov="better"
    else sign_ov="0"; dir_ov="same"; fi

    if [ "$d_tr" -gt 0 ] 2>/dev/null; then sign_tr="+${d_tr}"; dir_tr="worse"
    elif [ "$d_tr" -lt 0 ] 2>/dev/null; then sign_tr="${d_tr}"; dir_tr="better"
    else sign_tr="0"; dir_tr="same"; fi

    echo "| Overages | ${b_ov} | ${t_ov} | ${sign_ov} | ${dir_ov} |"
    echo "| Truncated Chars | ${b_tr} | ${t_tr} | ${sign_tr} | ${dir_tr} |"
  else
    echo "## Comparison with Baseline"
    echo ""
    echo "No baseline available. Run \`token-baseline.sh measure --save\` to create a baseline for comparison."
  fi
  echo ""
}

# --- Action dispatch ---
case "$ACTION" in
  measure)
    RESULT=$(build_measurement "$PHASE_FILTER")
    if [ "$SAVE_BASELINE" = "true" ]; then
      mkdir -p "$BASELINES_DIR" 2>/dev/null || true
      echo "$RESULT" > "$BASELINE_FILE" 2>/dev/null || true
    fi
    echo "$RESULT"
    ;;
  compare)
    build_comparison
    ;;
  report)
    build_report
    ;;
esac

exit 0
