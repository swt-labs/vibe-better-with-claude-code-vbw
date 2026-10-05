#!/usr/bin/env bash
# vbw tools [--json] | answer yes|no: whether the user allowed VBW to look for
# the best tools for this project (docs/tools.md). The answer and its time live
# in the project record (project.tools), so the question is asked once per
# project, whatever the session or worktree. Nothing here searches or installs.

cmd_tools() {
  local sub="${1:-}" t
  vbw_require_project
  case "$sub" in
    "" | --json)
      t=$(record_read | jq -c '(.project.tools // null) as $t | {asked: ($t != null), answer: ($t.answer // null), at: ($t.at // null)}')
      if [ "$sub" = "--json" ]; then
        printf '%s\n' "$t"
      else
        printf '%s' "$t" | jq -r 'if .asked then "tool search: asked, answer \(.answer) (\(.at))" else "tool search: not asked yet" end'
      fi
      ;;
    answer)
      [ $# -eq 2 ] || vbw_usage_error "usage: vbw tools answer yes|no"
      case "$2" in yes | no) ;; *) vbw_usage_error "the answer is yes or no" ;; esac
      record_update '.project.tools = {answer: $a, at: $at}' --arg a "$2" --arg at "$(vbw_now)"
      printf 'tool search: %s\n' "$2"
      ;;
    *) vbw_usage_error "usage: vbw tools [--json] | answer yes|no" ;;
  esac
}
