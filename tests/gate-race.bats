#!/usr/bin/env bats
# R69 (2026-10-06, found by the Linux suite): the check gate's lock is never
# taken from a live owner. A waiting check that finds the lock's owner file
# empty (it was read while the owner released the lock and a new owner had not
# yet written it) retries; it does not treat the owner as dead and remove the
# lock, which deleted a fresh lock under a running proof ("mutex/pid: No such
# file or directory"). A lock with no owner is taken over only after a wait.
# L1: the gate on a fixture.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p tests
  printf 'true\n' > tests/ok.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/ok.sh"], files:["tests/ok.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["tests/ok.sh"], after:[], status:"done"}]
    | del(.requirements[]?.rules)' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

@test "R69: a lock whose owner file reads empty is not taken over at once: the check waits" {
  mkdir -p .vbw/runtime/gate/mutex
  : > .vbw/runtime/gate/mutex/pid
  VBW_CHECK_WAIT_SECONDS=2 run "$VBW" check C1
  [ "$status" -ne 0 ] || { echo "the check took the lock: $output"; false; }
  [[ "$output" == *"waited"* ]]
  [ -d .vbw/runtime/gate/mutex ]
}

@test "R69: a lock with no owner left for long is taken over, and the check runs" {
  mkdir -p .vbw/runtime/gate/mutex
  VBW_CHECK_WAIT_SECONDS=30 run "$VBW" check C1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"C1 pass"* ]]
}

@test "R69: the owner write never prints an error when the lock vanished under it" {
  ! grep -nE 'printf .*> "\$g/mutex/pid"$' "$PLUGIN_ROOT/lib/checks.sh"
}
