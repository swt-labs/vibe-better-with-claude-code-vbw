#!/usr/bin/env bats
# R270: an estimate from thin or spread history is a range. lib/steps-expect.jq
# gives the step's low and high seconds, its run count and whether the estimate
# is rough: fewer than 5 kept runs, or a high above 1.5 times the low (the two
# thresholds are one definition there, documented in docs/panel.md). No run
# still says 'no end time yet'; 1 or 2 runs now give a rough range naming the
# run count instead of nothing; 5 or more tight runs keep the single figure as
# it was. The step's sentence (vbw next --json .step.say, vbw run start, vbw
# status) reads 'roughly 15 to 21 min, until around 14:20 to 14:26 (rough guess
# from 2 runs)'; the road (.road.say) 'Milestone end: roughly L to H min, until
# around A to B (rough guess)' when any part is rough, its 'counting ...' tail
# kept; the step note (.vbw/runtime/step.json) carries end_low, end_high, rough
# and runs beside end; the status line shows 'until ~14:20-14:26' when rough
# and the panel words the same fields. Times are local (Europe/Zurich). L1.

load helper
load step-helper
load fixture-helper

range_project() {
  vbw_setup
  step_project
  SL="$PLUGIN_ROOT/scripts/vbw-statusline.sh"
  export TZ=Europe/Zurich
}
setup_file() { fixture_build range range_project; }
setup() { fixture_copy range; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# The clock as VBW words it: HH:MM, after "tomorrow " or the weekday when it falls
# on another local day than now (the tests hold at any hour, midnight included).
CLK='def clk($e): ($e | fromdateiso8601) as $t | def day($x): $x | localtime | mktime / 86400 | floor;
  (day($t) - day(now)) as $d
  | (if $d == 0 then "" elif $d == 1 then "tomorrow " elif $d == -1 then "yesterday " else ($t | strflocaltime("%A ")) end) + ($t | strflocaltime("%H:%M"));'

step_of() { "$VBW" next --json < /dev/null | jq -c '.step'; }
road_of() { "$VBW" next --json < /dev/null | jq -c '.road'; }

# step_is JQ: the step of vbw next --json satisfies JQ (with clk defined), else it is printed.
step_is() { local s; s=$(step_of); printf '%s' "$s" | jq -e "$CLK$1" > /dev/null || { echo "$s"; false; }; }
road_is() { local r; r=$(road_of); printf '%s' "$r" | jq -e "$CLK$1" > /dev/null || { echo "$r"; false; }; }

# hm FIELD: the local clock of the note's FIELD, as clk words it.
hm() { jq -r --arg f "$1" "$CLK"'clk(.[$f])' "$NOTE"; }

render() {
  jq -nc --arg d "$PROJECT" '{session_id: "s1", workspace: {project_dir: $d, current_dir: $d}, model: {display_name: "Sonnet 5.5"}, version: "2.1.286"}' \
    | NO_COLOR=1 bash "$SL"
}

@test "R270 kernel: no run still gives no end time, in the words of today" {
  step_is '.seconds == null and .end == null and .low == null and .high == null and .runs == 0
    and .say == "Building P1.1, P1.2 and P1.3: no end time yet (VBW has timed fewer than 3 steps like this here)"'
}

@test "R270 kernel: one run gives a rough figure naming the one run; two runs a rough range naming both" {
  step_seed build 300 1 1
  step_is '.rough == true and .runs == 1 and .low == 900 and .high == 900 and .seconds == 900 and .end_low == .end_high
    and .say == "Building P1.1, P1.2 and P1.3: roughly 15 min, until around \(clk(.end_low)) (rough guess from 1 run)"'
  step_seed build 420 1 1
  step_is '.rough == true and .runs == 2 and .low == 900 and .high == 1260 and (.end_low < .end_high)
    and .say == "Building P1.1, P1.2 and P1.3: roughly 15 to 21 min, until around \(clk(.end_low)) to \(clk(.end_high)) (rough guess from 2 runs)"'
}

@test "R270 kernel: four runs that agree are still rough (fewer than 5 kept runs); five that agree give the single figure as before" {
  step_seed build 300 1 4
  step_is '.rough == true and .runs == 4 and .low == 900 and .high == 900
    and .say == "Building P1.1, P1.2 and P1.3: roughly 15 min, until around \(clk(.end_low)) (rough guess from 4 runs)"'
  step_seed build 300 1 1
  step_is '.rough == false and .runs == 5 and .low == 900 and .high == 900 and .seconds == 900
    and .say == "Building P1.1, P1.2 and P1.3: about 15 min, until around \(clk(.end))"'
}

@test "R270 kernel: ten runs spread beyond 1.5 times give a rough range naming the ten runs" {
  step_seed build 300 1 5
  step_seed build 600 1 5
  step_is '.rough == true and .runs == 10 and .low == 900 and .high == 1800
    and .say == "Building P1.1, P1.2 and P1.3: roughly 15 to 30 min, until around \(clk(.end_low)) to \(clk(.end_high)) (rough guess from 10 runs)"'
}

@test "R270 kernel: the thresholds are one definition in lib/steps-expect.jq" {
  grep -q '^def rough' "$PLUGIN_ROOT/lib/steps-expect.jq" || { echo "no def rough in steps-expect.jq"; false; }
  [ "$(grep -c '1\.5' "$PLUGIN_ROOT/lib/steps-expect.jq")" = 1 ] || { echo "1.5 appears other than once"; false; }
  [ "$(grep -c '< 5' "$PLUGIN_ROOT/lib/steps-expect.jq")" = 1 ] || { echo "'< 5' appears other than once"; false; }
}

@test "R270 kernel: the road is a range when any part is rough, keeping its counting tail; tight parts keep the single figure" {
  step_seed proof 60 1 5
  step_seed build 300 1 2
  road_is '.rough == true and .low == 960 and .high == 960 and .seconds == 960
    and .say == "Milestone end: roughly 16 min, until around \(clk(.end_low)) (rough guess), counting no fix rounds: fewer than 3 finished express phases here"'
  step_seed build 600 1 1
  road_is '.rough == true and .low == 960 and .high == 1860
    and .say == "Milestone end: roughly 16 to 31 min, until around \(clk(.end_low)) to \(clk(.end_high)) (rough guess), counting no fix rounds: fewer than 3 finished express phases here"'
  step_seed build 300 1 2
  road_is '.rough == true and (.say | startswith("Milestone end: roughly "))'
  step_seed build 300 1 20
  road_is '.rough == false and .low == 960 and .high == 960
    and .say == "Milestone end: about 16 min, until around \(clk(.end)), counting no fix rounds: fewer than 3 finished express phases here"'
}

@test "R270 kernel: the step note carries both ends, the rough flag and the run count; vbw run start and vbw status say the range" {
  step_seed build 300 1 1
  step_seed build 420 1 1
  run "$VBW" run start build P1.1 P1.2 P1.3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e "$CLK"'.rough == true and .runs == 2 and (.end_low < .end_high)
    and ((.end_low | fromdateiso8601) - (.started_at | fromdateiso8601)) == 900
    and ((.end_high | fromdateiso8601) - (.started_at | fromdateiso8601)) == 1260' "$NOTE" || { cat "$NOTE"; false; }
  [[ "$output" == *"Building P1.1, P1.2 and P1.3: roughly 15 to 21 min, until around $(hm end_low) to $(hm end_high) (rough guess from 2 runs)"* ]] || { echo "$output"; false; }
  run "$VBW" status
  [[ "$output" == *"building P1.1, P1.2, P1.3 · 0 of 3 · roughly 15 to 21 min, until around $(hm end_low) to $(hm end_high) (rough guess from 2 runs)"* ]] || { echo "$output"; false; }
}

@test "R270 line: the status line shows 'until ~HH:MM-HH:MM' for a rough range, and the single clock as before for a tight one" {
  step_seed build 300 1 1
  step_seed build 420 1 1
  "$VBW" run start build P1.1 P1.2 P1.3 > /dev/null
  run render
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"building P1.1, P1.2, P1.3 · 0 of 3 · until ~$(hm end_low)-$(hm end_high)"* ]] || { echo "${lines[0]}"; false; }
  [[ "${lines[0]}" != *"roughly"* && "${lines[0]}" != *"rough guess"* ]] || { echo "${lines[0]}"; false; }
}

