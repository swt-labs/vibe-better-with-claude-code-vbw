#!/usr/bin/env bats
# tools/bench-hooks.sh measures the guard's own CPU cost, so a busy machine
# cannot fail it while a real regression (more work per call) still does.

load helper

setup() {
  vbw_setup
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
}
teardown() { vbw_teardown; }

# hooks_with FILTER: rewrite every PreToolUse command of the copied plugin.
hooks_with() {
  jq "(.hooks.PreToolUse[].hooks[].command) |= ($1)" "$PLUGIN_ROOT/hooks/hooks.json" > "$TEST_ROOT/plugin/hooks/hooks.json"
}

# bench [BUDGET_MS]: the benchmark on the copied plugin.
bench() {
  VBW_HOOK_BUDGET_MS="${1:-8}" VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=20 \
    bash "$BATS_TEST_DIRNAME/../tools/bench-hooks.sh"
}

# own_cost INPUT: the own cost the bench printed for one input, in ms.
own_cost() { printf '%s\n' "$output" | sed -n "s/^guard ($1): \([0-9.]*\) ms.*/\1/p"; }

@test "time a hook spends waiting is not counted as its cost" {
  # Both hooks start the same sleep process; one waits 30 ms in it.
  hooks_with '"sleep 0; " + .'
  run bench 100
  local quick
  quick=$(own_cost git)
  hooks_with '"sleep 0.03; " + .'
  run bench 100
  [ -n "$quick" ] && [ -n "$(own_cost git)" ] || { echo "$output"; false; }
  perl -e 'exit(abs($ARGV[0] - $ARGV[1]) < 2 ? 0 : 1)' -- "$(own_cost git)" "$quick" \
    || { echo "waiting counted: $quick ms without it, $(own_cost git) ms with it"; false; }
}

@test "extra work in a hook is over the budget" {
  hooks_with '. + "; jq -n 1 > /dev/null; jq -n 1 > /dev/null"'
  run bench
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'OVER'
}
