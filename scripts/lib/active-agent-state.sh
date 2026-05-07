#!/usr/bin/env bash
# Shared active-agent state helpers.
#
# Function library only: callers must read hook stdin exactly once and pass the
# captured JSON string to these helpers. This file must never read stdin.

VBW_ACTIVE_AGENT_LEGACY_SOURCE_ID="__vbw_legacy_global"

vbw_active_agent_is_safe_session_id() {
  local sid="${1:-}"

  [ -n "$sid" ] || return 1
  [ "$sid" != "null" ] || return 1
  [ "$sid" != "unknown" ] || return 1
  [ "$sid" != "$VBW_ACTIVE_AGENT_LEGACY_SOURCE_ID" ] || return 1
  case "$sid" in .|..) return 1 ;; esac
  case "$sid" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-]*) return 1 ;;
  esac

  return 0
}

vbw_active_agent_session_id() {
  local input="${1:-}"
  local sid=""

  if [ -n "$input" ] && command -v jq >/dev/null 2>&1; then
    sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || sid=""
    if vbw_active_agent_is_safe_session_id "$sid"; then
      printf '%s\n' "$sid"
      return 0
    fi
  fi

  sid="${CLAUDE_SESSION_ID:-}"
  if vbw_active_agent_is_safe_session_id "$sid"; then
    printf '%s\n' "$sid"
    return 0
  fi

  return 1
}

_vbw_active_agent_legacy_source_id() {
  printf '%s\n' "$VBW_ACTIVE_AGENT_LEGACY_SOURCE_ID"
}

_vbw_active_agent_is_aggregate_source_id() {
  local source_id="${1:-}"

  [ -n "$source_id" ] || return 1
  if [ "$source_id" = "$VBW_ACTIVE_AGENT_LEGACY_SOURCE_ID" ]; then
    return 0
  fi
  vbw_active_agent_is_safe_session_id "$source_id"
}

vbw_active_agent_has_safe_session() {
  vbw_active_agent_session_id "${1:-}" >/dev/null 2>&1
}

vbw_active_agent_normalize_role() {
  local value="${1:-}"
  local lower

  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  lower="${lower#@}"
  lower="${lower#vbw:}"

  case "$lower" in
    vbw-lead|vbw-lead-[0-9]*|lead|lead-[0-9]*|team-lead|team-lead-[0-9]*) printf 'lead'; return 0 ;;
    vbw-dev|vbw-dev-[0-9]*|dev|dev-[0-9]*|team-dev|team-dev-[0-9]*) printf 'dev'; return 0 ;;
    vbw-qa|vbw-qa-[0-9]*|qa|qa-[0-9]*|team-qa|team-qa-[0-9]*) printf 'qa'; return 0 ;;
    vbw-scout|vbw-scout-[0-9]*|scout|scout-[0-9]*|team-scout|team-scout-[0-9]*) printf 'scout'; return 0 ;;
    vbw-debugger|vbw-debugger-[0-9]*|debugger|debugger-[0-9]*|team-debugger|team-debugger-[0-9]*) printf 'debugger'; return 0 ;;
    vbw-architect|vbw-architect-[0-9]*|architect|architect-[0-9]*|team-architect|team-architect-[0-9]*) printf 'architect'; return 0 ;;
    vbw-docs|vbw-docs-[0-9]*|docs|docs-[0-9]*|team-docs|team-docs-[0-9]*) printf 'docs'; return 0 ;;
  esac

  return 1
}

vbw_active_agent_session_dir() {
  local planning_dir="$1"
  local session_id="$2"

  printf '%s/.active-agents/%s\n' "$planning_dir" "$session_id"
}

_vbw_active_agent_state_dir() {
  local planning_dir="$1"
  local session_id="${2:-}"

  if [ -n "$session_id" ]; then
    vbw_active_agent_session_dir "$planning_dir" "$session_id"
  else
    printf '%s\n' "$planning_dir"
  fi
}

_vbw_active_agent_count_file() {
  local planning_dir="$1"
  local session_id="${2:-}"

  if [ -n "$session_id" ]; then
    printf '%s/active-agent-count\n' "$(_vbw_active_agent_state_dir "$planning_dir" "$session_id")"
  else
    printf '%s/.active-agent-count\n' "$planning_dir"
  fi
}

_vbw_active_agent_roles_file() {
  local planning_dir="$1"
  local session_id="${2:-}"

  if [ -n "$session_id" ]; then
    printf '%s/active-agent-roles\n' "$(_vbw_active_agent_state_dir "$planning_dir" "$session_id")"
  else
    printf '%s/.active-agent-roles\n' "$planning_dir"
  fi
}

_vbw_active_agent_role_pids_file() {
  local planning_dir="$1"
  local session_id="${2:-}"

  if [ -n "$session_id" ]; then
    printf '%s/active-agent-role-pids\n' "$(_vbw_active_agent_state_dir "$planning_dir" "$session_id")"
  else
    printf '%s/.active-agent-role-pids\n' "$planning_dir"
  fi
}

