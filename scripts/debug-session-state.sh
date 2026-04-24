#!/usr/bin/env bash
# debug-session-state.sh — Manage standalone debug session lifecycle.
#
# Usage:
#   debug-session-state.sh start           <planning-dir> <slug>         → creates session, prints session_id
#   debug-session-state.sh start-with-source-todo <planning-dir> <slug>  → creates session, writes Source Todo from stdin, rolls back on failure
#   debug-session-state.sh start-with-selected-todo <planning-dir> <slug> <detail-status>
#                                                               → creates session from selected todo JSON + detail helper output
#   debug-session-state.sh get             <planning-dir>                → prints active session metadata
#   debug-session-state.sh get-or-latest   <planning-dir>                → active session or latest unresolved
#   debug-session-state.sh resume          <planning-dir> <session-id>   → resumes unresolved session or returns completed-session metadata without reopening
#   debug-session-state.sh set-status      <planning-dir> <status>       → updates status field
#   debug-session-state.sh increment-qa    <planning-dir>                → bumps qa_round, sets qa_last_result=pending
#   debug-session-state.sh increment-uat   <planning-dir>                → bumps uat_round, sets uat_last_result=pending
#   debug-session-state.sh clear-active    <planning-dir>                → removes active pointer
#   debug-session-state.sh list            <planning-dir>                → lists all sessions with status
#
# State fields in frontmatter:
#   status:          investigating | fix_applied | qa_pending | qa_failed | uat_pending | uat_failed | complete
#   qa_round:        integer (0 = no QA yet)
#   qa_last_result:  pending | skipped_no_fix_required | pass | fail
#   uat_round:       integer (0 = no UAT yet)
#   uat_last_result: pending | skipped_no_fix_required | pass | issues_found
#
# Active pointer: <planning-dir>/debugging/.active-session (contains session filename)
# Session files:  <planning-dir>/debugging/active/{YYYYMMDD-HHMMSS}-{slug}.md   (in-progress)
#                 <planning-dir>/debugging/completed/{YYYYMMDD-HHMMSS}-{slug}.md (finished)

set -euo pipefail

CMD="${1:-}"
PLANNING_DIR="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$CMD" ] || [ -z "$PLANNING_DIR" ]; then
  echo "Usage: debug-session-state.sh <command> <planning-dir> [args...]" >&2
  exit 1
fi

DEBUG_DIR="$PLANNING_DIR/debugging"
ACTIVE_DIR="$DEBUG_DIR/active"
COMPLETED_DIR="$DEBUG_DIR/completed"
ACTIVE_FILE="$DEBUG_DIR/.active-session"
SKIPPED_NO_FIX_REQUIRED="skipped_no_fix_required"

# Valid status values
VALID_STATUSES="investigating fix_applied qa_pending qa_failed uat_pending uat_failed complete"
VALID_DETAIL_STATUSES="ok not_found error none"

validate_status() {
  local s="$1"
  for v in $VALID_STATUSES; do
    [ "$s" = "$v" ] && return 0
  done
  echo "Error: invalid status '$s'. Valid: $VALID_STATUSES" >&2
  return 1
}

