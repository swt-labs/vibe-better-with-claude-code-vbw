#!/usr/bin/env bats
# R76 (hot path, CLAUDE.md): judging what a program writes during a run adds
# work to the guard, which runs before every tool call. The hook benchmark
# measures that case too (a build agent running Python on a build lease) and
# the guard stays within the hook budget for it, as for every other input.

load helper

@test "R76: the hook benchmark measures a program command during a run, and it is within budget" {
  VBW_BENCH_RUNS=30 run bash "$BATS_TEST_DIRNAME/../tools/bench-hooks.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"guard (interp):"* ]] || { echo "$output"; false; }
  # Every input that was measured is within budget, none reported OVER.
  [[ "$output" != *OVER* ]]
}
