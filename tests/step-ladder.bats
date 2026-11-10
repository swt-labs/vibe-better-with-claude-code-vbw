#!/usr/bin/env bats
# R191, phase P149 (L1): a step's expected seconds come from how long one unit of
# its work took before at its rigor tier, times this step's size. A plan (T174,
# tests/build-pace.bats: at the wave's quantile 0.75^(1/n), not the median; per
# task plus break when the history recorded breaks): the seconds per task over the
# latest 10 finished plans of its tier that recorded tasks, times its tasks; fewer
# than 3 such plans: the seconds per plan at that tier; fewer than 3 of those: per
# plan of any tier; fewer than 3 plan units in all: today's rule on the builds that
# recorded only parts (median seconds per plan times the wave's plans); fewer than 3
# plans in all: no end time, never a guess. A build wave takes as long as its
# longest plan (they build side by side), never their sum. A fix round: the median wall time of the latest 10 fix
# rounds at its tier (else of any tier; fewer than 3 in all: none), whatever the
# fix count. Planning: the median seconds per open requirement over the latest 10
# planning steps that recorded a count, times the requirements to plan now (fewer
# than 3: the median planning time). QA: the sum over its phases of the median
# seconds per phase at the phase's tier (fewer than 3 at a tier: per phase of any
# tier; fewer than 3 in all: today's median QA time, else none). Seen in vbw next
# --json's step, in the note vbw run start writes and in run start's sentence, in
# D425's unchanged wording.

load helper
load step-helper
load road-helper

# R284: the kernel's clock is set (VBW_NOW, a UTC time), so the clock times hold at any real hour.
setup() {
  vbw_setup
  export TZ=Europe/Lisbon VBW_NOW=2030-01-15T10:00:00Z
  tiered_project
}
teardown() { vbw_teardown; }

step_of() { "$VBW" next --json | jq -c '.step'; }

@test "R191: rung 1: a plan takes the median seconds per task of the latest 10 plans of its tier, times its tasks; the wave takes its longest plan" {
  # An old outlier (the 11th latest), then ten standard plans at 100 s a task.
  hist_build standard 1 100000 1
  hist_build standard 2 200 4
  hist_build standard 4 400 3
  hist_build standard 1 100 3
  # Another tier is not counted.
  hist_build deep 1 100000 3
  local s
  s=$(step_of)
  # P1.1 two tasks (200 s), P1.2 five (500 s), P1.3 three (300 s): the wave is 500 s, not 1000.
  printf '%s' "$s" | jq -e '.kind == "build" and .parts == 3 and .seconds == 500' || { echo "$s"; false; }
  printf '%s' "$s" | jq -e '.end == "2030-01-15T10:08:20Z" and .say == "Building P1.1, P1.2 and P1.3: about 8 min, until around 10:08"' || { echo "$s"; false; }
}

@test "R191: a wave of two plans of different sizes ends with the bigger one, never with their sum" {
  hist_build standard 2 200 3
  "$VBW" run start build P1.1 P1.2 > /dev/null
  [ "$(step_secs first_end)" -eq 500 ] || { cat "$NOTE"; false; }
  [ "$(step_secs end)" -eq 500 ] || { cat "$NOTE"; false; }
  jq -e '.parts == {done: 0, total: 2}' "$NOTE" || { cat "$NOTE"; false; }
  "$VBW" run end > /dev/null
  "$VBW" run start build P1.1 > /dev/null
  [ "$(step_secs first_end)" -eq 200 ] || { cat "$NOTE"; false; }
}

@test "R191: rung 2: with no plan of the tier that recorded tasks, the seconds per plan at that tier" {
  # Another tier's quick plans must not pull it down.
  hist_build deep - 10 3
  hist_build standard - 300 1
  hist_build standard - 500 1
  hist_build standard - 700 1
  # Three plans side by side (T174): the quantile 0.909 of 300, 500 and 700 s is 663 s.
  step_of | jq -e '.seconds == 663' || { step_of; false; }
}

@test "R191: rung 3: with no plan of the tier, the seconds per plan of any tier" {
  hist_build deep - 100 1
  hist_build deep - 200 1
  hist_build express - 900 1
  # The quantile 0.909 of 100, 200 and 900 s (T174).
  step_of | jq -e '.seconds == 772' || { step_of; false; }
}

@test "R191: the coarse rung: builds that recorded only parts still count, by today's rule (median per plan times the wave's plans)" {
  step_seed build 300 1 3
  step_of | jq -e '.seconds == 900' || { step_of; false; }
  "$VBW" run start build P1.1 P1.2 P1.3 > /dev/null
  [ "$(step_secs first_end)" -eq 900 ] || { cat "$NOTE"; false; }
}

