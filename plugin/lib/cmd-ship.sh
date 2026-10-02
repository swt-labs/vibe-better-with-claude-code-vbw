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
  # The proof reads the files on disk; shipped work must also be in git history.
  local entry dirty=""
  while IFS= read -r -d '' entry; do
    dirty="$dirty ${entry:3}"
  done < <(git -C "$VBW_ROOT" status --porcelain=v1 -z --no-renames --untracked-files=all -- . ':(exclude).vbw')
  [ -z "$dirty" ] || vbw_die "the proven work is not committed:$dirty (commit it, then vbw ship)"
  record_update "$VBW_JQ_DEFS"'.milestone.id as $m | .milestone.status = "shipped"
    | .shipped += [{id: .milestone.id, title: .milestone.title, at: $at}]
    | .decisions += [{id: (.decisions | next_id("D")), at: $at,
        text: "Shipped \(.milestone.id) \(.milestone.title): \([.requirements[] | select(.milestone == $m)] | length) requirements proven or accepted"}]' \
    --arg at "$(vbw_now)"
  record_commit "chore(vbw): ship $(jq -r .milestone.id "$VBW_RECORD")"
  jq -r '"shipped \(.milestone.id) \(.milestone.title)"' "$VBW_RECORD"
}
