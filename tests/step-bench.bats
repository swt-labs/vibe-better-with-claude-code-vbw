#!/usr/bin/env bats
# R190, phase P147 (L1): the speed limits hold with a step running. The hook
# bench (tools/bench-hooks.sh) measures the status line with a running step's
# note against the status line's 60 ms budget, and fails when the step did not
# show, so the measure never leaves it out (the panel bench's case is
# tests/step-panel-bench.bats's). Whether the costs
# stay within their budgets is the benchmarks' own verdict in the release run
# (bash tools/test.sh --release), never in vbw prove: here the limits are set
# out of reach and only the cases are judged.

load helper

setup() {
  vbw_setup
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
}
teardown() { vbw_teardown; }

@test "R190: the hook bench measures the status line with a step running, against the status line budget" {
  run env VBW_BENCH_ONLY='status line (step running)' VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=1 VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 bash "$REPO_ROOT/tools/bench-hooks.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ (^|$'\n')"status line (step running): "[0-9.]+" ms CPU per call; budget 100000 ms" ]] || { echo "$output"; false; }
  [[ "$output" != *"the step was not shown"* ]] || { echo "$output"; false; }
}

@test "R190: a status line that does not show the step fails the hook bench" {
  # A status line whose step shows no end time.
  sed -i.bak 's/until /untl /g' "$TEST_ROOT/plugin/scripts/statusline.jq"
  run env VBW_BENCH_ONLY='status line (step running)' VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=1 VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 bash "$REPO_ROOT/tools/bench-hooks.sh"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"status line (step running): the step was not shown, so the measure left it out"* ]] || { echo "$output"; false; }
}

# R235 (T205): a miss of the step is explained. When the first line has no step the
# bench prints the first line it read and, when the status line's error file
# (.vbw/runtime/statusline.err, written by the render) has text, that text, each
# prefixed with the case's label; the failure text itself stays as pinned above.

@test "R235: when the status line falls back, the bench's failure names the first line and jq's error from statusline.err" {
  printf '\n| ) (\n' >> "$TEST_ROOT/plugin/scripts/statusline.jq"
  run env VBW_BENCH_ONLY='status line (step running)' VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=1 VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 bash "$REPO_ROOT/tools/bench-hooks.sh"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"status line (step running): the step was not shown, so the measure left it out"* ]] || { echo "$output"; false; }
  [[ "$output" == *"status line (step running): first line: [VBW] status line unavailable"* ]] || { echo "$output"; false; }
  [[ "$output" == *"status line (step running): statusline.err: jq: error"* ]] || { echo "$output"; false; }
}

@test "R235: a status line that renders without the step names the line it read, and no error file text" {
  sed -i.bak 's/until /untl /g' "$TEST_ROOT/plugin/scripts/statusline.jq"
  run env VBW_BENCH_ONLY='status line (step running)' VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=1 VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 bash "$REPO_ROOT/tools/bench-hooks.sh"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"status line (step running): first line: "*"1 of 2"* ]] || { echo "$output"; false; }
  [[ "$output" != *"statusline.err:"* ]] || { echo "$output"; false; }
}