_vbw_active_agent_marker_file() {
  local planning_dir="$1"
  local session_id="${2:-}"

  if [ -n "$session_id" ]; then
    printf '%s/active-agent\n' "$(_vbw_active_agent_state_dir "$planning_dir" "$session_id")"
  else
    printf '%s/.active-agent\n' "$planning_dir"
  fi
}

_vbw_active_agent_lock_dir() {
  printf '%s/.active-agent-count.lock\n' "$1"
}

vbw_active_agent_acquire_lock() {
  local planning_dir="$1"
  local lock_dir attempts max_attempts now lock_mtime age

  lock_dir=$(_vbw_active_agent_lock_dir "$planning_dir")
  attempts=0
  max_attempts=100

  while [ "$attempts" -lt "$max_attempts" ]; do
    if mkdir "$lock_dir" 2>/dev/null; then
      return 0
    fi

    attempts=$((attempts + 1))

    if [ "$attempts" -eq 50 ] && [ -d "$lock_dir" ]; then
      now=$(date +%s 2>/dev/null || echo 0)
      if [ "$(uname)" = "Darwin" ]; then
        lock_mtime=$(stat -f %m "$lock_dir" 2>/dev/null || echo 0)
      else
        lock_mtime=$(stat -c %Y "$lock_dir" 2>/dev/null || echo 0)
      fi
      age=$((now - lock_mtime))
      if [ "$age" -gt 5 ]; then
        rmdir "$lock_dir" 2>/dev/null || true
      fi
    fi

    sleep 0.01
  done

  return 1
}

vbw_active_agent_release_lock() {
  rmdir "$(_vbw_active_agent_lock_dir "$1")" 2>/dev/null || true
}

_vbw_active_agent_read_count_file() {
  local count_file="$1"
  local raw

  raw=$(cat "$count_file" 2>/dev/null | tr -d '[:space:]')
  if printf '%s' "$raw" | grep -Eq '^[0-9]+$'; then
    printf '%s\n' "$raw"
  else
    printf '0\n'
  fi
}

_vbw_active_agent_read_count() {
  _vbw_active_agent_read_count_file "$(_vbw_active_agent_count_file "$1" "${2:-}")"
}

vbw_active_agent_current_count() {
  local planning_dir="$1"
  local input="${2:-}"
  local session_id=""

  if session_id=$(vbw_active_agent_session_id "$input"); then
    _vbw_active_agent_read_count "$planning_dir" "$session_id"
  else
    _vbw_active_agent_read_count "$planning_dir" ""
  fi
}

_vbw_active_agent_update_role_count() {
  local planning_dir="$1"
  local session_id="${2:-}"
  local target_role="$3"
  local delta="$4"
  local roles_file tmp role count found

  [ -n "$target_role" ] || return 0
  roles_file=$(_vbw_active_agent_roles_file "$planning_dir" "$session_id")
  tmp="${roles_file}.tmp.$$"
  found=false
  mkdir -p "$(dirname "$roles_file")" 2>/dev/null || return 0
  : > "$tmp" 2>/dev/null || return 0

  if [ -f "$roles_file" ]; then
    while read -r role count; do
      [ -z "$role" ] && continue
      if ! printf '%s' "$count" | grep -Eq '^[0-9]+$'; then
        count=0
      fi
      if [ "$role" = "$target_role" ]; then
        count=$((count + delta))
        found=true
      fi
      if [ "$count" -gt 0 ]; then
        printf '%s %s\n' "$role" "$count" >> "$tmp"
      fi
    done < "$roles_file"
  fi

  if [ "$found" = false ] && [ "$delta" -gt 0 ]; then
    printf '%s %s\n' "$target_role" "$delta" >> "$tmp"
  fi

  if [ -s "$tmp" ]; then
    mv "$tmp" "$roles_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  else
    rm -f "$tmp" "$roles_file" 2>/dev/null || true
  fi
}

_vbw_active_agent_role_stats() {
  local roles_file

  roles_file=$(_vbw_active_agent_roles_file "$1" "${2:-}")
  if [ -f "$roles_file" ]; then
    awk '($2 ~ /^[0-9]+$/) && $2 > 0 { sum += $2; count += 1; role = $1 } END { printf "%d %d %s\n", sum + 0, count + 0, role }' "$roles_file" 2>/dev/null
  else
    printf '0 0 \n'
  fi
}

