#!/usr/bin/env bats
# R22: after planning every phase has a rigor tier and reasons that name the
# measured signals; the approval screen shows each phase's tier and reasons on
# one line; the record holds the tier, reasons, escalations and outcome.

load helper
load rigor-helper

teardown() { vbw_teardown; }

@test "apply gives every phase a tier, its reasons and the predicted tier" {
  rigor_project 1
  run rigor_apply "$(rigor_doc 1 "" src/note.txt)"
  [ "$status" -eq 0 ]
  phase_json '.phases | all(.[]; (.tier | IN("express", "standard", "deep")) and (.reasons | type == "array") and .predicted == .tier)'
}

@test "the reasons name each measured signal, with its numbers" {
  rigor_project 2
  printf 'abcde' > src/a.txt
  printf 'abcdefg' > src/b.txt
  rigor_apply "$(rigor_doc 2 "" src/a.txt src/b.txt src/c.txt)" > /dev/null
  phase_json '.phases[0].reasons | any(.[]; . == "requirements: 2") and any(.[]; . == "files: 3 (12 bytes)")
    and any(.[]; startswith("risk: ")) and any(.[]; startswith("breaks: ")) and any(.[]; startswith("tests: "))'
}

@test "a risk path is named in the reasons, and proven requirements it could break too" {
  rigor_project 2
  rigor_second_milestone
  rigor_apply "$(PH=P2 R0=2 rigor_doc 1 "" src/old.js src/auth/login.js)" > /dev/null
  phase_json '.phases[] | select(.id == "P2") | .reasons
    | any(.[]; startswith("risk: ") and contains("src/auth/login.js")) and any(.[]; . == "breaks: R1")'
}

@test "a phase with nothing risky is a one-line express phase on the approval screen" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  vbw_run show contract
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^  P1 ')" -eq 1 ]
  line=$(printf '%s\n' "$output" | grep '^  P1 ')
  [[ "$line" == *express* ]]
  [[ "$line" == *"requirements: 1"* ]]
  [[ "$line" == *"risk: none"* ]]
}

@test "the approval line of a risky phase shows its higher tier and the risk" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/payments/charge.js)" > /dev/null
  vbw_run show contract
  line=$(printf '%s\n' "$output" | grep '^  P1 ')
  [[ "$line" == *deep* ]]
  [[ "$line" == *"src/payments/charge.js"* ]]
}

@test "the record validator accepts tier, reasons, escalations, outcome and cost, and still accepts phases without them" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  edit_record '.phases[0].escalations = [{at: "2026-10-03T10:00:00Z", from: "express", to: "standard", reason: "Dev blocked P1.1: stuck"}]
    | .phases[0].cost_usd = 0.5
    | .phases[0].outcome = {tier: "standard", predicted: "express", held: false, fix_rounds: 1, qa_findings: 0, escalations: 1, cost_usd: null}'
  vbw_run status
  [ "$status" -eq 0 ]
  edit_record '.phases[0] |= del(.tier, .reasons, .predicted, .escalations, .outcome, .cost_usd)'
  vbw_run status
  [ "$status" -eq 0 ]
}

@test "the record validator refuses a bad tier, a bad escalation and a bad outcome" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  phase_json '.phases[0].tier == "express"'
  cp .vbw/record.json "$TEST_ROOT/good.json"
  edit_record '.phases[0].tier = "huge"'
  vbw_run status
  [ "$status" -ne 0 ]
  [[ "$output" == *tier* ]]
  cp "$TEST_ROOT/good.json" .vbw/record.json
  edit_record '.phases[0].escalations = [{at: "2026-10-03T10:00:00Z", from: "express", to: "standard", reason: ""}]'
  vbw_run status
  [ "$status" -ne 0 ]
  cp "$TEST_ROOT/good.json" .vbw/record.json
  edit_record '.phases[0].outcome = {tier: "standard", predicted: "express", held: "no", fix_rounds: 1, qa_findings: 0, escalations: 1, cost_usd: null}'
  vbw_run status
  [ "$status" -ne 0 ]
}
