#!/usr/bin/env bash
# debug-session-state.sh — Manage standalone debug session lifecycle.
#
# Usage:
#   debug-session-state.sh start           <planning-dir> <slug>         → creates session, prints session_id
#   debug-session-state.sh get             <planning-dir>                → prints active session metadata
#   debug-session-state.sh get-or-latest   <planning-dir>                → active session or latest unresolved
#   debug-session-state.sh resume          <planning-dir> <session-id>   → sets active pointer to session
#   debug-session-state.sh set-status      <planning-dir> <status>       → updates status field
#   debug-session-state.sh increment-qa    <planning-dir>                → bumps qa_round, sets qa_last_result=pending
#   debug-session-state.sh increment-uat   <planning-dir>                → bumps uat_round, sets uat_last_result=pending
#   debug-session-state.sh clear-active    <planning-dir>                → removes active pointer
#   debug-session-state.sh list            <planning-dir>                → lists all sessions with status
#
# State fields in frontmatter:
#   status:          investigating | fix_applied | qa_pending | qa_failed | uat_pending | uat_failed | complete
#   qa_round:        integer (0 = no QA yet)
#   qa_last_result:  pending | pass | fail
#   uat_round:       integer (0 = no UAT yet)
#   uat_last_result: pending | pass | issues_found
#
# Active pointer: <planning-dir>/debugging/.active-session (contains session filename)
# Session files:  <planning-dir>/debugging/{YYYYMMDD-HHMMSS}-{slug}.md

set -euo pipefail

CMD="${1:-}"
PLANNING_DIR="${2:-}"

if [ -z "$CMD" ] || [ -z "$PLANNING_DIR" ]; then
  echo "Usage: debug-session-state.sh <command> <planning-dir> [args...]" >&2
  exit 1
fi

DEBUG_DIR="$PLANNING_DIR/debugging"
ACTIVE_FILE="$DEBUG_DIR/.active-session"

# Valid status values
VALID_STATUSES="investigating fix_applied qa_pending qa_failed uat_pending uat_failed complete"

validate_status() {
  local s="$1"
  for v in $VALID_STATUSES; do
    [ "$s" = "$v" ] && return 0
  done
  echo "Error: invalid status '$s'. Valid: $VALID_STATUSES" >&2
  return 1
}

# Read frontmatter field from a session file
read_field() {
  local file="$1" field="$2"
  sed -n '/^---$/,/^---$/p' "$file" | grep "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//"
}

# Update frontmatter field in a session file
update_field() {
  local file="$1" field="$2" value="$3"
  if grep -q "^${field}:" "$file" 2>/dev/null; then
    sed -i '' "s/^${field}:.*/${field}: ${value}/" "$file"
  fi
  # Always update the 'updated' timestamp
  if [ "$field" != "updated" ]; then
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    sed -i '' "s/^updated:.*/updated: ${now}/" "$file"
  fi
}

# Get active session file path (returns empty if none/stale)
get_active_session_path() {
  if [ ! -f "$ACTIVE_FILE" ]; then
    return
  fi
  local session_name
  session_name=$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '[:space:]')
  if [ -z "$session_name" ]; then
    return
  fi
  local session_path="$DEBUG_DIR/$session_name"
  if [ -f "$session_path" ]; then
    echo "$session_path"
  fi
  # Stale pointer — file doesn't exist
}

