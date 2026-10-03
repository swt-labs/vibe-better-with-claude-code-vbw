#!/usr/bin/env bats
# R25: while a phase runs, VBW raises its tier on its own and records and shows
# why; it never lowers a tier during a run. Later steps use the raised tier's
# agents, QA tier and models.

load helper
load rigor-helper

teardown() { vbw_teardown; }

last_escalation() { jq -r '.phases[0].escalations[-1] | "\(.from)>\(.to): \(.reason)"' .vbw/record.json; }

@test "a Dev block raises the tier and records the reason" {
  rigor_flow_setup
  rigor_flow_approve
  "$VBW" plan block P1.1 "needs the API key" > /dev/null
  phase_json '.phases[0] | .tier == "standard" and .predicted == "express" and (.escalations | length) == 1
    and (.escalations[0] | .from == "express" and .to == "standard" and (.reason | contains("P1.1") and contains("needs the API key")))'
}

@test "a standard phase is raised to deep, and a deep phase records the event and stays deep" {
  rigor_flow_setup
  "$VBW" config rigor standard > /dev/null
  rigor_flow_approve
  "$VBW" plan block P1.1 "first" > /dev/null
  phase_json '.phases[0].tier == "deep"'
  "$VBW" plan reset P1.1 > /dev/null
  "$VBW" plan block P1.1 "second" > /dev/null
  phase_json '.phases[0].tier == "deep" and (.phases[0].escalations | length) == 2'
}

@test "a fix that needs a second round raises the tier, a first failure does not" {
  rigor_flow_setup
  rigor_flow_approve
  printf 'wrong\n' > src/greet.txt
  "$VBW" commit P1.1 "feat(greet): wrong" > /dev/null
  edit_record '.plans[0].status = "done"'
  "$VBW" prove > /dev/null || true
  phase_json '.fixes[0].status == "open" and .phases[0].tier == "express"'
  edit_record '.fixes[0].status = "fixed"'
  "$VBW" prove > /dev/null || true
  phase_json '.fixes[0].attempts == 1 and .phases[0].tier == "standard" and (.phases[0].escalations[-1].reason | contains("F1") and contains("second round"))'
}

@test "QA finding a problem in an express phase raises it; in a standard phase it does not" {
  rigor_flow_setup
  rigor_flow_build
  "$VBW" qa finding R1 "the greeting is missing" > /dev/null
  phase_json '.phases[0].tier == "standard" and (.phases[0].escalations[-1].reason | contains("QA") and contains("R1"))'
  vbw_teardown
  rigor_flow_setup
  "$VBW" config rigor standard > /dev/null
  rigor_flow_build
  "$VBW" qa finding R1 "the greeting is missing" > /dev/null
  phase_json '.phases[0].tier == "standard" and ((.phases[0].escalations // []) | length) == 0'
}

@test "QA failing a phase a second time raises the tier" {
  rigor_flow_setup
  "$VBW" config rigor standard > /dev/null
  rigor_flow_build
  "$VBW" qa finding R1 "a" > /dev/null
  "$VBW" qa record P1 fail standard > /dev/null
  phase_json '.phases[0].tier == "standard"'
  "$VBW" qa finding R1 "b" > /dev/null
  "$VBW" qa record P1 fail standard > /dev/null
  phase_json '.phases[0].tier == "deep" and (.phases[0].escalations[-1].reason | contains("second round"))'
}

@test "a commit that touches a risk path raises the phase to deep" {
  rigor_project 1
  printf '%s' '{"phases":[{"id":"P1","title":"Notes","reqs":["R1"],"goal":"Notes","criteria":["x"]}],
    "plans":[{"id":"P1.1","phase":"P1","title":"Notes","reqs":["R1"],"files":["src/"],"after":[]}],"checks":[]}' | "$VBW" apply > /dev/null
  jq -e '.phases[0].tier == "express"' .vbw/record.json
  "$VBW" approve > /dev/null || true
  mkdir -p src/auth
  printf 'x\n' > src/auth/login.js
  "$VBW" commit P1.1 "feat(auth): add" > /dev/null
  phase_json '.phases[0].tier == "deep" and (.phases[0].escalations[-1].reason | contains("risk") and contains("src/auth/login.js"))'
}

