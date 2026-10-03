#!/usr/bin/env bats
# R24: an express phase is approved in one step (its requirement, check and
# plan together), built by one Dev and proved, and runs QA only when a
# requirement needs a person's judgement or the phase escalated. Standard and
# deep phases keep their multi-step approval and QA.

load helper
load rigor-helper

teardown() { vbw_teardown; }

@test "an express phase shows its requirement, check and plan together on one line" {
  rigor_flow_setup
  jq -e '.phases[0].tier == "express"' .vbw/record.json
  vbw_run show contract
  [ "$status" -eq 0 ]
  line=$(printf '%s\n' "$output" | grep express | grep R1 | grep C1 | grep 'P1\.1' | head -1)
  [ -n "$line" ]
}

@test "a standard phase keeps the separate requirement, check and plan listing" {
  rigor_flow_setup
  "$VBW" config rigor standard > /dev/null
  vbw_run show contract
  [ "$status" -eq 0 ]
  [[ "$output" == *"R1 [auto]"* ]]
  [ -z "$(printf '%s\n' "$output" | grep R1 | grep C1 | grep 'P1\.1' | head -1)" ]
}

@test "one approval records the requirement, check and plan of an express phase" {
  rigor_flow_setup
  vbw_run approve
  [ "$status" -eq 0 ]
  [ "$(jq '[.decisions[] | select(.text | startswith("Contract approved"))] | length' .vbw/record.json)" -eq 1 ]
  text=$(jq -r '.decisions[-1].text' .vbw/record.json)
  [[ "$text" == *express* ]]
  [[ "$text" == *R1* ]]
  [[ "$text" == *C1* ]]
  [[ "$text" == *P1.1* ]]
  vbw_run next --json
  echo "$output" | jq -e '.action == "build"'
}

@test "an express phase has exactly one plan; a higher tier may have several" {
  rigor_project 2
  local doc
  doc=$(rigor_doc 2 "" src/a.txt | jq -c '.plans[0].reqs = ["R1"] | .plans += [{id: "P1.2", phase: "P1", title: "More", reqs: ["R2"], files: ["src/b.txt"], after: []}]')
  cp .vbw/record.json "$TEST_ROOT/before.json"
  run rigor_apply "$doc"
  [ "$status" -ne 0 ]
  [[ "$output" == *express* ]]
  [[ "$output" == *"one plan"* ]]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
  run rigor_apply "$(printf '%s' "$doc" | jq -c '.phases[0].tier = "standard"')"
  [ "$status" -eq 0 ]
}

@test "an express phase is built by one Dev" {
  rigor_flow_setup
  vbw_run next --json
  echo "$output" | jq -e '.rigor.P1.tier == "express" and .rigor.P1.agents.dev == 1'
}

@test "an express phase with only [auto] requirements is not sent to QA once proven" {
  rigor_flow_setup
  rigor_flow_build
  vbw_run next --json
  echo "$output" | jq -e '.action == "ship"'
}

@test "an express phase with a [human] requirement runs QA, at the express QA tier" {
  rigor_flow_setup human
  rigor_flow_build
  vbw_run next --json
  echo "$output" | jq -e '.action == "qa" and .detail.phases == ["P1"] and .detail.tier == "quick"'
}

@test "an express phase that has escalated runs QA" {
  rigor_flow_setup
  rigor_flow_build
  edit_record '.phases[0].escalations = [{at: "2026-10-03T10:00:00Z", from: "express", to: "standard", reason: "Dev blocked P1.1: stuck"}]'
  vbw_run next --json
  echo "$output" | jq -e '.action == "qa" and .detail.phases == ["P1"]'
}

@test "a standard phase still goes to QA after its proof, as before" {
  rigor_flow_setup
  "$VBW" config rigor standard > /dev/null
  rigor_flow_build
  vbw_run next --json
  echo "$output" | jq -e '.action == "qa" and .detail.tier == "standard"'
}
