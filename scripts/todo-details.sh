#!/usr/bin/env bash
set -euo pipefail

# todo-details.sh — CRUD helper for the todo detail registry
#
# Manages `.vbw-planning/todo-details.json`, a sidecar registry that stores
# extended context for todo items. STATE.md bullets remain brief (token-friendly
# for context compilation); this registry holds supplementary detail loaded
# on-demand when a specific todo is selected for action.
#
# Usage:
#   todo-details.sh add <hash> <json-detail> [registry-path]  Upsert a detail entry
#   todo-details.sh get <hash> [registry-path]                 Retrieve detail for a hash
#                                                             Falls back to legacy
#                                                             .vbw-planning/todo-details/<hash>.json
#   todo-details.sh remove <hash> [registry-path]              Delete an entry and legacy
#                                                             fallback file if present
#   todo-details.sh list [registry-path]                       Dump all entries
#   todo-details.sh gc <state-path> [registry-path]            Remove orphaned entries
#
# If registry-path is omitted, defaults to $VBW_PLANNING_DIR/todo-details.json
# (or .vbw-planning/todo-details.json).
#
# Schema (todo-details.json):
#   {
#     "schema_version": 1,
#     "items": {
#       "<hash>": {
#         "summary": "Brief one-liner (same as STATE.md bullet text)",
#         "context": "Extended detail...",
#         "files": ["optional/file/paths.ts"],
#         "added": "YYYY-MM-DD",
#         "source": "user|known-issue|session"
#       }
#     }
#   }
#
# Exit codes: always 0 (fail-open for agent consumption).
# Errors are reported as JSON on stdout: {"status":"error","message":"..."}

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
REGISTRY_PATH="${PLANNING_DIR}/todo-details.json"
MAX_CONTEXT_LENGTH=2000

# --- Error helpers ---
error_json() {
  local msg="$1"
  jq -n --arg m "$msg" '{"status":"error","message":$m}'
  exit 0
}

# --- Registry validation ---
registry_exists() {
  [ -f "$REGISTRY_PATH" ]
}

registry_is_valid() {
  [ -f "$REGISTRY_PATH" ] && jq -e '.schema_version == 1 and (.items | type == "object")' "$REGISTRY_PATH" >/dev/null 2>&1
}

ensure_registry() {
  if ! registry_exists; then
    mkdir -p "$(dirname "$REGISTRY_PATH")"
    printf '{"schema_version":1,"items":{}}\n' > "$REGISTRY_PATH"
  elif ! registry_is_valid; then
    # Reset malformed registry to empty state (fail-open: prefer data loss over blocking)
    printf '{"schema_version":1,"items":{}}\n' > "$REGISTRY_PATH"
  fi
}

planning_dir_for_registry() {
  dirname "$REGISTRY_PATH"
}

legacy_detail_path() {
  local hash="$1"
  printf '%s/todo-details/%s.json\n' "$(planning_dir_for_registry)" "$hash"
}

legacy_detail_is_valid() {
  local hash="$1"
  local path
  path=$(legacy_detail_path "$hash")
  [ -f "$path" ] && jq -e 'type == "object"' "$path" >/dev/null 2>&1
}

# --- Atomic write ---
write_registry() {
  local content="$1"
  local tmp_file
  tmp_file=$(mktemp "${REGISTRY_PATH}.tmp.XXXXXX")
  printf '%s\n' "$content" > "$tmp_file"
  mv "$tmp_file" "$REGISTRY_PATH"
}

# --- Subcommands ---

