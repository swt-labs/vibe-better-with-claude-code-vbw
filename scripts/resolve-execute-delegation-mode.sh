#!/usr/bin/env bash
set -euo pipefail

# resolve-execute-delegation-mode.sh — dependency-aware Execute routing helper
#
# Usage:
#   resolve-execute-delegation-mode.sh --phase-dir <dir> [--config <path>] [--execution-state <path>] [--route-map <path>] [--segments]
#
# Computes whether the current Execute segment should use true team mode or
# serialized subagents. Missing route-map entries default to delegate. Route-map
# entries may explicitly set route=delegate|turbo|direct.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_DIR=""
CONFIG_PATH=".vbw-planning/config.json"
EXEC_STATE_PATH=".vbw-planning/.execution-state.json"
ROUTE_MAP_PATH=""
SEGMENTS_MODE=false

usage() {
  echo "usage: resolve-execute-delegation-mode.sh --phase-dir <dir> [--config <path>] [--execution-state <path>] [--route-map <path>] [--segments]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --phase-dir)
      PHASE_DIR="${2:-}"
      shift 2
      ;;
    --phase-dir=*)
      PHASE_DIR="${1#--phase-dir=}"
      shift
      ;;
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --config=*)
      CONFIG_PATH="${1#--config=}"
      shift
      ;;
    --execution-state)
      EXEC_STATE_PATH="${2:-}"
      shift 2
      ;;
    --execution-state=*)
      EXEC_STATE_PATH="${1#--execution-state=}"
      shift
      ;;
    --route-map)
      ROUTE_MAP_PATH="${2:-}"
      shift 2
      ;;
    --route-map=*)
      ROUTE_MAP_PATH="${1#--route-map=}"
      shift
      ;;
    --segments)
      SEGMENTS_MODE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

fail_json() {
  local reason="$1"
  local diagnostic="${2:-$1}"
  jq -cn \
    --arg reason "$reason" \
    --arg diagnostic "$diagnostic" \
    '{prefer_teams:null,effective_effort:null,remaining_count:0,delegate_count:0,excluded_plan_ids:[],turbo_plan_ids:[],direct_plan_ids:[],max_parallel_width:0,requested_mode:"subagent",delegation_mode:"subagent",reason:$reason,diagnostic:$diagnostic}'
}

if [ -z "$PHASE_DIR" ]; then
  usage
  fail_json "missing_phase_dir" "--phase-dir is required"
  exit 2
fi
if [ ! -d "$PHASE_DIR" ]; then
  fail_json "missing_phase_dir" "phase dir does not exist: $PHASE_DIR"
  exit 2
fi
if [ ! -f "$EXEC_STATE_PATH" ]; then
  fail_json "missing_execution_state" "execution state does not exist: $EXEC_STATE_PATH"
  exit 2
fi
if ! jq empty "$EXEC_STATE_PATH" >/dev/null 2>&1; then
  fail_json "invalid_execution_state" "execution state is not valid JSON: $EXEC_STATE_PATH"
  exit 2
fi
if [ -n "$ROUTE_MAP_PATH" ]; then
  if [ ! -f "$ROUTE_MAP_PATH" ]; then
    fail_json "invalid_route_map" "route map does not exist: $ROUTE_MAP_PATH"
    exit 2
  fi
  if ! jq empty "$ROUTE_MAP_PATH" >/dev/null 2>&1; then
    fail_json "invalid_route_map" "route map is not valid JSON: $ROUTE_MAP_PATH"
    exit 2
  fi
fi