_vbw_active_agent_sync_marker() {
  local planning_dir="$1"
  local session_id="${2:-}"
  local count stats role_sum role_count single_role marker_file

  count=$(_vbw_active_agent_read_count "$planning_dir" "$session_id")
  stats=$(_vbw_active_agent_role_stats "$planning_dir" "$session_id")
  IFS=' ' read -r role_sum role_count single_role <<EOF
$stats
EOF
  role_sum="${role_sum:-0}"
  role_count="${role_count:-0}"
  single_role="${single_role:-}"
  marker_file=$(_vbw_active_agent_marker_file "$planning_dir" "$session_id")

  if [ "$role_sum" -eq "$count" ] && [ "$role_count" -eq 1 ] && [ -n "$single_role" ]; then
    mkdir -p "$(dirname "$marker_file")" 2>/dev/null || return 0
    printf '%s\n' "$single_role" > "$marker_file" 2>/dev/null || true
  else
    rm -f "$marker_file" 2>/dev/null || true
  fi
}

_vbw_active_agent_upsert_role_pid() {
  local planning_dir="$1"
  local session_id="${2:-}"
  local pid="$3"
  local role="$4"
  local role_pids_file tmp

  [ -n "$pid" ] && [ -n "$role" ] || return 0
  printf '%s' "$pid" | grep -Eq '^[0-9]+$' || return 0

  role_pids_file=$(_vbw_active_agent_role_pids_file "$planning_dir" "$session_id")
  mkdir -p "$(dirname "$role_pids_file")" 2>/dev/null || return 0
  tmp="${role_pids_file}.tmp.$$"
  if [ -f "$role_pids_file" ]; then
    awk -v p="$pid" '$1 != p { print }' "$role_pids_file" > "$tmp" 2>/dev/null || : > "$tmp"
  else
    : > "$tmp" 2>/dev/null || return 0
  fi
  printf '%s %s\n' "$pid" "$role" >> "$tmp" 2>/dev/null || true
  mv "$tmp" "$role_pids_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
}

_vbw_active_agent_remove_role_pid() {
  local planning_dir="$1"
  local session_id="${2:-}"
  local pid="$3"
  local role_pids_file tmp

  [ -n "$pid" ] || return 0
  role_pids_file=$(_vbw_active_agent_role_pids_file "$planning_dir" "$session_id")
  [ -f "$role_pids_file" ] || return 0
  tmp="${role_pids_file}.tmp.$$"
  awk -v p="$pid" '$1 != p { print }' "$role_pids_file" > "$tmp" 2>/dev/null || : > "$tmp"
  if [ -s "$tmp" ]; then
    mv "$tmp" "$role_pids_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  else
    rm -f "$tmp" "$role_pids_file" 2>/dev/null || true
  fi
}

_vbw_active_agent_lookup_role_by_pid() {
  local planning_dir="$1"
  local session_id="${2:-}"
  local pid="$3"
  local role_pids_file

  [ -n "$pid" ] || return 1
  role_pids_file=$(_vbw_active_agent_role_pids_file "$planning_dir" "$session_id")
  [ -f "$role_pids_file" ] || return 1
  awk -v p="$pid" '$1 == p { print $2; exit }' "$role_pids_file" 2>/dev/null
}

_vbw_active_agent_log_role_reconciliation() {
  local planning_dir="$1"
  local reason="$2"
  local before_count="$3"
  local after_count="$4"
  local before_role_sum="$5"
  local action="$6"
  local ts

  [ -d "$planning_dir" ] || return 0
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  printf '{"event":"active_agent_role_reconcile","reason":"%s","before_count":%s,"after_count":%s,"before_role_sum":%s,"action":"%s","timestamp":"%s"}\n' \
    "$reason" "${before_count:-0}" "${after_count:-0}" "${before_role_sum:-0}" "$action" "$ts" \
    >> "$planning_dir/.event-log.jsonl" 2>/dev/null || true
}

_vbw_active_agent_discard_role_markers() {
  local planning_dir="$1"
  local session_id="${2:-}"
  local reason="$3"
  local before_count="$4"
  local after_count="$5"
  local before_role_sum="$6"

  _vbw_active_agent_log_role_reconciliation "$planning_dir" "$reason" "$before_count" "$after_count" "$before_role_sum" "discard_role_markers"
  rm -f \
    "$(_vbw_active_agent_roles_file "$planning_dir" "$session_id")" \
    "$(_vbw_active_agent_role_pids_file "$planning_dir" "$session_id")" \
    "$(_vbw_active_agent_marker_file "$planning_dir" "$session_id")" \
    2>/dev/null || true
}