@test "R270 line: the status line keeps the single clock for a tight estimate" {
  step_seed build 300 1 5
  "$VBW" run start build P1.1 P1.2 P1.3 > /dev/null
  run render
  [[ "${lines[0]}" == *"building P1.1, P1.2, P1.3 · 0 of 3 · until around $(hm end)"* ]] || { echo "${lines[0]}"; false; }
  [[ "${lines[0]}" != *"~"* ]] || { echo "${lines[0]}"; false; }
}

@test "R270 line: the panel words a rough note as a range from the same fields" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  step_seed build 300 1 1
  step_seed build 420 1 1
  "$VBW" run start build P1.1 P1.2 P1.3 > /dev/null
  run node --input-type=module -e "
    import { pathToFileURL } from 'node:url'
    const step = await import(pathToFileURL(process.argv[1]).href)
    const note = JSON.parse(process.argv[2])
    const w = step.stepWords(note, Date.parse(note.started_at))
    console.log(w.text)" "$PLUGIN_ROOT/hooks/panel-step.js" "$(cat "$NOTE")"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "roughly 15 to 21 min, until around $(hm end_low) to $(hm end_high) (rough guess from 2 runs)" ]] || { echo "$output"; false; }
}

@test "R270 docs: docs/panel.md documents the two thresholds, and docs/next.md and docs/statusline.md the range wording" {
  grep -q 'fewer than 5' "$REPO_ROOT/docs/panel.md" || { echo "docs/panel.md does not state the 5-run threshold"; false; }
  grep -q '1\.5' "$REPO_ROOT/docs/panel.md" || { echo "docs/panel.md does not state the 1.5 spread threshold"; false; }
  grep -q 'rough guess from' "$REPO_ROOT/docs/panel.md" || { echo "docs/panel.md does not show the range wording"; false; }
  grep -q 'rough guess from' "$REPO_ROOT/docs/next.md" || { echo "docs/next.md does not show the range wording"; false; }
  grep -q 'until ~' "$REPO_ROOT/docs/statusline.md" || { echo "docs/statusline.md does not show the status line's range form"; false; }
}

