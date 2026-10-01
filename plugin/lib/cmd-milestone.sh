#!/usr/bin/env bash
# vbw milestone start TITLE | rename TITLE.
# start opens the next milestone once the current one has shipped. Shipped
# requirements, plans and checks stay in the record: their checks keep running
# in every vbw prove, so later work cannot silently break shipped work. The new
# milestone starts with no requirements (vbw next: spec).
# rename names the current milestone (vbw init calls M1 "First milestone");
# a shipped milestone keeps the name it shipped with.

cmd_milestone() {
  [ $# -eq 2 ] && { [ "$1" = start ] || [ "$1" = rename ]; } && [ -n "$2" ] \
    || vbw_usage_error "usage: vbw milestone start TITLE | milestone rename TITLE"
  vbw_require_project
  if [ "$1" = rename ]; then
    record_read | jq -e '.milestone.status != "shipped"' > /dev/null \
      || vbw_die "$(record_read | jq -r '"\(.milestone.id) has shipped: start the next one (vbw milestone start TITLE)"')"
    record_update '.milestone.title = $t' --arg t "$2"
    jq -r '"\(.milestone.id) is now \(.milestone.title)"' "$VBW_RECORD"
    return 0
  fi
  record_read | jq -e '.milestone.status == "shipped"' > /dev/null \
    || vbw_die "$(record_read | jq -r '"\(.milestone.id) is not shipped yet: finish it first (vbw next)"')"
  record_update '.milestone = {id: "M\((.milestone.id | ltrimstr("M") | tonumber) + 1)", title: $t, status: "active"}' \
    --arg t "$2"
  record_commit "chore(vbw): start $(jq -r .milestone.id "$VBW_RECORD")"
  jq -r '"started \(.milestone.id) \(.milestone.title): add its requirements to .vbw/spec.md (vbw spec add)"' "$VBW_RECORD"
}
