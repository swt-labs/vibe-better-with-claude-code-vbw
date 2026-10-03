#!/usr/bin/env bash
# vbw tier raise PHASE TIER REASON: raise a phase's rigor tier and record why.
# A tier is never lowered during a run; the escalation is kept in the record
# and shown by vbw show phase.

# shellcheck source=rigor.sh
. "$VBW_LIB/rigor.sh"

cmd_tier() {
  [ $# -eq 4 ] && [ "$1" = raise ] && [ -n "$4" ] || vbw_usage_error "usage: vbw tier raise PHASE express|standard|deep REASON"
  case "$3" in express|standard|deep) ;; *) vbw_usage_error "unknown tier $3: express, standard or deep" ;; esac
  vbw_require_project
  local record from
  record=$(record_read)
  from=$(printf '%s' "$record" | jq -r --arg p "$2" '[.phases[] | select(.id == $p)][0] | if . == null then "" else (.tier // "express") end')
  [ -n "$from" ] || vbw_die "unknown phase $2"
  printf '%s' "$record" | jq -e --arg a "$from" --arg b "$3" "$VBW_JQ_DEFS"'($b | tier_rank) > ($a | tier_rank)' > /dev/null \
    || vbw_die "a tier is never lowered during a run: $2 is $from, so $3 is refused"
  rigor_escalate "$2" "$4" "$3"
  printf '%s raised from %s to %s: %s\n' "$2" "$from" "$3" "$4"
}