@test "R191: with one or two plans in all the wave's end time is a rough guess naming the runs; with none there is no end time" {
  step_seed build 300 1 2
  local s
  s=$(step_of)
  printf '%s' "$s" | jq -e '.kind == "build" and .seconds == 900 and .runs == 2 and .rough == true and .end != null
    and .end == "2030-01-15T10:15:00Z" and .say == "Building P1.1, P1.2 and P1.3: roughly 15 min, until around 10:15 (rough guess from 2 runs)"' || { echo "$s"; false; }
  rm "$STEPS"
  s=$(step_of)
  printf '%s' "$s" | jq -e '.kind == "build" and .seconds == null and .end == null
    and .say == "Building P1.1, P1.2 and P1.3: no end time yet (VBW has timed fewer than 3 steps like this here)"' || { echo "$s"; false; }
  "$VBW" run start build P1.1 > /dev/null
  jq -e '.first_end == null and .end == null' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R191: vbw run start says the step with the same expected time as vbw next, within a minute" {
  hist_build standard 1 100 5
  local e1
  e1=$(step_of | jq -r '.end | fromdateiso8601')
  vbw_run run start build P1.1 P1.2 P1.3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ Building\ P1\.1,\ P1\.2\ and\ P1\.3:\ about\ 8\ min,\ until\ around\ [0-9]{2}:[0-9]{2} ]] || { echo "$output"; false; }
  [ "$(step_secs first_end)" -eq 500 ] || { cat "$NOTE"; false; }
  jq -e --argjson e "$e1" '((.end | fromdateiso8601) - $e) | fabs <= 60' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R191: a fix round takes the median wall time of the latest 10 fix rounds at its tier, whatever the fix count" {
  step_edit '.plans[].status = "done" | .fixes = [{id: "F1", req: "R1", source: "qa", phase: "P1", attempts: 0, status: "open", note: "C1 fail"},
    {id: "F2", req: "R1", source: "qa", phase: "P1", attempts: 0, status: "open", note: "C1 fail"}]'
  git add -A && git commit -q -m "chore(vbw): fixes"
  hist_fix standard 300 5
  hist_fix deep 50 3
  local s
  s=$(step_of)
  printf '%s' "$s" | jq -e '.kind == "fix" and .parts == 2 and .seconds == 300 and (.say | startswith("Fixing F1 and F2: about 5 min"))' || { echo "$s"; false; }
}

@test "R191: a fix round with no round at its tier takes the median of any tier; with none in all it gives none" {
  step_edit '.plans[].status = "done" | .fixes = [{id: "F1", req: "R1", source: "qa", phase: "P1", attempts: 0, status: "open", note: "C1 fail"},
    {id: "F2", req: "R1", source: "qa", phase: "P1", attempts: 0, status: "open", note: "C1 fail"}]'
  git add -A && git commit -q -m "chore(vbw): fix"
  hist_fix deep 50 1
  hist_fix - 80 1
  hist_fix deep 200 1
  # No round at the phase's tier (standard): the median of 50, 80 and 200 is 80, a rough guess from 3 runs; two fixes do not double it.
  step_of | jq -e '.kind == "fix" and .parts == 2 and .seconds == 80 and .runs == 3 and .rough == true' || { step_of; false; }
  jq 'del(.steps[] | select(.kind == "fix"))' "$STEPS" > "$TEST_ROOT/h.json" && cp "$TEST_ROOT/h.json" "$STEPS"
  step_of | jq -e '.kind == "fix" and .seconds == null and (.say | endswith("no end time yet (VBW has timed fewer than 3 steps like this here)"))' || { step_of; false; }
}

@test "R191: planning takes the median seconds per open requirement, times the requirements to plan now" {
  step_edit '.checks = []'
  hist_plan 2 100 3
  hist_plan 4 400 1
  step_of | jq -e '.kind == "plan" and .parts == null and .seconds == 50 and (.say | startswith("Planning the work: "))' || { step_of; false; }
  printf -- '- R2 [auto] A customer gets a receipt\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  step_edit '.checks = []'
  step_of | jq -e '.kind == "plan" and .seconds == 100' || { step_of; false; }
  "$VBW" run start plan > /dev/null
  [ "$(step_secs first_end)" -eq 100 ] || { cat "$NOTE"; false; }
}

@test "R191: with no planning step that recorded a count, planning takes its median time as before" {
  step_edit '.checks = []'
  hist_plan - 60 3
  step_of | jq -e '.kind == "plan" and .seconds == 60' || { step_of; false; }
}

