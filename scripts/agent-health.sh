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

# Derive a unique agent key from hook JSON.
# Preference: name > task_id > agent_name > agent_type (role fallback).
# Also extracts a normalized role for metadata.
extract_agent_key_and_role() {
  local input="$1"
  local key="" role=""

  # Extract unique key: prefer name (e.g. "dev-01"), then task_id, then agent_name
  key=$(echo "$input" | jq -r '.name // ""' 2>/dev/null)
  if [ -z "$key" ]; then
    key=$(echo "$input" | jq -r '.task_id // ""' 2>/dev/null)
  fi
  if [ -z "$key" ]; then
    key=$(echo "$input" | jq -r '.agent_name // ""' 2>/dev/null)
  fi
  if [ -z "$key" ]; then
    key=$(echo "$input" | jq -r '.agent_type // ""' 2>/dev/null)
  fi

  # Normalize key: strip prefixes, lowercase
  key=$(echo "$key" | sed -E 's/^@?vbw[:-]//i' | tr '[:upper:]' '[:lower:]')

  # Extract role separately (for metadata/reporting)
  role=$(echo "$input" | jq -r '.agent_type // .agent_name // .name // ""' 2>/dev/null)
  role=$(echo "$role" | sed -E 's/^@?vbw[:-]//i' | tr '[:upper:]' '[:lower:]')
  # Normalize to base role (strip numeric suffixes like dev-01 -> dev)
  role=$(echo "$role" | sed -E 's/-[0-9]+$//')

  echo "$key|$role"
}

orphan_recovery() {
  local role="$1"
  local pid="$2"
  local tasks_dir="${CLAUDE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/tasks"
  local advisory=""
  local task_file task_owner task_status task_id

  # Find team directory (assumes single team for now)
  # If multiple teams exist, we'll scan all of them
  if [ ! -d "$tasks_dir" ]; then
    echo "AGENT HEALTH: Orphan recovery — no tasks directory found"
    return
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

  # Extract unique key and normalized role
  key_role=$(extract_agent_key_and_role "$input")
  key="${key_role%%|*}"
  role="${key_role##*|}"

  # Skip if no key or PID extracted
  if [ -z "$key" ] || [ -z "$pid" ]; then
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
  local input key role key_role health_file pid idle_count now advisory
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
    advisory=$(orphan_recovery "$role" "$pid")
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
  local input key role key_role health_file pid advisory
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
      advisory=$(orphan_recovery "$key" "$pid")
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
