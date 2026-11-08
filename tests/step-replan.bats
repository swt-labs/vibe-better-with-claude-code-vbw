#!/usr/bin/env bats
# R229 (#734): at the approve step, vbw next --json carries detail.replan: the sentence
# the kernel would say for a planning run of this milestone's open requirements plus
# one (the cost of saying yes to a suggestion that adds a requirement), built by the
# same code as step.say for a plan step (steps.sh: step_size's reqs + 1, step_expect,
# step_say). With history it reads "Planning the work: about N min, until around
# HH:MM"; without, "Planning the work: no end time yet (VBW has timed fewer than 3
# steps like this here)". The field exists only at approve; every other step's detail
# has no such key (reads null). L1: the kernel on a planned, unapproved project.

load helper
load step-helper
load road-helper
load fixture-helper

# planned_project: step_project's shop (R1, P1 with three plans, C1), committed and
# not approved, so vbw next asks for the approval.
planned_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src
  printf 'a\n' > src/a.txt
  step_edit '.checks = [{id: "C1", req: "R1", run: ["true"]}]
    | .phases = [{id: "P1", title: "Pay", reqs: ["R1"], milestone: "M1", tier: "express"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "A", reqs: ["R1"], files: ["src/a.txt"], after: [], status: "planned"}]'
  git add -A
  git commit -q -m "chore(vbw): plan"
  STEPS="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/steps.json"
  export STEPS
}

setup_file() { fixture_build planned planned_project; }
setup() { fixture_copy planned; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

next() { "$VBW" next --json < /dev/null; }

@test "R229: at approve, detail.replan is the planning sentence without a basis when the history has fewer than 3 planning steps" {
  next | jq -e '.action == "approve"' > /dev/null || { next; false; }
  next | jq -e '.detail.replan == "Planning the work: no end time yet (VBW has timed fewer than 3 steps like this here)"' || { next; false; }
}

@test "R229: with history, detail.replan prices the open requirements plus one: three plans of 600 s per requirement and one open requirement give about 20 min" {
  hist_plan 1 600 5
  next | jq -e '.action == "approve" and (.detail.replan | test("^Planning the work: about 20 min, until around (tomorrow )?[0-9]{2}:[0-9]{2}$"))' || { next; false; }
  # The same history prices a planning run of the milestone (one requirement) at 10 min: the extra is the one.
  step_edit '.phases = [] | .plans = [] | .checks = []'
  next | jq -e '.action == "plan" and (.step.say | test("^Planning the work: about 10 min, until around (tomorrow )?[0-9]{2}:[0-9]{2}$"))' || { next; false; }
}

@test "R229: detail.replan exists only at approve: the plan step and the build step carry no such field" {
  step_edit '.phases = [] | .plans = [] | .checks = []'
  next | jq -e '.action == "plan" and .detail.replan == null and (.detail | has("replan") | not)' || { next; false; }
}

@test "R229: once approved, the build step carries no replan" {
  "$VBW" approve > /dev/null
  next | jq -e '.action == "build" and .detail.replan == null and (.detail | has("replan") | not)' || { next; false; }
}
