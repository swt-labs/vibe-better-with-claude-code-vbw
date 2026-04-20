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
# shellcheck disable=SC2034  # consumed by sourced todo-item-metadata helpers
DETAILS_PATH="${PLANNING_DIR}/todo-details.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # consumed by sourced todo-item-metadata helpers
DETAILS_CACHE_JSON=""

# shellcheck source=scripts/lib/todo-item-metadata.sh
. "$SCRIPT_DIR/lib/todo-item-metadata.sh"

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
  local all_items_json items_json
  local section_index=0
  local all_items_ndjson
  all_items_ndjson=$(mktemp)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Skip empty/whitespace-only todo lines (bare "- " with no text)
    local stripped="${line#- }"
    stripped="${stripped#"${stripped%%[![:space:]]*}"}"
    [ -z "$stripped" ] && continue
    section_index=$((section_index + 1))

    local parsed
    parsed=$(todo_item_parse_line_json "$line" "$section_index" "$state_path" "$section_name")
    printf '%s\n' "$parsed" >> "$all_items_ndjson"
  done <<< "$todo_lines"

  all_items_json=$(jq -sc '.' "$all_items_ndjson")
  rm -f "$all_items_ndjson"
  all_items_json=$(todo_item_annotate_identity_occurrence "$all_items_json")
  items_json=$(printf '%s' "$all_items_json" | jq -c --arg filter "$filter_lower" '
    [ .[]
      | if $filter == "" then . else select(.priority == $filter) end
    ]
    | to_entries
    | map(.value + {num:(.key + 1)})
  ')

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
  local display
  display=$(printf '%s' "$items_json" | jq -r '
    .[] |
      (
        (if .priority == "high" then "[HIGH] " elif .priority == "low" then "[low] " elif .priority == "known-issue" then "[KNOWN-ISSUE] " else "" end)
        + .normalized_text
        + (if .age then " (" + .age + ")" else "" end)
        + (if .ref then " [detail]" else "" end)
      ) as $body
      | "\(.num). \($body)"
  ')
  [ -n "$display" ] && display="${display}"$'\n'

  # Assemble final JSON via jq
  echo "$items_json" | jq --arg st "ok" --arg sp "$state_path" \
    --arg sec "$section_name" --argjson c "$filtered_count" \
    --arg f "${filter_lower:-null}" --arg d "$display" \
    '{status:$st, state_path:$sp, section:$sec, count:$c,
      filter:(if $f == "null" then null else $f end),
      display:$d, items:.}'
}

main
