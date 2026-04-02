#!/bin/bash
set -u
# agent-health.sh — Track VBW agent health and recover from failures
#
# Usage:
#   agent-health.sh start     # SubagentStart hook: Create health file
#   agent-health.sh idle      # TeammateIdle hook: Check liveness, increment idle count
#   agent-health.sh stop      # SubagentStop hook: Clean up health file
#   agent-health.sh cleanup   # Stop hook: Remove all health tracking

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
HEALTH_DIR="$PLANNING_DIR/.agent-health"
# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh" 2>/dev/null || true

normalize_agent_key() {
  local value="$1"
  local lower

  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  lower="${lower#@}"
  lower="${lower#vbw:}"
  lower="${lower#vbw-}"
  printf '%s' "$lower"
}

normalize_agent_role() {
  local value="$1"
  local lower

  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  lower="${lower#@}"
  lower="${lower#vbw:}"

  case "$lower" in
    vbw-lead|vbw-lead-[0-9]*|lead|lead-[0-9]*|team-lead|team-lead-[0-9]*)
      printf 'lead'
      return 0
      ;;
    vbw-dev|vbw-dev-[0-9]*|dev|dev-[0-9]*|team-dev|team-dev-[0-9]*)
      printf 'dev'
      return 0
      ;;
    vbw-qa|vbw-qa-[0-9]*|qa|qa-[0-9]*|team-qa|team-qa-[0-9]*)
      printf 'qa'
      return 0
      ;;
    vbw-scout|vbw-scout-[0-9]*|scout|scout-[0-9]*|team-scout|team-scout-[0-9]*)
      printf 'scout'
      return 0
      ;;
    vbw-debugger|vbw-debugger-[0-9]*|debugger|debugger-[0-9]*|team-debugger|team-debugger-[0-9]*)
      printf 'debugger'
      return 0
      ;;
    vbw-architect|vbw-architect-[0-9]*|architect|architect-[0-9]*|team-architect|team-architect-[0-9]*)
      printf 'architect'
      return 0
      ;;
    vbw-docs|vbw-docs-[0-9]*|docs|docs-[0-9]*|team-docs|team-docs-[0-9]*)
      printf 'docs'
      return 0
      ;;
  esac

  return 1
}

has_vbw_context() {
  [ -f "$PLANNING_DIR/.vbw-session" ] \
    || [ -f "$PLANNING_DIR/.active-agent" ] \
    || [ -f "$PLANNING_DIR/.active-agent-count" ]
}

is_explicit_vbw_agent() {
  local value="$1"
  local lower

  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  echo "$lower" | grep -qE '^@?vbw:|^@?vbw-'
}

# Derive a unique agent key from hook JSON.
# Preference: agent_id > teammate_name > name > task_id > agent_name > agentName > agent_type.
# Role preference: agent_type > agent_name > agentName > name > teammate_name.
# Also extracts a normalized role for metadata.
extract_agent_key_and_role() {
  local input="$1"
  local key="" role="" native_agent_type legacy_role_source role_source=""

  native_agent_type=$(echo "$input" | jq -r '.agent_type // ""' 2>/dev/null)
  legacy_role_source=$(echo "$input" | jq -r '.agent_name // .agentName // .name // .teammate_name // ""' 2>/dev/null)

  if [ -n "$native_agent_type" ]; then
    if is_explicit_vbw_agent "$native_agent_type"; then
      role_source="$native_agent_type"
    else
      echo "|"
      return 0
    fi
  elif is_explicit_vbw_agent "$legacy_role_source" || has_vbw_context; then
    role_source="$legacy_role_source"
  else
    echo "|"
    return 0
  fi

  # Extract unique key: prefer native agent_id (e.g. "dev-01"), then fall
  # back through legacy fields used by older Claude Code runtimes.
  key=$(echo "$input" | jq -r '.agent_id // ""' 2>/dev/null)
  if [ -z "$key" ]; then
    key=$(echo "$input" | jq -r '.teammate_name // ""' 2>/dev/null)
  fi
  if [ -z "$key" ]; then
    key=$(echo "$input" | jq -r '.name // ""' 2>/dev/null)
  fi
  if [ -z "$key" ]; then
    key=$(echo "$input" | jq -r '.task_id // ""' 2>/dev/null)
  fi
  if [ -z "$key" ]; then
    key=$(echo "$input" | jq -r '.agent_name // ""' 2>/dev/null)
  fi
  if [ -z "$key" ]; then
    key=$(echo "$input" | jq -r '.agentName // ""' 2>/dev/null)
  fi
  if [ -z "$key" ]; then
    key=$(echo "$input" | jq -r '.agent_type // ""' 2>/dev/null)
  fi

  # Normalize key for use as a stable health-file name.
  key=$(normalize_agent_key "$key")

  # Extract role separately (for metadata/reporting and orphan recovery).
  if role=$(normalize_agent_role "$role_source"); then
    :
  else
    role=$(normalize_agent_key "$role_source")
    role=$(echo "$role" | sed -E 's/-[0-9]+$//')
  fi

  echo "$key|$role"
}

