#!/usr/bin/env bash
set -euo pipefail

# list-todos.sh — Extract and format pending todos from STATE.md
#
# Usage: list-todos.sh [priority-filter]
#   priority-filter: optional "high", "low", "known-issue", or "normal" (case-insensitive)
#
# Resolves milestone-scoped STATE.md, extracts ## Todos (or ### Pending Todos
# for legacy/pre-migration STATE.md), parses priority tags and dates, computes
# relative ages, and outputs a ready-to-display numbered list.
#
# Output (JSON):
#   { "status": "ok"|"empty"|"no-match"|"error",
#     "state_path": "...",
#     "section": "## Todos"|"### Pending Todos",
#     "count": N,
#     "filter": "high"|"low"|"normal"|"known-issue"|null,
#     "display": "formatted numbered list",
#     "items": [
#       {
#         "num": 1,
#         "section_index": 2,
#         "line": "raw line",
#         "text": "full todo text with tags/date/ref",
#         "display_identity": "display text without date/ref",
#         "normalized_text": "tag-free text for matching/logging",
#         "command_text": "tag-free text for command routing",
#         "priority": "high"|"normal"|"low"|"known-issue",
#         "date": "YYYY-MM-DD"|null,
#         "age": "3d ago"|null,
#         "ref": "abcd1234"|null,
#         "state_path": "...",
#         "section": "## Todos"|"### Pending Todos",
#         "known_issue_signature": { ... }|null
#       },
#       ...
#     ] }
#
# Exit codes: always 0 (fail-open for agent consumption)

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
FILTER="${1:-}"
DETAILS_PATH="${PLANNING_DIR}/todo-details.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Resolve STATE.md for todos (project-level data lives at root) ---
resolve_state_path() {
  local state_path="$PLANNING_DIR/STATE.md"

  # Project-level todos always live at root STATE.md.
  if [ -f "$state_path" ]; then
    echo "$state_path"
    return 0
  fi

  # Fallback: no root — use most-recently-modified archived STATE.md
  local latest_milestone=""
  local latest_mtime=0
  for f in "$PLANNING_DIR"/milestones/*/STATE.md; do
    [ -f "$f" ] || continue
    local mtime
    mtime=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null || echo 0)
    if [[ "$mtime" -gt "$latest_mtime" ]]; then
      latest_mtime="$mtime"
      latest_milestone="$f"
    fi
  done
  if [ -n "$latest_milestone" ]; then
    echo "$latest_milestone"
    return 0
  fi

  echo '{"status":"error","message":"STATE.md not found at '"$state_path"'. Run /vbw:init to set up your project."}'
  return 1
}

# --- Extract todo lines from a section ---
extract_todos() {
  local file="$1"
  local section_name=""
  local lines=""

  # Try ## Todos first (current format — items directly under heading)
  # Must NOT match items inside a ### subsection
  lines=$(awk '
    /^## Todos$/ { found=1; next }
    found && /^##/ { exit }
    found && /^### / { sub_found=1; next }
    found && sub_found && /^##/ { exit }
    found && !sub_found && /^- / { print }
  ' "$file")

  if [ -n "$lines" ]; then
    section_name="## Todos"
  else
    # Legacy fallback: ### Pending Todos subsection (pre-migration STATE.md)
    lines=$(awk '
      /^### Pending Todos$/ { found=1; next }
      found && /^### Completed Todos$/ { exit }
      found && /^##/ { exit }
      found && /^- / { print }
    ' "$file")
    if [ -n "$lines" ]; then
      section_name="### Pending Todos"
    fi
  fi

  # Check for "None." placeholder (no actual todo lines)
  if [ -z "$lines" ]; then
    echo ""
    return
  fi

  echo "$section_name"
  echo "$lines"
}

# --- Compute relative age from YYYY-MM-DD ---
relative_age() {
  local date_str="$1"
  local now days

  # Validate date format
  if ! [[ "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo ""
    return
  fi

  now=$(date +%s)
  local then_ts
  then_ts=$(date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null) || {
    # Linux fallback
    then_ts=$(date -d "$date_str" +%s 2>/dev/null) || { echo ""; return; }
  }

  days=$(( (now - then_ts) / 86400 ))

  if [ "$days" -lt 0 ]; then
    echo ""
    return
  elif [ "$days" -eq 0 ]; then
    echo "today"
  elif [ "$days" -eq 1 ]; then
    echo "1d ago"
  elif [ "$days" -lt 30 ]; then
    echo "${days}d ago"
  elif [ "$days" -lt 365 ]; then
    local months=$(( days / 30 ))
    echo "${months}mo ago"
  else
    local years=$(( days / 365 ))
    echo "${years}y ago"
  fi
}

decode_base64() {
  printf '%s' "$1" | base64 -d 2>/dev/null || printf '%s' "$1" | base64 -D 2>/dev/null
}

# --- Parse a single todo line ---
parse_todo_line() {
  local line="$1"
  local section_index="$2"
  local state_path="$3"
  local section_name="$4"
  local text priority date_str age ref display_identity normalized_text command_text detail_json known_issue_signature source

  # Strip leading "- "
  text="${line#- }"

  # Extract priority/category
  if [[ "$text" == "[HIGH] "* ]]; then
    priority="high"
  elif [[ "$text" == "[low] "* ]]; then
    priority="low"
  elif [[ "$text" == "[KNOWN-ISSUE] "* ]]; then
    priority="known-issue"
  else
    priority="normal"
  fi

  # Extract date from (added YYYY-MM-DD)
  date_str=""
  if [[ "$text" =~ \(added\ ([0-9]{4}-[0-9]{2}-[0-9]{2})\) ]]; then
    date_str="${BASH_REMATCH[1]}"
  fi

  # Extract detail ref hash from (ref:<8-hex-chars>)
  ref=""
  if [[ "$text" =~ \(ref:([a-f0-9]{8})\)[[:space:]]*$ ]]; then
    ref="${BASH_REMATCH[1]}"
  fi

  # Compute age
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
  if [ -n "$ref" ] && [ -f "$DETAILS_PATH" ]; then
    detail_json=$(bash "$SCRIPT_DIR/todo-details.sh" get "$ref" "$DETAILS_PATH" 2>/dev/null | jq -c '.detail // {}' 2>/dev/null || echo '{}')
    known_issue_signature=$(printf '%s' "$detail_json" | jq -c '
      .known_issue_signature // null
      | if type == "object" then {
          phase: (.phase // null),
          phase_dir: (.phase_dir // null),
          test: (.test // null),
          file: (.file // null),
          error: (.error // null),
          source_kind: (.source_kind // null),
          disposition: (.disposition // null),
          source_path: (.source_path // null)
        } else null end
    ' 2>/dev/null || echo 'null')
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
    --arg ref "$ref" \
    --arg state_path "$state_path" \
    --arg section "$section_name" \
    --argjson section_index "$section_index" \
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
      ref:(if $ref == "" then null else $ref end),
      state_path:$state_path,
      section:$section,
      section_index:$section_index,
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

# --- Main ---
main() {
  local filter_lower=""
  if [ -n "$FILTER" ]; then
    filter_lower=$(echo "$FILTER" | tr '[:upper:]' '[:lower:]')
  fi

  # Resolve STATE.md
  local state_path
  state_path=$(resolve_state_path) || { echo "$state_path"; exit 0; }

  # Extract todos
  local raw_output section_name
  raw_output=$(extract_todos "$state_path")

  if [ -z "$raw_output" ]; then
    jq -n --arg sp "$state_path" --arg f "${filter_lower:-null}" \
      '{status:"empty", state_path:$sp, section:null, count:0,
        filter:(if $f == "null" then null else $f end),
        display:"No pending todos.", items:[]}'
    exit 0
  fi

  # First line is section name, rest are todo lines
  section_name=$(echo "$raw_output" | head -1)
  local todo_lines
  todo_lines=$(echo "$raw_output" | tail -n +2)

  # Parse all todos into a JSON array via jq
  local all_items_json="[]"
  local items_json="[]"
  local num=0
  local section_index=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Skip empty/whitespace-only todo lines (bare "- " with no text)
    local stripped="${line#- }"
    stripped="${stripped#"${stripped%%[![:space:]]*}"}"
    [ -z "$stripped" ] && continue
    section_index=$((section_index + 1))

    local parsed pri
    parsed=$(parse_todo_line "$line" "$section_index" "$state_path" "$section_name")
    all_items_json=$(echo "$all_items_json" | jq --argjson item "$parsed" '. + [$item]')
  done <<< "$todo_lines"

  all_items_json=$(annotate_identity_occurrence "$all_items_json")

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    local parsed pri
    parsed="$row"
    pri=$(echo "$parsed" | jq -r '.priority')

    # Apply filter
    if [ -n "$filter_lower" ] && [ "$filter_lower" != "$pri" ]; then
      continue
    fi

    # num tracks filtered position (matches display numbering)
    num=$((num + 1))
    items_json=$(echo "$items_json" | jq --argjson n "$num" --argjson item "$parsed" '. + [($item + {num:$n})]')
  done < <(printf '%s' "$all_items_json" | jq -c '.[]')

  local filtered_count
  filtered_count=$(echo "$items_json" | jq 'length')

  if [ "$filtered_count" -eq 0 ]; then
    local msg
    if [ -n "$filter_lower" ]; then
      msg="No ${filter_lower}-priority todos found."
    else
      msg="No pending todos."
    fi
    jq -n --arg st "$([ -n "$filter_lower" ] && echo "no-match" || echo "empty")" \
      --arg sp "$state_path" --arg sec "$section_name" \
      --arg f "${filter_lower:-null}" --arg msg "$msg" \
      '{status:$st, state_path:$sp, section:$sec, count:0,
        filter:(if $f == "null" then null else $f end),
        display:$msg, items:[]}'
    exit 0
  fi

  # Build display string from items
  local display=""
  local display_num=0
  for row in $(echo "$items_json" | jq -r '.[] | @base64'); do
    display_num=$((display_num + 1))
    local decoded_row text age pri pri_tag display_text age_suffix

    decoded_row=$(decode_base64 "$row")
    text=$(printf '%s' "$decoded_row" | jq -r '.text')
    age=$(printf '%s' "$decoded_row" | jq -r '.age')
    pri=$(printf '%s' "$decoded_row" | jq -r '.priority')

    pri_tag=""
    case "$pri" in
      high) pri_tag="[HIGH] " ;;
      low) pri_tag="[low] " ;;
      known-issue) pri_tag="[KNOWN-ISSUE] " ;;
    esac

    display_text=$(printf '%s' "$decoded_row" | jq -r '.normalized_text')

    # Show [detail] indicator for todos with extended detail
    local ref_indicator=""
    local item_ref
    item_ref=$(printf '%s' "$decoded_row" | jq -r '.ref // ""')
    if [ -n "$item_ref" ]; then
      ref_indicator=" [detail]"
    fi

    age_suffix=""
    if [ -n "$age" ]; then
      age_suffix=" ($age)"
    fi

    display="${display}${display_num}. ${pri_tag}${display_text}${age_suffix}${ref_indicator}"$'\n'
  done

  # Assemble final JSON via jq
  echo "$items_json" | jq --arg st "ok" --arg sp "$state_path" \
    --arg sec "$section_name" --argjson c "$filtered_count" \
    --arg f "${filter_lower:-null}" --arg d "$display" \
    '{status:$st, state_path:$sp, section:$sec, count:$c,
      filter:(if $f == "null" then null else $f end),
      display:$d, items:.}'
}

main
