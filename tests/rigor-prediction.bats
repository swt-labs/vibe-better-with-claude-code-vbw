#!/usr/bin/env bats
# R28: each finished phase records its predicted tier and the outcome (fix
# rounds, QA findings, escalations); vbw show rigor reports how often the
# prediction held. A phase is finished when its plans are done, its requirements
# proven (or accepted, for [human] ones), no fix is open, and QA has passed when
# its tier calls for QA.

load helper
load rigor-helper

teardown() { vbw_teardown; }

@test "a proven express phase is finished with its predicted tier and outcome" {
  rigor_flow_setup
  rigor_flow_build
  phase_json '.phases[0].outcome | .tier == "express" and .predicted == "express" and .held == true
    and .fix_rounds == 0 and .qa_findings == 0 and .escalations == 0'
}

@test "a standard phase is finished only once QA has passed it" {
  rigor_flow_setup
  "$VBW" config rigor standard > /dev/null
  rigor_flow_build
  phase_json '.phases[0] | has("outcome") | not'
  "$VBW" qa record P1 pass standard > /dev/null
  phase_json '.phases[0].outcome | .tier == "standard" and .predicted == "standard" and .held == true'
}

@test "an express phase with a [human] requirement is finished once QA passed and the user accepted" {
  rigor_flow_setup human
  rigor_flow_build
  "$VBW" qa record P1 pass quick > /dev/null
  phase_json '.phases[0] | has("outcome") | not'
  "$VBW" req accept R2 > /dev/null
  phase_json '.phases[0].outcome.tier == "express"'
}

@test "an escalated phase records that its prediction did not hold" {
  rigor_flow_setup
  rigor_flow_approve
  "$VBW" tier raise P1 standard "the user asked for more care" > /dev/null
  rigor_flow_work
  "$VBW" qa record P1 pass standard > /dev/null
  phase_json '.phases[0].outcome | .tier == "standard" and .predicted == "express" and .held == false and .escalations == 1'
}

@test "QA findings and fix rounds are counted" {
  rigor_flow_setup
  "$VBW" config rigor standard > /dev/null
  rigor_flow_build
  "$VBW" qa finding R1 "the greeting is missing" > /dev/null
  "$VBW" qa record P1 fail standard > /dev/null
  "$VBW" qa record P1 pass standard > /dev/null
  phase_json '.phases[0].outcome | .qa_findings == 1 and .fix_rounds == 1'
}

@test "the outcome of a finished phase is not rewritten by a later proof" {
  rigor_flow_setup
  rigor_flow_build
  phase_json '.phases[0].outcome.tier == "express"'
  cp .vbw/record.json "$TEST_ROOT/finished.json"
  "$VBW" prove > /dev/null
  [ "$(jq -c '.phases[0].outcome' .vbw/record.json)" = "$(jq -c '.phases[0].outcome' "$TEST_ROOT/finished.json")" ]
}

@test "vbw show rigor says plainly when no phase is finished" {
  rigor_flow_setup
  vbw_run show rigor
  [ "$status" -eq 0 ]
  [[ "$output" == *"no finished phases"* ]]
  [[ "$output" == *P1* ]]
  [[ "$output" == *express* ]]
}

@test "vbw show rigor reports how many finished phases held their predicted tier" {
  rigor_project 3
  edit_record '.phases = [
      {id: "P1", title: "A", reqs: ["R1"], milestone: "M1", tier: "express", reasons: ["requirements: 1"], predicted: "express",
       outcome: {tier: "express", predicted: "express", held: true, fix_rounds: 0, qa_findings: 0, escalations: 0}},
      {id: "P2", title: "B", reqs: ["R2"], milestone: "M1", tier: "standard", reasons: ["requirements: 1"], predicted: "standard",
       outcome: {tier: "standard", predicted: "standard", held: true, fix_rounds: 0, qa_findings: 0, escalations: 0}},
      {id: "P3", title: "C", reqs: ["R3"], milestone: "M1", tier: "deep", reasons: ["requirements: 1"], predicted: "express",
       outcome: {tier: "deep", predicted: "express", held: false, fix_rounds: 2, qa_findings: 1, escalations: 2}}]'
  vbw_run show rigor
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 of 3"* ]]
  [[ "$output" == *"67%"* ]]
  edit_record '.phases |= .[0:1]'
  vbw_run show rigor
  [[ "$output" == *"1 of 1"* ]]
  [[ "$output" == *"100%"* ]]
}
