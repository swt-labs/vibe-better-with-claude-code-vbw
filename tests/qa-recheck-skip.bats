#!/usr/bin/env bats
# R104 (docs/proof.md): a phase is not checked by QA again when the only change
# since its pass is a recorded decision, a closed finding with no code change,
# or a removed requirement that only a person judges; a phase whose code,
# tests, goal or remaining requirements changed is still checked again, also
# when one of those skip-type changes happens at the same time. L1.

load helper
load qa-recheck-helper
load qa-skip-helper

setup() { qa_skip_project; }
teardown() { vbw_teardown; }

@test "R104: right after its pass, the phase stands" {
  [ "$(rechecked)" = '[]' ]
  [ "$(standing)" = '["P1"]' ]
}

@test "R104: a newly recorded decision does not list the phase again" {
  "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null
  [ "$(rechecked)" = '[]' ]
  [ "$(standing)" = '["P1"]' ]
  next_json | jq -e '.action != "qa"'
}

@test "R104: a finding closed with no code change does not list the phase again" {
  edit_record '.fixes += [{id: "F1", req: "R1", attempts: 0, status: "open", note: "flaky check"}]'
  "$VBW" prove --full > /dev/null
  jq -e '.fixes[0].status == "closed"' .vbw/record.json
  [ "$(rechecked)" = '[]' ]
  [ "$(standing)" = '["P1"]' ]
}

@test "R104: removing one of the phase's [human] requirements does not list the phase again" {
  spec_drop 'R2 [human]'
  jq -e '(.requirements | map(.id)) == ["R1", "R3"] and (.phases[0].reqs == ["R1", "R3"])' .vbw/record.json
  [ "$(rechecked)" = '[]' ] || { next_json | jq -c '.qa.recheck'; false; }
  [ "$(standing)" = '["P1"]' ]
  next_json | jq -e '.action != "qa"'
}

@test "R104: a decision, a closed finding and a removed [human] requirement together still do not list the phase" {
  "$VBW" decide "Use blue buttons" > /dev/null
  edit_record '.fixes += [{id: "F1", req: "R1", attempts: 0, status: "open", note: "flaky check"}]'
  spec_drop 'R2 [human]'
  jq -e '.fixes[0].status == "closed"' .vbw/record.json
  [ "$(rechecked)" = '[]' ] || { next_json | jq -c '.qa.recheck'; false; }
}

@test "R104: a removed [human] requirement together with a code change lists the phase, with the reason" {
  spec_drop 'R2 [human]'
  qa_touch 1
  [ "$(rechecked)" = '["P1"]' ]
  next_json | jq -e '.qa.recheck.P1 | any(.[]; test("files changed"))'
}

@test "R104: a removed [human] requirement together with a changed goal lists the phase" {
  spec_drop 'R2 [human]'
  edit_record '(.phases[] | select(.id == "P1")).goal = "The parts work for every customer"'
  [ "$(rechecked)" = '["P1"]' ]
  next_json | jq -e '.qa.recheck.P1 | any(.[]; test("goal or plan changed"))'
}

@test "R104: a decision together with a changed test lists the phase" {
  "$VBW" decide "Use blue buttons" > /dev/null
  change_test
  [ "$(rechecked)" = '["P1"]' ]
  next_json | jq -e '.qa.recheck.P1 | any(.[]; test("tests changed"))'
}

@test "R104: a finding closed together with a code change lists the phase" {
  edit_record '.fixes += [{id: "F1", req: "R1", attempts: 0, status: "open", note: "flaky check"}]'
  qa_touch 1
  jq -e '.fixes[0].status == "closed"' .vbw/record.json
  [ "$(rechecked)" = '["P1"]' ]
  next_json | jq -e '.qa.recheck.P1 | any(.[]; test("files changed"))'
}
