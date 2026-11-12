#!/usr/bin/env bats
# R301 (T283): the Bash guard has headroom under its budget. Every Bash guard case of
# tools/bench-hooks.sh (git, npm, big, interp, a script run by name, cross-project and loop,
# on the small record, the large one and the records of 51, 500 and 2,000 checks) costs at
# most 20 ms of own CPU per call at the nominal machine's speed, and a script run by name at
# most 40 ms (the bench doubles the budget for it). The bench judges as it always does: the
# reference measured beside each case scales the budget on a slower machine, a case over its
# budget is measured once more, and a machine too busy to measure is reported, not judged.
# The default budget stays 25 ms (tests/bench-limits.bats): only the guard gets faster.
# A timed file: the release run only (tools/test.sh --release), never vbw prove.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

GUARD_CASES='guard (git|guard (npm|guard (big|guard (interp|guard (script|guard (cross-project|guard (loop'

@test "R301 timed: every Bash guard case costs at most 20 ms per call (40 ms for a script run by name) at every record size" {
  run env VBW_HOOK_BUDGET_MS=20 VBW_BENCH_ONLY="$GUARD_CASES" bash "$REPO_ROOT/tools/bench-hooks.sh"
  if [[ "$output" == *"machine too busy to measure"* ]]; then skip "$output"; fi
  [ "$status" -eq 0 ] || {
    echo "$output"
    false
  }
  ! printf '%s\n' "$output" | grep -q ': OVER$' || {
    echo "$output"
    false
  }
  # Every case the selector names was judged: 5 inputs on 5 records, cross-project, loop on 2 records.
  [ "$(printf '%s\n' "$output" | grep -cE '^guard \((git|npm|big|interp|script)(, [^)]*)?\): [0-9.]+ ms own CPU per call')" -eq 25 ] || {
    echo "not every case was judged:"
    echo "$output"
    false
  }
}
