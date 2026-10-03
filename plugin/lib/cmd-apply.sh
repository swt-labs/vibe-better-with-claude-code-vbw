#!/usr/bin/env bash
# vbw apply < PLAN_JSON: the Lead's one write (docs/workflows.md). Replaces
# the current milestone's phases, plans and checks in a single validated update:
#   {"phases": [{id, title, reqs, goal?, criteria?, tier?}],   (the Architect's)
#    "plans":  [{id, phase, title, reqs, files, after, tasks?, role?}],   (the Lead's)
#    "checks": [{id, req, run, files?, exit?, output?, timeout?}]}
# The phases and plans are the current milestone's; "checks" are the checks of
# its requirements. Earlier milestones' phases, plans and checks are kept (their
# checks keep guarding shipped work). Re-planning mid-milestone is allowed: a
# plan that has started must come back unchanged and keeps its status; every
# other plan is "planned". Refused while a build or fix run is open.
# Every phase gets its rigor tier here: the floor comes from rigor.sh; the
# Architect's optional tier may only raise it (a lower one is refused) and is
# kept as the phase's proposed tier (config rigor auto restores it), and
# settings.rigor forced to a tier overrides both. A phase that already existed
# keeps predicted, escalations, cost_usd and outcome, and a started or
# escalated phase never records a lower tier than it has.

# shellcheck source=rigor.sh
. "$VBW_LIB/rigor.sh"