phase_dir_base=$(basename "${PHASE_DIR%/}")
phase_prefix=$(printf '%s' "$phase_dir_base" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
if [ -z "$phase_prefix" ]; then
  fail_json "invalid_phase_dir" "cannot extract numeric phase prefix from: $phase_dir_base"
  exit 2
fi
phase_num=$((10#$phase_prefix))
phase_id=$(printf '%02d' "$phase_num")

trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

strip_quotes() {
  local value
  value=$(trim_value "$1")
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  trim_value "$value"
}

pad_number() {
  local raw="$1"
  case "$raw" in
    ''|*[!0-9]*) printf '%s' "$raw" ;;
    *) printf '%02d' "$((10#$raw))" ;;
  esac
}

normalize_plan_ref() {
  local raw="$1"
  local value ph pl
  value=$(strip_quotes "$raw")
  value="${value%,}"
  value=$(strip_quotes "$value")
  value="${value#\[}"
  value="${value%\]}"
  value=$(strip_quotes "$value")
  [ -z "$value" ] && return 1
  case "$value" in
    null|NULL|None|none|[])
      return 1
      ;;
  esac
  case "$value" in
    *-*)
      ph="${value%%-*}"
      pl="${value#*-}"
      if [ -n "$ph" ] && [ -n "$pl" ] && [[ "$ph" =~ ^[0-9]+$ ]] && [[ "$pl" =~ ^[0-9]+$ ]]; then
        printf '%s-%s\n' "$(pad_number "$ph")" "$(pad_number "$pl")"
      else
        printf '%s\n' "$value"
      fi
      ;;
    *)
      if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s-%s\n' "$phase_id" "$(pad_number "$value")"
      else
        printf '%s\n' "$value"
      fi
      ;;
  esac
}

normalize_status() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    complete|completed) printf 'complete\n' ;;
    partial) printf 'partial\n' ;;
    failed) printf 'failed\n' ;;
    running) printf 'running\n' ;;
    pending|"") printf 'pending\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

is_execute_satisfied_status() {
  case "$1" in
    complete|partial) return 0 ;;
    *) return 1 ;;
  esac
}

frontmatter_value() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    BEGIN { in_fm=0 }
    /^---[[:space:]]*$/ { if (in_fm == 0) { in_fm=1; next } else { exit } }
    in_fm && $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
      sub("^[[:space:]]*" key ":[[:space:]]*", "")
      gsub(/^[\"'"'"']|[\"'"'"']$/, "")
      print
      exit
    }
  ' "$file" 2>/dev/null || true
}

extract_dep_lines() {
  local file="$1"
  awk '
    function trim(v) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); return v }
    function emit(v, n, i, parts) {
      v = trim(v)
      sub(/[[:space:]]+#.*$/, "", v)
      v = trim(v)
      if (v == "" || v == "[]") return
      if (v ~ /^\[/) {
        gsub(/^\[/, "", v); gsub(/\].*$/, "", v)
        n = split(v, parts, ",")
        for (i = 1; i <= n; i++) {
          item = trim(parts[i])
          if (item != "") print item
        }
        return
      }
      print v
    }
    BEGIN { in_front=0; in_dep=0 }
    /^---[[:space:]]*$/ { if (in_front == 0) { in_front=1; next } else { exit } }
    in_front && /^[[:space:]]*depends_on:[[:space:]]*/ {
      line=$0
      sub(/^[[:space:]]*depends_on:[[:space:]]*/, "", line)
      if (trim(line) != "") { emit(line); exit }
      in_dep=1
      next
    }
    in_front && in_dep && /^[[:space:]]*-[[:space:]]*/ {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      emit(line)
      next
    }
    in_front && in_dep && /^[^[:space:]]/ { exit }
  ' "$file" 2>/dev/null || true
}

resolve_plan_path() {
  local id="$1"
  local plan_part="$id"
  local candidate=""
  case "$id" in
    *-*) plan_part="${id#*-}" ;;
  esac

  for candidate in \
    "$PHASE_DIR/${phase_id}-${plan_part}-PLAN.md" \
    "$PHASE_DIR/${id}-PLAN.md" \
    "$PHASE_DIR/${plan_part}-PLAN.md"; do
    [ -f "$candidate" ] || continue
    local fm_phase fm_plan norm_fm_id
    fm_phase=$(frontmatter_value "$candidate" phase)
    fm_plan=$(frontmatter_value "$candidate" plan)
    if [ -n "$fm_phase" ] || [ -n "$fm_plan" ]; then
      fm_phase=${fm_phase:-$phase_id}
      fm_plan=${fm_plan:-$plan_part}
      norm_fm_id=$(normalize_plan_ref "$(pad_number "$fm_phase")-$(pad_number "$fm_plan")" 2>/dev/null || true)
      if [ -n "$norm_fm_id" ] && [ "$norm_fm_id" != "$id" ]; then
        printf 'frontmatter_mismatch:%s:declares:%s\n' "$(basename "$candidate")" "$norm_fm_id" >&2
        return 3
      fi
    fi
    printf '%s\n' "$candidate"
    return 0
  done

  return 1
}

