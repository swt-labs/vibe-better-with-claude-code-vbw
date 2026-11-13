#!/usr/bin/env bats
# R78 and R81 (docs/workflows.md): when a build, fix or QA workflow finishes it
# confirms what its agents recorded (vbw run confirm) and says plainly which
# were not; every workflow that holds a run lease (plan, build, fix, QA) ends
# its own run (vbw run end) as its last step, so no lease stays open; a map
# run is ended by its caller, with the map (#731). The
# runtime is stubbed (tests/helpers/run-workflow.js), so no model is called (L1).
# The closing agent is labelled "close run" and answers {ended, recorded, report}.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows"
DONE='{"status":"done","summary":"s","notes":[]}'

setup() { command -v node > /dev/null 2>&1 || skip "node is not installed"; }

# wf NAME ARGS RESPONSES: the stubbed run's JSON.
wf() { node "$RUN" "$WF/$1.js" "$2" "$3"; }

closer_ok='{"close run": {"ended": true, "recorded": true, "report": "all recorded; run ended"}}'

@test "R78: the build workflow confirms its plans and ends its run as its last step" {
  run wf building '{"plans":["P1.1","P1.2"],"session":"sess1"}' "$(jq -nc --argjson d "$DONE" '{"dev P1.1": $d, "dev P1.2": $d, "close run": {ended: true, recorded: true, report: "all recorded; run ended", state: ({open: false, recorded: {"P1.1": true, "P1.2": true}} | tojson)}}')"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.calls[-1].opts.label == "close run"
    and (.calls[-1].prompt | contains("vbw run confirm P1.1 P1.2") and contains("vbw run end") and contains("VBW_SESSION_ID=sess1"))
    and (.calls[-1].opts.schema.required | index("ended") != null and index("recorded") != null and index("report") != null)
    and (.result.results | length) == 2 and .result.confirmation.recorded == true' || { echo "$output"; false; }
}

@test "R78: a plan whose Dev recorded nothing is named in the output" {
  run wf building '{"plans":["P1.1","P1.2"],"session":"sess1"}' "$(jq -nc --argjson d "$DONE" '{"dev P1.1": $d, "close run": {ended: true, recorded: false, report: "P1.2 not recorded: still building"}}')"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.result.confirmation.recorded == false and (.logs | any(contains("P1.2 not recorded")))' || { echo "$output"; false; }
}

@test "R78: when everything was recorded, nothing is reported as missing" {
  run wf building '{"plans":["P1.1"],"session":"s"}' "$(jq -nc --argjson d "$DONE" '{"dev P1.1": $d, "close run": {ended: true, recorded: true, report: "all recorded", state: ({open: false, recorded: {"P1.1": true}} | tojson)}}')"
  printf '%s' "$output" | jq -e '(.logs | any(contains("not recorded")) | not)' || { echo "$output"; false; }
}

@test "R78: the fix workflow confirms every fix of every group" {
  run wf fixing '{"groups":[["F1","F2"],["F3"]],"session":"s"}' "$(jq -nc --argjson d "$DONE" '{"F1+F2": $d, "F3": $d, "close run": {ended: true, recorded: false, report: "F3 not recorded: still open"}}')"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.calls[-1].opts.label == "close run" and (.calls[-1].prompt | contains("vbw run confirm F1 F2 F3") and contains("vbw run end"))
    and (.logs | any(contains("F3 not recorded")))' || { echo "$output"; false; }
}

@test "R78: the QA workflow confirms every phase verdict" {
  run wf verifying '{"phases":["P1","P2"],"tier":"standard","session":"s"}' '{"qa P1": {"verdict":"pass","checks":[]}, "qa P2": {"verdict":"pass","checks":[]}, "close run": {"ended": true, "recorded": false, "report": "P2 not recorded: no verdict"}}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.calls[-1].opts.label == "close run" and (.calls[-1].prompt | contains("vbw run confirm P1 P2") and contains("vbw run end"))
    and (.logs | any(contains("P2 not recorded")))' || { echo "$output"; false; }
}