cmd_add() {
  local hash="${1:-}"
  local detail_json="${2:-}"

  # Support stdin: if detail arg is "-", read JSON from stdin
  if [ "$detail_json" = "-" ]; then
    detail_json=$(cat)
  fi

  if [ -z "$hash" ] || [ -z "$detail_json" ]; then
    error_json "Usage: todo-details.sh add <hash> <json-detail>"
  fi

  # Validate hash format (8 hex chars)
  if ! [[ "$hash" =~ ^[a-f0-9]{8}$ ]]; then
    error_json "Invalid hash format: expected 8 hex characters, got '$hash'"
  fi

  # Validate detail_json is valid JSON
  if ! printf '%s' "$detail_json" | jq empty 2>/dev/null; then
    error_json "Invalid JSON in detail argument"
  fi

  ensure_registry

  # Truncate context field if over limit (guard against missing/non-string context)
  local context_len
  context_len=$(printf '%s' "$detail_json" | jq -r 'if .context then (.context | tostring | length) else 0 end' 2>/dev/null) || context_len=0
  if [ "$context_len" -gt "$MAX_CONTEXT_LENGTH" ]; then
    detail_json=$(printf '%s' "$detail_json" | jq --argjson max "$MAX_CONTEXT_LENGTH" \
      '.context = (.context | tostring | .[:$max] + " (truncated)")' 2>/dev/null) || true
  fi

  # Upsert: merge detail into items keyed by hash
  local updated
  updated=$(jq --arg h "$hash" --argjson d "$detail_json" \
    '.items[$h] = $d' "$REGISTRY_PATH")

  write_registry "$updated"
  printf '{"status":"ok","action":"upserted","hash":"%s"}\n' "$hash"
}

cmd_get() {
  local hash="${1:-}"

  if [ -z "$hash" ]; then
    error_json "Usage: todo-details.sh get <hash>"
  fi
  # Validate hash format (8 hex chars)
  if ! [[ "$hash" =~ ^[a-f0-9]{8}$ ]]; then
    jq -n --arg h "$hash" '{"status":"not_found","hash":$h}'
    return 0
  fi
  local entry="null"
  if registry_exists && registry_is_valid; then
    entry=$(jq --arg h "$hash" '.items[$h] // null' "$REGISTRY_PATH")
  fi

  if [ "$entry" != "null" ]; then
    printf '{"status":"ok","hash":"%s","detail":%s}\n' "$hash" "$entry"
    return 0
  fi

  local legacy_path legacy_entry
  legacy_path=$(legacy_detail_path "$hash")
  if legacy_detail_is_valid "$hash"; then
    legacy_entry=$(cat "$legacy_path")
    printf '{"status":"ok","hash":"%s","detail":%s}\n' "$hash" "$legacy_entry"
    return 0
  fi

  printf '{"status":"not_found","hash":"%s"}\n' "$hash"
}

cmd_remove() {
  local hash="${1:-}"

  if [ -z "$hash" ]; then
    error_json "Usage: todo-details.sh remove <hash>"
  fi

  # Validate hash format (8 hex chars)
  if ! [[ "$hash" =~ ^[a-f0-9]{8}$ ]]; then
    jq -n --arg h "$hash" '{"status":"ok","action":"noop","hash":$h}'
    return 0
  fi

  local had_key="no"
  local registry_warning=""
  local canonical_status="missing"
  if registry_exists; then
    if registry_is_valid; then
      had_key=$(jq --arg h "$hash" 'if .items[$h] then "yes" else "no" end' -r "$REGISTRY_PATH")

      local updated
      updated=$(jq --arg h "$hash" 'del(.items[$h])' "$REGISTRY_PATH")
      write_registry "$updated"
      if [ "$had_key" = "yes" ]; then
        canonical_status="removed"
      else
        canonical_status="noop"
      fi
    else
      canonical_status="malformed"
      registry_warning="Malformed todo-details.json; skipped canonical cleanup"
    fi
  fi

  local had_legacy="no"
  local legacy_path
  legacy_path=$(legacy_detail_path "$hash")
  if [ -f "$legacy_path" ]; then
    rm -f "$legacy_path"
    had_legacy="yes"
  fi

  local legacy_removed_json=false
  if [ "$had_legacy" = "yes" ]; then
    legacy_removed_json=true
  fi

  if [ "$had_key" = "yes" ] || [ "$had_legacy" = "yes" ]; then
    if [ -n "$registry_warning" ]; then
      printf '{"status":"ok","action":"removed","hash":"%s","warning":"%s","canonical_status":"%s","legacy_removed":%s}\n' \
        "$hash" "$registry_warning" "$canonical_status" "$legacy_removed_json"
    else
      printf '{"status":"ok","action":"removed","hash":"%s"}\n' "$hash"
    fi
  else
    if [ -n "$registry_warning" ]; then
      printf '{"status":"ok","action":"noop","hash":"%s","message":"Key not found","warning":"%s","canonical_status":"%s","legacy_removed":%s}\n' \
        "$hash" "$registry_warning" "$canonical_status" "$legacy_removed_json"
    else
      printf '{"status":"ok","action":"noop","hash":"%s","message":"Key not found"}\n' "$hash"
    fi
  fi
}