_vbw_active_agent_decrement_unknown_role() {
  local planning_dir="$1"
  local session_id="${2:-}"
  local new_count="$3"
  local old_count="$4"
  local stats role_sum role_count single_role

  stats=$(_vbw_active_agent_role_stats "$planning_dir" "$session_id")
  IFS=' ' read -r role_sum role_count single_role <<EOF
$stats
EOF
  role_sum="${role_sum:-0}"
  role_count="${role_count:-0}"
  single_role="${single_role:-}"

  if [ "$role_count" -eq 0 ]; then
    rm -f "$(_vbw_active_agent_marker_file "$planning_dir" "$session_id")" 2>/dev/null || true
    return 0
  fi

  if [ "$role_count" -eq 1 ] && [ -n "$single_role" ] && [ "$role_sum" -gt "$new_count" ]; then
    _vbw_active_agent_update_role_count "$planning_dir" "$session_id" "$single_role" -1
    return 0
  fi

  if [ "$role_sum" -eq "$new_count" ]; then
    return 0
  fi

  _vbw_active_agent_discard_role_markers "$planning_dir" "$session_id" "anonymous_stop_unreliable_role_state" "$old_count" "$new_count" "$role_sum"
}

_vbw_active_agent_reconcile_role_state() {
  local planning_dir="$1"
  local session_id="${2:-}"
  local reason="$3"
  local before_count="$4"
  local count stats role_sum role_count _single_role

  count=$(_vbw_active_agent_read_count "$planning_dir" "$session_id")
  stats=$(_vbw_active_agent_role_stats "$planning_dir" "$session_id")
  IFS=' ' read -r role_sum role_count _single_role <<EOF
$stats
EOF
  role_sum="${role_sum:-0}"
  role_count="${role_count:-0}"

  if [ "$role_count" -eq 0 ]; then
    rm -f "$(_vbw_active_agent_marker_file "$planning_dir" "$session_id")" 2>/dev/null || true
    return 0
  fi

  if [ "$role_sum" -eq "$count" ]; then
    _vbw_active_agent_sync_marker "$planning_dir" "$session_id"
    return 0
  fi

  _vbw_active_agent_discard_role_markers "$planning_dir" "$session_id" "$reason" "$before_count" "$count" "$role_sum"
}

_vbw_active_agent_root_files_remove() {
  local planning_dir="$1"

  rm -f \
    "$planning_dir/.active-agent" \
    "$planning_dir/.active-agent-count" \
    "$planning_dir/.active-agent-roles" \
    "$planning_dir/.active-agent-role-pids" \
    2>/dev/null || true
}