json_has_key() {
  local json="$1"
  local key="$2"
  jq -e --arg key "$key" 'has($key)' <<< "$json" >/dev/null 2>&1
}

json_array_contains() {
  local json="$1"
  local value="$2"
  jq -e --arg value "$value" 'index($value) != null' <<< "$json" >/dev/null 2>&1
}

json_array_add() {
  local json="$1"
  local value="$2"
  jq -c --arg value "$value" '. + [$value]' <<< "$json"
}

json_object_add_plan() {
  local json="$1"
  local id="$2"
  local status="$3"
  local route="$4"
  local reason="$5"
  local path="$6"
  jq -c \
    --arg id "$id" \
    --arg status "$status" \
    --arg route "$route" \
    --arg reason "$reason" \
    --arg path "$path" \
    '. + {($id): {status:$status, route:$route, reason:$reason, path:$path, deps:[]}}' <<< "$json"
}

json_object_set_deps() {
  local json="$1"
  local id="$2"
  local deps_json="$3"
  jq -c --arg id "$id" --argjson deps "$deps_json" '.[$id].deps = $deps' <<< "$json"
}

read_prefer_teams_raw() {
  if [ -f "$CONFIG_PATH" ]; then
    jq -r '.prefer_teams // "auto"' "$CONFIG_PATH" 2>/dev/null || printf 'auto\n'
  else
    printf 'auto\n'
  fi
}

prefer_raw=$(read_prefer_teams_raw)
if [ -x "$SCRIPT_DIR/normalize-prefer-teams.sh" ] || [ -f "$SCRIPT_DIR/normalize-prefer-teams.sh" ]; then
  prefer_teams=$(bash "$SCRIPT_DIR/normalize-prefer-teams.sh" --value "$prefer_raw" 2>/dev/null || printf '%s\n' "$prefer_raw")
else
  case "${prefer_raw:-auto}" in
    ""|null|false|when_parallel) prefer_teams="auto" ;;
    true) prefer_teams="always" ;;
    always|auto|never) prefer_teams="$prefer_raw" ;;
    *) prefer_teams="$prefer_raw" ;;
  esac
fi

effective_effort=$(jq -r '.effort // empty' "$EXEC_STATE_PATH" 2>/dev/null || true)
if [ -z "$effective_effort" ] || [ "$effective_effort" = "null" ]; then
  if [ -f "$CONFIG_PATH" ]; then
    effective_effort=$(jq -r '.effort // "balanced"' "$CONFIG_PATH" 2>/dev/null || printf 'balanced\n')
  else
    effective_effort="balanced"
  fi
fi
phase_effort=$(jq -r '.phase_effort // empty' "$EXEC_STATE_PATH" 2>/dev/null || true)
[ -z "$phase_effort" ] || [ "$phase_effort" = "null" ] && phase_effort="$effective_effort"

plans_json="{}"
all_plan_ids="[]"
completed_satisfied_nodes="[]"
pending_delegate_nodes="[]"
excluded_turbo_nodes="[]"
excluded_direct_nodes="[]"
invalid_reason=""
invalid_detail=""

