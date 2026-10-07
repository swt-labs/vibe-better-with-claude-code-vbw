#!/usr/bin/env bats
# R95 and R96 (docs/workflows.md, workflow part, L1): the build, fix, QA,
# planning and mapping workflows close with an agent whose own instructions
# allow it (the Lead), a workflow reports complete only when every result was
# recorded, an unrecorded result is named, a closing agent that stops leaves
# the exact commands to run by hand, and QA is always told the project's test
# command. The runtime is stubbed (tests/helpers/run-workflow.js): no model runs.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows"
DONE='{"status":"done","summary":"s","notes":[]}'
PASS='{"verdict":"pass","checks":[]}'
OK='{"ended":true,"recorded":true,"report":"all recorded; run ended"}'

setup() { command -v node > /dev/null 2>&1 || skip "node is not installed"; }

# wf NAME ARGS RESPONSES: the stubbed run's JSON.
wf() { node "$RUN" "$WF/$1.js" "$2" "$3"; }

@test "R95: QA is told the project's test command and its result when it ran" {
  local round='{"suite":{"command":"bash tools/test.sh","status":"pass","exit":0,"seconds":3,"tail":"ok"},"tiers":{}}'
  run wf verifying "$(jq -nc --argjson r "$round" '{phases:["P1"], round: $r}')" "{\"qa P1\": $PASS}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.calls[0].prompt | contains("bash tools/test.sh")' || { echo "$output"; false; }
}

@test "R95: when the project has no test command, QA is told so plainly instead of being left to guess" {
  run wf verifying '{"phases":["P1"],"tier":"standard"}' "{\"qa P1\": $PASS}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.calls[0].prompt | test("no test command"; "i")' || { echo "$output"; false; }
}

@test "R95: a workflow whose agents all recorded reports complete: build, fix and QA" {
  run wf building '{"plans":["P1.1"],"session":"s"}' "$(jq -nc --argjson d "$DONE" --argjson k "$OK" '{"dev P1.1": $d, "close run": $k}')"
  printf '%s' "$output" | jq -e '.result.complete == true' || { echo "$output"; false; }
  run wf fixing '{"groups":[["F1"]],"session":"s"}' "$(jq -nc --argjson d "$DONE" --argjson k "$OK" '{"F1": $d, "close run": $k}')"
  printf '%s' "$output" | jq -e '.result.complete == true' || { echo "$output"; false; }
  run wf verifying '{"phases":["P1"],"session":"s"}' "$(jq -nc --argjson d "$PASS" --argjson k "$OK" '{"qa P1": $d, "close run": $k}')"
  printf '%s' "$output" | jq -e '.result.complete == true' || { echo "$output"; false; }
}

@test "R95: a workflow with an unrecorded result is not reported as complete, and the closing report names it" {
  local bad='{"ended":true,"recorded":false,"report":"P1.2 not recorded: still building"}'
  run wf building '{"plans":["P1.1","P1.2"],"session":"s"}' "$(jq -nc --argjson d "$DONE" --argjson k "$bad" '{"dev P1.1": $d, "dev P1.2": $d, "close run": $k}')"
  printf '%s' "$output" | jq -e '.result.complete == false and (.result.confirmation.report | contains("P1.2"))' || { echo "$output"; false; }
  run wf fixing '{"groups":[["F1"]],"session":"s"}' "$(jq -nc --argjson d "$DONE" '{"F1": $d, "close run": {ended: true, recorded: false, report: "F1 not recorded: still open"}}')"
  printf '%s' "$output" | jq -e '.result.complete == false' || { echo "$output"; false; }
  run wf verifying '{"phases":["P1"],"session":"s"}' "$(jq -nc --argjson d "$PASS" '{"qa P1": $d, "close run": {ended: true, recorded: false, report: "P1 not recorded: no verdict"}}')"
  printf '%s' "$output" | jq -e '.result.complete == false' || { echo "$output"; false; }
}

@test "R95: an agent that stopped before reporting makes the workflow incomplete, even when the closing agent finds nothing else missing" {
  run wf building '{"plans":["P1.1","P1.2"],"session":"s"}' "$(jq -nc --argjson d "$DONE" --argjson k "$OK" '{"dev P1.1": $d, "close run": $k}')"
  printf '%s' "$output" | jq -e '.result.complete == false' || { echo "$output"; false; }
  run wf verifying '{"phases":["P1","P2"],"session":"s"}' "$(jq -nc --argjson d "$PASS" --argjson k "$OK" '{"qa P1": $d, "close run": $k}')"
  printf '%s' "$output" | jq -e '.result.complete == false' || { echo "$output"; false; }
}