_vbw_active_agent_has_positive_source_dirs_unlocked() {
  local planning_dir="$1"
  local sessions_dir session_dir source_id count

  sessions_dir="$planning_dir/.active-agents"
  [ -d "$sessions_dir" ] || return 1

  for session_dir in "$sessions_dir"/*; do
    [ -d "$session_dir" ] || continue
    source_id=$(basename "$session_dir")
    _vbw_active_agent_is_aggregate_source_id "$source_id" || continue
    count=$(_vbw_active_agent_read_count_file "$session_dir/active-agent-count")
    if [ "$count" -gt 0 ]; then
      return 0
    fi
  done

  return 1
}

_vbw_active_agent_migrate_legacy_root_to_source_unlocked() {
  local planning_dir="$1"
  local legacy_source legacy_dir count root_count roles_file role_pids_file marker_file
  local root_roles_file root_pids_file root_marker marker_role roles_sum

  legacy_source=$(_vbw_active_agent_legacy_source_id)
  legacy_dir=$(vbw_active_agent_session_dir "$planning_dir" "$legacy_source")
  [ ! -d "$legacy_dir" ] || return 0
  if _vbw_active_agent_has_positive_source_dirs_unlocked "$planning_dir"; then
    return 0
  fi

  root_roles_file="$planning_dir/.active-agent-roles"
  root_pids_file="$planning_dir/.active-agent-role-pids"
  root_marker="$planning_dir/.active-agent"
  root_count=$(_vbw_active_agent_read_count_file "$planning_dir/.active-agent-count")
  roles_sum=0
  if [ -f "$root_roles_file" ]; then
    roles_sum=$(awk '($2 ~ /^[0-9]+$/) && $2 > 0 { sum += $2 } END { print sum + 0 }' "$root_roles_file" 2>/dev/null)
  fi

  marker_role=""
  if [ -f "$root_marker" ]; then
    marker_role=$(cat "$root_marker" 2>/dev/null | head -n 1 | tr -d '[:space:]')
    if ! marker_role=$(vbw_active_agent_normalize_role "$marker_role" 2>/dev/null); then
      marker_role=""
    fi
  fi

  count="$root_count"
  if [ "$count" -le 0 ]; then
    if [ "${roles_sum:-0}" -gt 0 ]; then
      count="$roles_sum"
    elif [ -n "$marker_role" ]; then
      count=1
    else
      return 0
    fi
  fi
  [ "$count" -gt 0 ] || return 0

  mkdir -p "$legacy_dir" 2>/dev/null || return 0
  roles_file=$(_vbw_active_agent_roles_file "$planning_dir" "$legacy_source")
  role_pids_file=$(_vbw_active_agent_role_pids_file "$planning_dir" "$legacy_source")
  marker_file=$(_vbw_active_agent_marker_file "$planning_dir" "$legacy_source")
  printf '%s\n' "$count" > "$(_vbw_active_agent_count_file "$planning_dir" "$legacy_source")" 2>/dev/null || true

  rm -f "$roles_file" "$role_pids_file" "$marker_file" 2>/dev/null || true
  if [ -f "$root_roles_file" ]; then
    awk '($2 ~ /^[0-9]+$/) && $2 > 0 { print $1, $2 }' "$root_roles_file" > "$roles_file" 2>/dev/null || rm -f "$roles_file" 2>/dev/null || true
    [ -s "$roles_file" ] || rm -f "$roles_file" 2>/dev/null || true
  elif [ -n "$marker_role" ] && [ "$count" -eq 1 ]; then
    printf '%s 1\n' "$marker_role" > "$roles_file" 2>/dev/null || true
  fi

  if [ -f "$root_pids_file" ]; then
    awk 'NF >= 2 { print $1, $2 }' "$root_pids_file" > "$role_pids_file" 2>/dev/null || rm -f "$role_pids_file" 2>/dev/null || true
    [ -s "$role_pids_file" ] || rm -f "$role_pids_file" 2>/dev/null || true
  fi

  _vbw_active_agent_sync_marker "$planning_dir" "$legacy_source"
}

_vbw_active_agent_rebuild_aggregate_unlocked() {
  local planning_dir="$1"
  local sessions_dir total count session_dir session_id roles_file pids_file
  local tmp_roles tmp_pids tmp_roles_sum role_sum role_count single_role stats

  sessions_dir="$planning_dir/.active-agents"
  total=0
  tmp_roles="$planning_dir/.active-agent-roles.tmp.$$"
  tmp_pids="$planning_dir/.active-agent-role-pids.tmp.$$"
  tmp_roles_sum="$planning_dir/.active-agent-roles.sum.$$"
  : > "$tmp_roles" 2>/dev/null || true
  : > "$tmp_pids" 2>/dev/null || true

  if [ -d "$sessions_dir" ]; then
    for session_dir in "$sessions_dir"/*; do
      [ -d "$session_dir" ] || continue
      session_id=$(basename "$session_dir")
      _vbw_active_agent_is_aggregate_source_id "$session_id" || continue

      count=$(_vbw_active_agent_read_count_file "$session_dir/active-agent-count")
      if [ "$count" -le 0 ]; then
        continue
      fi
      total=$((total + count))

      roles_file="$session_dir/active-agent-roles"
      if [ -f "$roles_file" ]; then
        awk '($2 ~ /^[0-9]+$/) && $2 > 0 { print $1, $2 }' "$roles_file" >> "$tmp_roles" 2>/dev/null || true
      fi

      pids_file="$session_dir/active-agent-role-pids"
      if [ -f "$pids_file" ]; then
        awk 'NF >= 2 { print $1, $2 }' "$pids_file" >> "$tmp_pids" 2>/dev/null || true
      fi
    done
  fi

  if [ "$total" -le 0 ]; then
    _vbw_active_agent_root_files_remove "$planning_dir"
    rm -f "$tmp_roles" "$tmp_pids" "$tmp_roles_sum" 2>/dev/null || true
    return 0
  fi

  printf '%s\n' "$total" > "$planning_dir/.active-agent-count" 2>/dev/null || true

  if [ -s "$tmp_roles" ]; then
    awk '{ counts[$1] += $2 } END { for (role in counts) if (counts[role] > 0) print role, counts[role] }' "$tmp_roles" | sort > "$tmp_roles_sum" 2>/dev/null || : > "$tmp_roles_sum"
    if [ -s "$tmp_roles_sum" ]; then
      mv "$tmp_roles_sum" "$planning_dir/.active-agent-roles" 2>/dev/null || rm -f "$tmp_roles_sum" 2>/dev/null || true
    else
      rm -f "$planning_dir/.active-agent-roles" "$tmp_roles_sum" 2>/dev/null || true
    fi
  else
    rm -f "$planning_dir/.active-agent-roles" "$tmp_roles_sum" 2>/dev/null || true
  fi

  if [ -s "$tmp_pids" ]; then
    mv "$tmp_pids" "$planning_dir/.active-agent-role-pids" 2>/dev/null || rm -f "$tmp_pids" 2>/dev/null || true
  else
    rm -f "$planning_dir/.active-agent-role-pids" "$tmp_pids" 2>/dev/null || true
  fi
  rm -f "$tmp_roles" 2>/dev/null || true

  role_sum=0
  role_count=0
  single_role=""
  if [ -f "$planning_dir/.active-agent-roles" ]; then
    stats=$(awk '($2 ~ /^[0-9]+$/) && $2 > 0 { sum += $2; count += 1; role = $1 } END { printf "%d %d %s\n", sum + 0, count + 0, role }' "$planning_dir/.active-agent-roles" 2>/dev/null)
    IFS=' ' read -r role_sum role_count single_role <<EOF
$stats
EOF
  fi
  role_sum="${role_sum:-0}"
  role_count="${role_count:-0}"
  single_role="${single_role:-}"

  if [ "$role_sum" -eq "$total" ] && [ "$role_count" -eq 1 ] && [ -n "$single_role" ]; then
    printf '%s\n' "$single_role" > "$planning_dir/.active-agent" 2>/dev/null || true
  else
    rm -f "$planning_dir/.active-agent" 2>/dev/null || true
  fi
}

vbw_active_agent_rebuild_aggregate() {
  local planning_dir="$1"

  if vbw_active_agent_acquire_lock "$planning_dir"; then
    _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
    vbw_active_agent_release_lock "$planning_dir"
  else
    _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
  fi
}

vbw_active_agent_start() {
  local planning_dir="$1"
  local input="${2:-}"
  local role="$3"
  local pid="${4:-}"
  local session_id="" state_dir count count_file lock_acquired

  [ -n "$role" ] || return 0

  lock_acquired=false
  if vbw_active_agent_acquire_lock "$planning_dir"; then
    lock_acquired=true
    trap 'vbw_active_agent_release_lock "$planning_dir"' INT TERM
  fi

  _vbw_active_agent_migrate_legacy_root_to_source_unlocked "$planning_dir"

  if session_id=$(vbw_active_agent_session_id "$input"); then
    :
  else
    session_id=$(_vbw_active_agent_legacy_source_id)
  fi

  state_dir=$(_vbw_active_agent_state_dir "$planning_dir" "$session_id")
  mkdir -p "$state_dir" 2>/dev/null || true
  count_file=$(_vbw_active_agent_count_file "$planning_dir" "$session_id")
  count=$(_vbw_active_agent_read_count "$planning_dir" "$session_id")
  printf '%s\n' $((count + 1)) > "$count_file" 2>/dev/null || true
  _vbw_active_agent_update_role_count "$planning_dir" "$session_id" "$role" 1
  _vbw_active_agent_upsert_role_pid "$planning_dir" "$session_id" "$pid" "$role"
  _vbw_active_agent_sync_marker "$planning_dir" "$session_id"
  _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"

  if [ "$lock_acquired" = true ]; then
    vbw_active_agent_release_lock "$planning_dir"
    trap - INT TERM
  fi
}

vbw_active_agent_find_session_by_pid() {
  local planning_dir="$1"
  local pid="${2:-}"
  local sessions_dir role_pids_file session_dir session_id found count

  [ -n "$pid" ] || return 1
  printf '%s' "$pid" | grep -Eq '^[0-9]+$' || return 1

  sessions_dir="$planning_dir/.active-agents"
  [ -d "$sessions_dir" ] || return 1

  found=""
  count=0
  for role_pids_file in "$sessions_dir"/*/active-agent-role-pids; do
    [ -f "$role_pids_file" ] || continue
    if awk -v p="$pid" '$1 == p { found=1 } END { exit found ? 0 : 1 }' "$role_pids_file" 2>/dev/null; then
      session_dir=$(dirname "$role_pids_file")
      session_id=$(basename "$session_dir")
      _vbw_active_agent_is_aggregate_source_id "$session_id" || continue
      found="$session_id"
      count=$((count + 1))
    fi
  done

  if [ "$count" -eq 1 ] && [ -n "$found" ]; then
    printf '%s\n' "$found"
    return 0
  fi

  return 1
}

