#!/usr/bin/env bats
# R98 (L1): in an autonomous run, while this session's proof or workflow is
# still running in the background, the Stop hook (vbw auto gate) does not ask
# for that step again and spends no autonomous step on it. When the background
# step ends it resumes. Another session's background proof does not suppress
# this session's hook. A slow check on a fixture stands for the proof.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p tests
  printf 'sleep 4\n' > tests/slow.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/slow.sh"], files:["tests/slow.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["tests/slow.sh"], after:[], status:"done"}]
    | del(.requirements[]?.rules)' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" auto on sessA > /dev/null
  "$VBW" auto on sessB > /dev/null
}

teardown() { vbw_teardown; }

# gate SESSION: what the Stop hook prints for that session.
gate() { jq -nc --arg s "$1" '{hook_event_name: "Stop", session_id: $s, stop_hook_active: false}' | "$VBW" auto gate; }
steps() { "$VBW" auto status "$1" < /dev/null; }

# start_proof SESSION: vbw prove in the background, as that session; waits until it runs.
start_proof() {
  VBW_SESSION_ID="$1" "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 < /dev/null 3>&- &
  PROVE_PID=$!
  sleep 1
  kill -0 "$PROVE_PID"
}

@test "R98: while this session's proof runs in the background the hook asks for nothing and spends no step" {
  start_proof sessA
  run gate sessA
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
  [[ "$(steps sessA)" == "armed: step 0 of"* ]]
  wait "$PROVE_PID"
}

@test "R98: another session's background proof does not suppress this session's hook" {
  start_proof sessA
  run gate sessB
  [ "$status" -eq 0 ]
  [ -n "$output" ] || { echo "empty"; false; }
  wait "$PROVE_PID"
}

@test "R98: once the background proof has finished the hook resumes normally" {
  start_proof sessA
  wait "$PROVE_PID"
  run gate sessA
  [ "$status" -eq 0 ]
  [ -n "$output" ] || { echo "empty"; false; }
}

@test "R98: a proof from a session that is gone leaves nothing behind that suppresses the hook" {
  VBW_SESSION_ID=sessA "$VBW" prove > /dev/null 2>&1 < /dev/null
  run gate sessA
  [ -n "$output" ] || { echo "empty"; false; }
}

@test "R98: while this session's workflow run is open the hook asks for nothing and spends no step" {
  VBW_SESSION_ID=sessA "$VBW" run start plan > /dev/null
  run gate sessA
  [ -z "$output" ]
  [[ "$(steps sessA)" == "armed: step 0 of"* ]]
}
