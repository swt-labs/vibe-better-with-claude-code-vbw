#!/bin/bash
set -u
# delegated-workflow.sh — Manage delegated workflow markers for delegated paths
#
# Sets/clears/checks .vbw-planning/.delegated-workflow.json so runtime guards
# can enforce actual delegation semantics for execute/fix/debug flows.
#
# Usage:
#   delegated-workflow.sh set <mode> [effort] [delegation_mode] [team_name]
#   delegated-workflow.sh clear
#   delegated-workflow.sh check
#   delegated-workflow.sh status-json
#
# Actions:
#   set   — Write marker with mode (execute|fix|debug), optional effort
#           (default: balanced), optional delegation_mode
#           (team|subagent|direct), and optional team_name
#   clear — Remove marker file
#   check — Exit 0 if active, 1 if not active
#   status-json — Emit marker status JSON including live execute validation
#
# The marker file is transient (gitignored via planning-git.sh).

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
MARKER_FILE="$PLANNING_DIR/.delegated-workflow.json"
EXEC_STATE_FILE="$PLANNING_DIR/.execution-state.json"
STALE_SECS=14400

ACTION="${1:-}"
MODE="${2:-}"
EFFORT="${3:-balanced}"
DELEGATION_MODE="${4:-}"
TEAM_NAME="${5:-}"

json_field() {
  local file="$1"
  local query="$2"

  if ! command -v jq >/dev/null 2>&1; then
    printf '\n'
    return 0
  fi

  if ! jq empty "$file" >/dev/null 2>&1; then
    printf '\n'
    return 0
  fi

  jq -r "$query // \"\"" "$file" 2>/dev/null || printf '\n'
}

file_mtime() {
  local file="$1"
  if [ "$(uname)" = "Darwin" ]; then
    stat -f %m "$file" 2>/dev/null || printf '0\n'
  else
    stat -c %Y "$file" 2>/dev/null || printf '0\n'
  fi
}

marker_age_seconds() {
  local file="$1"
  local now mtime

  now=$(date +%s 2>/dev/null || printf '0\n')
  mtime=$(file_mtime "$file")

  if ! printf '%s' "$now" | grep -Eq '^[0-9]+$' || ! printf '%s' "$mtime" | grep -Eq '^[0-9]+$'; then
    printf '\n'
    return 0
  fi

  printf '%s\n' $((now - mtime))
}

print_status_json() {
  local exists=false
  local active=false
  local mode=""
  local effort=""
  local delegation_mode=""
  local team_name=""
  local started_at=""
  local session_id=""
  local correlation_id=""
  local exec_status=""
  local exec_correlation_id=""
  local marker_age_seconds_value=""
  local live=false
  local reason="missing_marker"

  if [ -f "$MARKER_FILE" ]; then
    exists=true
  fi

  if [ "$exists" = true ]; then
    if ! command -v jq >/dev/null 2>&1; then
      reason="jq_unavailable"
    elif ! jq empty "$MARKER_FILE" >/dev/null 2>&1; then
      reason="invalid_marker_json"
    else
      active=$(jq -r '.active // false' "$MARKER_FILE" 2>/dev/null || printf 'false\n')
      mode=$(json_field "$MARKER_FILE" '.mode')
      effort=$(json_field "$MARKER_FILE" '.effort')
      delegation_mode=$(json_field "$MARKER_FILE" '.delegation_mode')
      team_name=$(json_field "$MARKER_FILE" '.team_name')
      started_at=$(json_field "$MARKER_FILE" '.started_at')
      session_id=$(json_field "$MARKER_FILE" '.session_id')
      correlation_id=$(json_field "$MARKER_FILE" '.correlation_id')
      marker_age_seconds_value=$(marker_age_seconds "$MARKER_FILE")

      if [ "$active" != "true" ]; then
        reason="inactive"
      elif [ -z "$marker_age_seconds_value" ] || ! printf '%s' "$marker_age_seconds_value" | grep -Eq '^[0-9]+$'; then
        reason="unknown_marker_age"
      elif [ "$marker_age_seconds_value" -lt 0 ] || [ "$marker_age_seconds_value" -ge "$STALE_SECS" ]; then
        reason="stale_marker"
      elif [ "$mode" != "execute" ]; then
        live=true
        reason="ok"
      elif [ ! -f "$EXEC_STATE_FILE" ]; then
        reason="missing_execution_state"
      elif ! jq empty "$EXEC_STATE_FILE" >/dev/null 2>&1; then
        reason="invalid_execution_state"
      else
        exec_status=$(json_field "$EXEC_STATE_FILE" '.status')
        exec_correlation_id=$(json_field "$EXEC_STATE_FILE" '.correlation_id')

        if [ "$exec_status" != "running" ]; then
          reason="execution_not_running"
        elif [ -z "$correlation_id" ]; then
          reason="missing_marker_correlation_id"
        elif [ -z "$exec_correlation_id" ]; then
          reason="missing_execution_correlation_id"
        elif [ "$correlation_id" != "$exec_correlation_id" ]; then
          reason="correlation_mismatch"
        else
          live=true
          reason="ok"
        fi
      fi
    fi
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --argjson exists "$exists" \
      --argjson active "$active" \
      --arg mode "$mode" \
      --arg effort "$effort" \
      --arg delegation_mode "$delegation_mode" \
      --arg team_name "$team_name" \
      --arg started_at "$started_at" \
      --arg session_id "$session_id" \
      --arg correlation_id "$correlation_id" \
      --arg execution_status "$exec_status" \
      --arg execution_correlation_id "$exec_correlation_id" \
      --arg marker_age_seconds "$marker_age_seconds_value" \
      --argjson live "$live" \
      --arg reason "$reason" \
      '{
        exists: $exists,
        active: $active,
        mode: $mode,
        effort: $effort,
        delegation_mode: $delegation_mode,
        team_name: $team_name,
        started_at: $started_at,
        session_id: $session_id,
        correlation_id: $correlation_id,
        execution_status: $execution_status,
        execution_correlation_id: $execution_correlation_id,
        marker_age_seconds: $marker_age_seconds,
        live: $live,
        reason: $reason
      }'
  else
    printf '{"exists":%s,"active":%s,"mode":"%s","effort":"%s","delegation_mode":"%s","team_name":"%s","started_at":"%s","session_id":"%s","correlation_id":"%s","execution_status":"%s","execution_correlation_id":"%s","marker_age_seconds":"%s","live":%s,"reason":"%s"}\n' \
      "$exists" "$active" "$mode" "$effort" "$delegation_mode" "$team_name" "$started_at" "$session_id" "$correlation_id" "$exec_status" "$exec_correlation_id" "$marker_age_seconds_value" "$live" "$reason"
  fi
}