while IFS=$'\t' read -r raw_id raw_status; do
  [ -n "${raw_id:-}" ] || continue
  plan_id=$(normalize_plan_ref "$raw_id" 2>/dev/null || true)
  if [ -z "$plan_id" ]; then
    invalid_reason="invalid_dependency_graph"
    invalid_detail="invalid plan id in execution state: $raw_id"
    break
  fi
  if json_array_contains "$all_plan_ids" "$plan_id"; then
    invalid_reason="invalid_dependency_graph"
    invalid_detail="duplicate plan id in execution state: $plan_id"
    break
  fi

  status=$(normalize_status "$raw_status")
  route="delegate"
  route_reason="default_delegate"
  if [ "$effective_effort" = "turbo" ]; then
    route="turbo"
    route_reason="phase_effort_turbo"
  elif [ -n "$ROUTE_MAP_PATH" ]; then
    route=$(jq -r --arg id "$plan_id" --arg raw "$raw_id" '.plans[$id].route // .plans[$raw].route // "delegate"' "$ROUTE_MAP_PATH" 2>/dev/null || printf 'delegate\n')
    route_reason=$(jq -r --arg id "$plan_id" --arg raw "$raw_id" '.plans[$id].reason // .plans[$raw].reason // "route_map"' "$ROUTE_MAP_PATH" 2>/dev/null || printf 'route_map\n')
  fi
  case "$route" in
    delegate|turbo|direct) ;;
    *)
      invalid_reason="invalid_dependency_graph"
      invalid_detail="invalid route '$route' for plan $plan_id"
      break
      ;;
  esac

  plan_path=""
  resolve_err_file=$(mktemp "${TMPDIR:-/tmp}/vbw-resolve-plan.XXXXXX")
  if ! plan_path=$(resolve_plan_path "$plan_id" 2>"$resolve_err_file"); then
    _rp_err=$(cat "$resolve_err_file" 2>/dev/null || true)
    rm -f "$resolve_err_file" 2>/dev/null || true
    invalid_reason="invalid_dependency_graph"
    if [ -n "$_rp_err" ]; then
      invalid_detail="$_rp_err"
    else
      invalid_detail="plan file not found for $plan_id"
    fi
    break
  fi
  rm -f "$resolve_err_file" 2>/dev/null || true

  all_plan_ids=$(json_array_add "$all_plan_ids" "$plan_id")
  plans_json=$(json_object_add_plan "$plans_json" "$plan_id" "$status" "$route" "$route_reason" "$plan_path")

  if is_execute_satisfied_status "$status"; then
    completed_satisfied_nodes=$(json_array_add "$completed_satisfied_nodes" "$plan_id")
  else
    case "$route" in
      delegate) pending_delegate_nodes=$(json_array_add "$pending_delegate_nodes" "$plan_id") ;;
      turbo) excluded_turbo_nodes=$(json_array_add "$excluded_turbo_nodes" "$plan_id") ;;
      direct) excluded_direct_nodes=$(json_array_add "$excluded_direct_nodes" "$plan_id") ;;
    esac
  fi
done < <(jq -r '.plans[]? | [(.id // ""), (.status // "pending")] | @tsv' "$EXEC_STATE_PATH")

if [ -n "$invalid_reason" ]; then
  fail_json "$invalid_reason" "$invalid_detail"
  exit 2
fi

remaining_nodes=$(jq -cn --argjson a "$pending_delegate_nodes" --argjson b "$excluded_turbo_nodes" --argjson c "$excluded_direct_nodes" '$a + $b + $c')
remaining_count=$(jq -r 'length' <<< "$remaining_nodes")
delegate_count=$(jq -r 'length' <<< "$pending_delegate_nodes")

# Extract dependencies for every plan and validate references against satisfied or remaining known nodes.
for plan_id in $(jq -r 'keys[]' <<< "$plans_json"); do
  plan_path=$(jq -r --arg id "$plan_id" '.[$id].path' <<< "$plans_json")
  deps_json="[]"
  while IFS= read -r dep_raw; do
    dep_id=$(normalize_plan_ref "$dep_raw" 2>/dev/null || true)
    [ -n "$dep_id" ] || continue
    deps_json=$(json_array_add "$deps_json" "$dep_id")
  done < <(extract_dep_lines "$plan_path")
  plans_json=$(json_object_set_deps "$plans_json" "$plan_id" "$deps_json")

  for dep_id in $(jq -r '.[]' <<< "$deps_json"); do
    if json_array_contains "$completed_satisfied_nodes" "$dep_id" || json_array_contains "$remaining_nodes" "$dep_id"; then
      continue
    fi
    fail_json "invalid_dependency_graph" "unresolved dependency: $plan_id depends on $dep_id"
    exit 2
  done
done

# Simulate topological waves over all remaining nodes. Count only delegate nodes in each wave.
completed_for_sim="$completed_satisfied_nodes"
unresolved="$remaining_nodes"
max_parallel_width=0
waves_json="[]"