# Find latest unresolved session (status != complete)
find_latest_unresolved() {
  if [ ! -d "$DEBUG_DIR" ]; then
    return
  fi
  # Collect files into array, sort reverse by name (which contains timestamp)
  local files=() f
  for f in "$DEBUG_DIR"/*.md; do
    [ -f "$f" ] && files+=("$f")
  done
  # Sort reverse: iterate from end of sorted array
  local i status
  for (( i=${#files[@]}-1; i>=0; i-- )); do
    f="${files[$i]}"
    status=$(read_field "$f" "status")
    if [ "$status" != "complete" ]; then
      echo "$f"
      return
    fi
  done
}

print_session_metadata() {
  local session_path="$1"
  local session_name
  session_name=$(basename "$session_path")
  local session_id="${session_name%.md}"
  printf 'session_id=%q\n' "$session_id"
  printf 'session_file=%q\n' "$session_path"
  printf 'status=%q\n' "$(read_field "$session_path" "status")"
  printf 'title=%q\n' "$(read_field "$session_path" "title")"
  printf 'qa_round=%q\n' "$(read_field "$session_path" "qa_round")"
  printf 'qa_last_result=%q\n' "$(read_field "$session_path" "qa_last_result")"
  printf 'uat_round=%q\n' "$(read_field "$session_path" "uat_round")"
  printf 'uat_last_result=%q\n' "$(read_field "$session_path" "uat_last_result")"
  printf 'created=%q\n' "$(read_field "$session_path" "created")"
  printf 'updated=%q\n' "$(read_field "$session_path" "updated")"
}

case "$CMD" in
  start)
    SLUG="${3:-}"
    if [ -z "$SLUG" ]; then
      echo "Usage: debug-session-state.sh start <planning-dir> <slug>" >&2
      exit 1
    fi
    # Sanitize slug: lowercase, replace spaces/special chars with dashes
    SLUG=$(printf '%s' "$SLUG" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 50)
    if [ -z "$SLUG" ]; then
      SLUG="debug"
    fi

    mkdir -p "$DEBUG_DIR"
    TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    SESSION_ID="${TIMESTAMP}-${SLUG}"
    SESSION_FILE="$DEBUG_DIR/${SESSION_ID}.md"
    NOW=$(date '+%Y-%m-%d %H:%M:%S')

    # Check for collision (extremely unlikely with second-precision timestamps)
    if [ -f "$SESSION_FILE" ]; then
      echo "Error: session file already exists: $SESSION_FILE" >&2
      exit 1
    fi

    cat > "$SESSION_FILE" << ENDSESSION
---
session_id: ${SESSION_ID}
title: ${SLUG}
status: investigating
created: ${NOW}
updated: ${NOW}
qa_round: 0
qa_last_result: pending
uat_round: 0
uat_last_result: pending
---

# Debug Session: ${SLUG}

## Issue

{Bug description pending from Debugger investigation.}

## Investigation

## Plan

## Implementation

### Changed Files

### Commit

## QA

## UAT
ENDSESSION

    # Set active pointer
    echo "${SESSION_ID}.md" > "$ACTIVE_FILE"

    echo "session_id=$SESSION_ID"
    echo "session_file=$SESSION_FILE"
    ;;

  get)
    SESSION_PATH=$(get_active_session_path)
    if [ -z "$SESSION_PATH" ]; then
      echo "active_session=none"
      exit 0
    fi
    echo "active_session=true"
    print_session_metadata "$SESSION_PATH"
    ;;

  get-or-latest)
    SESSION_PATH=$(get_active_session_path)
    if [ -z "$SESSION_PATH" ]; then
      # Stale or missing pointer — try latest unresolved
      SESSION_PATH=$(find_latest_unresolved)
      if [ -z "$SESSION_PATH" ]; then
        echo "active_session=none"
        exit 0
      fi
      echo "active_session=fallback"
      # Update the pointer to this session
      echo "$(basename "$SESSION_PATH")" > "$ACTIVE_FILE"
    else
      echo "active_session=true"
    fi
    print_session_metadata "$SESSION_PATH"
    ;;

  resume)
    SESSION_ID="${3:-}"
    if [ -z "$SESSION_ID" ]; then
      echo "Usage: debug-session-state.sh resume <planning-dir> <session-id>" >&2
      exit 1
    fi
    # Accept with or without .md extension
    SESSION_NAME="$SESSION_ID"
    case "$SESSION_NAME" in
      *.md) ;;
      *) SESSION_NAME="${SESSION_NAME}.md" ;;
    esac
    SESSION_PATH="$DEBUG_DIR/$SESSION_NAME"
    if [ ! -f "$SESSION_PATH" ]; then
      echo "Error: session file not found: $SESSION_PATH" >&2
      exit 1
    fi
    echo "$SESSION_NAME" > "$ACTIVE_FILE"
    echo "active_session=true"
    print_session_metadata "$SESSION_PATH"
    ;;

  set-status)
    STATUS="${3:-}"
    if [ -z "$STATUS" ]; then
      echo "Usage: debug-session-state.sh set-status <planning-dir> <status>" >&2
      exit 1
    fi
    validate_status "$STATUS" || exit 1
    SESSION_PATH=$(get_active_session_path)
    if [ -z "$SESSION_PATH" ]; then
      echo "Error: no active debug session" >&2
      exit 1
    fi
    update_field "$SESSION_PATH" "status" "$STATUS"
    echo "status=$STATUS"
    echo "session_file=$SESSION_PATH"
    ;;

  increment-qa)
    SESSION_PATH=$(get_active_session_path)
    if [ -z "$SESSION_PATH" ]; then
      echo "Error: no active debug session" >&2
      exit 1
    fi
    CURRENT=$(read_field "$SESSION_PATH" "qa_round")
    NEW_ROUND=$(( ${CURRENT:-0} + 1 ))
    update_field "$SESSION_PATH" "qa_round" "$NEW_ROUND"
    update_field "$SESSION_PATH" "qa_last_result" "pending"
    echo "qa_round=$NEW_ROUND"
    ;;

  increment-uat)
    SESSION_PATH=$(get_active_session_path)
    if [ -z "$SESSION_PATH" ]; then
      echo "Error: no active debug session" >&2
      exit 1
    fi
    CURRENT=$(read_field "$SESSION_PATH" "uat_round")
    NEW_ROUND=$(( ${CURRENT:-0} + 1 ))
    update_field "$SESSION_PATH" "uat_round" "$NEW_ROUND"
    update_field "$SESSION_PATH" "uat_last_result" "pending"
    echo "uat_round=$NEW_ROUND"
    ;;

  clear-active)
    rm -f "$ACTIVE_FILE"
    echo "active_session=cleared"
    ;;

  list)
    if [ ! -d "$DEBUG_DIR" ]; then
      echo "no_sessions=true"
      exit 0
    fi
    COUNT=0
    for f in "$DEBUG_DIR"/*.md; do
      [ -f "$f" ] || continue
      local_id=$(read_field "$f" "session_id")
      local_status=$(read_field "$f" "status")
      local_title=$(read_field "$f" "title")
      echo "session=${local_id}|${local_status}|${local_title}"
      COUNT=$((COUNT + 1))
    done
    if [ "$COUNT" -eq 0 ]; then
      echo "no_sessions=true"
    fi
    echo "session_count=$COUNT"
    ;;

  *)
    echo "Error: unknown command '$CMD'" >&2
    echo "Commands: start, get, get-or-latest, resume, set-status, increment-qa, increment-uat, clear-active, list" >&2
    exit 1
    ;;
esac
