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
# Session files:  <planning-dir>/debugging/active/{YYYYMMDD-HHMMSS}-{slug}.md   (in-progress)
#                 <planning-dir>/debugging/completed/{YYYYMMDD-HHMMSS}-{slug}.md (finished)

set -euo pipefail

CMD="${1:-}"
PLANNING_DIR="${2:-}"

if [ -z "$CMD" ] || [ -z "$PLANNING_DIR" ]; then
  echo "Usage: debug-session-state.sh <command> <planning-dir> [args...]" >&2
  exit 1
fi

DEBUG_DIR="$PLANNING_DIR/debugging"
ACTIVE_DIR="$DEBUG_DIR/active"
COMPLETED_DIR="$DEBUG_DIR/completed"
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

# Read frontmatter field from a session file (awk-based, fail-open under pipefail)
read_field() {
  local file="$1" field="$2"
  awk -v field="$field" '
    /^---$/ { if (!started) { started=1; in_fm=1; next } if (in_fm) exit }
    in_fm && index($0, field ":") == 1 {
      val = substr($0, length(field) + 2)
      sub(/^[[:space:]]*/, "", val)
      print val
      exit
    }
  ' "$file"
}

# Update a frontmatter field in a session file, scoped to the YAML frontmatter block only.
# Uses awk to restrict replacement to lines between the opening and closing --- delimiters.
update_field() {
  local file="$1" field="$2" value="$3"
  if ! grep -q "^${field}:" "$file" 2>/dev/null; then
    # Field not present at all — skip
    if [ "$field" != "updated" ]; then
      local now
      now=$(date '+%Y-%m-%d %H:%M:%S')
      update_field "$file" "updated" "$now"
    fi
    return
  fi

  awk -v field="$field" -v value="$value" '
    BEGIN { in_fm = 0; delim = 0 }
    $0 == "---" {
      delim++
      if (delim == 1) in_fm = 1
      else if (delim == 2) in_fm = 0
      print; next
    }
    in_fm && $0 ~ ("^" field ":") {
      print field ": " value
      next
    }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

  # Always update the 'updated' timestamp
  if [ "$field" != "updated" ]; then
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    update_field "$file" "updated" "$now"
  fi
}

