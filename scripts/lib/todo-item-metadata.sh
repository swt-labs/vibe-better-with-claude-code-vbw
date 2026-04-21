#!/usr/bin/env bash

# todo-item-metadata.sh — shared todo parsing / identity helpers for list and lifecycle flows.
#
# Callers must set DETAILS_PATH before using ref-aware helpers.

: "${DETAILS_PATH:=}"
: "${DETAILS_CACHE_JSON:=}"

todo_item_relative_age() {
  local date_str="$1"
  local now days then_ts

  if ! [[ "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo ""
    return
  fi

  now=$(date +%s)
  then_ts=$(date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null) || {
    then_ts=$(date -d "$date_str" +%s 2>/dev/null) || { echo ""; return; }
  }

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

todo_item_canonical_signature_json() {
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

todo_item_load_detail_for_ref() {
  local ref="${1:-}"
  if [ -z "$ref" ] || [ -z "$DETAILS_PATH" ] || [ ! -f "$DETAILS_PATH" ]; then
    echo '{}'
    return
  fi
  if [ -z "$DETAILS_CACHE_JSON" ]; then
    DETAILS_CACHE_JSON=$(cat "$DETAILS_PATH" 2>/dev/null || echo '{}')
  fi
  printf '%s' "$DETAILS_CACHE_JSON" | jq -c --arg ref "$ref" '.items[$ref] // {}' 2>/dev/null || echo '{}'
}

todo_item_parse_line_json() {
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
    age=$(todo_item_relative_age "$date_str")
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
  if [ -n "$ref" ] && [ -n "$DETAILS_PATH" ] && [ -f "$DETAILS_PATH" ]; then
    detail_json=$(todo_item_load_detail_for_ref "$ref")
    known_issue_signature=$(printf '%s' "$detail_json" | jq -c '.known_issue_signature // null' 2>/dev/null || echo 'null')
    known_issue_signature=$(todo_item_canonical_signature_json "$known_issue_signature")
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

todo_item_annotate_identity_occurrence() {
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
