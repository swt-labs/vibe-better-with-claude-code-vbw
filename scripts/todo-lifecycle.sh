#!/usr/bin/env bash
set -euo pipefail

# todo-lifecycle.sh — shared deterministic todo snapshot, validation, and mutation helper.
#
# Commands:
#   snapshot-save                 Read list-todos JSON from stdin and persist last-view snapshot
#   snapshot-show                 Print persisted snapshot JSON
#   snapshot-select <N> [--require-unfiltered]
#                                 Resolve N against persisted snapshot
#   validate-item                 Validate selected item JSON from stdin against live STATE.md
#   detail-warning <hash> [state-path]
#                                 Append detail-load warning using activity-heading preservation rules
#   pickup <command-label> <detail-status> <detail-cleanup-policy>
#                                 Mutate STATE.md for a claimed todo (reads selected item JSON from stdin)
#   remove <detail-status> <detail-cleanup-policy>
#                                 Mutate STATE.md for a removed todo (reads selected item JSON from stdin)
#
# detail-status: ok | not_found | error | none
# detail-cleanup-policy: safe | keep

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
SNAPSHOT_PATH="/tmp/.vbw-last-list-view-${SESSION_KEY}.json"
DETAILS_PATH="${PLANNING_DIR}/todo-details.json"
CMD="${1:-}"
shift || true

json_out() {
  jq -cn "$@"
}

error_json() {
  local code="$1"
  local message="$2"
  json_out --arg status "error" --arg code "$code" --arg message "$message" \
    '{status:$status, code:$code, message:$message}'
}

ok_json() {
  jq -cn "$@"
}

usage() {
  error_json "usage" "Usage: todo-lifecycle.sh <snapshot-save|snapshot-show|snapshot-select|validate-item|detail-warning|pickup|remove> [args]"
}

read_stdin() {
  cat
}

snapshot_requirements_filter() {
  local require_unfiltered="$1"
  if [ "$require_unfiltered" = "true" ]; then
    echo "Current list view is filtered — rerun unfiltered /vbw:list-todos before using this numbered todo command."
  else
    echo "Todo snapshot missing or invalid — rerun /vbw:list-todos first."
  fi
}

snapshot_validate_schema() {
  local json_input="$1"
  printf '%s' "$json_input" | jq -e '
    type == "object"
    and (.status | type == "string")
    and (
      if .status == "error" then
        (.message | type == "string")
      else
        (.state_path? | type == "string" or .state_path == null)
        and (.section? | type == "string" or .section == null)
        and (.items | type == "array")
      end
    )
  ' >/dev/null 2>&1
}

snapshot_save() {
  local json_input
  json_input=$(read_stdin)

  if ! printf '%s' "$json_input" | jq empty >/dev/null 2>&1; then
    error_json "snapshot_invalid" "Todo snapshot JSON is invalid. Rerun /vbw:list-todos."
    return 0
  fi

  if ! snapshot_validate_schema "$json_input"; then
    error_json "snapshot_invalid" "Todo snapshot JSON is malformed. Rerun /vbw:list-todos."
    return 0
  fi

  printf '%s' "$json_input" | jq -cS '.' > "$SNAPSHOT_PATH"
  ok_json --arg status "ok" --arg path "$SNAPSHOT_PATH" '{status:$status, path:$path}'
}

snapshot_show() {
  if [ ! -f "$SNAPSHOT_PATH" ]; then
    error_json "snapshot_missing" "Todo snapshot missing — rerun /vbw:list-todos first."
    return 0
  fi

  local json_input
  json_input=$(cat "$SNAPSHOT_PATH" 2>/dev/null || true)
  if ! printf '%s' "$json_input" | jq empty >/dev/null 2>&1; then
    error_json "snapshot_invalid" "Todo snapshot is malformed — rerun /vbw:list-todos first."
    return 0
  fi

  if ! snapshot_validate_schema "$json_input"; then
    error_json "snapshot_invalid" "Todo snapshot is malformed — rerun /vbw:list-todos first."
    return 0
  fi

  printf '%s\n' "$json_input"
}

