#!/usr/bin/env bats
# R233 (T204, L1): the per-step measure of one Bash guard call. VBW_BENCH_STEPS=1 makes
# tools/bench-hooks.sh print, instead of judging cases, one table of CPU ms per call
# (cpu_pair's method, over VBW_BENCH_RUNS runs) for the steps a guard call is made of:
# sh startup, jq startup (jq -n empty), program compile alone (the guard program over
# empty inputs), program run (the whole hooks.json command), and the reference call;
# one column per input (git, npm, big, interp). The same table is produced on this Mac,
# in both Linux images (tools/test-linux.sh -- env VBW_BENCH_STEPS=1 ...) and on GitHub's
# three runners by the workflow_dispatch job .github/workflows/bench-steps.yml, so the
# step that costs more on Linux than the reference is named with figures.

load helper

setup() {
  vbw_setup
  BENCH="$REPO_ROOT/tools/bench-hooks.sh"
}
teardown() { vbw_teardown; }

# row LABEL: the table row starting with LABEL, from $output.
row() { printf '%s\n' "$output" | grep -E "^$1( |\t)"; }

@test "R233: VBW_BENCH_STEPS=1 prints one table with the five steps as rows and the four inputs as columns, each cell CPU ms per call, and judges no case" {
  run env VBW_BENCH_STEPS=1 VBW_BENCH_RUNS=2 VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 bash "$BENCH"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^step\b.*\bgit\b.*\bnpm\b.*\bbig\b.*\binterp\b' || { echo "no header row naming the four inputs:"; echo "$output"; false; }
  local label
  for label in 'sh startup' 'jq startup' 'program compile' 'program run' 'reference'; do
    [ -n "$(row "$label")" ] || { echo "no row for $label:"; echo "$output"; false; }
    [ "$(row "$label" | grep -oE '(^|[[:space:]])[0-9]+\.[0-9]([[:space:]]|$)' | wc -l | tr -d ' ')" -ge 4 ] \
      || { echo "the $label row has fewer than four ms figures: $(row "$label")"; false; }
  done
  [[ "$output" != *"guard (git):"* ]] || { echo "a case was judged in step mode"; false; }
  [[ "$output" != *": OVER"* ]]
}

@test "R233: the step table names its method: CPU ms per call over the bench's runs, the runs stated" {
  run env VBW_BENCH_STEPS=1 VBW_BENCH_RUNS=2 VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 bash "$BENCH"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"CPU ms per call"* ]] || { echo "$output"; false; }
  [[ "$output" =~ (^|[^0-9])2\ runs ]] || { echo "the runs are not stated:"; echo "$output"; false; }
}

@test "R233: a workflow_dispatch job runs the step table on macos-latest, ubuntu-latest and ubuntu-26.04, and never on a pull request" {
  local wf="$REPO_ROOT/.github/workflows/bench-steps.yml"
  [ -f "$wf" ] || { echo "no $wf"; false; }
  grep -q 'workflow_dispatch' "$wf"
  ! grep -qE '^\s*(pull_request|push):' "$wf" || { echo "the job runs on push or pull_request"; false; }
  grep -q 'macos-latest' "$wf" && grep -q 'ubuntu-latest' "$wf" && grep -q 'ubuntu-26.04' "$wf" || { echo "the three runners are not all named"; false; }
  grep -q 'VBW_BENCH_STEPS=1' "$wf" || { echo "the job does not set VBW_BENCH_STEPS=1"; false; }
  grep -q 'tools/bench-hooks.sh' "$wf"
  grep -q 'jq --version' "$wf" || { echo "the job does not print jq's version, so the table cannot be read against it"; false; }
}