case "$ACTION" in
  set)
    if [ -z "$MODE" ]; then
      echo "Usage: delegated-workflow.sh set <mode> [effort] [delegation_mode] [team_name]" >&2
      exit 1
    fi
    [ -d "$PLANNING_DIR" ] || { echo "No .vbw-planning/ directory" >&2; exit 1; }
    STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)
    SESSION_ID="${CLAUDE_SESSION_ID:-}"
    CORRELATION_ID=""
    if command -v jq >/dev/null 2>&1 && [ -f "$EXEC_STATE_FILE" ]; then
      CORRELATION_ID=$(jq -r '.correlation_id // ""' "$EXEC_STATE_FILE" 2>/dev/null || printf '\n')
      [ "$CORRELATION_ID" = "null" ] && CORRELATION_ID=""
    fi
    if command -v jq >/dev/null 2>&1; then
      jq -n \
        --arg mode "$MODE" \
        --arg effort "$EFFORT" \
        --arg delegation_mode "$DELEGATION_MODE" \
        --arg team_name "$TEAM_NAME" \
        --arg started_at "$STARTED_AT" \
        --arg session_id "$SESSION_ID" \
        --arg correlation_id "$CORRELATION_ID" \
        '{
          mode: $mode,
          active: true,
          effort: $effort,
          delegation_mode: $delegation_mode,
          team_name: $team_name,
          started_at: $started_at,
          session_id: $session_id,
          correlation_id: $correlation_id
        }' \
        > "$MARKER_FILE" 2>/dev/null
    else
      printf '{"mode":"%s","active":true,"effort":"%s","delegation_mode":"%s","team_name":"%s","started_at":"%s","session_id":"%s","correlation_id":"%s"}\n' \
        "$MODE" "$EFFORT" "$DELEGATION_MODE" "$TEAM_NAME" "$STARTED_AT" "$SESSION_ID" "$CORRELATION_ID" > "$MARKER_FILE" 2>/dev/null
    fi
    ;;
  clear)
    rm -f "$MARKER_FILE" 2>/dev/null
    ;;
  check)
    if [ ! -f "$MARKER_FILE" ]; then
      exit 1
    fi
    if command -v jq >/dev/null 2>&1; then
      ACTIVE=$(jq -r '.active // false' "$MARKER_FILE" 2>/dev/null)
      if [ "$ACTIVE" = "true" ]; then
        exit 0
      fi
    else
      # Fallback: file exists = active
      exit 0
    fi
    exit 1
    ;;
  status-json)
    print_status_json
    ;;
  *)
    echo "Usage: delegated-workflow.sh {set|clear|check|status-json}" >&2
    exit 1
    ;;
esac
