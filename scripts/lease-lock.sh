#!/usr/bin/env bash
set -u

# lease-lock.sh <action> <task-id> [claimed-files... | --ttl=N]
# Lease-based lock upgrade to lock-lite with TTL/heartbeat support.
# action: acquire (create lock with TTL), renew (extend lease), release (remove),
#         check (detect conflicts + expired leases)
# Lock files: .vbw-planning/.locks/{task-id}.lock (JSON with ttl/expires_at)
# Fail-open: exit 0 always. Conflicts are logged to metrics, never blocking.

if [ $# -lt 2 ]; then
  echo "Usage: lease-lock.sh <acquire|renew|release|check> <task-id> [--ttl=N] [files...]" >&2
  exit 0
fi

ACTION="$1"
TASK_ID="$2"
shift 2

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
LOCKS_DIR="${PLANNING_DIR}/.locks"
LOCK_FILE="${LOCKS_DIR}/${TASK_ID}.lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${PLANNING_DIR}/config.json"

# Check lease_locks flag — if disabled, skip
# Legacy fallback: honor v3_lease_locks if unprefixed key missing (pre-migration brownfield)
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  LEASE_LOCKS=$(jq -r 'if .lease_locks != null then .lease_locks elif .v3_lease_locks != null then .v3_lease_locks else false end' "$CONFIG_PATH" 2>/dev/null || echo "false")
  if [ "$LEASE_LOCKS" != "true" ]; then
    case "$ACTION" in
      acquire) echo "skipped" ;;
      release) echo "skipped" ;;
      check)   echo "clear" ;;
      renew)   echo "skipped" ;;
      query)   echo "no_lock" ;;
    esac
    exit 0
  fi
fi

# v2_hard_gates graduated (always true)
HARD_GATES=true

# Parse --ttl=N from args, collect remaining as files
DEFAULT_TTL=300
TTL="$DEFAULT_TTL"
FILES_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --ttl=*)
      TTL="${arg#--ttl=}"
      ;;
    *)
      FILES_ARGS+=("$arg")
      ;;
  esac
done

now_epoch() {
  date -u +%s 2>/dev/null || echo "0"
}

