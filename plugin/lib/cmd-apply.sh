#!/usr/bin/env bash
# vbw apply < PLAN_JSON: the Lead's one write (docs/workflows.md). Replaces
# the current milestone's phases, plans and checks in a single validated update:
#   {"phases": [{id, title, reqs, goal?, criteria?}],      (the Architect's)
#    "plans":  [{id, phase, title, reqs, files, after, tasks?, role?}],   (the Lead's)
#    "checks": [{id, req, run, files?, exit?, output?, timeout?}]}
# The phases and plans are the current milestone's; "checks" are the checks of
# its requirements. Earlier milestones' phases, plans and checks are kept (their
# checks keep guarding shipped work). Re-planning mid-milestone is allowed: a
# plan that has started must come back unchanged and keeps its status; every
# other plan is "planned". Refused while a build or fix run is open.

cmd_apply() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw apply < plan.json"
  vbw_require_project
  local doc record problem
  doc=$(cat)
  printf '%s' "$doc" | jq -e 'type == "object"' > /dev/null 2>&1 || vbw_die "apply needs a JSON object on stdin"
  printf '%s' "$doc" | jq -e '(keys - ["phases", "plans", "checks"]) == [] and all(.phases, .plans, .checks; type == "array")' \
    > /dev/null || vbw_die "apply needs exactly phases, plans and checks, each an array"
  problem=$(printf '%s' "$doc" | jq -r '[
      (.phases[] | . as $o | keys[] | select(IN("id", "title", "reqs", "goal", "criteria") | not) | "\($o.id // "a phase") has an unknown field: \(.)"),
      (.plans[] | . as $o | keys[] | select(IN("id", "phase", "title", "reqs", "files", "after", "tasks", "role") | not) | "\($o.id // "a plan") has an unknown field: \(.)")
    ] | .[0] // empty')
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
  record_update '.milestone.id as $m
    | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | ([.requirements[] | select(.milestone == $m) | .id]) as $myreqs
    | (.plans | map({key: .id, value: .status}) | from_entries) as $status
    | .phases = [(.phases[] | select(.milestone != $m)), ($d.phases[] | {id, title, reqs, milestone: $m} + (with_entries(select(.key | IN("goal", "criteria")))))]
    | .plans = [(.plans[] | select(.phase as $p | any($mine[]; . == $p) | not)),
                ($d.plans[] | {id, phase, title, reqs, files, after: (.after // []), status: ($status[.id] // "planned")}
                  + (with_entries(select(.key | IN("tasks", "role")))))]
    | .checks = [(.checks[] | select(.req as $q | any($myreqs[]; . == $q) | not)), $d.checks[]]' --argjson d "$doc"
  jq -r '.milestone.id as $m | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | "applied \($mine | length) phases, \([.plans[] | select(.phase as $p | any($mine[]; . == $p))] | length) plans, \(.checks | length) checks in all"' "$VBW_RECORD"
}
