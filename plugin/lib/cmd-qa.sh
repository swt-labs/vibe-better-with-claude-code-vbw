#!/usr/bin/env bash
# vbw qa finding REQ TEXT | record PHASE pass|fail TIER [NOTE]: the QA agent's
# goal-backward verification of a built phase (VBW 1's QA mandate; docs/proof.md).
# A finding opens a fix item marked source "qa": only QA closes it, because the
# checks may pass while the work still deviates from the plan. The verdict is
# recorded against the digest of the phase's inputs and those of the phases it
# builds on (lib/qa-inputs.sh): a change to them needs QA again, others do not. Three failed rounds in a row escalate.

VBW_QA_ROUNDS=3

cmd_qa() {
  local sub="${1:-}"
  case "$sub" in
    finding) [ $# -eq 3 ] && [ -n "$3" ] || vbw_usage_error "usage: vbw qa finding REQ TEXT" ;;
    record)
      [ $# -ge 4 ] && [ $# -le 5 ] && { [ "$3" = pass ] || [ "$3" = fail ]; } \
        && { [ "$4" = quick ] || [ "$4" = standard ] || [ "$4" = deep ]; } \
        || vbw_usage_error "usage: vbw qa record PHASE pass|fail quick|standard|deep [NOTE]"
      ;;
    *) vbw_usage_error "usage: vbw qa finding REQ TEXT | qa record PHASE pass|fail TIER [NOTE]" ;;
  esac
  vbw_require_project
  local record
  record=$(record_read)
  if [ "$sub" = finding ]; then
    printf '%s' "$record" | jq -e --arg q "$2" 'any(.requirements[]; .id == $q)' > /dev/null || vbw_die "unknown requirement $2"
    record_update "$VBW_JQ_DEFS"'.fixes += [{id: (.fixes | next_id("F")), req: $q, source: "qa", attempts: 0, status: "open", note: $t}]
      | escalate_phases([.phases[] | select((.tier // "express") == "express" and (.reqs | index($q))) | .id]; null; "QA found a problem in \($q): \($t)"; $at)' \
      --arg q "$2" --arg t "$3" --arg at "$(vbw_now)"
    jq -r '.fixes[-1] | "\(.id) opened for \(.req) (qa): \(.note)"' "$VBW_RECORD"
    return 0
  fi
  local phase="$2" result="$3" tier="$4" note="${5:-}" tree digests
  printf '%s' "$record" | jq -e --arg p "$phase" 'any(.phases[]; .id == $p)' > /dev/null || vbw_die "unknown phase $phase"
  printf '%s' "$record" | jq -e '.evidence.tree' > /dev/null || vbw_die "no proof yet: QA verifies proven work (vbw prove first)"
  # shellcheck source=cmd-next.sh
  . "$VBW_LIB/cmd-next.sh"
  ! next_code_changed "$record" || vbw_die "the code changed since the last proof: run vbw prove, then record the verdict again"
  printf '%s' "$record" | jq -e '.evidence.full != false' > /dev/null || vbw_die "the last proof was partial: run vbw prove --full, then record the verdict again"
  # The pass covers this phase's inputs and those of the phases it builds on (D91).
  digests=$(qa_digests "$record")
  tree=$(printf '%s' "$digests" | jq -r --arg p "$phase" '.[$p].combined // empty')
  [ -n "$tree" ] || vbw_die "$phase is not a phase of the active milestone"
  if [ "$result" = fail ]; then
    printf '%s' "$record" | jq -e --arg p "$phase" '. as $r | ([.phases[] | select(.id == $p)][0].reqs) as $q
      | any(.fixes[]; .source == "qa" and .status == "open" and (.req as $x | any($q[]; . == $x)))' > /dev/null \
      || vbw_die "a failed verdict needs its findings first (vbw qa finding REQ TEXT for each)"
  fi
  record_update "$VBW_JQ_DEFS"'([.phases[] | select(.id == $p)][0]) as $ph
    | ($ph.reqs) as $q
    | (if $res == "fail" and ($ph.qa.result // "") == "fail" then ($ph.qa.rounds // 1) + 1 elif $res == "fail" then 1 else 0 end) as $rounds
    | (.phases[] | select(.id == $p)).qa = ({result: $res, tier: $tier, tree: $tree, at: $at}
        + (if $note != "" then {note: $note} else {} end) + (if $rounds > 0 then {rounds: $rounds} else {} end))
    | .fixes |= map(if .source == "qa" and (.req as $x | any($q[]; . == $x)) then
        (if $res == "pass" and (.status | IN("open", "fixed")) then .status = "closed"
         elif $res == "fail" and .status == "fixed" then .status = "closed"
         elif $res == "fail" and .status == "open" and $rounds >= $cap then .status = "escalated"
         else . end)
      else . end)
    | escalate_phases(if $rounds >= 2 then [$p] else [] end; null; "QA needs a second round"; $at)
    | finish_phases($cur)' \
    --arg p "$phase" --arg res "$result" --arg tier "$tier" --arg tree "$tree" --arg note "$note" \
    --arg at "$(vbw_now)" --argjson cap "$VBW_QA_ROUNDS" --argjson cur "$(printf '%s' "$digests" | jq -c 'map_values(.combined)')"
  qa_cache_put "$phase" "$digests"
  record_commit "chore(vbw): qa $phase $result"
  jq -r --arg p "$phase" '.phases[] | select(.id == $p) | "\(.id) qa \(.qa.result) (\(.qa.tier))\(if .qa.rounds then ", round \(.qa.rounds)" else "" end)"' "$VBW_RECORD"
}
