#!/usr/bin/env bash
# vbw apply < PLAN_JSON: the planner's one write (docs/workflows.md). Replaces
# phases, plans and checks in a single validated update:
#   {"phases": [{id, title, reqs}],
#    "plans":  [{id, phase, title, reqs, files, after}],
#    "checks": [{id, req, run, files?, exit?, output?, timeout?}]}
# Statuses are the kernel's (all "planned"). Refused once any plan has started,
# so a build is never re-planned from under itself.

cmd_apply() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw apply < plan.json"
  vbw_require_project
  local doc
  doc=$(cat)
  printf '%s' "$doc" | jq -e 'type == "object"' > /dev/null 2>&1 || vbw_die "apply needs a JSON object on stdin"
  printf '%s' "$doc" | jq -e '(keys - ["phases", "plans", "checks"]) == [] and all(.phases, .plans, .checks; type == "array")' \
    > /dev/null || vbw_die "apply needs exactly phases, plans and checks, each an array"
  local unknown
  unknown=$(printf '%s' "$doc" | jq -r '[
      (.phases[] | . as $o | keys[] | select(IN("id", "title", "reqs") | not) | "\($o.id // "a phase") has an unknown field: \(.)"),
      (.plans[] | . as $o | keys[] | select(IN("id", "phase", "title", "reqs", "files", "after") | not) | "\($o.id // "a plan") has an unknown field: \(.)")
    ] | .[0] // empty')
  [ -z "$unknown" ] || vbw_die "refused: $unknown"
  record_read | jq -e 'all(.plans[]; .status == "planned")' > /dev/null \
    || vbw_die "the build has started (a plan is past planned): planning again is not possible now"
  record_update '
    .phases = [$d.phases[] | {id, title, reqs}]
    | .plans = [$d.plans[] | {id, phase, title, reqs, files, after: (.after // []), status: "planned"}]
    | .checks = $d.checks' --argjson d "$doc"
  jq -r '"applied \(.phases | length) phases, \(.plans | length) plans, \(.checks | length) checks"' "$VBW_RECORD"
}