@test "R81: if the closing agent dies, the workflow still returns its results and says to end the run by hand" {
  run wf building '{"plans":["P1.1"],"session":"s"}' "$(jq -nc --argjson d "$DONE" '{"dev P1.1": $d, "close run": null}')"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '(.result.results | length) == 1 and (.logs | any(contains("vbw run end")))' || { echo "$output"; false; }
}

@test "R81: the planning workflow ends its own run on every way out: decisions, planned and blocked" {
  local reqs='[{"id":"R1","proof":"auto","text":"x"}]' d
  d='{"decisions":[{"question":"q","why_it_matters":"w","options":[{"label":"a","tradeoff":"t"},{"label":"b","tradeoff":"t"}],"recommended":"a"}]}'
  run wf planning "$(jq -nc --argjson r "$reqs" '{requirements: $r, session: "s"}')" "$(jq -nc --argjson d "$d" '{"architect (decide)": $d, "close run": {ended: true, recorded: true, report: "run ended"}}')"
  printf '%s' "$output" | jq -e '.result.status == "needs_decisions" and .calls[-1].opts.label == "close run" and (.calls[-1].prompt | contains("vbw run end"))' || { echo "$output"; false; }
  local scope='{"phases":[{"id":"P1","title":"t","reqs":["R1"],"goal":"g","criteria":["c"]}],"notes":[]}'
  run wf planning "$(jq -nc --argjson r "$reqs" '{requirements: $r, decided: true, session: "s"}')" "$(jq -nc --argjson s "$scope" '{"architect (scope)": $s, "lead": {applied: true, summary: "s", blockers: [], choices: []}, "close run": {ended: true, recorded: true, report: "run ended"}}')"
  printf '%s' "$output" | jq -e '.result.status == "planned" and .calls[-1].opts.label == "close run" and (.calls[-1].prompt | contains("vbw run end"))' || { echo "$output"; false; }
  run wf planning "$(jq -nc --argjson r "$reqs" '{requirements: $r, decided: true, session: "s"}')" "$(jq -nc --argjson s "$scope" '{"architect (scope)": $s, "lead": {applied: false, summary: "no", blockers: ["b"], choices: []}, "close run": {ended: true, recorded: true, report: "run ended"}}')"
  printf '%s' "$output" | jq -e '.result.status == "blocked" and .calls[-1].opts.label == "close run"' || { echo "$output"; false; }
}

# #731: the map run's record commit must hold the map, and only the session has
# it once the workflow returns: the mapping workflow never ends its run, and
# both callers end it with the map (vbw run end --map), so the kernel writes the
# map before it commits.
@test "#731: the mapping workflow never ends its run, even with the session; it returns the map" {
  run node "$BATS_TEST_DIRNAME/helpers/run-workflow-all.js" "$WF/mapping.js" '{"session":"s"}' '{"*":{"findings":["a"],"map":"the map","refused":[]}}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.result.map == "the map" and all(.calls[]; .opts.label != "close run" and (.prompt | contains("run end") | not))' || { echo "$output"; false; }
}

@test "#731: /vbw:map and the router end the map run with the map, never write .vbw/map.md themselves" {
  local f
  for f in "$PLUGIN_ROOT/skills/map/SKILL.md" "$PLUGIN_ROOT/skills/vibe/SKILL.md"; do
    grep -qF "jq -er '.result.map' FILE | VBW_SESSION_ID=\${CLAUDE_SESSION_ID} vbw run end --map" "$f" || { echo "$f"; false; }
    ! grep -qF '> .vbw/map.md' "$f" || { echo "$f"; false; }
  done
}

@test "R81: the router hands every workflow the session and no longer ends the run after it, but still ends an interrupted one" {
  local r="$PLUGIN_ROOT/skills/vibe/SKILL.md"
  [ "$(grep -c 'vbw run end' "$r")" -le 4 ]
  grep -q 'vbw run end --owner-closed' "$r"
  grep -q '`session`' "$r"
}

@test "R81: without the session in its args a workflow runs as before and starts no closing agent" {
  run wf building '{"plans":["P1.1"]}' "$(jq -nc --argjson d "$DONE" '{"dev P1.1": $d}')"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '(.calls | length) == 1 and (.calls | all(.opts.label != "close run"))' || { echo "$output"; false; }
}
