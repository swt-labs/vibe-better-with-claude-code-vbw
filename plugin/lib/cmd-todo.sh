#!/usr/bin/env bash
# vbw todo: backlog items in the plan of record.

cmd_todo() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    add)
      [ $# -eq 1 ] || vbw_usage_error "usage: vbw todo add TEXT"
      vbw_require_project
      record_update "$VBW_JQ_DEFS"'.todos += [{id: (.todos | next_id("T")), text: $text, status: "open"}]' \
        --arg text "$1"
      jq -r '.todos[-1] | "added \(.id): \(.text)"' "$VBW_RECORD"
      ;;
    *) vbw_usage_error "usage: vbw todo add TEXT" ;;
  esac
}