cmd_apply() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw apply < plan.json"
  vbw_require_project
  local doc record problem hypo tiers one
  doc=$(cat)
  printf '%s' "$doc" | jq -e 'type == "object"' > /dev/null 2>&1 || vbw_die "apply needs a JSON object on stdin"
  printf '%s' "$doc" | jq -e '(keys - ["phases", "plans", "checks"]) == [] and all(.phases, .plans, .checks; type == "array")' \
    > /dev/null || vbw_die "apply needs exactly phases, plans and checks, each an array"
  problem=$(printf '%s' "$doc" | jq -r '[
      (.phases[] | . as $o | keys[] | select(IN("id", "title", "reqs", "goal", "criteria", "tier") | not) | "\($o.id // "a phase") has an unknown field: \(.)"),
      (.plans[] | . as $o | keys[] | select(IN("id", "phase", "title", "reqs", "files", "after", "tasks", "role") | not) | "\($o.id // "a plan") has an unknown field: \(.)")
    ] | .[0] // empty')
  [ -z "$problem" ] || vbw_die "refused: $problem"
  problem=$(printf '%s' "$doc" | jq -r '.phases[] | select(has("tier") and (.tier | IN("express", "standard", "deep") | not))
    | "\(.id // "a phase") has the tier \(.tier | tojson): the tier must be express, standard or deep"' | head -n 1)
  [ -z "$problem" ] || vbw_die "refused: $problem"
  record=$(record_read)
  printf '%s' "$record" | jq -e '.lease == null or .lease.kind == "plan"' > /dev/null \
    || vbw_die "a $(printf '%s' "$record" | jq -r .lease.kind) run is open: plan again after it ends (vbw run end)"
  problem=$(printf '%s' "$record" | jq -r --argjson d "$doc" '.milestone.id as $m
    | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | [.plans[] | select(.status != "planned" and (.phase as $p | any($mine[]; . == $p))) | . as $old
        | ([$d.plans[] | select(.id == $old.id)][0]) as $new
        | select($new == null or ($new | {phase, reqs, files, after: (.after // [])}) != ($old | {phase, reqs, files, after}))
        | "\($old.id) is \($old.status): a plan that has started must stay as it is (same phase, requirements, files and order)"]
    | .[0] // empty')
  [ -z "$problem" ] || vbw_die "refused: $problem"
  hypo=$(printf '%s' "$record" | jq -c --argjson d "$doc" '.milestone.id as $m
    | .phases = [(.phases[] | select(.milestone != $m)), ($d.phases[] | {id, title, reqs, milestone: $m} + (with_entries(select(.key | IN("goal", "tier")))))]
    | .plans = [.plans[] | select(.phase as $p | $d.phases | any(.id == $p) | not)] + [$d.plans[] | {id, phase, title, reqs, files, after: (.after // [])}]')
  tiers=$(printf '%s' "$hypo" | rigor_assess "$(printf '%s' "$doc" | jq -r '.phases[].id')" 2> /dev/null) \
    || vbw_die "internal error: cannot compute the rigor tiers"
  problem=$(printf '%s' "$tiers" | jq -r --argjson d "$doc" '[.[] | . as $a | ([$d.phases[] | select(.id == $a.id)][0].tier) as $s
      | select($s != null and ($s | IN("express", "standard", "deep")) and (["express", "standard", "deep"] | index($s)) < (["express", "standard", "deep"] | index($a.floor)))
      | "\($a.id) is planned at \($s) but its signals set the floor at \($a.floor) (\($a.reasons | map(select(test("^(requirements|files|risk|breaks|tests): ") and (test(": none$") | not))) | join("; "))): the Architect may only raise a tier"]
    | .[0] // empty')
  if [ -n "$problem" ] && [ "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')" = auto ]; then
    vbw_die "refused: $problem"
  fi
  one=$(printf '%s' "$record" | jq -r --argjson d "$doc" --argjson tiers "$tiers" --arg mode "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')" '
      [$tiers[] | . as $a | (if $mode | IN("express", "standard", "deep") then $mode else $a.tier end) as $t
        | select($t == "express" and ([$d.plans[] | select(.phase == $a.id)] | length) > 1)
        | "\($a.id) is express: one plan, merge its plans or raise its tier"] | .[0] // empty')
  [ -z "$one" ] || vbw_die "refused: $one"
  record_update '.milestone.id as $m
    | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | ([.requirements[] | select(.milestone == $m) | .id]) as $myreqs
    | (.plans | map({key: .id, value: .status}) | from_entries) as $status
    | [.phases[] | select(.milestone == $m)] as $old
    | [.plans[] | select(.status != "planned") | .phase] as $started
    | .phases = [(.phases[] | select(.milestone != $m)), ($d.phases[] | . as $np | ([$old[] | select(.id == $np.id)][0]) as $o
                  | ([$tiers[] | select(.id == $np.id)][0]) as $a
                  | (.tier // null) as $sub
                  | ($mode | IN("express", "standard", "deep")) as $forced
                  | (($o != null) and (($o.escalations // []) != [] or any($started[]; . == $np.id))) as $locked
                  | (if $forced then $mode else $a.tier end) as $want
                  | (if $locked and ($o.tier != null)
                        and ((["express", "standard", "deep"] | index($o.tier)) > (["express", "standard", "deep"] | index($want)))
                     then $o.tier else $want end) as $tier
                  | {id, title, reqs, milestone: $m} + (with_entries(select(.key | IN("goal", "criteria"))))
                    + (if $sub != null then {proposed: $sub} else {} end)
                    + {tier: $tier,
                       reasons: ($a.reasons | map(select(startswith("Architect raised") | not))
                         + (if $forced then ["forced: vbw config rigor \($mode)"]
                            elif ($sub != null and $tier == $sub and $tier != $a.floor) then ["raised by the Architect"]
                            else [] end)),
                       predicted: ($o.predicted // $tier)}
                    + ($o // {} | with_entries(select(.key | IN("escalations", "cost_usd", "outcome")))))]
    | .plans = [(.plans[] | select(.phase as $p | any($mine[]; . == $p) | not)),
                ($d.plans[] | {id, phase, title, reqs, files, after: (.after // []), status: ($status[.id] // "planned")}
                  + (with_entries(select(.key | IN("tasks", "role")))))]
    | .checks = [(.checks[] | select(.req as $q | any($myreqs[]; . == $q) | not)), $d.checks[]]' --argjson d "$doc" --argjson tiers "$tiers" --arg mode "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')"
  jq -r '.milestone.id as $m | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | "applied \($mine | length) phases, \([.plans[] | select(.phase as $p | any($mine[]; . == $p))] | length) plans, \(.checks | length) checks in all"' "$VBW_RECORD"
}
