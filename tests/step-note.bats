#!/usr/bin/env bats
# R190, phase P146 (L1): while a step runs, the kernel keeps one note,
# .vbw/runtime/step.json, and vbw status --json gives it as .step: the kind,
# what the step is doing now, parts done of total, the start, the first end
# time, the current end time and whether it is later than usual; first_end null
# means no basis yet. Parts done update with each vbw plan done. A late step
# with parts (D424) moves its end to this run's own pace, marked later than
# usual, and never earlier than its first end time; a late step without parts
# keeps its first end time and vbw status --json says how many minutes past it
# the step is (.step.minutes_late). A note whose run has ended, or whose proof
# process is gone, is ignored, and removed by the next step (the next proof:
# tests/step-proof-history.bats).

load helper
load step-helper
load fixture-helper

built_project() {
  vbw_setup
  step_project
}
setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

status_step() { "$VBW" status --json | jq -c '.step'; }

@test "R190: vbw run start writes the note: kind, run, session, what it is doing, parts, start and end times" {
  step_seed build 300 1 3
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 P1.2 > /dev/null
  [ -f "$NOTE" ] || { echo "no note at .vbw/runtime/step.json"; false; }
  jq -e --slurpfile r .vbw/record.json '.kind == "build" and .run == $r[0].lease.run and .session == "s1"
    and .started_at == $r[0].lease.started_at and .ids == ["P1.1", "P1.2"]
    and (.doing | test("P1\\.1") and test("P1\\.2")) and .parts == {done: 0, total: 2} and .proof == null
    and (.first_end | type == "string") and .end == .first_end and .late == false' "$NOTE" || { cat "$NOTE"; false; }
  [ "$(step_secs first_end)" -eq 600 ]
}