_vbw_active_agent_decrement_state() {
  local planning_dir="$1"
  local session_id="${2:-}"
  local role="${3:-}"
  local pid="${4:-}"
  local count_file marker_file roles_file role_pids_file count new_count pid_role state_dir

  count_file=$(_vbw_active_agent_count_file "$planning_dir" "$session_id")
  marker_file=$(_vbw_active_agent_marker_file "$planning_dir" "$session_id")
  roles_file=$(_vbw_active_agent_roles_file "$planning_dir" "$session_id")
  role_pids_file=$(_vbw_active_agent_role_pids_file "$planning_dir" "$session_id")

  if [ -f "$count_file" ]; then
    count=$(_vbw_active_agent_read_count_file "$count_file")
    if [ "$count" -le 0 ] && [ -f "$marker_file" ]; then
      count=1
    fi

    new_count=$((count - 1))
    if [ "$new_count" -le 0 ]; then
      if [ -n "$session_id" ]; then
        state_dir=$(_vbw_active_agent_state_dir "$planning_dir" "$session_id")
        rm -rf "$state_dir" 2>/dev/null || true
      else
        rm -f "$marker_file" "$count_file" "$roles_file" "$role_pids_file" 2>/dev/null || true
      fi
      return 0
    fi

    printf '%s\n' "$new_count" > "$count_file" 2>/dev/null || true

    if [ -z "$role" ] && [ -n "$pid" ]; then
      pid_role=$(_vbw_active_agent_lookup_role_by_pid "$planning_dir" "$session_id" "$pid" || true)
      if [ -n "$pid_role" ] && role=$(vbw_active_agent_normalize_role "$pid_role"); then
        :
      else
        role=""
      fi
    fi

    _vbw_active_agent_remove_role_pid "$planning_dir" "$session_id" "$pid"

    if [ -n "$role" ]; then
      _vbw_active_agent_update_role_count "$planning_dir" "$session_id" "$role" -1
    else
      _vbw_active_agent_decrement_unknown_role "$planning_dir" "$session_id" "$new_count" "$count"
    fi

    _vbw_active_agent_reconcile_role_state "$planning_dir" "$session_id" "post_stop_role_count_mismatch" "$count"
  elif [ -f "$marker_file" ]; then
    if [ -n "$session_id" ]; then
      state_dir=$(_vbw_active_agent_state_dir "$planning_dir" "$session_id")
      rm -rf "$state_dir" 2>/dev/null || true
    else
      rm -f "$marker_file" "$roles_file" "$role_pids_file" 2>/dev/null || true
    fi
  fi
}