# Validate a session name is safe and well-formed.
# Expected format: {YYYYMMDD}-{HHMMSS}-{slug}.md (or basename without .md).
# Rejects path traversal, non-.md files, and names that don't match the timestamp-slug pattern.
validate_session_name() {
  local name="$1"
  # Strip .md suffix for pattern check (callers may pass with or without)
  local base="${name%.md}"
  case "$name" in
    */* | *..* | "")
      echo "Error: invalid session name (path traversal rejected): $name" >&2
      return 1 ;;
  esac
  # Must end in .md (or be the bare basename that will have .md appended)
  case "$name" in
    *.md) ;; # explicit .md — good
    *.*) # has a different extension
      echo "Error: invalid session name (must be .md): $name" >&2
      return 1 ;;
  esac
  # Must match YYYYMMDD-HHMMSS-slug pattern
  # shellcheck disable=SC2254
  case "$base" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-*) ;; # valid
    *)
      echo "Error: invalid session name (expected YYYYMMDD-HHMMSS-slug format): $name" >&2
      return 1 ;;
  esac
  return 0
}

# Safely move a session file to a target directory.
# Fails with an error if the destination already exists (prevents data loss from overwrites).
# Usage: safe_move_session <source_path> <target_dir>
# Echoes the new path on success.
safe_move_session() {
  local src="$1"
  local target_dir="$2"
  local fname
  fname=$(basename "$src")
  local dest="$target_dir/$fname"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "Error: destination already exists, refusing to overwrite: $dest" >&2
    return 1
  fi
  mkdir -p "$target_dir"
  mv "$src" "$dest"
  echo "$dest"
}

# Migrate a legacy flat-path session to the correct subdirectory based on its status.
# Moves complete sessions to completed/, all others to active/.
# Returns the new path. No-op if the file is already in a subdirectory.
migrate_legacy_session() {
  local file="$1"
  local dir
  dir=$(dirname "$file")
  # Only migrate files directly in DEBUG_DIR (not already in active/ or completed/)
  if [ "$dir" != "$DEBUG_DIR" ]; then
    echo "$file"
    return
  fi
  local fname
  fname=$(basename "$file")
  local file_status
  file_status=$(read_field "$file" "status")
  local target_dir
  if [ "$file_status" = "complete" ]; then
    target_dir="$COMPLETED_DIR"
  else
    target_dir="$ACTIVE_DIR"
  fi
  local new_path
  if ! new_path=$(safe_move_session "$file" "$target_dir"); then
    echo "$file"
    return 1
  fi
  # Update .active-session pointer if it referenced this file
  if [ -f "$ACTIVE_FILE" ]; then
    local pointer
    pointer=$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '[:space:]')
    if [ "$pointer" = "$fname" ]; then
      if [ "$file_status" = "complete" ]; then
        rm -f "$ACTIVE_FILE"
      fi
      # If not complete, pointer still valid — file is now in active/ and
      # get_active_session_path() will find it there
    fi
  fi
  echo "$new_path"
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
  if ! validate_session_name "$session_name"; then
    rm -f "$ACTIVE_FILE"  # Clear corrupted pointer
    return
  fi
  # Search active/ first (canonical location)
  local session_path="$ACTIVE_DIR/$session_name"
  if [ -f "$session_path" ] && [ ! -L "$session_path" ]; then
    # Self-heal: if active/ session has complete status, move to completed/
    local file_status
    file_status=$(read_field "$session_path" "status")
    if [ "$file_status" = "complete" ]; then
      safe_move_session "$session_path" "$COMPLETED_DIR" > /dev/null 2>&1 || true
      rm -f "$ACTIVE_FILE"
      return
    fi
    echo "$session_path"
    return
  fi
  # Check legacy flat location and migrate if found
  local legacy_path="$DEBUG_DIR/$session_name"
  if [ -f "$legacy_path" ] && [ ! -L "$legacy_path" ]; then
    local migrated
    if migrated=$(migrate_legacy_session "$legacy_path"); then
      # Only return path if it landed in active/ (completed sessions are not active)
      if [[ "$migrated" == "$ACTIVE_DIR/"* ]]; then
        echo "$migrated"
        return
      fi
      # Migrated to completed/ — fall through to clear stale pointer
    fi
    # Migration failed or session landed in completed/ — fall through
  fi
  # Check completed/ (session was completed but pointer not cleared)
  # Do not return completed/ path — completed sessions are not active.
  # Clear stale pointer so next call doesn't repeat the lookup.
  local completed_path="$COMPLETED_DIR/$session_name"
  if [ -f "$completed_path" ] && [ ! -L "$completed_path" ]; then
    rm -f "$ACTIVE_FILE"
    return
  fi
  # Stale pointer, missing, failed migration, or symlink — do not follow.
  # Clear the unresolved pointer so future commands can recover cleanly.
  rm -f "$ACTIVE_FILE"
}

# Find latest unresolved session (status != complete)
find_latest_unresolved() {
  if [ ! -d "$DEBUG_DIR" ]; then
    return
  fi
  # Migrate any legacy flat-path sessions first
  local legacy_f
  for legacy_f in "$DEBUG_DIR"/*.md; do
    [ -f "$legacy_f" ] && [ ! -L "$legacy_f" ] || continue
    if ! migrate_legacy_session "$legacy_f" > /dev/null 2>&1; then
      # Collision? If the blocking file in active/ is complete, resolve it
      local collision_file
      collision_file="$ACTIVE_DIR/$(basename "$legacy_f")"
      if [ -f "$collision_file" ] && [ "$(read_field "$collision_file" "status")" = "complete" ]; then
        safe_move_session "$collision_file" "$COMPLETED_DIR" > /dev/null 2>&1 || true
        # Retry migration now that collision is cleared
        if ! migrate_legacy_session "$legacy_f" > /dev/null 2>&1; then
          echo "Warning: could not migrate legacy session $(basename "$legacy_f")" >&2
        fi
      else
        echo "Warning: could not migrate legacy session $(basename "$legacy_f")" >&2
      fi
    fi
  done
  # Collect candidates from active/ and any unmigrated legacy files
  local all_candidates=() f
  if [ -d "$ACTIVE_DIR" ]; then
    for f in "$ACTIVE_DIR"/*.md; do
      [ -f "$f" ] && [ ! -L "$f" ] && all_candidates+=("$f")
    done
  fi
  for legacy_f in "$DEBUG_DIR"/*.md; do
    [ -f "$legacy_f" ] && [ ! -L "$legacy_f" ] || continue
    all_candidates+=("$legacy_f")
  done
  # Sort all candidates by basename (timestamp-based filename) for correct ordering
  local files=()
  if [ ${#all_candidates[@]} -gt 0 ]; then
    while IFS=$'\t' read -r _ path; do
      [ -n "$path" ] && files+=("$path")
    done < <(for c in "${all_candidates[@]}"; do printf '%s\t%s\n' "$(basename "$c")" "$c"; done | LC_ALL=C sort -t$'\t' -k1,1)
  fi
  # Iterate from end (latest timestamp first) to find latest unresolved
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

    mkdir -p "$ACTIVE_DIR"
    TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    SESSION_ID="${TIMESTAMP}-${SLUG}"
    SESSION_FILE="$ACTIVE_DIR/${SESSION_ID}.md"
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

### Hypotheses

### Root Cause

## Plan

## Implementation

### Changed Files

### Commit

## QA

## UAT

## Remediation History
ENDSESSION

    # Set active pointer
    echo "${SESSION_ID}.md" > "$ACTIVE_FILE"

    printf 'session_id=%q\n' "$SESSION_ID"
    printf 'session_file=%q\n' "$SESSION_FILE"
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
    validate_session_name "$SESSION_NAME" || exit 1
    case "$SESSION_NAME" in
      *.md) ;;
      *) SESSION_NAME="${SESSION_NAME}.md" ;;
    esac
    SESSION_PATH="$ACTIVE_DIR/$SESSION_NAME"
    # Search active/ first, then completed/, then legacy flat dir
    if [ ! -f "$SESSION_PATH" ]; then
      SESSION_PATH="$COMPLETED_DIR/$SESSION_NAME"
    fi
    if [ ! -f "$SESSION_PATH" ]; then
      # Check legacy flat location and migrate
      legacy_path="$DEBUG_DIR/$SESSION_NAME"
      if [ -f "$legacy_path" ] && [ ! -L "$legacy_path" ]; then
        if ! SESSION_PATH=$(migrate_legacy_session "$legacy_path"); then
          echo "Error: could not migrate legacy session: $SESSION_NAME" >&2
          exit 1
        fi
      else
        SESSION_PATH=""
      fi
    fi
    if [ -z "$SESSION_PATH" ] || [ ! -f "$SESSION_PATH" ]; then
      echo "Error: session file not found: $SESSION_NAME" >&2
      exit 1
    fi
    if [ -L "$SESSION_PATH" ]; then
      echo "Error: refusing to resume symlink session file: $SESSION_PATH" >&2
      exit 1
    fi
    # If found in completed/, move back to active/ (re-activating)
    if [[ "$SESSION_PATH" == "$COMPLETED_DIR/"* ]]; then
      SESSION_PATH=$(safe_move_session "$SESSION_PATH" "$ACTIVE_DIR") || exit 1
      update_field "$SESSION_PATH" "status" "investigating"
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
    # Auto-move to completed/ when status transitions to complete
    if [ "$STATUS" = "complete" ]; then
      fname=$(basename "$SESSION_PATH")
      current_dir=$(dirname "$SESSION_PATH")
      if [ "$current_dir" != "$COMPLETED_DIR" ]; then
        SESSION_PATH=$(safe_move_session "$SESSION_PATH" "$COMPLETED_DIR") || exit 1
      fi
      # Clear active pointer if it references this session
      if [ -f "$ACTIVE_FILE" ]; then
        pointer=$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '[:space:]')
        if [ "$pointer" = "$fname" ]; then
          rm -f "$ACTIVE_FILE"
        fi
      fi
    fi
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
    # Migrate legacy flat-path sessions first
    for f in "$DEBUG_DIR"/*.md; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      if ! migrate_legacy_session "$f" > /dev/null 2>&1; then
        # Collision? If the blocking file in active/ is complete, resolve it
        _collision_file="$ACTIVE_DIR/$(basename "$f")"
        if [ -f "$_collision_file" ] && [ "$(read_field "$_collision_file" "status")" = "complete" ]; then
          safe_move_session "$_collision_file" "$COMPLETED_DIR" > /dev/null 2>&1 || true
          if ! migrate_legacy_session "$f" > /dev/null 2>&1; then
            echo "Warning: could not migrate legacy session $(basename "$f")" >&2
          fi
        else
          echo "Warning: could not migrate legacy session $(basename "$f")" >&2
        fi
      fi
    done
    COUNT=0
    HEALED_FILES=""
    # List active sessions
    if [ -d "$ACTIVE_DIR" ]; then
      for f in "$ACTIVE_DIR"/*.md; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        local_id=$(read_field "$f" "session_id")
        local_status=$(read_field "$f" "status")
        local_title=$(read_field "$f" "title")
        # Self-heal: if active/ session has complete status, move to completed/
        if [ "$local_status" = "complete" ]; then
          local_fname=$(basename "$f")
          heal_location="active"
          if safe_move_session "$f" "$COMPLETED_DIR" > /dev/null 2>&1; then
            HEALED_FILES="${HEALED_FILES}${local_fname}:"
            heal_location="completed"
          fi
          if [ -f "$ACTIVE_FILE" ]; then
            pointer=$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '[:space:]')
            if [ "$pointer" = "$local_fname" ]; then
              rm -f "$ACTIVE_FILE"
            fi
          fi
          echo "session=${local_id}|${local_status}|${local_title}|${heal_location}"
          COUNT=$((COUNT + 1))
          continue
        fi
        echo "session=${local_id}|${local_status}|${local_title}|active"
        COUNT=$((COUNT + 1))
      done
    fi
    # List completed sessions
    if [ -d "$COMPLETED_DIR" ]; then
      for f in "$COMPLETED_DIR"/*.md; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        # Skip files already counted during self-heal from active/
        local_fname=$(basename "$f")
        if [ -n "$HEALED_FILES" ] && printf '%s' "$HEALED_FILES" | grep -qF "${local_fname}:"; then
          continue
        fi
        local_id=$(read_field "$f" "session_id")
        local_status=$(read_field "$f" "status")
        local_title=$(read_field "$f" "title")
        echo "session=${local_id}|${local_status}|${local_title}|completed"
        COUNT=$((COUNT + 1))
      done
    fi
    # Include any legacy files that couldn't be migrated (destination collision)
    for f in "$DEBUG_DIR"/*.md; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      local_id=$(read_field "$f" "session_id")
      local_status=$(read_field "$f" "status")
      local_title=$(read_field "$f" "title")
      local_location="active"
      if [ "$local_status" = "complete" ]; then
        local_location="completed"
      fi
      echo "session=${local_id}|${local_status}|${local_title}|${local_location}"
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