emit_conflict() {
  local conflicting_task="$1"
  local conflicting_file="$2"
  local phase="0"
  phase=$(echo "$TASK_ID" | cut -d'-' -f1 2>/dev/null) || phase="0"
  if [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
    bash "${SCRIPT_DIR}/collect-metrics.sh" file_conflict "$phase" \
      "task=${TASK_ID}" "conflicting_task=${conflicting_task}" "file=${conflicting_file}" 2>/dev/null || true
  fi
  echo "V3 lease conflict: ${conflicting_file} already locked by ${conflicting_task}" >&2
}

is_expired() {
  local lock_path="$1"
  local expires_at
  expires_at=$(jq -r '.expires_at // 0' "$lock_path" 2>/dev/null) || return 1
  [ "$expires_at" = "0" ] && return 1
  local now
  now=$(now_epoch)
  [ "$now" -gt "$expires_at" ] 2>/dev/null && return 0
  return 1
}

cleanup_expired() {
  [ ! -d "$LOCKS_DIR" ] && return
  for lock in "$LOCKS_DIR"/*.lock; do
    [ ! -f "$lock" ] && continue
    if is_expired "$lock"; then
      local expired_task
      expired_task=$(basename "$lock" .lock)
      rm -f "$lock" 2>/dev/null || true
      echo "V3 lease expired: ${expired_task}" >&2
    fi
  done
}

case "$ACTION" in
  acquire)
    mkdir -p "$LOCKS_DIR" 2>/dev/null || exit 0

    # Clean up expired locks first
    cleanup_expired

    # Build files JSON array
    FILES_JSON="[]"
    if [ ${#FILES_ARGS[@]} -gt 0 ]; then
      FILES_JSON=$(printf '%s\n' "${FILES_ARGS[@]}" | jq -R '.' | jq -s '.' 2>/dev/null) || FILES_JSON="[]"
    fi

    # Check for conflicts
    ACQUIRE_CONFLICTS=0
    for EXISTING_LOCK in "$LOCKS_DIR"/*.lock; do
      [ ! -f "$EXISTING_LOCK" ] && continue
      [ "$EXISTING_LOCK" = "$LOCK_FILE" ] && continue

      EXISTING_TASK=$(basename "$EXISTING_LOCK" .lock)
      EXISTING_FILES=$(jq -r '.files[]' "$EXISTING_LOCK" 2>/dev/null) || continue

      for CLAIMED_FILE in "${FILES_ARGS[@]}"; do
        [ -z "$CLAIMED_FILE" ] && continue
        while IFS= read -r existing_file; do
          [ -z "$existing_file" ] && continue
          if [ "$CLAIMED_FILE" = "$existing_file" ]; then
            emit_conflict "$EXISTING_TASK" "$CLAIMED_FILE"
            ACQUIRE_CONFLICTS=$((ACQUIRE_CONFLICTS + 1))
          fi
        done <<< "$EXISTING_FILES"
      done
    done

    # Hard enforcement: exit non-zero on conflict when v2_hard_gates=true (REQ-04)
    if [ "$ACQUIRE_CONFLICTS" -gt 0 ] && [ "$HARD_GATES" = "true" ]; then
      echo "conflict_blocked"
      exit 1
    fi

    # Write lock file with TTL
    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")
    NOW=$(now_epoch)
    EXPIRES_AT=$((NOW + TTL))

    jq -n \
      --arg task_id "$TASK_ID" \
      --arg pid "$$" \
      --arg ts "$TS" \
      --argjson files "$FILES_JSON" \
      --argjson ttl "$TTL" \
      --argjson expires_at "$EXPIRES_AT" \
      '{task_id: $task_id, pid: $pid, timestamp: $ts, files: $files, ttl: $ttl, expires_at: $expires_at}' \
      > "$LOCK_FILE" 2>/dev/null || exit 0

    echo "acquired"
    ;;

  renew)
    if [ ! -f "$LOCK_FILE" ]; then
      echo "no_lock"
      exit 0
    fi

    NOW=$(now_epoch)
    # Read existing TTL or use default
    EXISTING_TTL=$(jq -r '.ttl // 300' "$LOCK_FILE" 2>/dev/null) || EXISTING_TTL="$DEFAULT_TTL"
    NEW_EXPIRES=$((NOW + EXISTING_TTL))
    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

    jq --argjson expires_at "$NEW_EXPIRES" --arg ts "$TS" \
      '.expires_at = $expires_at | .timestamp = $ts' \
      "$LOCK_FILE" > "${LOCK_FILE}.tmp" 2>/dev/null && \
      mv "${LOCK_FILE}.tmp" "$LOCK_FILE" 2>/dev/null || exit 0

    echo "renewed"
    ;;

  release)
    if [ -f "$LOCK_FILE" ]; then
      rm -f "$LOCK_FILE" 2>/dev/null || true
      echo "released"
    else
      echo "no_lock"
    fi
    ;;

  check)
    [ ! -d "$LOCKS_DIR" ] && exit 0

    # Clean expired first
    cleanup_expired

    CONFLICTS=0
    for EXISTING_LOCK in "$LOCKS_DIR"/*.lock; do
      [ ! -f "$EXISTING_LOCK" ] && continue
      [ "$EXISTING_LOCK" = "$LOCK_FILE" ] && continue

      EXISTING_TASK=$(basename "$EXISTING_LOCK" .lock)
      EXISTING_FILES=$(jq -r '.files[]' "$EXISTING_LOCK" 2>/dev/null) || continue

      for CLAIMED_FILE in "${FILES_ARGS[@]}"; do
        [ -z "$CLAIMED_FILE" ] && continue
        while IFS= read -r existing_file; do
          [ -z "$existing_file" ] && continue
          if [ "$CLAIMED_FILE" = "$existing_file" ]; then
            emit_conflict "$EXISTING_TASK" "$CLAIMED_FILE"
            CONFLICTS=$((CONFLICTS + 1))
          fi
        done <<< "$EXISTING_FILES"
      done
    done

    if [ "$CONFLICTS" -gt 0 ]; then
      echo "conflicts:${CONFLICTS}"
      # Hard enforcement: exit non-zero on conflict when v2_hard_gates=true (REQ-04)
      if [ "$HARD_GATES" = "true" ]; then
        exit 1
      fi
    else
      echo "clear"
    fi
    ;;

  query)
    # Read-only lock inspection — no cleanup, no modifications (REQ-04)
    if [ -f "$LOCK_FILE" ]; then
      cat "$LOCK_FILE"
    else
      echo "no_lock"
    fi
    ;;

  *)
    echo "Unknown action: $ACTION. Valid: acquire, renew, release, check, query" >&2
    ;;
esac

exit 0