trim() {
  printf '%s' "${1:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

relative_age() {
  local date_str="$1"
  local now then_ts days

  if ! [[ "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo ""
    return
  fi

  now=$(date +%s)
  then_ts=$(date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null) || \
    then_ts=$(date -d "$date_str" +%s 2>/dev/null) || { echo ""; return; }

  days=$(( (now - then_ts) / 86400 ))
  if [ "$days" -lt 0 ]; then
    echo ""
  elif [ "$days" -eq 0 ]; then
    echo "today"
  elif [ "$days" -eq 1 ]; then
    echo "1d ago"
  elif [ "$days" -lt 30 ]; then
    echo "${days}d ago"
  elif [ "$days" -lt 365 ]; then
    echo "$(( days / 30 ))mo ago"
  else
    echo "$(( days / 365 ))y ago"
  fi
}

load_detail_for_ref() {
  local ref="${1:-}"
  if [ -z "$ref" ] || [ ! -f "$DETAILS_PATH" ]; then
    echo '{}'
    return
  fi
  bash "$SCRIPT_DIR/todo-details.sh" get "$ref" "$DETAILS_PATH" 2>/dev/null | jq -c '.detail // {}' 2>/dev/null || echo '{}'
}

canonical_signature_json() {
  local signature_json="$1"
  printf '%s' "$signature_json" | jq -cS '
    if type != "object" then null else {
      phase: (.phase // null),
      phase_dir: (.phase_dir // null),
      test: (.test // null),
      file: (.file // null),
      error: (.error // null),
      source_kind: (.source_kind // null),
      disposition: (.disposition // null),
      source_path: (.source_path // null)
    } end
  ' 2>/dev/null || echo 'null'
}

parse_todo_line_json() {
  local line="$1"
  local section_index="$2"
  local state_path="$3"
  local section_name="$4"
  local text priority date_str age ref display_identity normalized_text command_text detail_json known_issue_signature source

  text="${line#- }"
  priority="normal"
  case "$text" in
    "[HIGH] "*) priority="high" ;;
    "[low] "*) priority="low" ;;
    "[KNOWN-ISSUE] "*) priority="known-issue" ;;
  esac

  date_str=""
  if [[ "$text" =~ \(added\ ([0-9]{4}-[0-9]{2}-[0-9]{2})\) ]]; then
    date_str="${BASH_REMATCH[1]}"
  fi

  ref=""
  if [[ "$text" =~ \(ref:([a-f0-9]{8})\)[[:space:]]*$ ]]; then
    ref="${BASH_REMATCH[1]}"
  fi

  age=""
  if [ -n "$date_str" ]; then
    age=$(relative_age "$date_str")
  fi

  display_identity="$text"
  display_identity=$(printf '%s\n' "$display_identity" | sed 's/ *(ref:[a-f0-9]\{8\})$//')
  display_identity=$(printf '%s\n' "$display_identity" | sed 's/ *(added [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\})$//')

  normalized_text="$display_identity"
  normalized_text="${normalized_text#\[HIGH\] }"
  normalized_text="${normalized_text#\[low\] }"
  normalized_text="${normalized_text#\[KNOWN-ISSUE\] }"
  command_text="$normalized_text"

  detail_json='{}'
  known_issue_signature='null'
  source='null'
  if [ -n "$ref" ]; then
    detail_json=$(load_detail_for_ref "$ref")
    known_issue_signature=$(printf '%s' "$detail_json" | jq -c '.known_issue_signature // null' 2>/dev/null || echo 'null')
    known_issue_signature=$(canonical_signature_json "$known_issue_signature")
    source=$(printf '%s' "$detail_json" | jq -c '.source // null' 2>/dev/null || echo 'null')
  fi

  jq -cn \
    --arg line "$line" \
    --arg text "$text" \
    --arg display_identity "$display_identity" \
    --arg normalized_text "$normalized_text" \
    --arg command_text "$command_text" \
    --arg priority "$priority" \
    --arg date "$date_str" \
    --arg age "$age" \
    --arg state_path "$state_path" \
    --arg section "$section_name" \
    --argjson section_index "$section_index" \
    --arg ref "$ref" \
    --argjson known_issue_signature "$known_issue_signature" \
    --argjson source "$source" \
    '{
      line:$line,
      text:$text,
      display_identity:$display_identity,
      normalized_text:$normalized_text,
      command_text:$command_text,
      priority:$priority,
      date:(if $date == "" then null else $date end),
      age:(if $age == "" then null else $age end),
      state_path:$state_path,
      section:$section,
      section_index:$section_index,
      ref:(if $ref == "" then null else $ref end),
      known_issue_signature:$known_issue_signature,
      source:$source
    }'
}

annotate_identity_occurrence() {
  local items_json="$1"
  printf '%s' "$items_json" | jq -c '
    def identity($item): {
      normalized_text: ($item.normalized_text // ""),
      ref: ($item.ref // null),
      known_issue_signature: ($item.known_issue_signature // null)
    };

    . as $items
    | [range(0; length) as $i |
        $items[$i] as $item
        | $item + {
            identity_occurrence: ([range(0; $i + 1) | $items[.] | select(identity(.) == identity($item))] | length),
            identity_total: ([ $items[] | select(identity(.) == identity($item)) ] | length)
          }
      ]
  '
}

section_items_json() {
  local state_path="$1"
  local section_name="$2"
  local current_lines items_json

  current_lines=$(extract_section_lines "$state_path" "$section_name" 2>/dev/null || true)
  items_json='[]'

  while IFS=$'\t' read -r current_line_no current_line; do
    [ -n "$current_line_no" ] || continue
    local section_index item_json
    section_index=$(printf '%s' "$items_json" | jq 'length + 1')
    item_json=$(parse_todo_line_json "$current_line" "$section_index" "$state_path" "$section_name")
    item_json=$(printf '%s' "$item_json" | jq -c --argjson line_no "$current_line_no" '. + {line_no: $line_no}')
    items_json=$(printf '%s' "$items_json" | jq --argjson item "$item_json" '. + [$item]')
  done <<< "$current_lines"

  annotate_identity_occurrence "$items_json"
}

extract_section_lines() {
  local state_path="$1"
  local section_name="$2"

  case "$section_name" in
    "## Todos")
      awk -v state_path="$state_path" -v section_name="$section_name" '
        /^## Todos?$/ { found=1; next }
        found && /^##/ { exit }
        found && /^### / { sub_found=1; next }
        found && !sub_found && /^- / { print NR "\t" $0 }
      ' "$state_path"
      ;;
    "### Pending Todos")
      awk -v state_path="$state_path" -v section_name="$section_name" '
        /^### Pending Todos$/ { found=1; next }
        found && /^### Completed Todos$/ { exit }
        found && /^##/ { exit }
        found && /^- / { print NR "\t" $0 }
      ' "$state_path"
      ;;
    *)
      return 1
      ;;
  esac
}

archived_state_message() {
  echo "This todo came from archived milestone state. Restore the writable root STATE.md first by restarting so session-start.sh can run migration, or run 'bash scripts/migrate-orphaned-state.sh .vbw-planning'."
}

state_path_is_archived() {
  local state_path="$1"
  case "$state_path" in
    */.vbw-planning/milestones/*|.vbw-planning/milestones/*) return 0 ;;
    *) return 1 ;;
  esac
}

snapshot_select() {
  local selection="${1:-}"
  local require_unfiltered="false"
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --require-unfiltered) require_unfiltered="true" ;;
    esac
    shift || true
  done

  if [ -z "$selection" ] || ! [[ "$selection" =~ ^[0-9]+$ ]]; then
    error_json "invalid_selection" "Invalid selection — choose a numbered todo from /vbw:list-todos."
    return 0
  fi

  local snapshot
  snapshot=$(snapshot_show)
  local snapshot_status
  snapshot_status=$(printf '%s' "$snapshot" | jq -r '.status // "ok"' 2>/dev/null || echo 'error')
  if [ "$snapshot_status" = "error" ]; then
    printf '%s\n' "$snapshot"
    return 0
  fi

  local filter
  filter=$(printf '%s' "$snapshot" | jq -r '.filter // empty')
  if [ "$require_unfiltered" = "true" ] && [ -n "$filter" ]; then
    error_json "snapshot_filtered" "Current list view is filtered — rerun unfiltered /vbw:list-todos before using this numbered todo command."
    return 0
  fi

  local count idx
  count=$(printf '%s' "$snapshot" | jq '.items | length')
  selection=$((10#$selection))
  if [ "$selection" -lt 1 ] || [ "$selection" -gt "$count" ]; then
    error_json "invalid_selection" "Invalid selection — only items 1-${count} exist."
    return 0
  fi

  idx=$((selection - 1))
  printf '%s' "$snapshot" | jq -c --argjson idx "$idx" --argjson num "$selection" '
    .items[$idx]
    | . + {
        status: "ok",
        selection_source: "snapshot",
        num: $num,
        snapshot_filter: (.snapshot_filter // null),
        snapshot_state_path: .state_path,
        snapshot_section: .section
      }
  '
}

validate_item_against_live() {
  local item_json="$1"
  local state_path section_name expected_normalized expected_ref expected_signature expected_line expected_occurrence expected_total current_items_json candidate_count candidate_json current_signature

  state_path=$(printf '%s' "$item_json" | jq -r '.state_path // empty')
  section_name=$(printf '%s' "$item_json" | jq -r '.section // empty')
  expected_normalized=$(printf '%s' "$item_json" | jq -r '.normalized_text // empty')
  expected_ref=$(printf '%s' "$item_json" | jq -r '.ref // empty')
  expected_signature=$(printf '%s' "$item_json" | jq -c '.known_issue_signature // null')
  expected_signature=$(canonical_signature_json "$expected_signature")
  expected_line=$(printf '%s' "$item_json" | jq -r '.line // empty')
  expected_occurrence=$(printf '%s' "$item_json" | jq -r '.identity_occurrence // empty')
  expected_total=$(printf '%s' "$item_json" | jq -r '.identity_total // empty')

  if [ -z "$state_path" ] || [ -z "$section_name" ] || [ -z "$expected_occurrence" ] || [ -z "$expected_total" ]; then
    error_json "invalid_item" "Todo selection payload is missing required metadata. Rerun /vbw:list-todos."
    return 0
  fi

  if [ ! -f "$state_path" ]; then
    error_json "state_missing" "Todo selection no longer matches live backlog. Rerun /vbw:list-todos."
    return 0
  fi

  current_items_json=$(section_items_json "$state_path" "$section_name")
  candidate_count=$(printf '%s' "$current_items_json" | jq \
    --arg normalized_text "$expected_normalized" \
    --arg ref "$expected_ref" \
    --argjson signature "$expected_signature" \
    --argjson occurrence "$expected_occurrence" '
      [ .[]
        | select(.normalized_text == $normalized_text)
        | select((.ref // "") == $ref)
        | select((.known_issue_signature // null) == $signature)
        | select(.identity_occurrence == $occurrence)
      ] | length
    ')

  if [ "$candidate_count" -ne 1 ] 2>/dev/null; then
    error_json "selection_stale" "Todo selection no longer matches live backlog. Rerun /vbw:list-todos."
    return 0
  fi

  candidate_json=$(printf '%s' "$current_items_json" | jq -c \
    --arg normalized_text "$expected_normalized" \
    --arg ref "$expected_ref" \
    --argjson signature "$expected_signature" \
    --argjson occurrence "$expected_occurrence" '
      [ .[]
        | select(.normalized_text == $normalized_text)
        | select((.ref // "") == $ref)
        | select((.known_issue_signature // null) == $signature)
        | select(.identity_occurrence == $occurrence)
      ][0]
    ')

  current_signature=$(printf '%s' "$candidate_json" | jq -c '.known_issue_signature // null')
  if [ "$expected_signature" != "$current_signature" ]; then
    error_json "selection_stale" "Todo selection no longer matches live backlog. Rerun /vbw:list-todos."
    return 0
  fi

  if [ "$(printf '%s' "$candidate_json" | jq -r '.identity_total')" != "$expected_total" ]; then
    error_json "selection_stale" "Todo selection no longer matches live backlog. Rerun /vbw:list-todos."
    return 0
  fi

  if [ -n "$expected_line" ] && [ "$(printf '%s' "$candidate_json" | jq -r '.line // empty')" != "$expected_line" ]; then
    error_json "selection_stale" "Todo selection no longer matches live backlog. Rerun /vbw:list-todos."
    return 0
  fi

  printf '%s\n' "$candidate_json"
}

validate_item_cmd() {
  local item_json
  item_json=$(read_stdin)
  if ! printf '%s' "$item_json" | jq empty >/dev/null 2>&1; then
    error_json "invalid_item" "Todo selection payload is invalid. Rerun /vbw:list-todos."
    return 0
  fi
  validate_item_against_live "$item_json"
}

append_activity_line_to_file() {
  local file_path="$1"
  local activity_line="$2"
  local tmp_file heading_line next_heading
  tmp_file=$(mktemp "${file_path}.activity.XXXXXX")

  heading_line=$(grep -nE '^## (Recent Activity|Activity Log|Activity)$' "$file_path" 2>/dev/null | head -1 | cut -d: -f1 || true)
  if [ -n "$heading_line" ]; then
    next_heading=$(awk -v start="$heading_line" 'NR > start && /^## / { print NR; exit }' "$file_path")
    if [ -n "$next_heading" ]; then
      awk -v heading_line="$heading_line" -v next_heading="$next_heading" -v activity_line="$activity_line" '
        NR == next_heading { print activity_line; print "" }
        { print }
        END {
          if (NR < next_heading) {
            print activity_line
          }
        }
      ' "$file_path" > "$tmp_file"
    else
      cat "$file_path" > "$tmp_file"
      printf '\n%s\n' "$activity_line" >> "$tmp_file"
    fi
  else
    cat "$file_path" > "$tmp_file"
    printf '\n## Activity Log\n\n%s\n' "$activity_line" >> "$tmp_file"
  fi

  mv "$tmp_file" "$file_path"
}

append_activity_entry() {
  local state_path="$1"
  local message="$2"
  local today line
  [ -f "$state_path" ] || return 0
  today=$(date +%Y-%m-%d)
  line="- ${today}: ${message}"
  append_activity_line_to_file "$state_path" "$line"
}

detail_warning() {
  local ref_hash="${1:-}"
  local state_path="${2:-${PLANNING_DIR}/STATE.md}"
  if [ -z "$ref_hash" ]; then
    error_json "usage" "Usage: todo-lifecycle.sh detail-warning <hash> [state-path]"
    return 0
  fi
  if [ ! -f "$state_path" ]; then
    ok_json --arg status "ok" --arg action "skipped" '{status:$status, action:$action}'
    return 0
  fi
  append_activity_entry "$state_path" "Detail for ref ${ref_hash} could not be loaded"
  ok_json --arg status "ok" --arg action "logged" --arg state_path "$state_path" '{status:$status, action:$action, state_path:$state_path}'
}

normalize_phase_dir() {
  local phase_dir="$1"
  if [ -z "$phase_dir" ]; then
    echo ""
    return
  fi
  case "$phase_dir" in
    /*) printf '%s\n' "$phase_dir" ;;
    *)
      if [ -d "$phase_dir" ]; then
        printf '%s\n' "$phase_dir"
      else
        printf '%s\n' "${PLANNING_DIR%/}/${phase_dir#./}"
      fi
      ;;
  esac
}

phase_dir_for_number() {
  local phase_num="$1"
  find "${PLANNING_DIR%/}/phases" -maxdepth 1 -type d -name "${phase_num}-*" 2>/dev/null | head -1
}

lookup_legacy_known_issue_signature() {
  local item_json="$1"
  local display_text issue_text phase_num phase_dir source_path disposition query_json lookup_result lookup_status
  local parsed_test parsed_file parsed_error

  display_text=$(printf '%s' "$item_json" | jq -r '.display_identity // .text // empty')
  issue_text="${display_text#\[KNOWN-ISSUE\] }"
  issue_text=$(printf '%s' "$issue_text" | sed 's/ *(added [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\})$//')

  disposition="unresolved"
  if printf '%s' "$issue_text" | grep -q 'accepted as process-exception for this phase'; then
    disposition="accepted-process-exception"
    issue_text=$(printf '%s' "$issue_text" | sed 's/ — accepted as process-exception for this phase//')
  fi

  source_path=$(printf '%s' "$issue_text" | sed -n 's/.*(see \([^)]*\)).*/\1/p')
  issue_text=$(printf '%s' "$issue_text" | sed 's/ *(see [^)]*)//')

  phase_num=$(printf '%s' "$issue_text" | sed -n 's/.*(phase \([0-9][0-9]*\), seen [0-9][0-9]*x).*/\1/p')
  issue_text=$(printf '%s' "$issue_text" | sed 's/ *(phase [0-9][0-9]*, seen [0-9][0-9]*x)//')

  if ! [[ "$issue_text" =~ ^(.+)[[:space:]]+\(([^()]+)\):[[:space:]]*(.+)$ ]]; then
    error_json "suppression_missing_signature" "Known-issue suppression metadata is unavailable. The todo was removed, but it may be re-promoted."
    return 0
  fi

  parsed_test="${BASH_REMATCH[1]}"
  parsed_file="${BASH_REMATCH[2]}"
  parsed_error="${BASH_REMATCH[3]}"
  phase_dir=$(phase_dir_for_number "$phase_num")
  if [ -z "$phase_dir" ]; then
    error_json "suppression_missing_phase" "Known-issue suppression metadata is incomplete. The todo was removed, but it may be re-promoted."
    return 0
  fi

  query_json=$(jq -cn \
    --arg test "$parsed_test" \
    --arg file "$parsed_file" \
    --arg error "$parsed_error" \
    --arg disposition "$disposition" \
    --arg source_path "$source_path" \
    '{test:$test, file:$file, error:$error, disposition:$disposition, source_path:$source_path}')

  lookup_result=$(printf '%s' "$query_json" | bash "$SCRIPT_DIR/track-known-issues.sh" lookup-signature "$phase_dir" 2>/dev/null || true)
  lookup_status=$(printf '%s' "$lookup_result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$lookup_status" != "ok" ]; then
    printf '%s\n' "$lookup_result"
    return 0
  fi

  printf '%s\n' "$lookup_result"
}

suppress_known_issue() {
  local item_json="$1"
  local command_label="$2"
  local signature_json phase_dir output_json status_val lookup_result lookup_status

  signature_json=$(printf '%s' "$item_json" | jq -c '.known_issue_signature // null')
  if [ "$signature_json" = "null" ]; then
    lookup_result=$(lookup_legacy_known_issue_signature "$item_json")
    lookup_status=$(printf '%s' "$lookup_result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
    if [ "$lookup_status" != "ok" ]; then
      printf '%s\n' "$lookup_result"
      return 0
    fi
    signature_json=$(printf '%s' "$lookup_result" | jq -c '.signature')
  fi

  phase_dir=$(printf '%s' "$signature_json" | jq -r '.phase_dir // empty')
  phase_dir=$(normalize_phase_dir "$phase_dir")
  if [ -z "$phase_dir" ]; then
    error_json "suppression_missing_phase" "Known-issue suppression metadata is incomplete. The todo was removed, but it may be re-promoted."
    return 0
  fi

  output_json=$(printf '%s' "$signature_json" | jq -c --arg via "$command_label" '. + {via:$via}' | bash "$SCRIPT_DIR/track-known-issues.sh" suppress "$phase_dir" 2>/dev/null || true)
  status_val=$(printf '%s' "$output_json" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$status_val" != "ok" ]; then
    printf '%s\n' "$output_json"
    return 0
  fi

  printf '%s\n' "$output_json"
}

cleanup_detail_if_safe() {
  local item_json="$1"
  local detail_status="$2"
  local cleanup_policy="$3"
  local ref result status_val

  ref=$(printf '%s' "$item_json" | jq -r '.ref // empty')
  if [ -z "$ref" ] || [ "$detail_status" = "none" ]; then
    ok_json --arg status "ok" --arg action "skipped" '{status:$status, action:$action}'
    return 0
  fi

  if [ "$detail_status" = "not_found" ] || [ "$detail_status" = "error" ]; then
    jq -cn \
      --arg status "warning" \
      --arg code "detail_cleanup_skipped" \
      --arg message "Todo detail cleanup was skipped for ref ${ref} because the detail load status was ${detail_status}. The todo was removed, but the sidecar registry was left untouched." \
      '{status:$status, code:$code, message:$message}'
    return 0
  fi

  if [ "$cleanup_policy" != "safe" ]; then
    ok_json --arg status "ok" --arg action "skipped" '{status:$status, action:$action}'
    return 0
  fi

  result=$(bash "$SCRIPT_DIR/todo-details.sh" remove "$ref" "$DETAILS_PATH" 2>/dev/null || true)
  status_val=$(printf '%s' "$result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$status_val" != "ok" ]; then
    error_json "detail_cleanup_failed" "Todo detail cleanup failed for ref ${ref}. The todo was removed, but cleanup needs attention."
    return 0
  fi

  printf '%s\n' "$result"
}

rewrite_state_for_item() {
  local item_json="$1"
  local activity_message="$2"
  local state_path section_name section_index line_no direct_count tmp_file

  state_path=$(printf '%s' "$item_json" | jq -r '.state_path // empty')
  section_name=$(printf '%s' "$item_json" | jq -r '.section // empty')
  section_index=$(printf '%s' "$item_json" | jq -r '.section_index // empty')
  line_no=$(printf '%s' "$item_json" | jq -r '.line_no // empty')

  if [ -z "$state_path" ] || [ -z "$section_name" ] || [ -z "$line_no" ]; then
    error_json "invalid_item" "Todo selection payload is missing required metadata. Rerun /vbw:list-todos."
    return 0
  fi

  if state_path_is_archived "$state_path"; then
    error_json "archived_state" "$(archived_state_message)"
    return 0
  fi

  direct_count=$(extract_section_lines "$state_path" "$section_name" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')
  tmp_file=$(mktemp "${state_path}.rewrite.XXXXXX")

  if [ "$direct_count" -le 1 ] 2>/dev/null; then
    awk -v target="$line_no" '
      NR == target { print "None."; next }
      { print }
    ' "$state_path" > "$tmp_file"
  else
    awk -v target="$line_no" '
      NR == target { next }
      { print }
    ' "$state_path" > "$tmp_file"
  fi

  append_activity_entry "$tmp_file" "$activity_message"
  mv "$tmp_file" "$state_path"

  ok_json --arg status "ok" --arg state_path "$state_path" '{status:$status, state_path:$state_path}'
}

mutate_item() {
  local mode="$1"
  local command_label="$2"
  local detail_status="$3"
  local cleanup_policy="$4"
  local item_json validated_json activity_text rewrite_result rewrite_status detail_cleanup_result detail_cleanup_status suppression_result suppression_status final_status final_warning

  item_json=$(read_stdin)
  if ! printf '%s' "$item_json" | jq empty >/dev/null 2>&1; then
    error_json "invalid_item" "Todo selection payload is invalid. Rerun /vbw:list-todos."
    return 0
  fi

  validated_json=$(validate_item_against_live "$item_json")
  rewrite_status=$(printf '%s' "$validated_json" | jq -r '.status // "ok"' 2>/dev/null || echo 'error')
  if [ "$rewrite_status" = "error" ]; then
    printf '%s\n' "$validated_json"
    return 0
  fi

  if state_path_is_archived "$(printf '%s' "$validated_json" | jq -r '.state_path // empty')"; then
    error_json "archived_state" "$(archived_state_message)"
    return 0
  fi

  activity_text=$(printf '%s' "$validated_json" | jq -r '.display_identity // .normalized_text // "todo"')
  case "$mode" in
    pickup) activity_text="Picked up todo via ${command_label}: ${activity_text}" ;;
    remove) activity_text="Removed todo via /vbw:list-todos: ${activity_text}" ;;
    *) activity_text="Updated todo: ${activity_text}" ;;
  esac

  rewrite_result=$(rewrite_state_for_item "$validated_json" "$activity_text")
  rewrite_status=$(printf '%s' "$rewrite_result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$rewrite_status" != "ok" ]; then
    printf '%s\n' "$rewrite_result"
    return 0
  fi

  final_status="ok"
  final_warning=""

  detail_cleanup_result=$(cleanup_detail_if_safe "$validated_json" "$detail_status" "$cleanup_policy")
  detail_cleanup_status=$(printf '%s' "$detail_cleanup_result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$detail_cleanup_status" != "ok" ]; then
    final_status="partial"
    final_warning=$(printf '%s' "$detail_cleanup_result" | jq -r '.message // empty' 2>/dev/null || true)
  fi

  if [ "$(printf '%s' "$validated_json" | jq -r '.priority // empty')" = "known-issue" ]; then
    suppression_result=$(suppress_known_issue "$validated_json" "$command_label")
    suppression_status=$(printf '%s' "$suppression_result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
    if [ "$suppression_status" != "ok" ]; then
      final_status="partial"
      if [ -n "$final_warning" ]; then
        final_warning+=" "
      fi
      final_warning+=$(printf '%s' "$suppression_result" | jq -r '.message // empty' 2>/dev/null || true)
    fi
  fi

  jq -cn \
    --arg status "$final_status" \
    --arg action "$mode" \
    --arg command_label "$command_label" \
    --arg state_path "$(printf '%s' "$validated_json" | jq -r '.state_path // empty')" \
    --arg warning "$final_warning" \
    '{
      status:$status,
      action:$action,
      command_label:$command_label,
      state_path:$state_path,
      warning:(if $warning == "" then null else $warning end)
    }'
}

case "$CMD" in
  snapshot-save)
    snapshot_save
    ;;
  snapshot-show)
    snapshot_show
    ;;
  snapshot-select)
    snapshot_select "$@"
    ;;
  validate-item)
    validate_item_cmd
    ;;
  detail-warning)
    detail_warning "$@"
    ;;
  pickup)
    mutate_item "pickup" "${1:-}" "${2:-none}" "${3:-keep}"
    ;;
  remove)
    mutate_item "remove" "/vbw:list-todos" "${1:-none}" "${2:-keep}"
    ;;
  *)
    usage
    ;;
esac