validate_detail_status() {
  local s="$1"
  for v in $VALID_DETAIL_STATUSES; do
    [ "$s" = "$v" ] && return 0
  done
  echo "Error: invalid detail status '$s'. Valid: $VALID_DETAIL_STATUSES" >&2
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

DEBUG_SESSION_INSPECT_STATUS=""
DEBUG_SESSION_INSPECT_QA_ROUND=""
DEBUG_SESSION_INSPECT_UAT_ROUND=""
DEBUG_SESSION_INSPECT_QA_LAST_RESULT=""
DEBUG_SESSION_INSPECT_UAT_LAST_RESULT=""

inspect_normalization_fields() {
  local file="$1"
  local old_ifs="$IFS"

  IFS=$'\t' read -r \
    DEBUG_SESSION_INSPECT_STATUS \
    DEBUG_SESSION_INSPECT_QA_ROUND \
    DEBUG_SESSION_INSPECT_UAT_ROUND \
    DEBUG_SESSION_INSPECT_QA_LAST_RESULT \
    DEBUG_SESSION_INSPECT_UAT_LAST_RESULT <<EOF
$(awk '
  BEGIN {
    in_fm = 0
    delim = 0
    status = ""
    qa_round = ""
    uat_round = ""
    qa_last_result = ""
    uat_last_result = ""
  }
  $0 == "---" {
    delim++
    if (delim == 1) {
      in_fm = 1
      next
    }
    if (delim == 2) {
      exit
    }
  }
  !in_fm { next }
  /^status:[[:space:]]*/ {
    value = $0
    sub(/^status:[[:space:]]*/, "", value)
    status = value
    next
  }
  /^qa_round:[[:space:]]*/ {
    value = $0
    sub(/^qa_round:[[:space:]]*/, "", value)
    qa_round = value
    next
  }
  /^uat_round:[[:space:]]*/ {
    value = $0
    sub(/^uat_round:[[:space:]]*/, "", value)
    uat_round = value
    next
  }
  /^qa_last_result:[[:space:]]*/ {
    value = $0
    sub(/^qa_last_result:[[:space:]]*/, "", value)
    qa_last_result = value
    next
  }
  /^uat_last_result:[[:space:]]*/ {
    value = $0
    sub(/^uat_last_result:[[:space:]]*/, "", value)
    uat_last_result = value
    next
  }
  END {
    printf "%s\t%s\t%s\t%s\t%s\n", status, qa_round, uat_round, qa_last_result, uat_last_result
  }
' "$file")
EOF

  IFS="$old_ifs"
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

# Normalize terminal metadata for completed standalone debug sessions that never ran QA/UAT.
# This is intentionally idempotent: it only rewrites sessions that are complete,
# still have zero QA/UAT rounds, and still carry the template-default pending results.
normalize_completed_no_verification_results() {
  local file="$1"
  local fields_state="${2:-}"
  [ -f "$file" ] && [ ! -L "$file" ] || return 1

  local file_status qa_round uat_round qa_last_result uat_last_result now
  if [ "$fields_state" != "preloaded" ]; then
    inspect_normalization_fields "$file" || return 1
  fi
  file_status="$DEBUG_SESSION_INSPECT_STATUS"
  qa_round="$DEBUG_SESSION_INSPECT_QA_ROUND"
  uat_round="$DEBUG_SESSION_INSPECT_UAT_ROUND"
  qa_last_result="$DEBUG_SESSION_INSPECT_QA_LAST_RESULT"
  uat_last_result="$DEBUG_SESSION_INSPECT_UAT_LAST_RESULT"

  if [ "$file_status" != "complete" ] \
    || [ "${qa_round:-0}" != "0" ] \
    || [ "${uat_round:-0}" != "0" ] \
    || [ "$qa_last_result" != "pending" ] \
    || [ "$uat_last_result" != "pending" ]; then
    return 0
  fi

  now=$(date '+%Y-%m-%d %H:%M:%S')
  awk -v skipped="$SKIPPED_NO_FIX_REQUIRED" -v now="$now" '
    BEGIN { in_fm = 0; delim = 0 }
    $0 == "---" {
      delim++
      if (delim == 1) in_fm = 1
      else if (delim == 2) in_fm = 0
      print
      next
    }
    in_fm && /^qa_last_result:/ {
      print "qa_last_result: " skipped
      next
    }
    in_fm && /^uat_last_result:/ {
      print "uat_last_result: " skipped
      next
    }
    in_fm && /^updated:/ {
      print "updated: " now
      next
    }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

  DEBUG_SESSION_INSPECT_QA_LAST_RESULT="$SKIPPED_NO_FIX_REQUIRED"
  DEBUG_SESSION_INSPECT_UAT_LAST_RESULT="$SKIPPED_NO_FIX_REQUIRED"
}

# Reconcile a session's physical location with its frontmatter status.
# - complete sessions belong in completed/
# - all other statuses belong in active/
# Echoes the canonicalized path on success.
reconcile_session_location() {
  local file="$1"
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  inspect_normalization_fields "$file" || return 1
  normalize_completed_no_verification_results "$file" preloaded || return 1

  local file_status target_dir current_dir fname moved pointer collision_file
  file_status="$DEBUG_SESSION_INSPECT_STATUS"
  if [ "$file_status" = "complete" ]; then
    target_dir="$COMPLETED_DIR"
  else
    target_dir="$ACTIVE_DIR"
  fi

  current_dir=$(dirname "$file")
  if [ "$current_dir" = "$target_dir" ]; then
    echo "$file"
    return 0
  fi

  fname=$(basename "$file")
  if moved=$(safe_move_session "$file" "$target_dir" 2>/dev/null); then
    echo "$moved"
    return 0
  fi

  if [ "$target_dir" = "$ACTIVE_DIR" ]; then
    collision_file="$ACTIVE_DIR/$fname"
    if [ -f "$collision_file" ] && [ ! -L "$collision_file" ] && [ "$(read_field "$collision_file" "status")" = "complete" ]; then
      if safe_move_session "$collision_file" "$COMPLETED_DIR" > /dev/null 2>&1; then
        if [ -f "$ACTIVE_FILE" ]; then
          pointer=$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '[:space:]')
          if [ "$pointer" = "$fname" ]; then
            rm -f "$ACTIVE_FILE"
          fi
        fi
        if moved=$(safe_move_session "$file" "$target_dir" 2>/dev/null); then
          echo "$moved"
          return 0
        fi
      fi
    fi
  fi

  return 1
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
  inspect_normalization_fields "$file" || return 1
  normalize_completed_no_verification_results "$file" preloaded || return 1
  local fname
  fname=$(basename "$file")
  local file_status
  file_status="$DEBUG_SESSION_INSPECT_STATUS"
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
    local reconciled
    if reconciled=$(reconcile_session_location "$session_path"); then
      if [[ "$reconciled" == "$ACTIVE_DIR/"* ]]; then
        echo "$reconciled"
        return
      fi
      rm -f "$ACTIVE_FILE"
      return
    fi
    rm -f "$ACTIVE_FILE"
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
  local completed_path="$COMPLETED_DIR/$session_name"
  if [ -f "$completed_path" ] && [ ! -L "$completed_path" ]; then
    local reconciled
    if reconciled=$(reconcile_session_location "$completed_path"); then
      if [[ "$reconciled" == "$ACTIVE_DIR/"* ]]; then
        echo "$reconciled"
        return
      fi
    fi
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
      if [ -f "$collision_file" ] && [ ! -L "$collision_file" ] && [ "$(read_field "$collision_file" "status")" = "complete" ]; then
        if safe_move_session "$collision_file" "$COMPLETED_DIR" > /dev/null 2>&1; then
          # Clear stale pointer if it referenced the moved file
          if [ -f "$ACTIVE_FILE" ] && [ "$(tr -d '[:space:]' < "$ACTIVE_FILE")" = "$(basename "$collision_file")" ]; then
            rm -f "$ACTIVE_FILE"
          fi
        fi
        # Retry migration now that collision is cleared
        if ! migrate_legacy_session "$legacy_f" > /dev/null 2>&1; then
          echo "Warning: could not migrate legacy session $(basename "$legacy_f")" >&2
        fi
      else
        echo "Warning: could not migrate legacy session $(basename "$legacy_f")" >&2
      fi
    fi
  done
  # Self-heal canonical active/completed placement before selecting candidates.
  if [ -d "$ACTIVE_DIR" ]; then
    for f in "$ACTIVE_DIR"/*.md; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      reconcile_session_location "$f" > /dev/null 2>&1 || true
    done
  fi
  if [ -d "$COMPLETED_DIR" ]; then
    for f in "$COMPLETED_DIR"/*.md; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      reconcile_session_location "$f" > /dev/null 2>&1 || true
    done
  fi
  # Collect candidates from active/ and any unmigrated legacy files
  local all_candidates=() f
  if [ -d "$ACTIVE_DIR" ]; then
    for f in "$ACTIVE_DIR"/*.md; do
      [ -f "$f" ] && [ ! -L "$f" ] && all_candidates+=("$f")
    done
  fi
  for legacy_f in "$DEBUG_DIR"/*.md; do
    [ -f "$legacy_f" ] && [ ! -L "$legacy_f" ] || continue
    # Skip if active/ already has a non-symlink file with this basename —
    # that file was already considered in the active/ scan above and is canonical.
    local _active_dup
    _active_dup="$ACTIVE_DIR/$(basename "$legacy_f")"
    if [ -f "$_active_dup" ] && [ ! -L "$_active_dup" ]; then
      continue
    fi
    all_candidates+=("$legacy_f")
  done
  # Sort all candidates by basename (timestamp-based filename) for correct ordering
  local files=() _basename path
  if [ ${#all_candidates[@]} -gt 0 ]; then
    while IFS=$'\t' read -r _basename path; do
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
  printf 'session_status=%q\n' "$(read_field "$session_path" "status")"
  printf 'title=%q\n' "$(read_field "$session_path" "title")"
  printf 'qa_round=%q\n' "$(read_field "$session_path" "qa_round")"
  printf 'qa_last_result=%q\n' "$(read_field "$session_path" "qa_last_result")"
  printf 'uat_round=%q\n' "$(read_field "$session_path" "uat_round")"
  printf 'uat_last_result=%q\n' "$(read_field "$session_path" "uat_last_result")"
  printf 'created=%q\n' "$(read_field "$session_path" "created")"
  printf 'updated=%q\n' "$(read_field "$session_path" "updated")"
}

create_session() {
  local slug_input="$1"
  local slug_sanitized timestamp now session_id session_file

  slug_sanitized=$(printf '%s' "$slug_input" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 50)
  if [ -z "$slug_sanitized" ]; then
    slug_sanitized="debug"
  fi

  mkdir -p "$ACTIVE_DIR"
  timestamp=$(date '+%Y%m%d-%H%M%S')
  session_id="${timestamp}-${slug_sanitized}"
  session_file="$ACTIVE_DIR/${session_id}.md"
  now=$(date '+%Y-%m-%d %H:%M:%S')

  if [ -f "$session_file" ]; then
    echo "Error: session file already exists: $session_file" >&2
    return 1
  fi

  cat > "$session_file" << ENDSESSION
---
session_id: ${session_id}
title: ${slug_sanitized}
status: investigating
created: ${now}
updated: ${now}
qa_round: 0
qa_last_result: pending
uat_round: 0
uat_last_result: pending
---

# Debug Session: ${slug_sanitized}

## Issue

{Bug description pending from Debugger investigation.}

## Source Todo

### Selected Todo

- **Text:** none
- **Raw Line:** none
- **Ref:** none
- **Detail Status:** none

### Related Files

None recorded.

### Detail Context

No persisted detail context.

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

  echo "${session_id}.md" > "$ACTIVE_FILE"

  printf 'session_id=%q\n' "$session_id"
  printf 'session_file=%q\n' "$session_file"
}

build_source_todo_from_selected() {
  local detail_status="$1"
  local selected_json detail_result_json text raw_line ref related_files detail_context detail_result_status

  validate_detail_status "$detail_status" || return 1

  selected_json=$(cat)
  if ! printf '%s' "$selected_json" | jq empty >/dev/null 2>&1; then
    echo "Error: invalid selected todo JSON" >&2
    return 1
  fi

  detail_result_json="${TODO_DETAIL_RESULT_JSON:-}"
  if [ -n "$detail_result_json" ] && ! printf '%s' "$detail_result_json" | jq empty >/dev/null 2>&1; then
    echo "Error: invalid TODO_DETAIL_RESULT_JSON payload" >&2
    return 1
  fi

  text=$(printf '%s' "$selected_json" | jq -r '.command_text // .normalized_text // .text // "none"')
  raw_line=$(printf '%s' "$selected_json" | jq -r '.line // .text // "none"')
  ref=$(printf '%s' "$selected_json" | jq -r '.ref // "none"')
  related_files='[]'
  detail_context=''

  if [ "$detail_status" = "ok" ]; then
    if [ -z "$detail_result_json" ]; then
      echo "Error: detail status ok requires TODO_DETAIL_RESULT_JSON" >&2
      return 1
    fi

    detail_result_status=$(printf '%s' "$detail_result_json" | jq -r '.status // empty')
    if [ "$detail_result_status" != "ok" ]; then
      echo "Error: detail status ok requires todo-details.sh get output with status=ok" >&2
      return 1
    fi

    related_files=$(printf '%s' "$detail_result_json" | jq -c '(.detail.files // []) | if type == "array" then . else [] end')
    detail_context=$(printf '%s' "$detail_result_json" | jq -r '.detail.context // empty')
  fi

  jq -cn \
    --arg mode "source-todo" \
    --arg text "$text" \
    --arg raw_line "$raw_line" \
    --arg ref "$ref" \
    --arg detail_status "$detail_status" \
    --argjson related_files "$related_files" \
    --arg detail_context "$detail_context" \
    '{mode:$mode, text:$text, raw_line:$raw_line, ref:$ref, detail_status:$detail_status, related_files:$related_files, detail_context:$detail_context}'
}

start_with_source_todo() {
  local slug_input="$1"
  local source_todo_json session_output session_id session_file previous_active_pointer had_previous_pointer=0
  source_todo_json=$(cat)

  previous_active_pointer=""
  if [ -f "$ACTIVE_FILE" ]; then
    previous_active_pointer=$(cat "$ACTIVE_FILE" 2>/dev/null || true)
    had_previous_pointer=1
  fi

  if ! session_output=$(create_session "$slug_input"); then
    return 1
  fi

  eval "$session_output"

  if ! printf '%s' "$source_todo_json" | bash "$SCRIPT_DIR/write-debug-session.sh" "$session_file" >/dev/null; then
    rm -f "$session_file"
    if [ "$had_previous_pointer" -eq 1 ]; then
      printf '%s\n' "$previous_active_pointer" > "$ACTIVE_FILE"
    else
      rm -f "$ACTIVE_FILE"
    fi
    echo "Error: failed to persist Source Todo for new debug session" >&2
    return 1
  fi

  printf '%s\n' "$session_output"
}

start_with_selected_todo() {
  local slug_input="$1"
  local detail_status="${2:-none}"
  local selected_json source_todo_json

  validate_detail_status "$detail_status" || return 1

  selected_json=$(cat)
  if ! source_todo_json=$(build_source_todo_from_selected "$detail_status" <<< "$selected_json"); then
    return 1
  fi

  printf '%s' "$source_todo_json" | start_with_source_todo "$slug_input"
}

case "$CMD" in
  start)
    SLUG="${3:-}"
    if [ -z "$SLUG" ]; then
      echo "Usage: debug-session-state.sh start <planning-dir> <slug>" >&2
      exit 1
    fi
    create_session "$SLUG"
    ;;

  start-with-source-todo)
    SLUG="${3:-}"
    if [ -z "$SLUG" ]; then
      echo "Usage: debug-session-state.sh start-with-source-todo <planning-dir> <slug>" >&2
      exit 1
    fi
    start_with_source_todo "$SLUG"
    ;;

  start-with-selected-todo)
    SLUG="${3:-}"
    DETAIL_STATUS="${4:-none}"
    if [ -z "$SLUG" ]; then
      echo "Usage: debug-session-state.sh start-with-selected-todo <planning-dir> <slug> <detail-status>" >&2
      exit 1
    fi
    start_with_selected_todo "$SLUG" "$DETAIL_STATUS"
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
      basename "$SESSION_PATH" > "$ACTIVE_FILE"
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
    SESSION_PATH=$(reconcile_session_location "$SESSION_PATH") || exit 1
    session_file_status=$(read_field "$SESSION_PATH" "status")
    # Explicit targeting of a completed session is metadata-only: preserve the
    # terminal lifecycle state so the command layer can stop cleanly instead of
    # silently reopening the investigation.
    if [ "$session_file_status" = "complete" ]; then
      if [ -f "$ACTIVE_FILE" ]; then
        pointer=$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '[:space:]')
        if [ "$pointer" = "$SESSION_NAME" ]; then
          rm -f "$ACTIVE_FILE"
        fi
      fi
    else
      echo "$SESSION_NAME" > "$ACTIVE_FILE"
    fi
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
      normalize_completed_no_verification_results "$SESSION_PATH" || exit 1
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
        if [ -f "$_collision_file" ] && [ ! -L "$_collision_file" ] && [ "$(read_field "$_collision_file" "status")" = "complete" ]; then
          if safe_move_session "$_collision_file" "$COMPLETED_DIR" > /dev/null 2>&1; then
            # Clear stale pointer if it referenced the moved file
            if [ -f "$ACTIVE_FILE" ] && [ "$(tr -d '[:space:]' < "$ACTIVE_FILE")" = "$(basename "$_collision_file")" ]; then
              rm -f "$ACTIVE_FILE"
            fi
          fi
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
        reconciled="$f"
        if reconciled=$(reconcile_session_location "$f"); then
          if [[ "$reconciled" == "$COMPLETED_DIR/"* ]]; then
            local_fname=$(basename "$reconciled")
            HEALED_FILES="${HEALED_FILES}${local_fname}:"
            local_id=$(read_field "$reconciled" "session_id")
            local_status=$(read_field "$reconciled" "status")
            local_title=$(read_field "$reconciled" "title")
            echo "session=${local_id}|${local_status}|${local_title}|completed"
            COUNT=$((COUNT + 1))
            continue
          fi
        fi
        local_id=$(read_field "$reconciled" "session_id")
        local_status=$(read_field "$reconciled" "status")
        local_title=$(read_field "$reconciled" "title")
        echo "session=${local_id}|${local_status}|${local_title}|active"
        COUNT=$((COUNT + 1))
      done
    fi
    # List completed sessions
    if [ -d "$COMPLETED_DIR" ]; then
      for f in "$COMPLETED_DIR"/*.md; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        reconciled="$f"
        if reconciled=$(reconcile_session_location "$f"); then
          if [[ "$reconciled" == "$ACTIVE_DIR/"* ]]; then
            local_id=$(read_field "$reconciled" "session_id")
            local_status=$(read_field "$reconciled" "status")
            local_title=$(read_field "$reconciled" "title")
            echo "session=${local_id}|${local_status}|${local_title}|active"
            COUNT=$((COUNT + 1))
            continue
          fi
        fi
        # Skip files already counted during self-heal from active/
        local_fname=$(basename "$reconciled")
        if [ -n "$HEALED_FILES" ] && printf '%s' "$HEALED_FILES" | grep -qF "${local_fname}:"; then
          continue
        fi
        local_id=$(read_field "$reconciled" "session_id")
        local_status=$(read_field "$reconciled" "status")
        local_title=$(read_field "$reconciled" "title")
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
    echo "Commands: start, start-with-source-todo, start-with-selected-todo, get, get-or-latest, resume, set-status, increment-qa, increment-uat, clear-active, list" >&2
    exit 1
    ;;
esac