while [ "$(jq -r 'length' <<< "$unresolved")" -gt 0 ]; do
  runnable="[]"
  blocked="[]"
  for node in $(jq -r '.[]' <<< "$unresolved"); do
    deps=$(jq -c --arg id "$node" '.[$id].deps // []' <<< "$plans_json")
    deps_ok=true
    for dep in $(jq -r '.[]' <<< "$deps"); do
      if ! json_array_contains "$completed_for_sim" "$dep"; then
        deps_ok=false
        break
      fi
    done
    if [ "$deps_ok" = true ]; then
      runnable=$(json_array_add "$runnable" "$node")
    else
      blocked=$(json_array_add "$blocked" "$node")
    fi
  done

  runnable_count=$(jq -r 'length' <<< "$runnable")
  if [ "$runnable_count" -eq 0 ]; then
    fail_json "invalid_dependency_graph" "cyclic or blocked dependency graph: $(jq -c '.' <<< "$unresolved")"
    exit 2
  fi

  delegate_width=$(jq -r --argjson delegate "$pending_delegate_nodes" '[.[] as $node | select($delegate | index($node))] | length' <<< "$runnable")
  if [ "$delegate_width" -gt "$max_parallel_width" ]; then
    max_parallel_width="$delegate_width"
  fi
  waves_json=$(jq -c --argjson wave "$runnable" '. + [$wave]' <<< "$waves_json")
  completed_for_sim=$(jq -cn --argjson a "$completed_for_sim" --argjson b "$runnable" '$a + $b')
  unresolved="$blocked"
done

requested_mode="subagent"
delegation_mode="subagent"
reason="auto_serial_dependency_graph"

if [ "$remaining_count" -eq 0 ]; then
  requested_mode="subagent"
  delegation_mode="subagent"
  reason="no_remaining_plans"
elif [ "$delegate_count" -eq 0 ]; then
  if [ "$(jq -r 'length' <<< "$excluded_turbo_nodes")" -gt 0 ]; then
    requested_mode="turbo"
    delegation_mode="direct"
    reason="no_delegate_eligible_plans"
  elif [ "$(jq -r 'length' <<< "$excluded_direct_nodes")" -gt 0 ]; then
    requested_mode="direct"
    delegation_mode="direct"
    reason="no_delegate_eligible_plans"
  fi
elif [ "$effective_effort" = "turbo" ]; then
  requested_mode="turbo"
  delegation_mode="direct"
  reason="phase_effort_turbo"
else
  case "$prefer_teams" in
    always)
      requested_mode="team"
      delegation_mode="team"
      reason="prefer_teams_always"
      ;;
    auto)
      if [ "$max_parallel_width" -gt 1 ]; then
        requested_mode="team"
        delegation_mode="team"
        reason="parallel_delegate_width:$max_parallel_width"
      else
        requested_mode="subagent"
        delegation_mode="subagent"
        reason="auto_max_parallel_width:$max_parallel_width"
      fi
      ;;
    never)
      requested_mode="subagent"
      delegation_mode="subagent"
      reason="prefer_teams_never"
      ;;
    *)
      requested_mode="subagent"
      delegation_mode="subagent"
      reason="unknown_prefer_teams:$prefer_teams"
      ;;
  esac
fi

