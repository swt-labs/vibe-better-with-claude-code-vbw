#!/usr/bin/env bats
# R152 (hook cost budget, test diet lever L3): a test that asserts on one line of
# the hook bench asks for that case with VBW_BENCH_ONLY, so the bench builds and
# measures only what is asked, instead of the whole bench (about 26 s) to see
# one line. A selector is the start of a printed label, matched against the
# label plus its colon: 'guard (git' names every git case, 'status line:' only
# the plain status line. Several selectors are joined with '|' (the labels hold
# commas). Unset, the bench is the full bench the release run needs. A selector
# that names no case exits 2 and lists the cases: a typo never passes as an
# empty run. The verdict logic of each case is the same with and without the
# selector (tests/bench-limits.bats and the other bench files judge it through
# the selector). L1: limits are set out of reach, only which cases ran is judged.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

bench() {
  run env VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 VBW_HANDBACK_BUDGET_MS=100000 VBW_BENCH_RUNS=1 "$@" bash "$REPO_ROOT/tools/bench-hooks.sh"
}

# measured: the label of every case the bench measured, in output order.
measured() {
  printf '%s\n' "$output" | sed -n -E 's/^((guard \([^)]*\))|(status line( \([^)]*\))?)): .*/\1/p'
}

# nothing_built: no record was built (the large record and the sized records print a line when built).
nothing_built() {
  ! printf '%s\n' "$output" | grep -qE '^(large record|record \()' || { echo "a record was built:"; echo "$output"; false; }
}

@test "R152: a selector measures only the case it names, and builds nothing else" {
  bench VBW_BENCH_ONLY='guard (answer)'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(measured)" = "guard (answer)" ] || { echo "$output"; false; }
  nothing_built
  bench VBW_BENCH_ONLY='status line (loaded copy)'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(measured)" = "status line (loaded copy)" ] || { echo "$output"; false; }
  nothing_built
}

@test "R152: a selector is the start of a printed label; a trailing colon names exactly one case" {
  bench VBW_BENCH_ONLY='guard (loop'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(measured)" = $'guard (loop)\nguard (loop, large record)' ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^large record: [0-9]+ bytes$' || { echo "the large record the loop case needs was not built"; echo "$output"; false; }
  ! printf '%s\n' "$output" | grep -qE '^record \(' || { echo "a sized record was built:"; echo "$output"; false; }
  bench VBW_BENCH_ONLY='guard (loop):'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(measured)" = "guard (loop)" ] || { echo "$output"; false; }
  nothing_built
  bench VBW_BENCH_ONLY='status line:'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(measured)" = "status line" ] || { echo "$output"; false; }
}

@test "R152: several selectors joined with | run in the bench's own order, each case once" {
  bench VBW_BENCH_ONLY='status line (VBW off)|guard (read)|guard (read)|guard (git):'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(measured)" = $'guard (git)\nguard (read)\nstatus line (VBW off)' ] || { echo "$output"; false; }
  nothing_built
}

@test "R152: a selector that names no case exits 2 and lists the cases, measuring and building nothing" {
  local sel
  for sel in 'guard (nothing)' 'Guard (git)' 'guard (git)|status line (nowhere)' 'guard (git)|' '|guard (git)' 'guard (git)||guard (npm)'; do
    bench VBW_BENCH_ONLY="$sel"
    [ "$status" -eq 2 ] || { echo "selector '$sel' exited $status:"; echo "$output"; false; }
    [ -z "$(measured)" ] || { echo "selector '$sel' measured:"; echo "$output"; false; }
    nothing_built
    [[ "$output" == *"VBW_BENCH_ONLY"* && "$output" == *"guard (git):"* && "$output" == *"status line (loaded copy):"* ]] || { echo "$output"; false; }
  done
}

@test "R152, R224: without a selector the bench is the full bench: every case it can be asked for runs, in the listed order, the no-project hand-back among them" {
  bench VBW_BENCH_ONLY='no such case'
  [ "$status" -eq 2 ]
  local listed
  listed=$(printf '%s\n' "$output" | sed -n -E 's/^  (.*):$/\1/p')
  # Seven inputs on five projects, the tools guard in the main session, the loop case on two,
  # and six status lines.
  [ "$(printf '%s\n' "$listed" | wc -l | tr -d ' ')" -eq 44 ] || { echo "$listed"; false; }
  printf '%s\n' "$listed" | grep -qxF 'status line (no project)' || { echo "the no-project hand-back is not a case:"; echo "$listed"; false; }
  bench
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(measured)" = "$listed" ] || { printf 'listed:\n%s\nmeasured:\n%s\n' "$listed" "$(measured)"; false; }
  printf '%s\n' "$output" | grep -qE '^large record: [0-9]+ bytes$' || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -cE '^record \((51|500|2000) checks\): [0-9]+ bytes, schema 4$')" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" != *VBW_BENCH_ONLY* ]] || { echo "$output"; false; }
}
