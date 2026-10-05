#!/usr/bin/env bats
# R56 and R58: the cost line and the time estimates stay within the panel's CPU
# budget (tools/bench-panel.sh), use no network, and are explained for people in
# docs/panel.md. Behaviour is in tests/panel/cost.test.mjs, estimate.test.mjs and
# glance.test.mjs. L1.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

BENCH="$BATS_TEST_DIRNAME/../tools/bench-panel.sh"

@test "R56 and R58: a refresh that also reads the cost and works out two estimates stays within the panel's budget" {
  command -v node > /dev/null 2>&1 || { echo "node is needed for the panel tests"; false; }
  [ -f "$BENCH" ]
  VBW_BENCH_RUNS=30 run bash "$BENCH"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ (^|$'\n')"refresh with cost and estimates: "[0-9.]+" ms CPU" ]] || { echo "$output"; false; }
}

@test "R58: the estimate code is pure and local: it reaches nothing but its inputs" {
  local f="$PLUGIN_ROOT/hooks/panel-estimate.js"
  [ -f "$f" ]
  ! grep -nE '\$\.|fetch\(|import |require\(|node:|Date\.now|Math\.random|new Date\(\)' "$f"
  grep -q 'export const MIN_STEPS = 3' "$f"
  grep -q 'export function estimate' "$f"
}

@test "R58: the panel reads the history only from the clone cache file steps.json" {
  grep -q 'vbw/steps.json' "$PLUGIN_ROOT/hooks/panel.js"
  ! grep -nE 'steps\.json.*(write|\$\.fs\.write)' "$PLUGIN_ROOT/hooks/panel.js"
}

@test "R56: docs/panel.md says the cost is one line, from this session, and when it is not available" {
  grep -qiE 'cost' "$REPO_ROOT/docs/panel.md"
  grep -qiE 'not available' "$REPO_ROOT/docs/panel.md"
}

@test "R58: docs/panel.md says how many finished steps an estimate needs, that it is approximate, and where the history is kept" {
  grep -qiE 'at least 3|three finished|3 finished' "$REPO_ROOT/docs/panel.md"
  grep -qiE 'approximate|about' "$REPO_ROOT/docs/panel.md"
  grep -q 'steps.json' "$REPO_ROOT/docs/panel.md"
}
