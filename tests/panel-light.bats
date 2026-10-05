#!/usr/bin/env bats
# R55: the panel stays light. Its CPU cost per refresh is measured by
# tools/bench-panel.sh (like tools/bench-hooks.sh does for the hooks) against a
# stated budget; it uses no network and reads no credentials; its code is
# read-only; and the kernel and workflow budgets still hold. Behaviour is in
# tests/panel/light.test.mjs. L1.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

BENCH="$BATS_TEST_DIRNAME/../tools/bench-panel.sh"

@test "R55: the bench measures the CPU of a refresh that found nothing new and of one that redraws, within the stated budget" {
  command -v node > /dev/null 2>&1 || { echo "node is needed for the panel tests"; false; }
  [ -f "$BENCH" ]
  VBW_BENCH_RUNS=30 run bash "$BENCH"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ (^|$'\n')"tick, nothing changed: "[0-9.]+" ms CPU" ]] || { echo "$output"; false; }
  [[ "$output" =~ (^|$'\n')"refresh, state changed: "[0-9.]+" ms CPU" ]] || { echo "$output"; false; }
  [[ "$output" =~ (^|$'\n')"budget: "[0-9.]+" ms" ]] || { echo "$output"; false; }
}

@test "R55: the budget is enforced: a budget no refresh can meet fails the bench" {
  [ -f "$BENCH" ]
  VBW_PANEL_BUDGET_MS=0.00001 VBW_BENCH_RUNS=10 run bash "$BENCH"
  [ "$status" -ne 0 ]
}

@test "R55: the budget is stated for people too, in docs/panel.md" {
  grep -qiE 'budget' "$BATS_TEST_DIRNAME/../docs/panel.md"
  grep -qE '[0-9.]+ ?ms' "$BATS_TEST_DIRNAME/../docs/panel.md"
}

@test "R55: the panel's code reaches no network and no credentials and never writes" {
  local f
  for f in "$PLUGIN_ROOT"/hooks/panel*.js; do
    [ -f "$f" ]
    ! grep -nE '\$\.(http|mcp|model|process|env|settings|agent|tool)\b|\$\.fs\.(write|list)|fetch\(|XMLHttpRequest|WebSocket|node:|require\(|import\(|credentials|\.ssh|ANTHROPIC|api[_-]?key' "$f" || { echo "in $f"; false; }
  done
  [ -f "$PLUGIN_ROOT/hooks/panel.js" ]
}

@test "R55: the panel never names the record as something to write" {
  ! grep -nE 'record\.json.*(write|set)|(write|set).*record\.json' "$PLUGIN_ROOT"/hooks/panel*.js
  [ -f "$PLUGIN_ROOT/hooks/panel.js" ]
}

@test "R55: the kernel stays within its budget and the workflows within theirs" {
  run bats --filter "kernel stays within" "$BATS_TEST_DIRNAME/standards.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bats --filter "workflows stay within" "$BATS_TEST_DIRNAME/standards.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R55: the panel's node tests are part of the suite, so a regression fails bash tools/test.sh" {
  grep -q 'node --test' "$BATS_TEST_DIRNAME/panel-suite.bats"
  grep -q 'tests/panel' "$BATS_TEST_DIRNAME/panel-suite.bats"
}
