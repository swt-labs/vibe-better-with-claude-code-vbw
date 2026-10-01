#!/usr/bin/env bash
# vbw milestone start TITLE: open the next milestone once the current one has
# shipped. Shipped requirements, plans and checks stay in the record: their
# checks keep running in every vbw prove, so later work cannot silently break
# shipped work. The new milestone starts with no requirements (vbw next: spec).

cmd_milestone() {
  [ $# -eq 2 ] && [ "$1" = start ] && [ -n "$2" ] || vbw_usage_error "usage: vbw milestone start TITLE"
  vbw_require_project
  record_read | jq -e '.milestone.status == "shipped"' > /dev/null \
    || vbw_die "$(record_read | jq -r '"\(.milestone.id) is not shipped yet: finish it first (vbw next)"')"
  record_update '.milestone = {id: "M\((.milestone.id | ltrimstr("M") | tonumber) + 1)", title: $t, status: "active"}' \
    --arg t "$2"
  record_commit "chore(vbw): start $(jq -r .milestone.id "$VBW_RECORD")"
  jq -r '"started \(.milestone.id) \(.milestone.title): add its requirements to .vbw/spec.md (vbw spec add)"' "$VBW_RECORD"
}
