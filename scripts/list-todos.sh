#!/usr/bin/env bash
set -euo pipefail

# list-todos.sh — Extract and format pending todos from STATE.md
#
# Usage: list-todos.sh [priority-filter]
#   priority-filter: optional "high", "low", or "normal" (case-insensitive)
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
#     "filter": "high"|"low"|"normal"|null,
#     "display": "formatted numbered list",
#     "items": [ { "num": 1, "line": "raw line", "text": "...", "priority": "high"|"normal"|"low", "date": "YYYY-MM-DD", "age": "3d ago" }, ... ] }
#
# Exit codes: always 0 (fail-open for agent consumption)

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
FILTER="${1:-}"

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

# --- Parse a single todo line ---
parse_todo_line() {
  local line="$1"
  local text priority date_str age

  # Strip leading "- "
  text="${line#- }"

  # Extract priority
  if [[ "$text" == "[HIGH] "* ]]; then
    priority="high"
  elif [[ "$text" == "[low] "* ]]; then
    priority="low"
  else
    priority="normal"
  fi

  # Extract date from (added YYYY-MM-DD)
  date_str=""
  if [[ "$text" =~ \(added\ ([0-9]{4}-[0-9]{2}-[0-9]{2})\) ]]; then
    date_str="${BASH_REMATCH[1]}"
  fi

  # Compute age
  age=""
  if [ -n "$date_str" ]; then
    age=$(relative_age "$date_str")
  fi

  # Output as tab-separated: priority\tdate\tage\ttext
  printf '%s\t%s\t%s\t%s\n' "$priority" "$date_str" "$age" "$text"
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
  local items_json="[]"
  local num=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Skip empty/whitespace-only todo lines (bare "- " with no text)
    local stripped="${line#- }"
    stripped="${stripped#"${stripped%%[![:space:]]*}"}"
    [ -z "$stripped" ] && continue
    local parsed
    parsed=$(parse_todo_line "$line")

    local pri date_val age text
    pri=$(echo "$parsed" | cut -f1)
    date_val=$(echo "$parsed" | cut -f2)
    age=$(echo "$parsed" | cut -f3)
    text=$(echo "$parsed" | cut -f4-)

    # Apply filter
    if [ -n "$filter_lower" ] && [ "$filter_lower" != "$pri" ]; then
      continue
    fi

    # num tracks filtered position (matches display numbering)
    num=$((num + 1))
    items_json=$(echo "$items_json" | jq --argjson n "$num" \
      --arg l "$line" --arg t "$text" --arg p "$pri" \
      --arg d "$date_val" --arg a "$age" \
      '. + [{num:$n, line:$l, text:$t, priority:$p, date:$d, age:$a}]')
  done <<< "$todo_lines"

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
    local text age pri pri_tag display_text age_suffix

    text=$(echo "$row" | base64 -d | jq -r '.text')
    age=$(echo "$row" | base64 -d | jq -r '.age')
    pri=$(echo "$row" | base64 -d | jq -r '.priority')

    pri_tag=""
    case "$pri" in
      high) pri_tag="[HIGH] " ;;
      low) pri_tag="[low] " ;;
    esac

    # Strip priority prefix and date suffix for clean display
    display_text="${text#\[HIGH\] }"
    display_text="${display_text#\[low\] }"
    display_text=$(echo "$display_text" | sed 's/ *(added [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\})$//')

    age_suffix=""
    if [ -n "$age" ]; then
      age_suffix=" ($age)"
    fi

    display="${display}${display_num}. ${pri_tag}${display_text}${age_suffix}"$'\n'
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
