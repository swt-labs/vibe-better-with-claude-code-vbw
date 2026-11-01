#!/usr/bin/env bats
# R152: tools/bench-hooks.sh measures the guard's own CPU cost, so waiting on a busy
# machine is not counted (the limits are in tests/bench-limits.bats).

load helper
load bench-waiting

setup() {
  vbw_setup
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
}
teardown() { vbw_teardown; }

# hooks_with FILTER: rewrite every PreToolUse command of the copied plugin.
hooks_with() {
  jq "(.hooks.PreToolUse[].hooks[].command) |= ($1)" "$PLUGIN_ROOT/hooks/hooks.json" > "$TEST_ROOT/plugin/hooks/hooks.json"
}

# bench: the benchmark on the copied plugin, with a generous limit.
bench() {
  VBW_HOOK_BUDGET_MS="${1:-100}" VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=20 \
    bash "$BATS_TEST_DIRNAME/../tools/bench-hooks.sh"
}

@test "time a hook spends waiting is not counted as its cost" {
  # Both hooks start the same sleep process; one waits 50 ms in it. Measured by
  # the clock, the wait adds all 50 ms; as CPU time it adds nothing beyond noise
  # (CPU time still varies by several ms on a busy virtual machine, as in CI).
  # Judged as the bench judges (tests/bench-waiting.bash): a run whose sh and jq
  # startup reads busy is skipped, and a difference over the margin is measured once more.
  hooks_with '"sleep 0; " + .'
  run bench 100
  local quick first second verdict
  quick=$output
  hooks_with '"sleep 0.05; " + .'
  run bench 100
  first=$output
  verdict=$(waiting_judge 20 25 "$quick" "$first") || true
  if [ "$verdict" = again ]; then
    run bench 100
    second=$output
    verdict=$(waiting_judge 20 25 "$quick" "$first" "$second") || true
  fi
  case "$verdict" in
    busy*) skip "the machine was busy: sh and jq startup ${verdict#busy } ms, above the 20 ms hook limit" ;;
    ok) ;;
    *) echo "$verdict"; false ;;
  esac
}