@test "R190: vbw status --json gives the running step as the note says it" {
  step_seed build 300 1 3
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 P1.2 > /dev/null
  status_step | jq -e --slurpfile n "$NOTE" '.kind == "build" and .doing == $n[0].doing and .parts == {done: 0, total: 2}
    and .started_at == $n[0].started_at and .first_end == $n[0].first_end and .end == $n[0].end and .late == false
    and (.minutes_late // null) == null' || { status_step; false; }
}

@test "R190: each kind of step says what it is doing; QA names the phases it checks" {
  local k
  for k in plan map; do
    "$VBW" run start "$k" > /dev/null
    jq -e --arg k "$k" '.kind == $k and (.doing | type == "string" and length > 0) and .parts == null
      and .doing == (if $k == "plan" then "planning" else "mapping the project" end)' "$NOTE" || { cat "$NOTE"; false; }
    "$VBW" run end > /dev/null
  done
  step_edit '.phases[0].tier = "standard" | .plans[].status = "done"'
  git add -A && git commit -q -m "chore(vbw): built"
  "$VBW" run start qa > /dev/null
  jq -e '.kind == "qa" and .ids == ["P1"] and .doing == "checking P1" and (.doing | test("QA") | not) and .parts == null' "$NOTE" || { cat "$NOTE"; false; }
  "$VBW" run end > /dev/null
  step_edit '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  git add -A && git commit -q -m "chore(vbw): fix"
  "$VBW" run start fix F1 > /dev/null
  jq -e '.kind == "fix" and .ids == ["F1"] and .doing == "fixing F1" and .parts == {done: 0, total: 1}' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R190: each vbw plan done counts one more part done, at once" {
  step_seed build 300 1 3
  "$VBW" run start build P1.1 P1.2 > /dev/null
  step_finish P1.1 src/a.txt
  jq -e '.parts == {done: 1, total: 2} and .ids == ["P1.1", "P1.2"]' "$NOTE" || { cat "$NOTE"; false; }
  status_step | jq -e '.parts == {done: 1, total: 2}'
  step_finish P1.2 src/b.txt
  jq -e '.parts == {done: 2, total: 2}' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R190 (D424): a late step with parts moves its end to this run's own pace, marked later than usual, and can move again" {
  # 300 s a plan, three plans: the first end is 900 s after the start.
  step_seed build 300 1 3
  "$VBW" run start build P1.1 P1.2 P1.3 > /dev/null
  [ "$(step_secs first_end)" -eq 900 ]
  # One plan done after 1000 s: at that pace the three take 3000 s.
  step_back 1000
  step_finish P1.1 src/a.txt
  [ "$(step_secs first_end)" -eq 900 ] || { cat "$NOTE"; false; }
  [ "$(step_secs end)" -ge 2990 ] && [ "$(step_secs end)" -le 3600 ] || { cat "$NOTE"; false; }
  jq -e '.late == true' "$NOTE" || { cat "$NOTE"; false; }
  status_step | jq -e '.late == true and .end != .first_end'
  # The second plan after 1500 s in all: 2250 s for three, still after 900 s.
  step_back 500
  step_finish P1.2 src/b.txt
  [ "$(step_secs end)" -ge 2240 ] && [ "$(step_secs end)" -le 2700 ] || { cat "$NOTE"; false; }
  jq -e '.late == true' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R190 (D424): the end time never moves earlier than the first end time" {
  step_seed build 300 1 3
  "$VBW" run start build P1.1 P1.2 P1.3 > /dev/null
  # One plan done after 100 s: this pace would end at 300 s, before the first end time.
  step_back 100
  step_finish P1.1 src/a.txt
  [ "$(step_secs end)" -eq 900 ] || { cat "$NOTE"; false; }
  jq -e '.late == false and .end == .first_end' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R190 (D424): a late step without parts keeps its first end time and says how many minutes past it it is" {
  step_seed plan 60 - 3
  "$VBW" run start plan > /dev/null
  # Started 460 s ago, due after 60 s: 400 s past its end, 6 whole minutes.
  step_back 460
  status_step | jq -e '.kind == "plan" and .end == .first_end and .late == false and .minutes_late == 6' || { status_step; false; }
  jq -e '.end == .first_end' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R190: with no basis the note and vbw status say so: no end time" {
  "$VBW" run start build P1.1 > /dev/null
  jq -e '.first_end == null and .end == null and .late == false' "$NOTE" || { cat "$NOTE"; false; }
  status_step | jq -e '.kind == "build" and .first_end == null and .end == null'
}

@test "R190: when the step ends its note goes; a note of an ended run is ignored and the next step replaces it" {
  "$VBW" run start build P1.1 > /dev/null
  cp "$NOTE" "$TEST_ROOT/old-note.json"
  "$VBW" run end > /dev/null
  [ ! -e "$NOTE" ] || { echo "the note outlived its run"; cat "$NOTE"; false; }
  "$VBW" status --json | jq -e 'has("step") and .step == null' > /dev/null || { "$VBW" status --json; false; }
  # A note left behind (a run ended without its note being removed) is not a running step.
  cp "$TEST_ROOT/old-note.json" "$NOTE"
  "$VBW" status --json | jq -e 'has("step") and .step == null' > /dev/null || { "$VBW" status --json; false; }
  "$VBW" run start plan > /dev/null
  jq -e '.kind == "plan"' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R190: the note of a proof whose process is gone is never a running step, and the next step removes it" {
  local gone
  sh -c 'exit 0' &
  gone=$!
  wait "$gone" || true
  jq -n --argjson pid "$gone" '{kind: "proof", run: null, session: "s9", pid: $pid, started_at: (now | floor | todateiso8601),
    ids: [], doing: "proving 3 of 40 checks", parts: {done: 3, total: 40}, proof: {done: 3, total: 40},
    first_end: (now + 600 | floor | todateiso8601), end: (now + 600 | floor | todateiso8601), late: false}' > "$NOTE"
  "$VBW" status --json | jq -e 'has("step") and .step == null' > /dev/null || { "$VBW" status --json; false; }
  "$VBW" run start plan > /dev/null
  jq -e '.kind == "plan"' "$NOTE" || { cat "$NOTE"; false; }
}
