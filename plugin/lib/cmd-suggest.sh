#!/usr/bin/env bash
# vbw suggest decline TEXT | list: suggestions the user declined, kept in the
# plan of record (project.declined) so they are never offered again in the
# project (R40). Matching ignores case and spacing.

cmd_suggest() {
  local sub="${1:-}"
  vbw_require_project
  case "$sub" in
    decline)
      [ $# -eq 2 ] && [ -n "$2" ] || vbw_usage_error "usage: vbw suggest decline TEXT"
      record_update "$VBW_JQ_DEFS"'def norm: ascii_downcase | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
        if any((.project.declined // [])[]; (.text | norm) == ($t | norm)) then .
        else .project.declined = ((.project.declined // []) + [{text: $t, at: $at}]) end' \
        --arg t "$2" --arg at "$(vbw_now)"
      printf 'declined: %s\n' "$2"
      ;;
    list)
      [ $# -eq 1 ] || vbw_usage_error "usage: vbw suggest list"
      record_read | jq -r '(.project.declined // []) | if length == 0 then "none declined" else .[].text end'
      ;;
    *) vbw_usage_error "usage: vbw suggest decline TEXT | list" ;;
  esac
}
