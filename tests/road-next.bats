#!/usr/bin/env bats
# R191, phase P150 (L1): vbw next --json carries road, the kernel's one clock time
# for the end of the milestone: {seconds, end, rounds: {tier: n}, basis, say}. It adds,
# for every phase of the milestone not yet passed by QA, each build wave still to
# build (P149's rule: the plans' tiers and tasks, waves as vbw show contract lists
# them), one proof per wave over the phase's checks not yet passed (P149's proof
# rule), QA when the phase's tier needs it, and the phase's usual fix rounds, each
# one fix round plus one proof plus one QA recheck. The usual fix rounds per tier
# are the median of outcome.fix_rounds over the latest 10 finished phases of that
# tier, rounded; fewer than 3 finished phases of a tier counts 0 rounds and the
# sentence says so. Before planning the road is the planning step alone. A piece
# with no basis makes end null and names the missing kind. No phase left: null.
# vbw status --json and vbw status carry the same road. Times are local
# (Europe/Zurich here).
#
# The fixture (road-helper.bash): P1 deep with P1.1 (2 tasks) and P1.2 (5 tasks),
# P2 standard with P2.1 (3 tasks) after P1.1; a task takes 100 s at either tier; a
# deep QA check 200 s, a standard one 100 s; a deep fix round 300 s; a proof of
# check:C1 10 s, of check:C2 20 s (ratio 1); finished deep phases took 1, 2, 2 and 5
# fix rounds. Waves: [P1.1, P1.2] then [P2.1]. The road: 500 (wave 1, its longest
# plan) + 10 (proof of C1) + 300 (wave 2) + 20 (proof of C2) + 200 (QA P1) + 100 (QA
# P2) + 2 deep rounds of (300 + 10 + 200) = 2150 s, about 36 min; no standard rounds.

load helper
load step-helper
load road-helper
load fixture-helper

built_project() {
  vbw_setup
  export TZ=Europe/Zurich
  road_project
  ROAD_HIST_RUNS=5 road_hist
  outcomes_seed deep 1 2 2 5
}
setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# hm ISO: the local HH:MM of a UTC time as VBW words it: today bare, tomorrow, yesterday, else the weekday.
hm() {
  jq -nr --arg t "$1" '($t | fromdateiso8601) as $t | def day($e): $e | localtime | mktime / 86400 | floor;
    (day($t) - day(now)) as $d
    | (if $d == 0 then "" elif $d == 1 then "tomorrow " elif $d == -1 then "yesterday " else ($t | strflocaltime("%A ")) end) + ($t | strflocaltime("%H:%M"))'
}

@test "R191: the road adds the waves, their proofs, QA and the usual fix rounds; its sentence names the end and the rounds counted" {
  local r
  r=$(road_of)
  printf '%s' "$r" | jq -e '.seconds == 2150 and .rounds == {deep: 2, standard: 0} and (.basis | type == "string" and length > 0)
    and ((.end | fromdateiso8601) - now | . >= 2100 and . <= 2200)' || { echo "$r"; false; }
  printf '%s' "$r" | jq -e --arg at "$(hm "$(printf '%s' "$r" | jq -r .end)")" '.say | startswith("Milestone end: about 36 min, until around \($at), counting ")' || { echo "$r"; false; }
  printf '%s' "$r" | jq -e '.say | contains("2 fix rounds per deep phase") and contains("(the usual here)") and contains("fewer than 3 finished standard phases here")' || { echo "$r"; false; }
  "$VBW" next --json | jq -e '.action == "build"' > /dev/null
}

@test "R191: the usual fix rounds are the rounded median of outcome.fix_rounds of the latest 10 finished phases of the tier (1, 2, 2, 5 gives 2)" {
  road_of | jq -e '.rounds.deep == 2' || { road_of; false; }
  outcomes_seed deep 9 9 9 9 9 9 9
  road_of | jq -e '.rounds.deep == 9 and .seconds == 2150 + 7 * 510' || { road_of; false; }
}

@test "R191: with fewer than 3 finished phases of a tier the road counts no fix rounds and says why" {
  jq 'del(.phases[] | select(.milestone == "M0"))' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  outcomes_seed deep 4 4
  local r
  r=$(road_of)
  printf '%s' "$r" | jq -e '.rounds == {deep: 0, standard: 0} and .seconds == 1130
    and (.say | startswith("Milestone end: about 19 min, until around "))
    and (.say | test("counting no fix rounds: fewer than 3 finished deep( and standard)? phases here"))' || { echo "$r"; false; }
}

@test "R191: a wave already built leaves the road; a built phase whose checks are not passed still counts one proof" {
  step_edit '(.plans[] | select(.id == "P1.1")).status = "done" | (.plans[] | select(.id == "P1.2")).status = "done"'
  local r
  r=$(road_of)
  # Left: proof of C1 10 (P1 is built, not proved) + wave [P2.1] 300 + proof of C2 20 + QA P1 200 + QA P2 100 + P1's 2 rounds 1020 = 1650.
  printf '%s' "$r" | jq -e '.seconds == 1650' || { echo "$r"; false; }
}

