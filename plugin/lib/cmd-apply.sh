#!/usr/bin/env bash
# vbw apply < PLAN_JSON: the Lead's one write (docs/workflows.md). Replaces
# the current milestone's phases, plans and checks in a single validated update:
#   {"phases": [{id, title, reqs, goal?, criteria?, tier?}],   (the Architect's)
#    "plans":  [{id, phase, title, reqs, files, after, tasks?, role?}],   (the Lead's)
#    "checks": [{id, req, run, files?, exit?, output?, timeout?, alone?}],
#    "rules":  [{req, text, check}]}   (optional, the Lead's: R31)
# A check may carry "alone": true (a boolean): it never runs beside another VBW check (R45).
# "rules" are the conditions, edges and error cases an [auto] requirement
# states, each with the check that tests it. When present, apply refuses a rule
# whose check is not in the plan or belongs to another requirement, a rule for a
# [human] requirement, and any unproven [auto] requirement of the plan's phases
# that lists no rules (earlier rules count). Without the key nothing changes.
# The phases and plans are the current milestone's; "checks" are the checks of
# its requirements. Earlier milestones' phases, plans and checks are kept (their
# checks keep guarding shipped work). Re-planning mid-milestone is allowed: a
# plan that has started must come back unchanged and keeps its status; every
# other plan is "planned". Refused while a build or fix run is open.
# Every phase gets its rigor tier here: the floor comes from rigor.sh; the
# Architect's optional tier may only raise it (a lower one is refused) and is
# kept as the phase's proposed tier (config rigor auto restores it), and
# settings.rigor forced to a tier overrides both. A phase that already existed
# keeps escalations, outcome and its qa verdict (and the predicted tier, once work began), and a started or
# escalated phase never records a lower tier than it has.
# vbw apply --patch < DOC: only plans, checks and rules, merged by id (R80).
# vbw apply --add < DOC: new phases with their plans, checks and rules (R116),
# appended to the milestone; a phase id it already has, a requirement any
# phase covers (in any milestone) or that belongs to another milestone, or a
# plan or check id in use is refused and nothing changes.
# Every existing item stays as it was and keeps the tier it was accepted at:
# the rigor floor and the one-plan-per-express rule judge only the phases the
# doc brings (their signals see the whole milestone); every other rule above
# holds for the merged whole.

# shellcheck source=rigor.sh
. "$VBW_LIB/rigor.sh"

