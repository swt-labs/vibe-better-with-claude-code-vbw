#!/usr/bin/env bats
# R190, phase P148 (L1): vbw next --json, for a step to run, carries .step: its
# kind, its size (plans in the wave; fixes; proof units left to run after
# reuse), its expected length in seconds and end time from the history, or null
# for both with no basis, and .say, the sentence VBW's chat message uses (D425):
# 'Building P1.1, P1.2 and P1.3: about 15 min, until around 14:20', or
# '...: no end time yet (VBW has timed fewer than 3 steps like this here)'.
# vbw run start says the same sentence, its time within a minute of next's;
# vbw status prints the running step in the same words, the later-than-usual
# and minutes-late cases included. Times are local (Europe/Zurich here).

load helper
load step-helper
load fixture-helper

built_project() {
  vbw_setup
  step_project
  export TZ=Europe/Zurich
}
setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# hm FIELD: the local HH:MM of the note's FIELD, after "tomorrow ", "yesterday " or the
# weekday when it falls on another local day than now, as VBW words it:
# the test holds at any hour, local midnight included.
hm() {
  jq -r --arg f "$1" '(.[$f] | fromdateiso8601) as $t | def day($e): $e | localtime | mktime / 86400 | floor;
    (day($t) - day(now)) as $d
    | (if $d == 0 then "" elif $d == 1 then "tomorrow " elif $d == -1 then "yesterday " else ($t | strflocaltime("%A ")) end) + ($t | strflocaltime("%H:%M"))' "$NOTE"
}
step_of() { "$VBW" next --json | jq -c '.step'; }

@test "R190: next gives a build wave its expected length and end time, and the sentence to say" {
  # An end after midnight in the local zone reads "tomorrow HH:MM", so the test names both forms.
  step_seed build 300 1 5
  local s
  s=$(step_of)
  printf '%s' "$s" | jq -e '.kind == "build" and .parts == 3 and .seconds == 900
    and (((.end | fromdateiso8601) - now) | . >= 880 and . <= 910)
    and (.say == "Building P1.1, P1.2 and P1.3: about 15 min, until around \(.end | fromdateiso8601 | strflocaltime("%H:%M"))"
         or .say == "Building P1.1, P1.2 and P1.3: about 15 min, until around tomorrow \(.end | fromdateiso8601 | strflocaltime("%H:%M"))")' \
    || { echo "$s"; false; }
}

@test "R190: without a basis next names the step and says there is no end time yet" {
  local s
  s=$(step_of)
  printf '%s' "$s" | jq -e '.kind == "build" and .parts == 3 and .seconds == null and .end == null
    and .say == "Building P1.1, P1.2 and P1.3: no end time yet (VBW has timed fewer than 3 steps like this here)"' || { echo "$s"; false; }
}

@test "R190: a proof's size is the units left to run after reuse" {
  mkdir -p tests
  printf 'cat src/a.txt > /dev/null\n' > tests/reads-a.sh
  step_edit '.plans[].status = "done" | .checks = [{id: "C1", req: "R1", run: ["sh", "tests/reads-a.sh"], files: ["tests/reads-a.sh"]},
    {id: "C2", req: "R1", run: ["true"]}, {id: "C3", req: "R1", run: ["true"]}]'
  git add -A && git commit -q -m "chore(vbw): checks"
  "$VBW" approve > /dev/null
  step_seed proof 30 3 3
  local s
  s=$(step_of)
  printf '%s' "$s" | jq -e '.kind == "proof" and .parts == 3 and .seconds == 30 and (.say | startswith("Proving"))' || { echo "$s"; false; }
  "$VBW" prove > /dev/null
  printf 'paid\n' >> src/a.txt
  git add src/a.txt && git commit -q -m "feat(pay): change a"
  s=$(step_of)
  printf '%s' "$s" | jq -e '.kind == "proof" and .parts == 1 and .seconds == 10' || { echo "$s"; false; }
}

@test "R190: planning, QA and a fix carry their own kind and expected length" {
  step_seed plan 60 - 3
  step_seed qa 120 - 3
  step_seed fix 200 1 3
  # A requirement with no check: the next step is planning.
  step_edit '.checks = []'
  step_of | jq -e '.kind == "plan" and .parts == null and .seconds == 60 and (.say | startswith("Planning"))' || { "$VBW" next --json; false; }
  step_edit '.checks = [{id: "C1", req: "R1", run: ["true"]}] | .phases[0].tier = "standard" | .plans[].status = "done"'
  git add -A && git commit -q -m "chore(vbw): built"
  "$VBW" approve > /dev/null
  "$VBW" prove --full > /dev/null
  step_of | jq -e '.kind == "qa" and .parts == null and .seconds == 120 and (.say | startswith("Checking P1"))' || { "$VBW" next --json; false; }
  step_edit '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  git add -A && git commit -q -m "chore(vbw): fix"
  step_of | jq -e '.kind == "fix" and .parts == 1 and .seconds == 200 and (.say | startswith("Fixing F1"))' || { "$VBW" next --json; false; }
}

@test "R190: vbw run start says what starts and when it should end, within a minute of next's time" {
  step_seed build 300 1 5
  local e1
  e1=$(step_of | jq -r '.end | fromdateiso8601')
  vbw_run run start build P1.1 P1.2 P1.3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ Building\ P1\.1,\ P1\.2\ and\ P1\.3:\ about\ 1[45]\ min,\ until\ around\ $(hm end) ]] || { echo "$output"; cat "$NOTE"; false; }
  jq -e --argjson e "$e1" '((.end | fromdateiso8601) - $e) | fabs <= 60' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R190: vbw status prints the running step, its progress and its end time in the same words" {
  step_seed build 300 1 5
  "$VBW" run start build P1.1 P1.2 > /dev/null
  vbw_run status
  [[ "$output" == *"P1.1"* && "$output" == *"0 of 2"* ]] || { echo "$output"; false; }
  [[ "$output" =~ about\ (9|10)\ min,\ until\ around\ $(hm end) ]] || { echo "$output"; cat "$NOTE"; false; }
}

@test "R190: vbw status says later than usual, minutes late, and no end time yet as the panel does" {
  step_seed build 300 1 3
  step_seed plan 60 - 3
  "$VBW" run start build P1.1 P1.2 P1.3 > /dev/null
  step_back 1000
  step_finish P1.1 src/a.txt
  vbw_run status
  [[ "$output" == *"until around $(hm end), later than usual"* ]] || { echo "$output"; cat "$NOTE"; false; }
  "$VBW" run end > /dev/null
  "$VBW" run start plan > /dev/null
  step_back 460
  vbw_run status
  [[ "$output" == *"until around $(hm first_end), 6 min late"* ]] || { echo "$output"; cat "$NOTE"; false; }
  "$VBW" run end > /dev/null
  "$VBW" run start qa > /dev/null
  vbw_run status
  [[ "$output" == *"no end time yet (VBW has timed fewer than 3 steps like this here)"* ]] || { echo "$output"; false; }
}

@test "R190: the Stop hook's gate does not pay for the step; vbw next does" {
  "$VBW" auto on s1 > /dev/null
  printf '%s' '{"session_id":"s1"}' | "$VBW" auto gate > /dev/null
  jq -e '.action == "build" and (has("step") | not)' .vbw/runtime/next.json || { cat .vbw/runtime/next.json; false; }
  "$VBW" next --json > /dev/null
  jq -e '.step.kind == "build"' .vbw/runtime/next.json || { cat .vbw/runtime/next.json; false; }
}