@test "R191: before planning the road is the planning step alone and says the rest follows once the work is planned" {
  step_edit '.phases = [] | .plans = [] | .checks = []'
  "$VBW" next --json | jq -e '.action == "plan"' > /dev/null || { "$VBW" next --json; false; }
  local r
  r=$(road_of)
  printf '%s' "$r" | jq -e '.end == null and .seconds == null and .rounds == {}
    and .say == "no milestone end time yet (VBW has timed fewer than 3 planning steps here)"' || { echo "$r"; false; }
  hist_plan 2 100 5
  r=$(road_of)
  printf '%s' "$r" | jq -e '.seconds == 100 and (.end | type == "string") and .rounds == {}
    and (.say | test("^Milestone end: planning about 2 min, until around (tomorrow )?[0-9]{2}:[0-9]{2}; the rest follows once the work is planned$"))' || { echo "$r"; false; }
}

@test "R191: a piece with no basis gives no end and names the missing kind; a made-up time never appears" {
  jq 'del(.steps[] | select(.kind == "proof"))' "$STEPS" > "$TEST_ROOT/h.json" && cp "$TEST_ROOT/h.json" "$STEPS"
  rm -f "$(dirname "$STEPS")/runs.json" "$(dirname "$STEPS")/run-times.json"
  local r
  r=$(road_of)
  printf '%s' "$r" | jq -e '.end == null and .seconds == null and .rounds == {deep: 2, standard: 0}
    and .say == "no milestone end time yet (VBW has timed fewer than 3 proofs here)"
    and (.basis | contains("fewer than 3 proofs"))' || { echo "$r"; false; }
  jq 'del(.steps[] | select(.kind == "qa"))' "$STEPS" > "$TEST_ROOT/h.json" && cp "$TEST_ROOT/h.json" "$STEPS"
  road_of | jq -e '.end == null and (.say | startswith("no milestone end time yet (VBW has timed fewer than 3 "))' || { road_of; false; }
}

@test "R191: durations over an hour read 'about 2 h 36 min' and the clock follows the step's rules" {
  jq 'del(.steps[] | select(.kind == "build"))' "$STEPS" > "$TEST_ROOT/h.json" && cp "$TEST_ROOT/h.json" "$STEPS"
  hist_build deep 1 1000 5
  hist_build standard 1 1000 5
  local r
  r=$(road_of)
  # 5000 + 10 + 3000 + 20 + 200 + 100 + 1020 = 9350 s.
  printf '%s' "$r" | jq -e '.seconds == 9350' || { echo "$r"; false; }
  printf '%s' "$r" | jq -e --arg at "$(hm "$(printf '%s' "$r" | jq -r .end)")" '.say | startswith("Milestone end: about 2 h 36 min, until around \($at), counting ")' || { echo "$r"; false; }
}

@test "R191: with no phase left the road is null; a shipped milestone shows nothing" {
  step_edit '.milestone.status = "shipped" | .shipped += [{id: "M1", title: "Shop", at: "2026-01-02T00:00:00Z"}]'
  "$VBW" next --json | jq -e '.action == "milestone" and .road == null' || { "$VBW" next --json; false; }
  "$VBW" status --json | jq -e '.road == null' || { "$VBW" status --json; false; }
  ! "$VBW" status | grep -qi 'milestone end'
}

@test "R191: vbw status --json carries the same road as vbw next --json, and vbw status prints its sentence" {
  local n s
  n=$(road_of)
  s=$("$VBW" status --json | jq -c '.road')
  [ "$(printf '%s' "$n" | jq -c '{seconds, rounds, basis}')" = "$(printf '%s' "$s" | jq -c '{seconds, rounds, basis}')" ] || { echo "$n"; echo "$s"; false; }
  jq -n --argjson n "$n" --argjson s "$s" -e '(($n.end | fromdateiso8601) - ($s.end | fromdateiso8601)) | fabs <= 60' || { echo "$n"; echo "$s"; false; }
  vbw_run status
  [[ "$output" == *"Milestone end: about 36 min, until around"* ]] || { echo "$output"; false; }
}

@test "R191: while a step runs, vbw next --json, vbw status --json and the note give the identical milestone end" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  local n s o
  n=$("$VBW" next --json | jq -r '.road.end')
  s=$("$VBW" status --json | jq -r '.road.end')
  o=$(jq -r '.road.end' "$NOTE")
  [ -n "$o" ] && [ "$o" != null ] || { cat "$NOTE"; false; }
  [ "$n" = "$o" ] || { echo "next: $n note: $o"; false; }
  [ "$s" = "$o" ] || { echo "status: $s note: $o"; false; }
  vbw_run status
  [[ "$output" == *"now: building P1.1, P1.2"* && "$output" == *"Milestone end: about "* ]] || { echo "$output"; false; }
}
