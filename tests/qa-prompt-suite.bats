#!/usr/bin/env bats
# R131 (L1): every QA agent is told the project's test command and how its
# output ended, in plain words. When the round's suite ran, the QA prompt names
# the command and includes the end of its output; when a piece is missing (the
# command, the output, the exit code, the time) the prompt says so in plain
# words; no prompt built from any mix of missing and present pieces contains
# "undefined" or "null". With no suite, or a suite that did not run, the
# prompt keeps its instructions (no test command; do not retry). vbw next
# hands over the project's own test command with the proof's result. The
# workflow runs under node with stubbed agents (tests/helpers/run-workflow.js).

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows/verifying.js"
FULL='{"command":"bash tools/test.sh","status":"pass","exit":0,"seconds":7,"tail":"all 9 tests ok"}'

teardown() { [ -z "${TEST_ROOT:-}" ] || vbw_teardown; }

# prompt SUITE: the QA prompt for phase P1 when the round carries SUITE (JSON, or "none").
prompt() {
  command -v node > /dev/null || skip "node is not installed"
  local args out
  if [ "$1" = none ]; then
    args='{"phases":["P1"],"tier":"standard","round":{"suite":null}}'
  else
    args=$(jq -nc --argjson s "$1" '{phases: ["P1"], tier: "standard", round: {suite: $s}}')
  fi
  out=$(node "$RUN" "$WF" "$args" '{}') || { echo "$out"; return 1; }
  printf '%s' "$out" | jq -r '[.calls[] | select(.opts.label == "qa P1")][0].prompt // error("no QA agent for P1")'
}

# without FIELDS...: $FULL with each named field removed.
without() { jq -nc --argjson s "$FULL" '$ARGS.positional as $f | $s | with_entries(select(.key as $k | $f | index($k) | not))' --args "$@"; }

@test "R131: when the suite ran, the QA prompt names the test command, its result and the end of its output" {
  local p
  p=$(prompt "$FULL")
  [[ "$p" == *"bash tools/test.sh"* ]] || { echo "$p"; false; }
  [[ "$p" == *"all 9 tests ok"* ]] || { echo "$p"; false; }
  [[ "$p" == *"pass"* && "$p" == *"exit 0"* && "$p" == *"7s"* ]] || { echo "$p"; false; }
  [[ "$p" == *"Do not run the project's test command"* ]] || { echo "$p"; false; }
}

@test "R131: each missing piece of a suite that ran is named in plain words instead of a value" {
  local p
  p=$(prompt "$(without command)")
  printf '%s' "$p" | grep -qi 'test command was not named' || { echo "$p"; false; }
  [[ "$p" == *"all 9 tests ok"* ]] || { echo "$p"; false; }
  p=$(prompt "$(without tail)")
  printf '%s' "$p" | grep -qi 'output was not kept' || { echo "$p"; false; }
  [[ "$p" == *"bash tools/test.sh"* ]] || { echo "$p"; false; }
  p=$(prompt "$(without exit)")
  printf '%s' "$p" | grep -qi 'exit code was not kept' || { echo "$p"; false; }
  p=$(prompt "$(without seconds)")
  printf '%s' "$p" | grep -qi 'time was not kept' || { echo "$p"; false; }
  # A null or empty value is missing too.
  p=$(prompt "$(jq -nc --argjson s "$FULL" '$s + {exit: null, command: "", tail: ""}')")
  printf '%s' "$p" | grep -qi 'exit code was not kept' || { echo "$p"; false; }
  printf '%s' "$p" | grep -qi 'test command was not named' || { echo "$p"; false; }
  printf '%s' "$p" | grep -qi 'output was not kept' || { echo "$p"; false; }
}

@test "R131: no QA prompt from any mix of missing or present suite fields contains undefined or null" {
  local status mask s p fields f i
  fields=(command exit seconds tail)
  for status in pass fail skipped "not run" absent; do
    for ((mask = 0; mask < 16; mask++)); do
      s=$(jq -nc --argjson s "$FULL" --arg st "$status" '$s | if $st == "absent" then del(.status) else .status = $st end')
      for ((i = 0; i < 4; i++)); do
        f=${fields[$i]}
        if (((mask >> i) & 1)); then s=$(jq -nc --argjson s "$s" --arg f "$f" '$s | del(.[$f])'); fi
      done
      p=$(prompt "$s") || { echo "$p"; false; }
      if printf '%s' "$p" | grep -qE 'undefined|null'; then
        echo "suite $s gives: $p"
        false
      fi
    done
  done
  # Null values, as a proof writes for a command that was not approved.
  p=$(prompt '{"command":null,"status":"pass","exit":null,"seconds":null,"tail":null}')
  ! printf '%s' "$p" | grep -qE 'undefined|null' || { echo "$p"; false; }
}

@test "R131: with no suite, or a suite that did not run, the prompt keeps its instructions" {
  local p
  p=$(prompt none)
  printf '%s' "$p" | grep -q 'no test command' || { echo "$p"; false; }
  ! printf '%s' "$p" | grep -qE 'undefined|null' || { echo "$p"; false; }
  p=$(prompt '{"command":"bash tools/test.sh","status":"skipped","exit":null,"seconds":0,"tail":"not approved"}')
  printf '%s' "$p" | grep -q 'did not run' || { echo "$p"; false; }
  printf '%s' "$p" | grep -q 'Do not retry' || { echo "$p"; false; }
  ! printf '%s' "$p" | grep -qE 'undefined|null' || { echo "$p"; false; }
  p=$(prompt '{"status":"not run"}')
  printf '%s' "$p" | grep -q 'did not run' || { echo "$p"; false; }
  ! printf '%s' "$p" | grep -qE 'undefined|null' || { echo "$p"; false; }
}

@test "R131: at the qa step, vbw next hands over the project's own test command with the proof's result" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  # A built, proven phase whose QA verdict is on other code; the proof's result has no command name.
  jq '.requirements = [{id:"R1", text:"Pay", proof:"auto", status:"proven", milestone: "M1"}]
      | .checks = [{id:"C1", req:"R1", run:["true"]}]
      | .commands = {test: ["sh", "t.sh"]}
      | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone: "M1"}]
      | .plans = [{id:"P1.1", phase:"P1", title:"Form", reqs:["R1"], files:["a.js"], after:[], status:"done"}]
      | .phases[0].qa = {result: "pass", tier: "standard", tree: ("e" * 40), at: "2026-10-01T09:00:00Z"}' .vbw/record.json > "$TEST_ROOT/e.json"
  cp "$TEST_ROOT/e.json" .vbw/record.json
  local hash tree out
  hash=$(vbw_contract_hash)
  tree=$(vbw_kernel 'vbw_code_tree')
  jq --arg h "$hash" --arg t "$tree" '.evidence = {at: "2026-10-01T09:00:00Z", contract: $h, tree: $t, passed: true, checks: {},
      commands: {test: {status: "pass", exit: 0, seconds: 7, tail: "all 9 tests ok"}}, scope: []}' .vbw/record.json > "$TEST_ROOT/n.json"
  cp "$TEST_ROOT/n.json" .vbw/record.json
  vbw_consent_contract
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/cmd-approve.sh"; approve_commands "$(cat "$VBW_RECORD")" > /dev/null'
  out=$("$VBW" next --json < /dev/null)
  printf '%s' "$out" | jq -e '.action == "qa" and .round.suite.command == "sh t.sh" and .round.suite.tail == "all 9 tests ok"' || { echo "$out"; false; }
}