# own_proof_note N: a proof of N units starts in a session of its own (no run lease);
# proofsteps_begin writes the note, which stays at $NOTE.
own_proof_note() {
  # shellcheck disable=SC2016 # expanded by the inner bash
  PS_N=$1 bash -c 'cd "$1"; VBW_LIB="$2/lib"; . "$VBW_LIB/core.sh"; . "$VBW_LIB/record.sh"; . "$VBW_LIB/consent.sh"; . "$VBW_LIB/contract.sh"; . "$VBW_LIB/proofsteps.sh"
    vbw_project; VBW_PLUGIN="$2"; proofsteps_begin "$PS_N"; cp "$(step_note_file)" "$VBW_RUNTIME/kept.json"' _ "$PROJECT" "$PLUGIN_ROOT"
  # The guard's exit trap removes the note a proof of its own made; the copy stands in for it.
  cp "$PROJECT/.vbw/runtime/kept.json" "$NOTE"
}

@test "R270 kernel: a proof of VBW's own writes its note with the range fields, rough from thin or spread history, single from five tight runs" {
  step_seed proof 100 5 2
  own_proof_note 4
  jq -e '.kind == "proof" and .rough == true and .runs == 2 and .end_low != null and .end_high != null and (.end_low <= .end) and (.end <= .end_high)' "$NOTE" || { cat "$NOTE"; false; }
  # The same words the proof's own vbw next sentence says, from the same fields.
  run render
  [[ "${lines[0]}" == *"until ~$(hm end_low)"* ]] || { echo "${lines[0]}"; false; }
  [[ "${lines[0]}" != *"until around"* ]] || { echo "${lines[0]}"; false; }
  # Spread runs (a high above 1.5 times the low) are rough however many.
  rm -f "$NOTE" "$STEPS"
  step_seed proof 100 5 3
  step_seed proof 400 5 3
  own_proof_note 4
  jq -e '.rough == true and .runs == 6 and .end_low < .end_high' "$NOTE" || { cat "$NOTE"; false; }
  # Five tight runs keep the single figure.
  rm -f "$NOTE" "$STEPS"
  step_seed proof 100 5 5
  own_proof_note 4
  jq -e '.rough == false and .runs == 5 and .end != null' "$NOTE" || { cat "$NOTE"; false; }
  run render
  [[ "${lines[0]}" == *"until around $(hm end)"* && "${lines[0]}" != *"~"* ]] || { echo "${lines[0]}"; false; }
}
