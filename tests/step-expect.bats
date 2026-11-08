#!/usr/bin/env bats
# R190, phase P146 (L1): how long a step should take, from the clone's step
# history. A kind with parts (build, fix, proof): the median time per part over
# its latest 10 finished steps that recorded parts, times this step's parts. A
# kind without parts (planning, QA, mapping): the median of its latest 10
# finished steps. With fewer than 3 finished steps of that kind there is no end
# time, never a guess. The median of an even count is the mean of the two
# middle values. Seen in the note vbw run start writes (.vbw/runtime/step.json):
# first_end and end, against started_at.

load helper
load step-helper
load fixture-helper

expect_project() {
  vbw_setup
  step_project
}

setup_file() { fixture_build expect expect_project; }
setup() { fixture_copy expect; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

@test "R190: a build's end time is the median time per part of the latest 10 builds with parts, times its plans" {
  # Two old outliers, then ten builds: five at 300 s for 1 plan, five at 1000 s
  # for 2 plans (500 s a plan). Median per plan 400 s; two plans: 800 s. With
  # the outliers counted it would be 1000 s.
  step_seed build 100000 1 2
  step_seed build 300 1 5
  step_seed build 1000 2 5
  # Steps from before parts were recorded say nothing about time per part.
  step_seed build 5000 - 3
  "$VBW" run start build P1.1 P1.2 > /dev/null
  [ "$(step_secs first_end)" -eq 800 ] || { cat "$NOTE"; false; }
  [ "$(step_secs end)" -eq 800 ] || { cat "$NOTE"; false; }
  jq -e '.parts == {done: 0, total: 2} and .late == false' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R190: the same history gives a three-plan build three times the time per part" {
  step_seed build 300 1 3
  "$VBW" run start build P1.1 P1.2 P1.3 > /dev/null
  [ "$(step_secs first_end)" -eq 900 ] || { cat "$NOTE"; false; }
}

@test "R190: a step without parts takes the median of the latest 10 steps of its kind" {
  step_seed plan 100000 - 2
  step_seed plan 60 - 5
  step_seed plan 120 - 5
  "$VBW" run start plan > /dev/null
  [ "$(step_secs first_end)" -eq 90 ] || { cat "$NOTE"; false; }
  jq -e '.parts == null' "$NOTE" || { cat "$NOTE"; false; }
  "$VBW" run end > /dev/null
  step_seed qa 30 - 1
  step_seed qa 60 - 1
  step_seed qa 600 - 1
  "$VBW" run start qa > /dev/null
  [ "$(step_secs first_end)" -eq 60 ] || { cat "$NOTE"; false; }
}

@test "R190: with one or two finished steps of the kind the end time is a rough guess naming the runs; with none there is no end time" {
  step_seed build 300 1 2
  step_seed plan 60 - 5
  "$VBW" run start build P1.1 > /dev/null
  jq -e '.kind == "build" and .first_end != null and .end != null and .rough == true and .runs == 2' "$NOTE" || { cat "$NOTE"; false; }
  "$VBW" run end > /dev/null
  "$VBW" run start qa > /dev/null
  jq -e '.kind == "qa" and .first_end == null and .end == null' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R190: builds that recorded no parts do not count among the runs an estimate learned from" {
  step_seed build 300 1 2
  step_seed build 300 - 5
  "$VBW" run start build P1.1 > /dev/null
  jq -e '.first_end != null and .rough == true and .runs == 2' "$NOTE" || { cat "$NOTE"; false; }
}
