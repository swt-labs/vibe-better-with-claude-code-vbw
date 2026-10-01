#!/usr/bin/env bash
# vbw ship: the user ships the milestone once vbw next says so (everything
# proven on the current files and accepted). Marks it shipped and logs the
# decision; it publishes nothing (no tag, no push).

cmd_ship() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw ship"
  vbw_require_project
  # shellcheck source=cmd-next.sh
  . "$VBW_LIB/cmd-next.sh"
  local action
  action=$(cmd_next --json | jq -r .action)
  [ "$action" = ship ] || vbw_die "not ready to ship: vbw next says $action ($(cmd_next | cut -d: -f2- | sed 's/^ //'))"
  record_update "$VBW_JQ_DEFS"'.milestone.status = "shipped"
    | .decisions += [{id: (.decisions | next_id("D")), at: $at,
        text: "Shipped \(.milestone.id) \(.milestone.title): \(.requirements | length) requirements proven or accepted"}]' \
    --arg at "$(vbw_now)"
  jq -r '"shipped \(.milestone.id) \(.milestone.title)"' "$VBW_RECORD"
}
