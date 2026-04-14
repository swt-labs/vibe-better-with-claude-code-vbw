#!/usr/bin/env bash
# research-session-state.sh — Manage standalone research session lifecycle.
#
# Usage:
#   research-session-state.sh start     <planning-dir> <slug>       → creates session, prints session_id + file
#   research-session-state.sh complete  <planning-dir> <session-id> → marks session complete
#   research-session-state.sh list      <planning-dir> [--status active|complete|all] → lists sessions as JSON lines
#   research-session-state.sh get       <planning-dir> <session-id> → prints eval-friendly vars
#   research-session-state.sh latest    <planning-dir>              → prints latest session's eval-friendly vars
#   research-session-state.sh migrate   <planning-dir>              → moves root-level RESEARCH-*.md into research/
#
# Directory structure:
#   <planning-dir>/research/{YYYYMMDD-HHMMSS}-{slug}.md
#
# Frontmatter fields:
#   title, type (standalone-research), status (active|complete),
#   confidence, created, updated, base_commit, linked_sessions

set -euo pipefail

CMD="${1:-}"
PLANNING_DIR="${2:-}"

if [ -z "$CMD" ] || [ -z "$PLANNING_DIR" ]; then
  echo "Usage: research-session-state.sh <command> <planning-dir> [args...]" >&2
  exit 1
fi

RESEARCH_DIR="$PLANNING_DIR/research"

# ── Helpers ──────────────────────────────────────────────

# Sanitize slug: lowercase, a-z0-9 and dashes only, max 50 chars
sanitize_slug() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9-]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//' \
    | sed 's/-$//' \
    | head -c 50
}

# Read a frontmatter field from a file (awk-based, fail-open under pipefail)
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

# Update a frontmatter field in a file (scoped to YAML frontmatter block)
update_field() {
  local file="$1" field="$2" value="$3"
  if ! awk -v field="$field" '
    /^---$/ { if (!s) { s=1; f=1; next } if (f) exit }
    f && index($0, field ":") == 1 { found=1; exit }
    END { exit !found }
  ' "$file" 2>/dev/null; then
    return 1
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

  # Always update the 'updated' timestamp when changing another field
  if [ "$field" != "updated" ]; then
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    update_field "$file" "updated" "$now" || inject_field "$file" "updated" "$now"
  fi
}

# Inject a frontmatter field if it doesn't already exist
inject_field() {
  local target="$1" fname="$2" fval="$3"
  # Check if field exists within frontmatter only (not body)
  if awk -v field="$fname" '
    /^---$/ { if (!s) { s=1; f=1; next } if (f) exit }
    f && index($0, field ":") == 1 { found=1; exit }
    END { exit !found }
  ' "$target" 2>/dev/null; then
    return  # Field already exists in frontmatter
  fi
  # Insert field before the closing --- (second occurrence)
  awk -v field="$fname" -v value="$fval" '
    BEGIN { delim = 0 }
    $0 == "---" {
      delim++
      if (delim == 2) { print field ": " value }
    }
    { print }
  ' "$target" > "$target.tmp" && mv "$target.tmp" "$target"
}