cmd_list() {
  if ! registry_exists; then
    printf '{"status":"ok","count":0,"items":{}}\n'
    return 0
  fi

  if ! registry_is_valid; then
    error_json "Malformed todo-details.json"
  fi

  local count
  count=$(jq '.items | length' "$REGISTRY_PATH")
  jq --argjson c "$count" '{status:"ok", count:$c, items:.items}' "$REGISTRY_PATH"
}

cmd_gc() {
  local state_path="${1:-}"

  if [ -z "$state_path" ]; then
    error_json "Usage: todo-details.sh gc <state-path>"
  fi

  if [ ! -f "$state_path" ]; then
    error_json "STATE.md not found at $state_path"
  fi

  if ! registry_exists; then
    printf '{"status":"ok","action":"noop","removed":0,"remaining":0}\n'
    return 0
  fi

  if ! registry_is_valid; then
    error_json "Malformed todo-details.json"
  fi

  # Extract all ref hashes from STATE.md Todos section (supports both ## Todos and legacy ### Pending Todos)
  local state_refs
  state_refs=$(awk '
    /^(##|###) (Pending )?Todos$/ { found=1; next }
    found && /^##[^#]/ { exit }
    found { print }
  ' "$state_path" | grep -oE '\(ref:[a-f0-9]{8}\)' | sed 's/(ref://;s/)//' || true)

  # Get all keys from the registry
  local registry_keys
  registry_keys=$(jq -r '.items | keys[]' "$REGISTRY_PATH" 2>/dev/null || true)

  # Find orphaned keys (in registry but not in STATE.md)
  local orphaned=()
  local key
  for key in $registry_keys; do
    if ! printf '%s\n' "$state_refs" | grep -qxF "$key"; then
      orphaned+=("$key")
    fi
  done

  if [ "${#orphaned[@]}" -eq 0 ]; then
    local remaining
    remaining=$(jq '.items | length' "$REGISTRY_PATH")
    printf '{"status":"ok","action":"noop","removed":0,"remaining":%d}\n' "$remaining"
    return 0
  fi

  # Remove orphaned entries
  local updated
  updated=$(cat "$REGISTRY_PATH")
  for key in "${orphaned[@]}"; do
    updated=$(printf '%s' "$updated" | jq --arg h "$key" 'del(.items[$h])')
  done

  write_registry "$updated"

  local remaining
  remaining=$(printf '%s' "$updated" | jq '.items | length')
  printf '{"status":"ok","action":"gc","removed":%d,"remaining":%d}\n' "${#orphaned[@]}" "$remaining"
}

# --- Main dispatch ---
CMD="${1:-}"
shift || true

case "$CMD" in
  add)
    # add <hash> <json-detail> [registry-path]
    [ -n "${3:-}" ] && REGISTRY_PATH="$3"
    cmd_add "${1:-}" "${2:-}"
    ;;
  get)
    # get <hash> [registry-path]
    [ -n "${2:-}" ] && REGISTRY_PATH="$2"
    cmd_get "${1:-}"
    ;;
  remove)
    # remove <hash> [registry-path]
    [ -n "${2:-}" ] && REGISTRY_PATH="$2"
    cmd_remove "${1:-}"
    ;;
  list)
    # list [registry-path]
    [ -n "${1:-}" ] && REGISTRY_PATH="$1"
    cmd_list
    ;;
  gc)
    # gc <state-path> [registry-path]
    [ -n "${2:-}" ] && REGISTRY_PATH="$2"
    cmd_gc "${1:-}"
    ;;
  *)
    error_json "Unknown command: '$CMD'. Usage: todo-details.sh <add|get|remove|list|gc> [args...]"
    ;;
esac
