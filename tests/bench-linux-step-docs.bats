#!/usr/bin/env bats
# R243 (T212, L1): docs/guards.md's bench section states the one guard step whose cost is
# Linux-only, with the figures measured on GitHub's three runners (macos-latest,
# ubuntu-latest, ubuntu-26.04) by .github/workflows/bench-steps.yml, and no longer claims
# that each Linux quotient is within 1.25 of macOS's, which PR #741 disproved (macOS 1.39
# against Ubuntu 26.04 1.82).

load helper

DOC="$REPO_ROOT/docs/guards.md"

bench_section() { sed -n '/^## Engineering/,/^## SessionStart/p' "$DOC"; }

@test "R243: the bench section names the Linux-only step with figures from GitHub's three runners" {
  bench_section | grep -q 'Linux-only' || { echo "docs/guards.md names no Linux-only step"; false; }
  bench_section | grep -q 'bench-steps.yml' || { echo "docs/guards.md does not name the workflow that measured it"; false; }
  local runner
  for runner in 'macos-latest' 'ubuntu-latest' 'ubuntu-26.04'; do
    bench_section | grep -qE "^\|.*$runner" || { echo "no table row for $runner in the bench section"; false; }
    bench_section | grep -E "^\|.*$runner" | grep -qE '[0-9]+\.[0-9]+' || { echo "the $runner row carries no figure"; false; }
  done
  # The step is named in the same sentence as its Linux-only cost, and the figures are quotients to the reference.
  bench_section | grep -E 'Linux-only' | grep -qE 'shell prelude|program compile|program run|reference compile|reference run' \
    || { echo "the Linux-only sentence names no step of the table"; false; }
}

@test "R243: the disproved claim that each Linux quotient is within 1.25 of macOS's is gone, replaced by the measured figures" {
  ! bench_section | grep -q 'each Linux quotient within 1.25' || { echo "the disproved claim is still in docs/guards.md"; false; }
  bench_section | grep -qE '1\.25' || { echo "the 1.25 target is not stated with the measured figures"; false; }
}

# F344: the docs stated the nominal figure from before the reference was reshaped (10.3 ms
# against the bench's 17.8 ms). Every "nominal ... N ms" figure in the bench section is the
# bench's own NOMINAL_MS.
@test "R243: every nominal figure the bench section states is the bench's own NOMINAL_MS" {
  local nominal stated
  nominal=$(sed -n -E 's/^NOMINAL_MS=([0-9.]+)$/\1/p' "$REPO_ROOT/tools/bench-hooks.sh")
  [ -n "$nominal" ] || { echo "no NOMINAL_MS in tools/bench-hooks.sh"; false; }
  stated=$(bench_section | tr '\n' ' ' | grep -oE 'nominal figure is[[:space:]]+one, [0-9]+\.[0-9]+ ms' | grep -oE '[0-9]+\.[0-9]+' || true)
  [ -n "$stated" ] || { echo "the bench section states no nominal figure"; false; }
  [ "$stated" = "$nominal" ] || { echo "docs/guards.md states nominal $stated ms; the bench's NOMINAL_MS is $nominal"; false; }
}