vbw_active_agent_stop() {
  local planning_dir="$1"
  local input="${2:-}"
  local role="${3:-}"
  local pid="${4:-}"
  local session_id="" session_scoped=false lock_acquired

  lock_acquired=false
  if vbw_active_agent_acquire_lock "$planning_dir"; then
    lock_acquired=true
    trap 'vbw_active_agent_release_lock "$planning_dir"' INT TERM
  fi

  _vbw_active_agent_migrate_legacy_root_to_source_unlocked "$planning_dir"

  if session_id=$(vbw_active_agent_session_id "$input"); then
    session_scoped=true
  elif session_id=$(vbw_active_agent_find_session_by_pid "$planning_dir" "$pid"); then
    session_scoped=true
  elif [ -d "$(vbw_active_agent_session_dir "$planning_dir" "$(_vbw_active_agent_legacy_source_id)")" ]; then
    session_id=$(_vbw_active_agent_legacy_source_id)
    session_scoped=true
  else
    session_id=""
  fi

  _vbw_active_agent_decrement_state "$planning_dir" "$session_id" "$role" "$pid"
  if [ "$session_scoped" = true ]; then
    _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
  fi

  if [ "$lock_acquired" = true ]; then
    vbw_active_agent_release_lock "$planning_dir"
    trap - INT TERM
  fi
}

vbw_active_agent_remove_current_session() {
  local planning_dir="$1"
  local input="${2:-}"
  local session_id="" lock_acquired legacy_source

  if session_id=$(vbw_active_agent_session_id "$input"); then
    lock_acquired=false
    if vbw_active_agent_acquire_lock "$planning_dir"; then
      lock_acquired=true
      trap 'vbw_active_agent_release_lock "$planning_dir"' INT TERM
    fi
    _vbw_active_agent_migrate_legacy_root_to_source_unlocked "$planning_dir"
    rm -rf "$(vbw_active_agent_session_dir "$planning_dir" "$session_id")" 2>/dev/null || true
    _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
    if [ "$lock_acquired" = true ]; then
      vbw_active_agent_release_lock "$planning_dir"
      trap - INT TERM
    fi
  else
    lock_acquired=false
    if vbw_active_agent_acquire_lock "$planning_dir"; then
      lock_acquired=true
      trap 'vbw_active_agent_release_lock "$planning_dir"' INT TERM
    fi
    _vbw_active_agent_migrate_legacy_root_to_source_unlocked "$planning_dir"
    legacy_source=$(_vbw_active_agent_legacy_source_id)
    rm -rf "$(vbw_active_agent_session_dir "$planning_dir" "$legacy_source")" 2>/dev/null || true
    _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
    if [ "$lock_acquired" = true ]; then
      vbw_active_agent_release_lock "$planning_dir"
      trap - INT TERM
    fi
  fi
}

vbw_active_agent_clear_all() {
  local planning_dir="$1"
  local lock_acquired

  lock_acquired=false
  if vbw_active_agent_acquire_lock "$planning_dir"; then
    lock_acquired=true
    trap 'vbw_active_agent_release_lock "$planning_dir"' INT TERM
  fi
  rm -rf "$planning_dir/.active-agents" 2>/dev/null || true
  _vbw_active_agent_root_files_remove "$planning_dir"
  if [ "$lock_acquired" = true ]; then
    vbw_active_agent_release_lock "$planning_dir"
    trap - INT TERM
  fi
  rm -rf "$(_vbw_active_agent_lock_dir "$planning_dir")" 2>/dev/null || true
}

