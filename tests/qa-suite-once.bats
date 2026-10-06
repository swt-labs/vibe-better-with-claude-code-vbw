#!/usr/bin/env bats
# R70 (docs/proof.md, docs/workflows.md): a QA round runs the project's test
# command once and hands its result to every QA agent of that round; the agents
# do not run the whole suite again, and if the one run did not start the round
# says so instead of each agent retrying. The one run is the proof's: vbw next
# --json carries it as round.suite at the qa step, the router passes it as
# args.round, and the QA workflow puts it in every QA prompt. L1, with stubbed
# agents (tests/helpers/run-workflow.js).

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
SUITE='{"command":"test","status":"pass","exit":0,"seconds":7,"tail":"all 9 tests ok"}'
SKIPPED='{"command":"test","status":"skipped","exit":null,"seconds":0,"tail":"not approved"}'

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

# qa_step FILTER EVIDENCE_COMMANDS: a built, proven phase whose QA verdict is on
# other code, so QA is next; FILTER edits the record first, EVIDENCE_COMMANDS
# replaces evidence.commands. Prints vbw next --json.
qa_step() {
  jq '.requirements = [{id:"R1", text:"Pay", proof:"auto", status:"proven", milestone: "M1"}]
      | .checks = [{id:"C1", req:"R1", run:["true"]}]
      | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone: "M1"}]
      | .plans = [{id:"P1.1", phase:"P1", title:"Form", reqs:["R1"], files:["a.js"], after:[], status:"done"}]
      | .phases[0].qa = {result: "pass", tier: "standard", tree: ("e" * 40), at: "2026-10-01T09:00:00Z"}' .vbw/record.json > "$TEST_ROOT/e.json"
  jq "$1" "$TEST_ROOT/e.json" > .vbw/record.json
  local hash tree
  hash=$(vbw_contract_hash)
  tree=$(vbw_code_tree)
  jq --arg h "$hash" --arg t "$tree" --argjson c "$2" '.evidence = {at: "2026-10-01T09:00:00Z", contract: $h, tree: $t, passed: true, checks: {}, commands: $c, scope: []}' \
    .vbw/record.json > "$TEST_ROOT/n.json" && cp "$TEST_ROOT/n.json" .vbw/record.json
  vbw_consent_contract
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/cmd-approve.sh"; approve_commands "$(cat "$VBW_RECORD")" > /dev/null'
  "$VBW" next --json < /dev/null
}

@test "R70: at the qa step, vbw next carries the proof's one run of the test command; the step's detail is unchanged" {
  run qa_step '.commands = {test: ["sh","t.sh"]}' "{\"test\": $SUITE}"
  echo "$output" | jq -e '.action == "qa" and .detail == {phases: ["P1"], tier: "standard"}' || { echo "$output"; false; }
  echo "$output" | jq -e --argjson s "$SUITE" '.round.suite == $s' || { echo "$output"; false; }
}

@test "R70: a project with no test command has no suite to hand over" {
  run qa_step '.' '{}'
  echo "$output" | jq -e '.action == "qa" and .round.suite == null' || { echo "$output"; false; }
}

@test "R70: a test command that did not run in the proof is handed over as not run or skipped, never as passing" {
  run qa_step '.commands = {test: ["sh","t.sh"]}' "{\"test\": $SKIPPED}"
  echo "$output" | jq -e '.round.suite.status == "skipped"' || { echo "$output"; false; }
  run qa_step '.commands = {test: ["sh","t.sh"]}' '{}'
  echo "$output" | jq -e '.round.suite.status == "not run" and .round.suite.command == "test"' || { echo "$output"; false; }
}

@test "R70: every QA agent of the round is given the one result and told not to run the suite" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  run node "$RUN" "$PLUGIN_ROOT/workflows/verifying.js" "{\"phases\":[\"P1\",\"P2\",\"P3\"],\"tier\":\"standard\",\"round\":{\"suite\":$SUITE}}" '{}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.calls[] | select(.opts.label | test("^qa P"))] as $qa
    | ($qa | length) == 3 and all($qa[]; .prompt | contains("all 9 tests ok") and contains("Do not run the project'"'"'s test command"))' || { echo "$output"; false; }
}

@test "R70: no agent is started to run the suite: only the QA agents (and the run's closing step)" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  run node "$RUN" "$PLUGIN_ROOT/workflows/verifying.js" "{\"phases\":[\"P1\",\"P2\"],\"tier\":\"standard\",\"round\":{\"suite\":$SUITE}}" '{}'
  printf '%s' "$output" | jq -e 'all(.calls[]; (.opts.label | test("^qa P[0-9]+$")) or .opts.label == "close run")' || { echo "$output"; false; }
}

@test "R70: when the one run did not start, the round says so once and no agent is told to retry" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  run node "$RUN" "$PLUGIN_ROOT/workflows/verifying.js" "{\"phases\":[\"P1\",\"P2\"],\"tier\":\"standard\",\"round\":{\"suite\":$SKIPPED}}" '{}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.logs[] | select(contains("did not run"))] | length == 1' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.calls[] | select(.opts.label | test("^qa P"))] | all(.[]; .prompt | contains("did not run") and contains("Do not retry") and (contains("all 9 tests ok") | not))' || { echo "$output"; false; }
}

@test "R70: a suite that ran and failed is handed over as failed, and is not a reason to run it again" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  run node "$RUN" "$PLUGIN_ROOT/workflows/verifying.js" '{"phases":["P1"],"tier":"standard","round":{"suite":{"command":"test","status":"fail","exit":1,"seconds":3,"tail":"2 tests failed"}}}' '{}'
  printf '%s' "$output" | jq -e '(.calls[0].prompt | contains("2 tests failed") and contains("Do not run the project'"'"'s test command")) and (.logs | any(contains("did not run")) | not)' || { echo "$output"; false; }
}

@test "R70: without a round the QA workflow still works, and the QA agent and the router say the same" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  run node "$RUN" "$PLUGIN_ROOT/workflows/verifying.js" '{"phases":["P1"],"tier":"standard"}' '{}'
  [ "$status" -eq 0 ]
  grep -q "Do not run the project's test command" "$PLUGIN_ROOT/agents/qa.md"
  grep -q '"round"' "$PLUGIN_ROOT/skills/vibe/SKILL.md"
}
