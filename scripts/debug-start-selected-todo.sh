#!/usr/bin/env bash
set -euo pipefail

# debug-start-selected-todo.sh — deterministic /vbw:debug numbered-todo startup.
#
# Usage:
#   debug-start-selected-todo.sh <planning-dir> <N> [--competing|--parallel|--serial]
#
# Resolves a numbered todo from the persisted unfiltered /vbw:list-todos snapshot,
# loads optional detail, creates or identifies the debug session, performs pickup,
# and returns one compact JSON payload for commands/debug.md to consume.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/vbw-config-root.sh
[ -f "$SCRIPT_DIR/lib/vbw-config-root.sh" ] && . "$SCRIPT_DIR/lib/vbw-config-root.sh" && find_vbw_root "$SCRIPT_DIR" >/dev/null 2>&1 || true
ARCHIVED_STATE_MESSAGE="This todo came from archived milestone state. Restore the writable root STATE.md first by restarting so session-start.sh can run migration, or run 'bash scripts/migrate-orphaned-state.sh .vbw-planning'."
AUTO_PICKUP_NOTE="Selected todo was already picked up automatically."

json_error() {
  local code="$1"
  local message="$2"
  jq -cn --arg status "error" --arg code "$code" --arg message "$message" \
    '{status:$status, code:$code, message:$message}'
}

usage_json() {
  json_error "usage" "Usage: debug-start-selected-todo.sh <planning-dir> <N> [--competing|--parallel|--serial]"
}

