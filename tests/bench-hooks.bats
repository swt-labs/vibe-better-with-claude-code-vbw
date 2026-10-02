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

# bench [RATIO [MS]]: the benchmark on the copied plugin. Within budget means
# within MS of own CPU, or within RATIO times the platform's own shell and jq
# startup.
bench() {
  VBW_HOOK_BUDGET="${1:-1.0}" VBW_HOOK_BUDGET_MS="${2:-8}" VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=20 \
    bash "$BATS_TEST_DIRNAME/../tools/bench-hooks.sh"
}

# own_cost INPUT: the own cost the bench printed for one input, in ms.
own_cost() { printf '%s\n' "$output" | sed -n "s/^guard ($1): \([0-9.]*\) ms.*/\1/p"; }

@test "time a hook spends waiting is not counted as its cost" {
  # Both hooks start the same sleep process; one waits 50 ms in it. Measured by
  # the clock, the wait adds all 50 ms; as CPU time it adds nothing beyond noise
  # (CPU time still varies by several ms on a busy virtual machine, as in CI).
  hooks_with '"sleep 0; " + .'
  run bench 20 100
  local quick
  quick=$(own_cost git)
  hooks_with '"sleep 0.05; " + .'
  run bench 20 100
  [ -n "$quick" ] && [ -n "$(own_cost git)" ] || { echo "$output"; false; }
  perl -e 'exit($ARGV[0] - $ARGV[1] < 25 ? 0 : 1)' -- "$(own_cost git)" "$quick" \
    || { echo "waiting counted: $quick ms without it, $(own_cost git) ms with it"; false; }
}

@test "within budget means within the milliseconds or within the ratio to startup" {
  # A loaded machine (slower cores) grows startup and the guard's own cost
  # together, so the ratio holds; a quiet machine of any platform meets the
  # milliseconds.
  run bench
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qE '^guard \(git\): [0-9.]+ ms own CPU per call, [0-9.]+x the platform.s sh and jq startup \([0-9.]+ ms\); budget 8 ms or 1.0x$'
  run bench 0.01 100
  [ "$status" -eq 0 ]
  run bench 100 0
  [ "$status" -eq 0 ]
  run bench 0.01 0
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'OVER'
}

@test "extra work in a hook is over the budget" {
  hooks_with '. + "; jq -n 1 > /dev/null; jq -n 1 > /dev/null"'
  run bench
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'OVER'
}