base_output=$(jq -cn \
  --arg prefer_teams "$prefer_teams" \
  --arg effective_effort "$effective_effort" \
  --arg phase_effort "$phase_effort" \
  --argjson remaining_count "$remaining_count" \
  --argjson delegate_count "$delegate_count" \
  --argjson completed_satisfied_nodes "$completed_satisfied_nodes" \
  --argjson pending_delegate_nodes "$pending_delegate_nodes" \
  --argjson excluded_turbo_nodes "$excluded_turbo_nodes" \
  --argjson excluded_direct_nodes "$excluded_direct_nodes" \
  --argjson max_parallel_width "$max_parallel_width" \
  --arg requested_mode "$requested_mode" \
  --arg delegation_mode "$delegation_mode" \
  --arg reason "$reason" \
  --argjson plans "$plans_json" \
  --argjson waves "$waves_json" \
  '{
    prefer_teams:$prefer_teams,
    effective_effort:$effective_effort,
    phase_effort:$phase_effort,
    remaining_count:$remaining_count,
    delegate_count:$delegate_count,
    completed_satisfied_nodes:$completed_satisfied_nodes,
    pending_delegate_nodes:$pending_delegate_nodes,
    excluded_turbo_nodes:$excluded_turbo_nodes,
    excluded_direct_nodes:$excluded_direct_nodes,
    excluded_plan_ids:([$excluded_turbo_nodes[] | {id: ., route:"turbo", reason:($plans[.].reason // "turbo")}] + [$excluded_direct_nodes[] | {id: ., route:"direct", reason:($plans[.].reason // "direct")}]),
    turbo_plan_ids:$excluded_turbo_nodes,
    direct_plan_ids:$excluded_direct_nodes,
    max_parallel_width:$max_parallel_width,
    requested_mode:$requested_mode,
    delegation_mode:$delegation_mode,
    reason:$reason,
    plans:$plans,
    dependency_waves:$waves
   }')

if [ "$SEGMENTS_MODE" != true ]; then
  printf '%s\n' "$base_output"
  exit 0
fi

segments_json="[]"
team_segment_index=0
for wave in $(jq -cr '.[]' <<< "$waves_json"); do
  # Direct and turbo plans are always serialized one plan at a time.
  for route in turbo direct; do
    for node in $(jq -r --arg route "$route" --argjson plans "$plans_json" '.[] | select($plans[.].route == $route)' <<< "$wave"); do
      seg_effort="$route"
      seg_delegation="direct"
      segments_json=$(jq -c \
        --arg route "$route" \
        --arg effort "$seg_effort" \
        --arg delegation_mode "$seg_delegation" \
        --arg id "$node" \
        '. + [{route:$route, plan_ids:[$id], effort:$effort, delegation_mode:$delegation_mode, prerequisite_merge_required:false, worktree_refresh_required:true}]' <<< "$segments_json")
    done
  done

  delegate_wave=$(jq -c --argjson plans "$plans_json" '[.[] | select($plans[.].route == "delegate")]' <<< "$wave")
  delegate_wave_count=$(jq -r 'length' <<< "$delegate_wave")
  if [ "$delegate_wave_count" -gt 0 ]; then
    seg_mode="subagent"
    seg_reason="segment_serial_delegate_width:$delegate_wave_count"
    case "$prefer_teams" in
      always)
        seg_mode="team"
        seg_reason="prefer_teams_always"
        ;;
      auto)
        if [ "$delegate_wave_count" -gt 1 ]; then
          seg_mode="team"
          seg_reason="parallel_delegate_width:$delegate_wave_count"
        else
          seg_mode="subagent"
          seg_reason="auto_max_parallel_width:$delegate_wave_count"
        fi
        ;;
      never)
        seg_mode="subagent"
        seg_reason="prefer_teams_never"
        ;;
      *)
        seg_mode="subagent"
        seg_reason="unknown_prefer_teams:$prefer_teams"
        ;;
    esac
    team_name=""
    if [ "$seg_mode" = "team" ]; then
      team_segment_index=$((team_segment_index + 1))
      team_name="vbw-phase-${phase_id}"
      if [ "$team_segment_index" -gt 1 ]; then
        team_name="vbw-phase-${phase_id}-segment-${team_segment_index}"
      fi
    fi
    segments_json=$(jq -c \
      --arg route "delegate" \
      --arg effort "$phase_effort" \
      --arg delegation_mode "$seg_mode" \
      --arg team_name "$team_name" \
      --arg reason "$seg_reason" \
      --argjson plan_ids "$delegate_wave" \
      '. + [{route:$route, plan_ids:$plan_ids, effort:$effort, delegation_mode:$delegation_mode, team_name:(if $team_name == "" then null else $team_name end), reason:$reason, prerequisite_merge_required:false, worktree_refresh_required:true}]' <<< "$segments_json")
  fi
done

jq -c --argjson segments "$segments_json" '. + {segments:$segments}' <<< "$base_output"