state_path_is_archived() {
  local state_path="$1"
  case "$state_path" in
    */.vbw-planning/milestones/*|.vbw-planning/milestones/*) return 0 ;;
    *) return 1 ;;
  esac
}

json_is_valid() {
  printf '%s' "$1" | jq empty >/dev/null 2>&1
}

read_frontmatter_field() {
  local file="$1"
  local field="$2"
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

read_source_todo_field() {
  local file="$1"
  local label="$2"
  awk -v label="$label" '
    $0 == "## Source Todo" { in_source = 1; next }
    in_source && /^## / { exit }
    in_source {
      prefix = "- **" label ":** "
      if (index($0, prefix) == 1) {
        print substr($0, length(prefix) + 1)
        exit
      }
    }
  ' "$file"
}

normalize_planning_dir() {
  local input_dir="$1"
  local parent_dir base_dir

  input_dir="${input_dir%/}"
  if [ -z "$input_dir" ]; then
    return 1
  fi

  case "$input_dir" in
    /*) ;;
    *) input_dir="$PWD/$input_dir" ;;
  esac

  parent_dir=$(dirname "$input_dir")
  base_dir=$(basename "$input_dir")
  if [ ! -d "$parent_dir" ] || [ ! -d "$parent_dir/$base_dir" ]; then
    return 1
  fi

  (
    cd "$parent_dir/$base_dir" && pwd -P
  )
}

append_json_string() {
  local array_json="$1"
  local value="$2"
  printf '%s' "$array_json" | jq -c --arg value "$value" '. + [$value]'
}

routing_flags_json_from_args() {
  local result='[]'
  local flag
  for flag in "$@"; do
    result=$(append_json_string "$result" "$flag")
  done
  printf '%s\n' "$result"
}

extract_markers_json() {
  local selected_json="$1"
  local detail_result_json="${2:-null}"

  if [ -z "$detail_result_json" ]; then
    detail_result_json="null"
  fi

  jq -cn --argjson selected "$selected_json" --argjson detail_result "$detail_result_json" '
    {selected:$selected, detail_result:$detail_result} as $root
    | def all_strings: [ $root | .. | strings ];
      def all_objects: [ $root | .. | objects ];
      def any_string($pattern): any(all_strings[]?; test($pattern; "i"));
      [
        (if any_string("\\[KNOWN-ISSUE\\]") or ($selected.priority? == "known-issue") then "[KNOWN-ISSUE]" else empty end),
        (if any_string("Disposition:[[:space:]]*accepted-process-exception") then "Disposition: accepted-process-exception" else empty end),
        (if any(all_objects[]?; (.known_issue_signature.disposition? // "") == "accepted-process-exception") then "known_issue_signature.disposition" else empty end),
        (if any_string("\\[UAT-DEVIATION\\]") then "[UAT-DEVIATION]" else empty end),
        (if any(all_objects[]?; (.source? // "") == "uat-deviation") then "source: \"uat-deviation\"" else empty end),
        (if any(all_objects[]?; has("uat_deviation")) then "uat_deviation" else empty end),
        (if any_string("Accepted UAT summary deviation") then "Accepted UAT summary deviation" else empty end)
      ] | unique
  '
}

live_ref_count() {
  local ref="$1"
  local list_json list_status

  if [ -z "$ref" ] || [ "$ref" = "null" ]; then
    printf '0\n'
    return 0
  fi

  list_json=$(VBW_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT_DIR/list-todos.sh" 2>/dev/null || true)
  list_status=$(printf '%s' "$list_json" | jq -r '.status // "error"' 2>/dev/null || echo "error")
  if [ "$list_status" != "ok" ]; then
    printf '0\n'
    return 0
  fi

  printf '%s' "$list_json" | jq -r --arg ref "$ref" '[.items[] | select((.ref // "") == $ref)] | length' 2>/dev/null || printf '0\n'
}

MATCH_FOUND=false
MATCH_SESSION_ID=""
MATCH_SESSION_FILE=""
MATCH_SESSION_STATUS=""

canonicalize_debug_sessions() {
  VBW_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT_DIR/debug-session-state.sh" list "$PLANNING_DIR" >/dev/null 2>&1 || true
}

find_completed_source_todo_match() {
  local selected_json="$1"
  local selected_ref selected_raw_line selected_identity_total completed_dir debugging_dir file
  local source_ref source_raw_line session_status ref_count_loaded ref_count_cached

  MATCH_FOUND=false
  MATCH_SESSION_ID=""
  MATCH_SESSION_FILE=""
  MATCH_SESSION_STATUS=""

  selected_ref=$(printf '%s' "$selected_json" | jq -r '.ref // empty')
  selected_raw_line=$(printf '%s' "$selected_json" | jq -r '.line // .raw_line // .text // empty')
  selected_identity_total=$(printf '%s' "$selected_json" | jq -r '.identity_total // 0')
  debugging_dir="${PLANNING_DIR%/}/debugging"
  completed_dir="${PLANNING_DIR%/}/debugging/completed"
  ref_count_loaded=false
  ref_count_cached=0

  [ -d "$debugging_dir" ] || return 0

  canonicalize_debug_sessions

  for file in "$completed_dir"/*.md "$debugging_dir"/*.md; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    session_status=$(read_frontmatter_field "$file" "status")
    [ "$session_status" = "complete" ] || continue

    source_ref=$(read_source_todo_field "$file" "Ref")
    source_raw_line=$(read_source_todo_field "$file" "Raw Line")
    case "$source_ref" in
      none|null) source_ref="" ;;
    esac

    if [ -n "$selected_ref" ] && [ "$selected_ref" != "null" ]; then
      [ "$source_ref" = "$selected_ref" ] || continue
      if [ "$source_raw_line" = "$selected_raw_line" ]; then
        MATCH_FOUND=true
      else
        if [ "$ref_count_loaded" != "true" ]; then
          ref_count_cached=$(live_ref_count "$selected_ref")
          case "$ref_count_cached" in
            ''|*[!0-9]*) ref_count_cached=0 ;;
          esac
          ref_count_loaded=true
        fi
      fi
      if [ "$ref_count_cached" = "1" ]; then
        MATCH_FOUND=true
      fi
    else
      [ -z "$source_ref" ] || continue
      if [ "$source_raw_line" = "$selected_raw_line" ] && [ "${selected_identity_total:-0}" = "1" ]; then
        MATCH_FOUND=true
      fi
    fi

    if [ "$MATCH_FOUND" = "true" ]; then
      MATCH_SESSION_FILE="$file"
      MATCH_SESSION_ID="$(basename "$file" .md)"
      MATCH_SESSION_STATUS="$session_status"
      return 0
    fi
  done
}

session_json() {
  local id="$1"
  local file="$2"
  local status_value="$3"
  jq -cn --arg id "$id" --arg file "$file" --arg status "$status_value" \
    '{id:$id, file:$file, status:$status}'
}

pickup_selected_todo() {
  local selected_json="$1"
  local detail_status="$2"
  local cleanup_policy="$3"
  VBW_PLANNING_DIR="$PLANNING_DIR" printf '%s' "$selected_json" | \
    VBW_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT_DIR/todo-lifecycle.sh" pickup /vbw:debug "$detail_status" "$cleanup_policy" 2>/dev/null || true
}

emit_error_with_session() {
  local code="$1"
  local message="$2"
  local session_obj="$3"
  local pickup_obj="${4:-null}"

  jq -cn \
    --arg status "error" \
    --arg code "$code" \
    --arg message "$message" \
    --argjson session "$session_obj" \
    --argjson pickup "$pickup_obj" \
    '{status:$status, code:$code, message:$message, mode:"selected_todo", todo_selected:true, session:$session, pickup:$pickup}'
}

emit_success() {
  local status_value="$1"
  local selected_json="$2"
  local detail_status="$3"
  local detail_obj="$4"
  local detail_has_signal="$5"
  local detail_warning_obj="$6"
  local markers_json="$7"
  local session_obj="$8"
  local pickup_obj="$9"
  local message="${10:-}"

  jq -cn \
    --arg status "$status_value" \
    --arg mode "selected_todo" \
    --arg bug_desc "$BUG_DESC" \
    --arg ref "$REF_VALUE" \
    --arg detail_status "$detail_status" \
    --argjson routing_flags "$ROUTING_FLAGS_JSON" \
    --argjson selected "$selected_json" \
    --argjson detail "$detail_obj" \
    --argjson detail_has_signal "$detail_has_signal" \
    --argjson detail_warning "$detail_warning_obj" \
    --argjson accepted_exception_markers "$markers_json" \
    --argjson session "$session_obj" \
    --argjson pickup_result "$pickup_obj" \
    --arg auto_note "$AUTO_PICKUP_NOTE" \
    --arg message "$message" \
    '{
      status:$status,
      mode:$mode,
      todo_selected:true,
      bug_desc:$bug_desc,
      routing_flags:$routing_flags,
      selected:$selected,
      ref:(if $ref == "" or $ref == "null" then null else $ref end),
      detail_status:$detail_status,
      detail:$detail,
      detail_has_signal:$detail_has_signal,
      accepted_exception_markers:$accepted_exception_markers,
      detail_warning:$detail_warning,
      session:$session,
      pickup:{
        status:($pickup_result.status // "unknown"),
        warning:($pickup_result.warning // null),
        auto_note:$auto_note,
        result:$pickup_result
      },
      message:(if $message == "" then null else $message end)
    }'
}

PLANNING_ARG="${1:-}"
SELECTION="${2:-}"
shift 2 2>/dev/null || true

if [ -z "$PLANNING_ARG" ] || [ -z "$SELECTION" ]; then
  usage_json
  exit 0
fi

ROUTING_FLAGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --competing|--parallel|--serial)
      ROUTING_FLAGS+=("$1")
      ;;
    *)
      json_error "usage" "Unknown routing flag for /vbw:debug selected todo: $1"
      exit 0
      ;;
  esac
  shift || true
done

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
  json_error "usage" "Invalid todo selection — choose a numbered todo from /vbw:list-todos."
  exit 0
fi

if ! PLANNING_DIR=$(normalize_planning_dir "$PLANNING_ARG"); then
  json_error "planning_dir_missing" "Planning directory not found: ${PLANNING_ARG}"
  exit 0
fi
PROJECT_ROOT=$(cd "${PLANNING_DIR%/}/.." && pwd -P)
cd "$PROJECT_ROOT"
export VBW_PLANNING_DIR="$PLANNING_DIR"

ROUTING_FLAGS_JSON=$(routing_flags_json_from_args "${ROUTING_FLAGS[@]}")

SELECTED_JSON=$(VBW_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT_DIR/resolve-todo-item.sh" "$SELECTION" --session-snapshot --require-unfiltered --validate-live 2>/dev/null || true)
if ! json_is_valid "$SELECTED_JSON"; then
  json_error "resolver_invalid_json" "Todo selection resolver returned invalid JSON. Rerun /vbw:list-todos."
  exit 0
fi
SELECTED_STATUS=$(printf '%s' "$SELECTED_JSON" | jq -r '.status // "error"' 2>/dev/null || echo "error")
if [ "$SELECTED_STATUS" != "ok" ]; then
  printf '%s\n' "$SELECTED_JSON"
  exit 0
fi

STATE_PATH=$(printf '%s' "$SELECTED_JSON" | jq -r '.state_path // empty')
if state_path_is_archived "$STATE_PATH"; then
  jq -cn --arg status "error" --arg code "archived_state" --arg message "$ARCHIVED_STATE_MESSAGE" \
    '{status:$status, code:$code, message:$message}'
  exit 0
fi

REF_VALUE=$(printf '%s' "$SELECTED_JSON" | jq -r '.ref // empty')
BUG_DESC=$(printf '%s' "$SELECTED_JSON" | jq -r '.command_text // .normalized_text // .text // empty')
SLUG=$(printf '%s' "$BUG_DESC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 50)
[ -n "$SLUG" ] || SLUG="debug"

DETAIL_STATUS="none"
DETAIL_RESULT_JSON="null"
DETAIL_OBJECT_JSON="null"
DETAIL_HAS_SIGNAL=false
DETAIL_WARNING_JSON="null"

if [ -n "$REF_VALUE" ] && [ "$REF_VALUE" != "null" ]; then
  DETAIL_RESULT_JSON=$(VBW_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT_DIR/todo-details.sh" get "$REF_VALUE" 2>/dev/null || true)
  if ! json_is_valid "$DETAIL_RESULT_JSON"; then
    DETAIL_STATUS="error"
    DETAIL_RESULT_JSON="null"
    DETAIL_WARNING_JSON=$(jq -cn --arg status "error" --arg message "Todo detail lookup returned invalid JSON for ref ${REF_VALUE}." '{status:$status, message:$message}')
  else
    DETAIL_STATUS=$(printf '%s' "$DETAIL_RESULT_JSON" | jq -r '.status // "error"' 2>/dev/null || echo "error")
    if [ "$DETAIL_STATUS" = "ok" ]; then
      DETAIL_OBJECT_JSON=$(printf '%s' "$DETAIL_RESULT_JSON" | jq -c '.detail // null')
      DETAIL_HAS_SIGNAL=$(printf '%s' "$DETAIL_RESULT_JSON" | jq -r '((.detail.context // "") | length > 0) or (((.detail.files // []) | if type == "array" then length else 0 end) > 0)' 2>/dev/null || echo "false")
    else
      case "$DETAIL_STATUS" in
        not_found|error) ;;
        *) DETAIL_STATUS="error" ;;
      esac
      DETAIL_WARNING_JSON=$(VBW_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT_DIR/todo-lifecycle.sh" detail-warning "$REF_VALUE" 2>/dev/null || true)
      if ! json_is_valid "$DETAIL_WARNING_JSON"; then
        DETAIL_WARNING_JSON=$(jq -cn --arg status "error" --arg message "Could not record detail warning for ref ${REF_VALUE}." '{status:$status, message:$message}')
      fi
      DETAIL_RESULT_JSON="null"
    fi
  fi
fi

ACCEPTED_EXCEPTION_MARKERS_JSON=$(extract_markers_json "$SELECTED_JSON" "$DETAIL_RESULT_JSON")
CLEANUP_POLICY="keep"
if [ "$DETAIL_STATUS" = "ok" ]; then
  CLEANUP_POLICY="safe"
fi

find_completed_source_todo_match "$SELECTED_JSON"
if [ "$MATCH_FOUND" = "true" ]; then
  COMPLETED_SESSION_JSON=$(session_json "$MATCH_SESSION_ID" "$MATCH_SESSION_FILE" "$MATCH_SESSION_STATUS")
  PICKUP_JSON=$(pickup_selected_todo "$SELECTED_JSON" "$DETAIL_STATUS" "$CLEANUP_POLICY")
  if ! json_is_valid "$PICKUP_JSON"; then
    PICKUP_JSON=$(jq -cn --arg status "error" --arg message "Todo pickup returned invalid JSON after completed-session match." '{status:$status, message:$message}')
  fi
  PICKUP_STATUS=$(printf '%s' "$PICKUP_JSON" | jq -r '.status // "error"' 2>/dev/null || echo "error")
  if [ "$PICKUP_STATUS" = "error" ]; then
    PICKUP_MESSAGE=$(printf '%s' "$PICKUP_JSON" | jq -r '.message // "Todo pickup failed after completed-session match."' 2>/dev/null || echo "Todo pickup failed after completed-session match.")
    emit_error_with_session "pickup_failed" "$PICKUP_MESSAGE" "$COMPLETED_SESSION_JSON" "$PICKUP_JSON"
    exit 0
  fi
  emit_success "already_complete" "$SELECTED_JSON" "$DETAIL_STATUS" "$DETAIL_OBJECT_JSON" "$DETAIL_HAS_SIGNAL" "$DETAIL_WARNING_JSON" "$ACCEPTED_EXCEPTION_MARKERS_JSON" "$COMPLETED_SESSION_JSON" "$PICKUP_JSON" "Source todo was already completed by the matching debug session and has been removed from the pending todo list; no duplicate session was created."
  exit 0
fi

SESSION_OUTPUT=""
if [ "$DETAIL_STATUS" = "ok" ]; then
  SESSION_OUTPUT=$(printf '%s' "$SELECTED_JSON" | TODO_DETAIL_RESULT_JSON="$DETAIL_RESULT_JSON" VBW_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT_DIR/debug-session-state.sh" start-with-selected-todo "$PLANNING_DIR" "$SLUG" "$DETAIL_STATUS" 2>&1) || {
    json_error "session_start_failed" "$SESSION_OUTPUT"
    exit 0
  }
else
  SESSION_OUTPUT=$(printf '%s' "$SELECTED_JSON" | VBW_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT_DIR/debug-session-state.sh" start-with-selected-todo "$PLANNING_DIR" "$SLUG" "$DETAIL_STATUS" 2>&1) || {
    json_error "session_start_failed" "$SESSION_OUTPUT"
    exit 0
  }
fi

# shellcheck disable=SC1090
if ! eval "$SESSION_OUTPUT"; then
  json_error "session_start_failed" "Debug session helper returned unparseable metadata."
  exit 0
fi
SESSION_JSON=$(session_json "${session_id:-}" "${session_file:-}" "investigating")

PICKUP_JSON=$(pickup_selected_todo "$SELECTED_JSON" "$DETAIL_STATUS" "$CLEANUP_POLICY")
if ! json_is_valid "$PICKUP_JSON"; then
  PICKUP_JSON=$(jq -cn --arg status "error" --arg message "Todo pickup returned invalid JSON after debug session creation." '{status:$status, message:$message}')
fi
PICKUP_STATUS=$(printf '%s' "$PICKUP_JSON" | jq -r '.status // "error"' 2>/dev/null || echo "error")
if [ "$PICKUP_STATUS" = "error" ]; then
  PICKUP_MESSAGE=$(printf '%s' "$PICKUP_JSON" | jq -r '.message // "Todo pickup failed after debug session creation."' 2>/dev/null || echo "Todo pickup failed after debug session creation.")
  emit_error_with_session "pickup_failed_after_session" "$PICKUP_MESSAGE" "$SESSION_JSON" "$PICKUP_JSON"
  exit 0
fi

emit_success "ok" "$SELECTED_JSON" "$DETAIL_STATUS" "$DETAIL_OBJECT_JSON" "$DETAIL_HAS_SIGNAL" "$DETAIL_WARNING_JSON" "$ACCEPTED_EXCEPTION_MARKERS_JSON" "$SESSION_JSON" "$PICKUP_JSON"