@test "R96: every workflow that closes a run does it with the Lead, not the Scout" {
  local w
  for w in building fixing verifying; do
    run wf "$w" '{"plans":["P1.1"],"groups":[["F1"]],"phases":["P1"],"session":"s"}' '{}'
    [ "$status" -eq 0 ] || { echo "$w: $output"; false; }
    printf '%s' "$output" | jq -e '.calls[-1].opts.label == "close run" and .calls[-1].opts.agentType == "vbw:lead"' || { echo "$w: $output"; false; }
  done
  local reqs='[{"id":"R1","proof":"auto","text":"x"}]'
  run wf planning "$(jq -nc --argjson r "$reqs" '{requirements: $r, session: "s"}')" '{"architect (decide)": {"decisions": []}, "architect (scope)": {"phases":[{"id":"P1","title":"t","reqs":["R1"],"goal":"g","criteria":["c"]}],"notes":[]}, "lead": {"applied": true, "summary": "s", "blockers": []}}'
  printf '%s' "$output" | jq -e '.calls[-1].opts.label == "close run" and .calls[-1].opts.agentType == "vbw:lead"' || { echo "$output"; false; }
  # The mapping workflow needs the runtime's parallel(), which the stub lacks: read its closing step.
  sed -n '/^const closeRun/,/^}/p' "$WF/mapping.js" | grep -q "agentType: 'vbw:lead'"
  ! sed -n '/^const closeRun/,/^}/p' "$WF/mapping.js" | grep -q "vbw:scout"
}

@test "R96: when the closing agent stops, the output names the exact commands to run by hand, with the session" {
  run wf building '{"plans":["P1.1","P1.2"],"session":"sess1"}' "$(jq -nc --argjson d "$DONE" '{"dev P1.1": $d, "dev P1.2": $d, "close run": null}')"
  printf '%s' "$output" | jq -e '(.logs | join("\n")) as $l
    | ($l | contains("VBW_SESSION_ID=sess1 vbw run confirm P1.1 P1.2")) and ($l | contains("VBW_SESSION_ID=sess1 vbw run end"))
    and .result.complete == false' || { echo "$output"; false; }
  run wf fixing '{"groups":[["F1","F2"]],"session":"sess1"}' "$(jq -nc --argjson d "$DONE" '{"F1+F2": $d, "close run": null}')"
  printf '%s' "$output" | jq -e '(.logs | join("\n")) | contains("VBW_SESSION_ID=sess1 vbw run confirm F1 F2") and contains("VBW_SESSION_ID=sess1 vbw run end")' || { echo "$output"; false; }
  run wf verifying '{"phases":["P1"],"session":"sess1"}' "$(jq -nc --argjson d "$PASS" '{"qa P1": $d, "close run": null}')"
  printf '%s' "$output" | jq -e '(.logs | join("\n")) | contains("VBW_SESSION_ID=sess1 vbw run confirm P1") and contains("VBW_SESSION_ID=sess1 vbw run end")' || { echo "$output"; false; }
}

@test "R96: when the run could not be ended, the output names the end command to run by hand" {
  run wf building '{"plans":["P1.1"],"session":"sess1"}' "$(jq -nc --argjson d "$DONE" '{"dev P1.1": $d, "close run": {ended: false, recorded: true, report: "run end refused"}}')"
  printf '%s' "$output" | jq -e '(.logs | join("\n")) | contains("VBW_SESSION_ID=sess1 vbw run end")' || { echo "$output"; false; }
}

@test "R96: the planning workflow confirms each planned phase and does not report planned when one has no plans" {
  local reqs='[{"id":"R1","proof":"auto","text":"x"}]' scope
  scope='{"phases":[{"id":"P1","title":"t","reqs":["R1"],"goal":"g","criteria":["c"]}],"notes":[]}'
  run wf planning "$(jq -nc --argjson r "$reqs" '{requirements: $r, decided: true, session: "s"}')" "$(jq -nc --argjson s "$scope" '{"architect (scope)": $s, "lead": {applied: true, summary: "s", blockers: []}, "close run": {ended: true, recorded: false, report: "P1 has no plans recorded"}}')"
  printf '%s' "$output" | jq -e '(.calls[-1].prompt | contains("vbw show phase P1") and contains("vbw run end"))
    and .result.status == "blocked" and (.result.summary | contains("P1 has no plans recorded"))' || { echo "$output"; false; }
  run wf planning "$(jq -nc --argjson r "$reqs" '{requirements: $r, decided: true, session: "s"}')" "$(jq -nc --argjson s "$scope" --argjson k "$OK" '{"architect (scope)": $s, "lead": {applied: true, summary: "s", blockers: []}, "close run": $k}')"
  printf '%s' "$output" | jq -e '.result.status == "planned"' || { echo "$output"; false; }
}
