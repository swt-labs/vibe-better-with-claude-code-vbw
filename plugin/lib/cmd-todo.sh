#!/usr/bin/env bash
# vbw todo [list] | add [--sort next|later --size small|medium|large] TEXT | sort ID next|later small|medium|large | done ID | drop ID: the backlog in the plan of
# record (ideas for later; they do not enter the current milestone by themselves).

# The open and in-progress items, next first, then later, then unsorted, each group by id.
TODO_OPEN_JQ='[.todos[] | select(.status == "open" or .status == "in_progress")]
  | sort_by([(if .sort == "next" then 0 elif .sort == "later" then 1 else 2 end), (.id[1:] | tonumber)])'

cmd_todo() {
  local sub="${1:-list}" sort="" size=""
  [ $# -gt 0 ] && shift
  case "$sub" in
    list) [ $# -eq 0 ] || vbw_usage_error "usage: vbw todo list" ;;
    add)
      while [ $# -gt 0 ]; do
        case "$1" in
          --sort) [ $# -ge 2 ] || vbw_usage_error "usage: vbw todo add [--sort next|later --size small|medium|large] TEXT"
            sort="$2"; shift 2 ;;
          --size) [ $# -ge 2 ] || vbw_usage_error "usage: vbw todo add [--sort next|later --size small|medium|large] TEXT"
            size="$2"; shift 2 ;;
          *) break ;;
        esac
      done
      [ $# -eq 1 ] && [ -n "$1" ] || vbw_usage_error "usage: vbw todo add [--sort next|later --size small|medium|large] TEXT"
      if [ -n "$sort$size" ]; then
        case "$sort" in next|later) ;; *) vbw_usage_error "--sort needs next or later, together with --size small, medium or large" ;; esac
        case "$size" in small|medium|large) ;; *) vbw_usage_error "--size needs small, medium or large, together with --sort next or later" ;; esac
      fi
      ;;
    sort) [ $# -eq 3 ] && [ "$2" = next -o "$2" = later ] && [ "$3" = small -o "$3" = medium -o "$3" = large ] \
      || vbw_usage_error "usage: vbw todo sort ID next|later small|medium|large" ;;
    done|drop) [ $# -eq 1 ] || vbw_usage_error "usage: vbw todo $sub ID" ;;
    *) vbw_usage_error "usage: vbw todo [list] | add [--sort next|later --size small|medium|large] TEXT | sort ID next|later small|medium|large | done ID | drop ID" ;;
  esac
  vbw_require_project
  case "$sub" in
    list)
      record_read | jq -r "$TODO_OPEN_JQ"'
        | if length == 0 then "no open todos (vbw todo add TEXT)"
          else .[] | if has("sort") then "\(.id) [\(.sort), \(.size)] \(.text)" else "\(.id) \(.text)" end end'
      ;;
    add)
      record_update "$VBW_JQ_DEFS"'.todos += [{id: (.todos | next_id("T")), text: $text} + (if $sort == "" then {} else {sort: $sort, size: $size} end) + {status: "open"}]' \
        --arg text "$1" --arg sort "$sort" --arg size "$size"
      jq -r '.todos[-1] | "added \(.id): \(.text)"' "$VBW_RECORD"
      ;;
    sort)
      local state
      state=$(record_read | jq -r --arg t "$1" '[.todos[] | select(.id == $t)][0] | if . == null then "unknown" else .status end')
      [ "$state" != unknown ] || vbw_die "unknown todo $1"
      case "$state" in open|in_progress) ;; *) vbw_die "$1 is closed ($state): only an open item can be sorted" ;; esac
      record_update '(.todos[] | select(.id == $t)) |= (.sort = $sort | .size = $size)' --arg t "$1" --arg sort "$2" --arg size "$3"
      record_read | jq -r --arg t "$1" '.todos[] | select(.id == $t) | "\(.id) [\(.sort), \(.size)] \(.text)"'
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