vbw_active_agent_current_scout() {
  local planning_dir="$1"
  local input="${2:-}"
  local session_id="" roles_file marker_file candidate role

  if session_id=$(vbw_active_agent_session_id "$input"); then
    roles_file=$(_vbw_active_agent_roles_file "$planning_dir" "$session_id")
    marker_file=$(_vbw_active_agent_marker_file "$planning_dir" "$session_id")
  else
    roles_file=$(_vbw_active_agent_roles_file "$planning_dir" "")
    marker_file=$(_vbw_active_agent_marker_file "$planning_dir" "")
  fi

  if [ -f "$roles_file" ] && awk '$1 == "scout" && ($2 ~ /^[0-9]+$/) && $2 > 0 { found=1 } END { exit found ? 0 : 1 }' "$roles_file" 2>/dev/null; then
    return 0
  fi

  if [ -f "$marker_file" ]; then
    candidate=$(cat "$marker_file" 2>/dev/null | head -n 1 | tr -d '[:space:]')
    if [ -n "$candidate" ] && role=$(vbw_active_agent_normalize_role "$candidate") && [ "$role" = "scout" ]; then
      return 0
    fi
  fi

  return 1
}

_vbw_active_agent_marker_is_fresh() {
  local marker="$1"
  local max_age="${2:-86400}"
  local now marker_mtime age

  [ -f "$marker" ] || return 1
  now=$(date +%s 2>/dev/null || echo 0)
  if [ "$(uname)" = "Darwin" ]; then
    marker_mtime=$(stat -f %m "$marker" 2>/dev/null || echo 0)
  else
    marker_mtime=$(stat -c %Y "$marker" 2>/dev/null || echo 0)
  fi
  age=$((now - marker_mtime))
  [ "$age" -ge 0 ] && [ "$age" -lt "$max_age" ]
}

vbw_active_agent_current_marker_fresh() {
  local planning_dir="$1"
  local input="${2:-}"
  local max_age="${3:-86400}"
  local session_id="" marker

  if session_id=$(vbw_active_agent_session_id "$input"); then
    for marker in \
      "$(_vbw_active_agent_count_file "$planning_dir" "$session_id")" \
      "$(_vbw_active_agent_marker_file "$planning_dir" "$session_id")" \
      "$(_vbw_active_agent_roles_file "$planning_dir" "$session_id")"; do
      if _vbw_active_agent_marker_is_fresh "$marker" "$max_age"; then
        return 0
      fi
    done
    return 1
  fi

  _vbw_active_agent_marker_is_fresh "$planning_dir/.active-agent" "$max_age"
}

_vbw_active_agent_session_has_live_pid() {
  local session_dir="$1"
  local role_pids_file pid

  role_pids_file="$session_dir/active-agent-role-pids"
  [ -f "$role_pids_file" ] || return 1

  while read -r pid _role; do
    [ -n "$pid" ] || continue
    printf '%s' "$pid" | grep -Eq '^[0-9]+$' || continue
    if kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  done < "$role_pids_file"

  return 1
}

vbw_active_agent_scan_stale_sessions() {
  local planning_dir="$1"
  local sessions_dir session_dir session_id count

  sessions_dir="$planning_dir/.active-agents"
  [ -d "$sessions_dir" ] || return 0

  for session_dir in "$sessions_dir"/*; do
    [ -d "$session_dir" ] || continue
    session_id=$(basename "$session_dir")
    _vbw_active_agent_is_aggregate_source_id "$session_id" || continue
    count=$(_vbw_active_agent_read_count_file "$session_dir/active-agent-count")
    [ "$count" -gt 0 ] || continue
    if ! _vbw_active_agent_session_has_live_pid "$session_dir"; then
      printf 'stale_marker|.active-agents/%s|dead session-local PIDs\n' "$session_id"
    fi
  done
}

vbw_active_agent_cleanup_stale_sessions() {
  local planning_dir="$1"
  local stale session_ref session_id removed lock_acquired

  removed=0
  stale=$(vbw_active_agent_scan_stale_sessions "$planning_dir" || true)
  [ -n "$stale" ] || return 0

  lock_acquired=false
  if vbw_active_agent_acquire_lock "$planning_dir"; then
    lock_acquired=true
    trap 'vbw_active_agent_release_lock "$planning_dir"' INT TERM
  fi

  while IFS='|' read -r _category session_ref _detail; do
    [ -n "$session_ref" ] || continue
    session_id="${session_ref#.active-agents/}"
    _vbw_active_agent_is_aggregate_source_id "$session_id" || continue
    rm -rf "$(vbw_active_agent_session_dir "$planning_dir" "$session_id")" 2>/dev/null || true
    removed=$((removed + 1))
  done <<EOF
$stale
EOF

  _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
  if [ "$lock_acquired" = true ]; then
    vbw_active_agent_release_lock "$planning_dir"
    trap - INT TERM
  fi

  return 0
}