@test "a commit that grows well beyond its plan raises the tier one step; a small commit does not" {
  rigor_project 1
  printf '%s' '{"phases":[{"id":"P1","title":"Notes","reqs":["R1"],"goal":"Notes","criteria":["x"]}],
    "plans":[{"id":"P1.1","phase":"P1","title":"Notes","reqs":["R1"],"files":["src/"],"after":[]}],"checks":[]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null || true
  printf 'x\n' > src/a1.txt
  "$VBW" commit P1.1 "feat(notes): one" > /dev/null
  phase_json '.phases[0].tier == "express"'
  printf 'x\n' > src/a2.txt; printf 'x\n' > src/a3.txt; printf 'x\n' > src/a4.txt; printf 'x\n' > src/a5.txt
  "$VBW" commit P1.1 "feat(notes): many" > /dev/null
  phase_json '.phases[0].tier == "standard" and (.phases[0].escalations[-1].reason | contains("beyond"))'
}

@test "a proven requirement that fails raises the tier" {
  rigor_flow_setup
  rigor_flow_build
  jq -e '.requirements[0].status == "proven"' .vbw/record.json
  printf 'broken\n' > src/greet.txt
  "$VBW" prove > /dev/null || true
  phase_json '.phases[0].tier == "standard" and (.phases[0].escalations[-1].reason | contains("R1") and contains("proven"))'
}

@test "vbw tier raise raises, records the reason, and refuses to lower or repeat" {
  rigor_flow_setup
  vbw_run tier raise P1 standard "the user asked for more care"
  [ "$status" -eq 0 ]
  [ "$(last_escalation)" = "express>standard: the user asked for more care" ]
  vbw_run tier raise P1 express "lower"
  [ "$status" -ne 0 ]
  [[ "$output" == *"never lowered"* ]]
  vbw_run tier raise P1 standard "again"
  [ "$status" -ne 0 ]
  vbw_run tier raise P1 huge "x"
  [ "$status" -ne 0 ]
  vbw_run tier raise P9 deep "x"
  [ "$status" -ne 0 ]
  phase_json '.phases[0].tier == "standard" and (.phases[0].escalations | length) == 1'
}

@test "nothing lowers a raised tier: planning again and changing the mode keep it" {
  rigor_flow_setup
  "$VBW" tier raise P1 deep "the user asked for more care" > /dev/null
  rigor_flow_doc | "$VBW" apply > /dev/null
  phase_json '.phases[0].tier == "deep" and .phases[0].predicted == "express" and (.phases[0].escalations | length) == 1'
  "$VBW" config rigor express > /dev/null
  phase_json '.phases[0].tier == "deep"'
  "$VBW" config rigor auto > /dev/null
  phase_json '.phases[0].tier == "deep"'
}

@test "after a raise, the later steps use the raised tier's agents, QA tier and models" {
  rigor_flow_setup
  rigor_flow_approve
  "$VBW" tier raise P1 standard "Dev blocked a sibling" > /dev/null
  rigor_flow_work
  vbw_run next --json
  printf '%s' "$output" | jq -e --slurpfile c "$BATS_TEST_DIRNAME/../plugin/lib/tiers.json" \
    '.action == "qa" and .rigor.P1 == ({tier: "standard"} + $c[0].balanced.standard) and .detail.tier == $c[0].balanced.standard.qa'
}

@test "vbw show phase shows the tier, the reason it was raised and the tier it started at" {
  rigor_flow_setup
  rigor_flow_approve
  "$VBW" plan block P1.1 "needs the API key" > /dev/null
  vbw_run show phase P1
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier: standard"* ]]
  [[ "$output" == *"needs the API key"* ]]
  [[ "$output" == *express* ]]
}