# Validate session name format: YYYYMMDD-HHMMSS-slug.md
validate_session_name() {
  local name="$1"
  local base="${name%.md}"
  case "$name" in
    */* | *..* | "")
      echo "Error: invalid session name: $name" >&2
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

# Print eval-friendly session metadata
print_session_metadata() {
  local session_path="$1"
  local session_name
  session_name=$(basename "$session_path")
  local session_id="${session_name%.md}"
  printf 'research_id=%q\n' "$session_id"
  printf 'research_file=%q\n' "$session_path"
  printf 'research_title=%q\n' "$(read_field "$session_path" "title")"
  printf 'research_status=%q\n' "$(read_field "$session_path" "status")"
  printf 'research_confidence=%q\n' "$(read_field "$session_path" "confidence")"
  printf 'research_base_commit=%q\n' "$(read_field "$session_path" "base_commit")"
  printf 'research_created=%q\n' "$(read_field "$session_path" "created")"
  printf 'research_updated=%q\n' "$(read_field "$session_path" "updated")"
}

# ── Commands ─────────────────────────────────────────────

case "$CMD" in
  start)
    SLUG="${3:-}"
    if [ -z "$SLUG" ]; then
      echo "Usage: research-session-state.sh start <planning-dir> <slug>" >&2
      exit 1
    fi

    # Migrate any stale root-level files first (idempotent)
    if compgen -G "$PLANNING_DIR/RESEARCH-*.md" > /dev/null 2>&1; then
      # Re-invoke ourselves with migrate (avoids code duplication)
      bash "$0" migrate "$PLANNING_DIR" 2>/dev/null || true
    fi

    SLUG=$(sanitize_slug "$SLUG")
    if [ -z "$SLUG" ]; then
      SLUG="research"
    fi

    mkdir -p "$RESEARCH_DIR"
    TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    SESSION_ID="${TIMESTAMP}-${SLUG}"
    SESSION_FILE="$RESEARCH_DIR/${SESSION_ID}.md"
    NOW=$(date '+%Y-%m-%d %H:%M:%S')
    BASE_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

    if [ -f "$SESSION_FILE" ]; then
      echo "Error: session file already exists: $SESSION_FILE" >&2
      exit 1
    fi

    cat > "$SESSION_FILE" << ENDSESSION
---
title: ${SLUG}
type: standalone-research
status: active
confidence: high
created: ${NOW}
updated: ${NOW}
base_commit: ${BASE_COMMIT}
linked_sessions: []
---

# Research: ${SLUG}

## Summary

{Pending from Scout investigation.}

## Findings

## Relevant Patterns

## Risks

## Recommendations
ENDSESSION

    printf 'research_id=%q\n' "$SESSION_ID"
    printf 'research_file=%q\n' "$SESSION_FILE"
    ;;

  complete)
    SESSION_ID="${3:-}"
    if [ -z "$SESSION_ID" ]; then
      echo "Usage: research-session-state.sh complete <planning-dir> <session-id>" >&2
      exit 1
    fi
    SESSION_NAME="$SESSION_ID"
    case "$SESSION_NAME" in
      *.md) ;;
      *) SESSION_NAME="${SESSION_NAME}.md" ;;
    esac
    validate_session_name "$SESSION_NAME" || exit 1
    SESSION_FILE="$RESEARCH_DIR/$SESSION_NAME"
    if [ ! -f "$SESSION_FILE" ]; then
      echo "Error: session file not found: $SESSION_FILE" >&2
      exit 1
    fi
    if ! update_field "$SESSION_FILE" "status" "complete"; then
      echo "Error: failed to update status field in session: $SESSION_FILE" >&2
      exit 1
    fi
    echo "complete"
    ;;

  list)
    STATUS_FILTER="${3:-all}"
    case "$STATUS_FILTER" in
      --status) STATUS_FILTER="${4:-all}" ;;
    esac

    if [ ! -d "$RESEARCH_DIR" ]; then
      exit 0
    fi

    for f in "$RESEARCH_DIR"/*.md; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      fname=$(basename "$f")
      fid="${fname%.md}"
      ftitle=$(read_field "$f" "title")
      fstatus=$(read_field "$f" "status")
      fcreated=$(read_field "$f" "created")
      fbase=$(read_field "$f" "base_commit")

      case "$STATUS_FILTER" in
        all) ;;
        active)   [ "$fstatus" = "active" ] || continue ;;
        complete) [ "$fstatus" = "complete" ] || continue ;;
        *) echo "Error: invalid status filter '$STATUS_FILTER'. Use: active, complete, all" >&2; exit 1 ;;
      esac

      jq -cn --arg id "$fid" --arg title "$ftitle" --arg status "$fstatus" \
        --arg created "$fcreated" --arg base_commit "$fbase" --arg file "$f" \
        '{id:$id,title:$title,status:$status,created:$created,base_commit:$base_commit,file:$file}'
    done
    ;;

  get)
    SESSION_ID="${3:-}"
    if [ -z "$SESSION_ID" ]; then
      echo "Usage: research-session-state.sh get <planning-dir> <session-id>" >&2
      exit 1
    fi
    SESSION_NAME="$SESSION_ID"
    case "$SESSION_NAME" in
      *.md) ;;
      *) SESSION_NAME="${SESSION_NAME}.md" ;;
    esac
    validate_session_name "$SESSION_NAME" || exit 1
    SESSION_FILE="$RESEARCH_DIR/$SESSION_NAME"
    if [ ! -f "$SESSION_FILE" ]; then
      echo "Error: research file not found: $SESSION_FILE" >&2
      exit 1
    fi
    print_session_metadata "$SESSION_FILE"
    ;;

  latest)
    if [ ! -d "$RESEARCH_DIR" ]; then
      printf 'research_id=\n'
      printf 'research_file=\n'
      printf 'research_title=\n'
      printf 'research_status=\n'
      printf 'research_confidence=\n'
      printf 'research_base_commit=\n'
      printf 'research_created=\n'
      printf 'research_updated=\n'
      exit 0
    fi
    LATEST=""
    for f in "$RESEARCH_DIR"/*.md; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      LATEST="$f"
    done
    if [ -z "$LATEST" ]; then
      printf 'research_id=\n'
      printf 'research_file=\n'
      printf 'research_title=\n'
      printf 'research_status=\n'
      printf 'research_confidence=\n'
      printf 'research_base_commit=\n'
      printf 'research_created=\n'
      printf 'research_updated=\n'
      exit 0
    fi
    print_session_metadata "$LATEST"
    ;;

  migrate)
    if [ ! -d "$PLANNING_DIR" ]; then
      exit 0
    fi
    MIGRATED=0
    for f in "$PLANNING_DIR"/RESEARCH-*.md; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      fname=$(basename "$f")
      # Derive slug from filename: RESEARCH-{slug}.md → {slug}
      slug="${fname#RESEARCH-}"
      slug="${slug%.md}"
      slug=$(sanitize_slug "$slug")
      [ -z "$slug" ] && slug="research"

      # Use file mtime for timestamp
      if stat -f '%Sm' -t '%Y%m%d-%H%M%S' "$f" > /dev/null 2>&1; then
        # macOS stat
        TIMESTAMP=$(stat -f '%Sm' -t '%Y%m%d-%H%M%S' "$f")
      elif stat -c '%Y' "$f" > /dev/null 2>&1; then
        # GNU stat
        EPOCH=$(stat -c '%Y' "$f")
        TIMESTAMP=$(date -d "@$EPOCH" '+%Y%m%d-%H%M%S' 2>/dev/null || date -r "$EPOCH" '+%Y%m%d-%H%M%S' 2>/dev/null || date '+%Y%m%d-%H%M%S')
      else
        TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
      fi

      NEW_NAME="${TIMESTAMP}-${slug}.md"
      mkdir -p "$RESEARCH_DIR"
      NEW_PATH="$RESEARCH_DIR/$NEW_NAME"

      if [ -e "$NEW_PATH" ]; then
        echo "[research] Skipping migration of $fname: target already exists" >&2
        continue
      fi

      mv "$f" "$NEW_PATH"

      # Compute file mtime for created/updated timestamps (used by both branches)
      if stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$NEW_PATH" > /dev/null 2>&1; then
        created_ts=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$NEW_PATH")  # macOS/BSD
      elif stat -c '%Y' "$NEW_PATH" > /dev/null 2>&1; then
        created_ts=$(date -d "@$(stat -c '%Y' "$NEW_PATH")" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')  # GNU/Linux
      else
        created_ts=$(date '+%Y-%m-%d %H:%M:%S')  # fallback
      fi

      # Determine whether the file has well-formed frontmatter (opening AND
      # closing ---). If only the opening delimiter exists, treat as no
      # frontmatter and prepend a full block.
      has_frontmatter=false
      if head -1 "$NEW_PATH" | grep -q '^---$'; then
        # Count --- delimiters; well-formed needs at least 2
        if awk '/^---$/ { c++ } c >= 2 { exit 0 } END { exit (c < 2) }' "$NEW_PATH" 2>/dev/null; then
          has_frontmatter=true
        fi
      fi

      if [ "$has_frontmatter" = "false" ]; then
        # Extract title from first heading, fallback to slug
        extracted_title=$(grep -m 1 '^#' "$NEW_PATH" | sed -E 's/^#+[[:space:]]*//' || true)
        [ -z "$extracted_title" ] && extracted_title="$slug"

        # YAML-safe title: quote to protect special chars (#, :, etc.)
        safe_title=$(printf '%s' "$extracted_title" | sed 's/\\/\\\\/g; s/"/\\"/g')
        {
          printf '%s\n' '---'
          printf 'title: "%s"\n' "$safe_title"
          printf 'type: standalone-research\n'
          printf 'status: complete\n'
          printf 'confidence: medium\n'
          printf 'created: %s\n' "$created_ts"
          printf 'updated: %s\n' "$created_ts"
          printf 'base_commit: unknown\n'
          printf 'linked_sessions: []\n'
          printf '%s\n' '---'
          printf '\n'
          cat "$NEW_PATH"
        } > "$NEW_PATH.tmp" && mv "$NEW_PATH.tmp" "$NEW_PATH"
      else
        # File has frontmatter — backfill all missing template fields.
        # inject_field only adds absent keys; it won't overwrite existing values.
        inject_field "$NEW_PATH" "status" "complete"
        inject_field "$NEW_PATH" "base_commit" "unknown"
        inject_field "$NEW_PATH" "type" "standalone-research"
        inject_field "$NEW_PATH" "confidence" "medium"
        inject_field "$NEW_PATH" "created" "$created_ts"
        inject_field "$NEW_PATH" "updated" "$created_ts"
        inject_field "$NEW_PATH" "linked_sessions" "[]"

        # Capture the correct 'updated' value BEFORE any update_field calls.
        # update_field cascades a wall-clock write to 'updated' on every
        # non-'updated' field change, which would clobber the original or
        # just-injected value.
        correct_updated=$(read_field "$NEW_PATH" "updated")
        correct_updated="${correct_updated:-$created_ts}"

        # Fill blank-but-present fields with defaults (inject_field skips
        # fields that exist even if their value is empty).
        # Guard update_field with || inject_field fallback: if the field key
        # exists but update_field fails (e.g. malformed frontmatter without
        # closing ---), fall back to inject_field which is more tolerant.
        _defaults="status:complete base_commit:unknown type:standalone-research confidence:medium linked_sessions:[]"
        for _pair in $_defaults; do
          _field="${_pair%%:*}"
          _val=$(read_field "$NEW_PATH" "$_field")
          if [ -z "$_val" ]; then
            update_field "$NEW_PATH" "$_field" "${_pair#*:}" || inject_field "$NEW_PATH" "$_field" "${_pair#*:}"
          fi
        done
        # Handle created separately (default is mtime, not a static string)
        if [ -z "$(read_field "$NEW_PATH" "created")" ]; then
          update_field "$NEW_PATH" "created" "$created_ts" || inject_field "$NEW_PATH" "created" "$created_ts"
        fi

        # Ensure status is complete (update_field used instead of inject_field
        # to handle the case where status exists with a non-complete value)
        existing_status=$(read_field "$NEW_PATH" "status")
        if [ "$existing_status" != "complete" ]; then
          update_field "$NEW_PATH" "status" "complete" || true
        fi

        # Restore 'updated' to its pre-mutation value. update_field does not
        # cascade when the target field IS 'updated', so this is safe.
        update_field "$NEW_PATH" "updated" "$correct_updated" || true
      fi

      MIGRATED=$((MIGRATED + 1))
      echo "[research] Migrated $fname → research/$NEW_NAME" >&2
    done
    echo "migrated=$MIGRATED"
    ;;

  *)
    echo "Error: unknown command '$CMD'" >&2
    echo "Usage: research-session-state.sh {start|complete|list|get|latest|migrate} <planning-dir> [args...]" >&2
    exit 1
    ;;
esac