@test "R191: QA takes, per phase, the median seconds per phase at the phase's tier; else of any tier; else the median QA time; else none" {
  step_edit '.plans[].status = "done"'
  git add -A && git commit -q -m "chore(vbw): built"
  "$VBW" prove --full > /dev/null
  hist_qa standard 120 5
  hist_qa deep 900 3
  step_of | jq -e '.kind == "qa" and .ids == ["P1"] and .parts == null and .seconds == 120 and (.say | startswith("Checking P1: about 2 min"))' || { step_of; false; }
  jq 'del(.steps[] | select(.kind == "qa" and .phases[0].tier == "standard"))' "$STEPS" > "$TEST_ROOT/h.json" && cp "$TEST_ROOT/h.json" "$STEPS"
  step_of | jq -e '.kind == "qa" and .seconds == 900' || { step_of; false; }
  jq 'del(.steps[] | select(.kind == "qa"))' "$STEPS" > "$TEST_ROOT/h.json" && cp "$TEST_ROOT/h.json" "$STEPS"
  step_seed qa 30 - 3
  step_of | jq -e '.kind == "qa" and .seconds == 30' || { step_of; false; }
  jq 'del(.steps[] | select(.kind == "qa"))' "$STEPS" > "$TEST_ROOT/h.json" && cp "$TEST_ROOT/h.json" "$STEPS"
  step_of | jq -e '.kind == "qa" and .seconds == null' || { step_of; false; }
  "$VBW" run start qa > /dev/null
  jq -e '.first_end == null and .end == null' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R191: QA with several phases sums the median seconds per phase, each at its own tier" {
  step_edit '.plans[].status = "done"
    | .phases += [{id: "P2", title: "Receipt", reqs: ["R1"], milestone: "M1", tier: "deep"}]
    | .plans += [{id: "P2.1", phase: "P2", title: "D", reqs: ["R1"], files: ["src/d.txt"], after: [], status: "done"}]'
  git add -A && git commit -q -m "chore(vbw): built"
  "$VBW" approve > /dev/null
  "$VBW" prove --full > /dev/null
  hist_qa standard 120 3
  hist_qa deep 900 3
  step_of | jq -e '.kind == "qa" and .ids == ["P1", "P2"] and .seconds == 1020' || { step_of; false; }
}

# R284: at 23:55 (Europe/Lisbon) an end after midnight carries the day word the kernel prints.
@test "R284: with the clock at 23:55 an end after midnight reads 'until around tomorrow 00:03'" {
  export VBW_NOW=2030-01-15T23:55:00Z
  hist_build standard 2 200 4
  hist_build standard 4 400 3
  hist_build standard 1 100 3
  local s
  s=$(step_of)
  printf '%s' "$s" | jq -e '.seconds == 500 and .end == "2030-01-16T00:03:20Z" and .say == "Building P1.1, P1.2 and P1.3: about 8 min, until around tomorrow 00:03"' || { echo "$s"; false; }
}

@test "R284: every test file that checks the kernel's clock times sets the kernel's clock and words its own clock from it, never from the wall clock" {
  local f
  for f in step-ladder road-next step-range statusline-step step-next; do
    grep -q 'VBW_NOW=' "$BATS_TEST_DIRNAME/$f.bats" || { echo "tests/$f.bats does not set the clock"; false; }
    # no[w] matches "now" but not this line's own text, so the scan never finds itself
    ! grep -nE 'day\(no[w]\)|, no[w]\]|\) - no[w]' "$BATS_TEST_DIRNAME/$f.bats" || { echo "tests/$f.bats words a clock from the wall clock"; false; }
  done
  grep -q 'VBW_NOW' "$PLUGIN_ROOT/lib/core.sh" || { echo "vbw_now does not read the set clock"; false; }
  local got
  got=$(VBW_NOW=2031-02-03T04:05:06Z bash -c 'source "$1/lib/core.sh"; vbw_now' _ "$PLUGIN_ROOT") || { echo "vbw_now failed"; false; }
  [ "$got" = "2031-02-03T04:05:06Z" ] || { echo "vbw_now printed '$got', not the set clock"; false; }
  got=$(VBW_NOW= bash -c 'source "$1/lib/core.sh"; vbw_now' _ "$PLUGIN_ROOT")
  [[ "$got" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { echo "vbw_now without the set clock printed '$got'"; false; }
  [ "$got" != "2031-02-03T04:05:06Z" ]
  ! grep -nE '\(now \| floor\)|now as \$now|step_move\(now' "$PLUGIN_ROOT/lib/steps.sh" "$PLUGIN_ROOT/lib/road.jq" "$PLUGIN_ROOT/lib/proofsteps.sh" "$PLUGIN_ROOT/scripts/statusline.jq" || { echo "the estimate path still reads jq's now"; false; }
}

@test "R284 docs: docs/panel.md says the kernel takes the time from one clock, which VBW_NOW sets for tests only" {
  grep -E 'VBW_NOW' "$REPO_ROOT/docs/panel.md" | grep -qiE 'tests? only|only (for|by) tests' || { echo "docs/panel.md does not name VBW_NOW as the tests' clock"; false; }
}