orphan_recovery() {
  local role="$1"
  local pid="$2"
  local key="${3:-}"
  local tasks_dir="${CLAUDE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/tasks"
  local advisory=""
  local task_file task_owner task_status task_id health_file live_key live_role live_pid

  # Find team directory (assumes single team for now)
  # If multiple teams exist, we'll scan all of them
  if [ ! -d "$tasks_dir" ]; then
    echo "AGENT HEALTH: Orphan recovery — no tasks directory found"
    return
  fi

  # Role-owned tasks are shared across same-role teammates. If another live
  # teammate with the same role still exists, do not clear ownership.
  if [ -d "$HEALTH_DIR" ] && [ -n "$role" ]; then
    for health_file in "$HEALTH_DIR"/*.json; do
      [ ! -f "$health_file" ] && continue
      live_key=$(jq -r '.key // ""' "$health_file" 2>/dev/null)
      live_role=$(jq -r '.role // ""' "$health_file" 2>/dev/null)
      live_pid=$(jq -r '.pid // ""' "$health_file" 2>/dev/null)

      [ -n "$key" ] && [ "$live_key" = "$key" ] && continue
      [ "$live_role" != "$role" ] && continue

      if [ -n "$live_pid" ] && kill -0 "$live_pid" 2>/dev/null; then
        echo "AGENT HEALTH: Orphan recovery — agent $role PID $pid is dead, but another live teammate with the same role is still active; leaving role-owned tasks unchanged"
        return
      fi
    done
  fi

  # Scan all team directories
  for team_dir in "$tasks_dir"/*; do
    [ ! -d "$team_dir" ] && continue

    # Scan task JSON files
    for task_file in "$team_dir"/*.json; do
      [ ! -f "$task_file" ] && continue

      # Extract task metadata
      task_owner=$(jq -r '.owner // ""' "$task_file" 2>/dev/null)
      task_status=$(jq -r '.status // ""' "$task_file" 2>/dev/null)
      task_id=$(jq -r '.id // ""' "$task_file" 2>/dev/null)

      # Check if this task is owned by the dead agent and is in_progress
      if [ "$task_owner" = "$role" ] && [ "$task_status" = "in_progress" ]; then
        # Clear owner field
        jq '.owner = ""' "$task_file" > "${task_file}.tmp" && mv "${task_file}.tmp" "$task_file"
        advisory="AGENT HEALTH: Orphan recovery — cleared ownership of task $task_id (owner $role PID $pid is dead)"
      fi
    done
  done

  if [ -z "$advisory" ]; then
    advisory="AGENT HEALTH: Orphan recovery — agent $role PID $pid is dead (no orphaned tasks found)"
  fi

  echo "$advisory"
}

cmd_start() {
  local input pid key role key_role now
  input=$(cat)

  # Extract PID
  pid=$(echo "$input" | jq -r '.pid // ""' 2>/dev/null)
  if [ -z "$pid" ]; then
    pid="$PPID"
  fi

  # Extract unique key and normalized role
  key_role=$(extract_agent_key_and_role "$input")
  key="${key_role%%|*}"
  role="${key_role##*|}"

  # Skip if no agent identity extracted.
  if [ -z "$key" ]; then
    exit 0
  fi

  # Create health directory
  mkdir -p "$HEALTH_DIR"

  # Generate ISO8601 timestamp
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Write health file keyed by unique identity, not role
  jq -n \
    --arg pid "$pid" \
    --arg key "$key" \
    --arg role "$role" \
    --arg ts "$now" \
    '{
      pid: $pid,
      key: $key,
      role: $role,
      started_at: $ts,
      last_event_at: $ts,
      last_event: "start",
      idle_count: 0
    }' > "$HEALTH_DIR/${key}.json"

  # Output hook response
  jq -n \
    --arg event "SubagentStart" \
    '{
      hookSpecificOutput: {
        hookEventName: $event,
        additionalContext: ""
      }
    }'
}

cmd_idle() {
  local input key role key_role health_file pid idle_count now advisory recovery_role
  input=$(cat)

  # Extract unique key and normalized role
  key_role=$(extract_agent_key_and_role "$input")
  key="${key_role%%|*}"
  role="${key_role##*|}"

  if [ -z "$key" ]; then
    exit 0
  fi

  health_file="$HEALTH_DIR/${key}.json"

  # Bootstrap on idle if no health file exists (SubagentStart may not have fired)
  if [ ! -f "$health_file" ]; then
    mkdir -p "$HEALTH_DIR"
    pid=$(echo "$input" | jq -r '.pid // ""' 2>/dev/null)
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -n \
      --arg pid "$pid" \
      --arg key "$key" \
      --arg role "$role" \
      --arg ts "$now" \
      '{
        pid: $pid,
        key: $key,
        role: $role,
        started_at: $ts,
        last_event_at: $ts,
        last_event: "idle_bootstrap",
        idle_count: 0
      }' > "$health_file"
  fi

  # Load health data
  pid=$(jq -r '.pid // ""' "$health_file" 2>/dev/null)
  idle_count=$(jq -r '.idle_count // 0' "$health_file" 2>/dev/null)

  # Check PID liveness
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    # PID is dead — call orphan recovery
    recovery_role="$role"
    [ -z "$recovery_role" ] && recovery_role="$key"
    advisory=$(orphan_recovery "$recovery_role" "$pid" "$key")
    jq -n \
      --arg event "TeammateIdle" \
      --arg context "$advisory" \
      '{
        hookSpecificOutput: {
          hookEventName: $event,
          additionalContext: $context
        }
      }'
    exit 0
  fi

  # Increment idle count
  idle_count=$((idle_count + 1))
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Update health file
  jq --arg ts "$now" --argjson count "$idle_count" \
    '.last_event_at = $ts | .last_event = "idle" | .idle_count = $count' \
    "$health_file" > "${health_file}.tmp" && mv "${health_file}.tmp" "$health_file"

  # Check for stuck agent (idle_count >= 3)
  advisory=""
  if [ "$idle_count" -ge 3 ]; then
    advisory="AGENT HEALTH: Agent $key (role=$role) appears stuck (idle_count=$idle_count). Same teammate has gone idle repeatedly — orchestrator should send one recovery nudge. If next idle repeats, consider terminating and respawning from last safe point, or stop and surface restart guidance to the user."
  fi

  # Output hook response
  jq -n \
    --arg event "TeammateIdle" \
    --arg context "$advisory" \
    '{
      hookSpecificOutput: {
        hookEventName: $event,
        additionalContext: $context
      }
    }'
}

cmd_stop() {
  local input key role key_role health_file pid advisory recovery_role
  input=$(cat)

  # Extract unique key and normalized role
  key_role=$(extract_agent_key_and_role "$input")
  key="${key_role%%|*}"
  role="${key_role##*|}"

  if [ -z "$key" ]; then
    exit 0
  fi

  health_file="$HEALTH_DIR/${key}.json"
  advisory=""

  if [ -f "$health_file" ]; then
    # Load PID and check liveness
    pid=$(jq -r '.pid // ""' "$health_file" 2>/dev/null)

    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      # PID is dead — call orphan recovery
      recovery_role="$role"
      [ -z "$recovery_role" ] && recovery_role="$key"
      advisory=$(orphan_recovery "$recovery_role" "$pid" "$key")
    fi

    # Remove health file
    rm -f "$health_file"
  fi

  # Output hook response
  jq -n \
    --arg event "SubagentStop" \
    --arg context "$advisory" \
    '{
      hookSpecificOutput: {
        hookEventName: $event,
        additionalContext: $context
      }
    }'
}

cmd_cleanup() {
  # Remove entire health tracking directory
  if [ -d "$HEALTH_DIR" ]; then
    rm -rf "$HEALTH_DIR"
  fi
  exit 0
}

CMD="${1:-}"

case "$CMD" in
  start)
    cmd_start
    ;;
  idle)
    cmd_idle
    ;;
  stop)
    cmd_stop
    ;;
  cleanup)
    cmd_cleanup
    ;;
  *)
    echo "Usage: $0 {start|idle|stop|cleanup}" >&2
    exit 1
    ;;
esac