cmd_apply() {
  local patch=false add=false
  case "${1:-}" in --patch) patch=true; shift ;; --add) add=true; shift ;; esac
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw apply [--patch | --add] < plan.json"
  vbw_require_project
  local doc record problem hypo tiers judged one pdoc='{}'
  doc=$(cat)
  if [ "$add" = true ]; then
    # --add: new phases with their plans, checks and rules, appended to the milestone;
    # every existing item stays as it is, its tier included; the rigor floor and the
    # one-plan-per-express rule judge the new phases only, every other rule the merged whole.
    printf '%s' "$doc" | jq -e 'type == "object" and (.phases | type == "array" and length > 0)
        and all(.phases[]; type == "object" and (.id | type == "string") and (.reqs | type == "array"))
        and all(.plans, .checks, .rules; . == null or (type == "array" and all(.[]; type == "object")))' > /dev/null 2>&1 \
      || vbw_die "apply --add needs a JSON object with the new phases ({id, title, reqs}) and their plans, checks and rules"
    pdoc=$(printf '%s' "$doc" | jq -c '{phases, plans: (.plans // []), checks: (.checks // []), rules: (.rules // [])}')
    problem=$(record_read | jq -r --argjson p "$pdoc" '. as $r | .milestone.id as $m
      | ([.phases[] | select(.milestone == $m)]) as $ph | [$p.phases[].id] as $new | [$p.phases[].reqs[]] as $newreqs
      | [($p.phases[] | select(.id as $i | any($ph[]; .id == $i)) | "\(.id) is already a phase of this milestone: --add takes new phases only"),
         ($p.phases[].reqs[] | . as $q | ([$r.phases[] | select(any(.reqs[]; . == $q))][0]) | select(. != null)
           | "\($q) is already covered by \(.id): --add takes requirements that have no phase yet"),
         ($p.phases[].reqs[] | . as $q | ([$r.requirements[] | select(.id == $q and .milestone != $m)][0]) | select(. != null)
           | "\($q) belongs to milestone \(.milestone): --add takes requirements of this milestone"),
         ($p.plans[] | select(.phase as $x | $new | index($x) | not) | "\(.id // "a plan") is for \(.phase // "no phase"), not a phase this --add brings"),
         ($p.plans[] | select(.id as $i | any(($r.plans // [])[]; .id == $i)) | "\(.id) is already a plan: --add takes new plans only"),
         ($p.checks[] | select(.id as $i | any(($r.checks // [])[]; .id == $i)) | "\(.id) is already a check: --add takes new checks only"),
         ($p.checks[], $p.rules[] | select(.req as $q | $newreqs | index($q) | not)
           | "\(.id // "the rule \"\(.text)\"") is for \(.req), not a requirement of the phases this --add brings")]
      | .[0] // empty') || vbw_die "internal error: cannot read the added phases"
    [ -z "$problem" ] || vbw_die "refused: $problem"
    doc=$(record_read | jq -c --argjson p "$pdoc" '.milestone.id as $m
      | ([.phases[] | select(.milestone == $m)]) as $ph
      | ([.requirements[] | select(.milestone == $m)]) as $rq
      | {phases: [($ph[] | {id, title, reqs} + with_entries(select(.key | IN("goal", "criteria")))
            + (if (.proposed // .tier) != null then {tier: (.proposed // .tier)} else {} end)), $p.phases[]],
         plans: ([.plans[] | select(.phase as $x | any($ph[]; .id == $x)) | with_entries(select(.key | IN("id", "phase", "title", "reqs", "files", "after", "tasks", "role")))] + $p.plans),
         checks: ([.checks[] | select(.req as $x | any($rq[]; .id == $x))] + $p.checks),
         rules: ([$rq[] | .id as $q | (.rules // [])[] | {req: $q, text, check}] + $p.rules)}') \
      || vbw_die "internal error: cannot merge the added phases"
  elif [ "$patch" = true ]; then
    # --patch: plans, checks and rules to change, merged by id (rules by requirement and text)
    # into the milestone; the merged whole then meets every rule a full apply does.
    printf '%s' "$doc" | jq -e 'type == "object" and (has("phases") | not)' > /dev/null 2>&1 \
      || vbw_die "a patch carries plans, checks and rules, never phases: change phases with a full apply"
    pdoc=$(printf '%s' "$doc" | jq -c '{plans: (.plans // []), checks: (.checks // []), rules: (.rules // [])}')
    doc=$(record_read | jq -c --argjson p "$pdoc" '.milestone.id as $m
      | ([.phases[] | select(.milestone == $m)]) as $ph
      | ([.requirements[] | select(.milestone == $m)]) as $rq
      | def merge($old; $new; $keys): [$old[] | . as $o | ([$new[] | select(. as $n | $keys | all(. as $k | $n[$k] == $o[$k]))][0]) // $o]
          + [$new[] | . as $n | select(any($old[]; . as $o | $keys | all(. as $k | $n[$k] == $o[$k])) | not)];
      {phases: [$ph[] | {id, title, reqs} + with_entries(select(.key | IN("goal", "criteria")))
          + (if (.proposed // .tier) != null then {tier: (.proposed // .tier)} else {} end)],
       plans: merge([.plans[] | select(.phase as $x | any($ph[]; .id == $x)) | with_entries(select(.key | IN("id", "phase", "title", "reqs", "files", "after", "tasks", "role")))]; $p.plans; ["id"]),
       checks: merge([.checks[] | select(.req as $x | any($rq[]; .id == $x))]; $p.checks; ["id"]),
       rules: merge([$rq[] | .id as $q | (.rules // [])[] | {req: $q, text, check}]; $p.rules; ["req", "text"])}') \
      || vbw_die "internal error: cannot merge the patch"
  fi
  printf '%s' "$doc" | jq -e 'type == "object"' > /dev/null 2>&1 || vbw_die "apply needs a JSON object on stdin"
  printf '%s' "$doc" | jq -e '(keys - ["phases", "plans", "checks", "rules"]) == [] and all(.phases, .plans, .checks; type == "array")
      and ((has("rules") | not) or (.rules | type == "array" and all(.[]; type == "object" and (keys - ["req", "text", "check"]) == [] and (.text | type == "string" and length > 0))))' \
    > /dev/null || vbw_die "apply needs phases, plans and checks, each an array, and optionally rules: [{req, text, check}]"
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
  problem=$(printf '%s' "$record" | jq -r --argjson d "$doc" '.milestone.id as $m | [.phases[] | select(.milestone == $m)] as $old
    | select(any(.plans[]; .status != "planned" and (.phase as $p | any($old[]; .id == $p))))
    | [($d.phases[] | . as $n | ([$old[] | select(.id == $n.id)][0]) as $o | select($o != null)
        | if $o.title != $n.title then "\($n.id) has work started: its title stays \"\($o.title)\" (a phase is not renamed once planned work has started)"
          elif ($o.reqs | sort) != ($n.reqs | sort) then "\($n.id) has work started: its requirements stay \($o.reqs | join(", "))" else empty end),
       ($d.phases[] | . as $n | select(any($old[]; .id == $n.id) | not)
        | select(any($old[]; any(.reqs[]; . as $q | any($n.reqs[]; . == $q))))
        | "\($n.id) is a new phase for requirements another phase already covers: once work has started, add plans to that phase"
      )] | .[0] // empty')
  [ -z "$problem" ] || vbw_die "refused: $problem"
  problem=$(printf '%s' "$record" | jq -r --argjson d "$doc" "$VBW_JQ_DEFS"'select($d | has("rules"))
    | . as $r | $d.rules as $rules
    | [($rules[] | . as $x | select(any($r.requirements[]; .id == $x.req and .proof == "human"))
        | "the rule \"\($x.text)\" is for \($x.req), a [human] requirement: only [auto] requirements list rules"),
       ($rules[] | . as $x | select(any($d.checks[]; .id == $x.check and .req == $x.req) | not)
        | "the rule \"\($x.text)\" names \($x.check), which is not a check of \($x.req) in this plan"),
       ($r.requirements[] | . as $q | select(.proof == "auto" and .status != "proven" and ($q | doc_only($d.plans; $d.checks) | not)
          and any($d.phases[].reqs[]; . == $q.id)
          and ((($rules | any(.req == $q.id)) or ((.rules // []) | length > 0)) | not))
        | "\(.id) lists no rules: list each condition, edge and error case its text states, with the check that tests it (rules)")]
    | .[0] // empty')
  [ -z "$problem" ] || vbw_die "refused: $problem"
  hypo=$(printf '%s' "$record" | jq -c --argjson d "$doc" '.milestone.id as $m
    | .phases = [(.phases[] | select(.milestone != $m)), ($d.phases[] | {id, title, reqs, milestone: $m} + (with_entries(select(.key | IN("goal", "tier")))))]
    | .plans = [.plans[] | select(.phase as $p | $d.phases | any(.id == $p) | not)] + [$d.plans[] | {id, phase, title, reqs, files, after: (.after // [])}]')
  # The phases judged: with --add only the ones it brings, else every phase of the doc.
  judged=$doc
  [ "$add" = false ] || judged=$pdoc
  tiers=$(printf '%s' "$hypo" | rigor_assess "$(printf '%s' "$judged" | jq -r '.phases[].id')" 2> /dev/null) \
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
    | .checks as $c0
    | .phases = (if $patch then .phases else [(.phases[] | select($add or .milestone != $m)), ((if $add then $pd.phases else $d.phases end)[] | . as $np | ([$old[] | select(.id == $np.id)][0]) as $o
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
                       predicted: (if $locked then ($o.predicted // $tier) else $tier end)}
                    + ($o // {} | with_entries(select(.key | IN("escalations", "outcome", "qa")))))] end)
    | ([($pd.plans // $d.plans)[] | {id, phase, title, reqs, files, after: (.after // []), status: ($status[.id] // "planned")}
          + (with_entries(select(.key | IN("tasks", "role"))))]) as $np
    | .plans = (if $patch or $add then [.plans[] | . as $o | ([$np[] | select(.id == $o.id)][0]) // $o] + [$np[] | select($status[.id] == null)]
        else [(.plans[] | select(.phase as $p | any($mine[]; . == $p) | not)), $np[]] end)
    | .checks = (if $patch or $add then [$c0[] | . as $o | ([$pd.checks[] | select(.id == $o.id)][0]) // $o] + [$pd.checks[] | select(.id as $i | $c0 | any(.id == $i) | not)]
        else [($c0[] | select(.req as $q | any($myreqs[]; . == $q) | not)), $d.checks[]] end)
    | if $d | has("rules") then .requirements |= map(. as $q
        | if any($d.rules[]; .req == $q.id) then .rules = [$d.rules[] | select(.req == $q.id) | {text, check}] else . end)
      else . end' --argjson d "$doc" --argjson tiers "$tiers" --argjson pd "$pdoc" --argjson patch "$patch" --argjson add "$add" --arg mode "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')"
  jq -r '.milestone.id as $m | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | "applied \($mine | length) phases, \([.plans[] | select(.phase as $p | any($mine[]; . == $p))] | length) plans, \(.checks | length) checks in all"' "$VBW_RECORD"
}
