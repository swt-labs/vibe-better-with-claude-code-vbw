#!/usr/bin/env bash
# vbw todo [list] | add TEXT | done ID | drop ID: the backlog in the plan of
# record (ideas for later; they do not enter the current milestone by themselves).

cmd_todo() {
  local sub="${1:-list}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    list) [ $# -eq 0 ] || vbw_usage_error "usage: vbw todo list" ;;
    add) [ $# -eq 1 ] && [ -n "$1" ] || vbw_usage_error "usage: vbw todo add TEXT" ;;
    done|drop) [ $# -eq 1 ] || vbw_usage_error "usage: vbw todo $sub ID" ;;
    *) vbw_usage_error "usage: vbw todo [list] | add TEXT | done ID | drop ID" ;;
  esac
  vbw_require_project
  case "$sub" in
    list)
      record_read | jq -r '[.todos[] | select(.status == "open" or .status == "in_progress")]
        | if length == 0 then "no open todos (vbw todo add TEXT)" else .[] | "\(.id) \(.text)" end'
      ;;
    add)
      record_update "$VBW_JQ_DEFS"'.todos += [{id: (.todos | next_id("T")), text: $text, status: "open"}]' \
        --arg text "$1"
      jq -r '.todos[-1] | "added \(.id): \(.text)"' "$VBW_RECORD"
      ;;
    done|drop)
      local outcome=dropped
      [ "$sub" = drop ] || outcome="done"
      record_read | jq -e --arg t "$1" 'any(.todos[]; .id == $t)' > /dev/null || vbw_die "unknown todo $1"
      record_update '(.todos[] | select(.id == $t)).status = $s' --arg t "$1" --arg s "$outcome"
      printf '%s %s\n' "$1" "$outcome"
      ;;
  esac
}
