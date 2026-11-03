#!/usr/bin/env bats
# R184 (with R151): tools/bench-hooks.sh measures the hand-back too. In a
# project that turns VBW off, the statusLine setting VBW writes runs VBW's
# script (which says "off") and then the user's earlier status line; the bench
# runs that setting as Claude Code does, with the bench's own plugin installed
# where the setting looks for it, and judges VBW's own CPU per call (the whole
# call minus the same earlier status line run on its own, which is the user's and
# the shell's) against 10 ms, on a line of its own: 'status line (VBW off)'.
# It fails when the earlier status line did not show, so the measure cannot
# leave the hand-back out. A machine too busy to measure is reported, not
# failed. The timing assertion of the hand-back lives here and nowhere else.
# L1: the bench runs on a copy of the plugin, two calls per input (30 for the
# one case that judges this machine's speed).

load helper

setup() {
  vbw_setup
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  BENCH="$REPO_ROOT/tools/bench-hooks.sh"
  SCRIPT="$TEST_ROOT/plugin/scripts/vbw-statusline.sh"
}

teardown() { vbw_teardown; }

burn() { printf "perl -e '1 while (times)[0] + (times)[1] < %s / 1000'" "$1"; }

# The limit is set on the bench's own line (60 ms, the status line's, unless a test gives another), as
# tests/bench-limits.bats does: these tests check the limit logic with wide margins, not this machine's speed.
# The cases asserted on: the hand-back, and the plain and large-record status lines (VBW_BENCH_ONLY joins selectors with '|').
CASES='status line (VBW off)|status line:|status line (large record):'
OFF='status line (VBW off)'

# A case that adds work and expects a failure pins VBW_BENCH_REFERENCE_MS=1 (ratio 1 or
# less: the absolute budget, R222), so a slow runner scaling the budget past the added
# work cannot read it as slow (T214). The R222 cases measure the ratio itself.
bench() {
  run env VBW_BENCH_ONLY="$CASES" VBW_STATUSLINE_BUDGET_MS=60 VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=2 "$@" bash "$BENCH"
}

quiet_or_skip() {
  if printf '%s\n' "$output" | grep -qi 'too busy to measure'; then
    skip "the machine is too busy to measure: $(printf '%s\n' "$output" | grep -i 'too busy to measure')"
  fi
}

# line REGEX: the one output line matching REGEX (extended), or a failure.
line() {
  local l
  l=$(printf '%s\n' "$output" | grep -E -- "$1") || {
    echo "no line matches: $1"
    printf '%s\n' "$output"
    return 1
  }
  printf '%s\n' "$l"
}

@test "R184: the bench measures VBW's own cost in the hand-back where VBW is off against 10 ms, the platform's bash, jq and sh startup and the earlier status line left out" {
  bench
  quiet_or_skip
  line '^status line \(VBW off\): -?[0-9.]+ ms own CPU per call \(a bash, a jq and a sh startup and the earlier status line: [0-9.]+ ms\); budget 10 ms(: OVER)?$' > /dev/null
  bench VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 VBW_HANDBACK_BUDGET_MS=100000
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
  line '^status line \(VBW off\): -?[0-9.]+ ms own CPU per call \(a bash, a jq and a sh startup and the earlier status line: [0-9.]+ ms\); budget 100000 ms$' > /dev/null
  [[ "$output" != *"earlier status line did not show"* ]]
  # Where VBW is on, the status line is still measured on both records.
  line '^status line: [0-9.]+ ms CPU per call; budget 100000 ms$' > /dev/null
  line '^status line \(large record\): [0-9.]+ ms CPU per call; budget 100000 ms$' > /dev/null
}

@test "R184: on a machine that can be measured, VBW's own cost in the hand-back is within 10 ms" {
  bench VBW_BENCH_ONLY="$OFF" VBW_BENCH_RUNS=30
  quiet_or_skip
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
  line '^status line \(VBW off\): -?[0-9.]+ ms own CPU per call .*; budget 10 ms$' > /dev/null
}

@test "R184: VBW's script above 10 ms makes the hand-back fail the bench, naming the cost and the limit" {
  {
    sed -n 1p "$SCRIPT"
    burn 100
    echo
    sed -n '2,$p' "$SCRIPT"
  } > "$TEST_ROOT/sl.sh"
  cat "$TEST_ROOT/sl.sh" > "$SCRIPT"
  bench VBW_BENCH_REFERENCE_MS=1 VBW_BENCH_ONLY="$OFF"
  quiet_or_skip
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  local l cost
  l=$(line '^status line \(VBW off\): -?[0-9.]+ ms own CPU per call .*; budget 10 ms: OVER$')
  cost=$(printf '%s\n' "$l" | sed -E 's/^.*: (-?[0-9.]+) ms own CPU per call.*$/\1/')
  perl -e 'exit($ARGV[0] > 60 ? 0 : 1)' -- "$cost" || {
    echo "a 100 ms script measured $cost ms of own cost in the hand-back: $l"
    false
  }
}

@test "R184: a hand-back that never shows the earlier status line fails the bench" {
  # A script that never says VBW is off: the setting never hands over.
  printf '#!/usr/bin/env bash\nwhile IFS= read -t 1 -r l; do :; done\necho "[VBW] always"\n' > "$SCRIPT"
  bench VBW_BENCH_ONLY="$OFF" VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  [[ "$output" == *"status line (VBW off): the earlier status line did not show"* ]] || {
    printf '%s\n' "$output"
    false
  }
}

@test "R184: on a machine too busy to measure, the hand-back is not judged either" {
  local real
  real=$(command -v jq)
  mkdir -p "$TEST_ROOT/slow"
  printf '#!/bin/sh\n%s\n"%s" "$@"\n' "$(burn 40)" "$real" > "$TEST_ROOT/slow/jq"
  chmod +x "$TEST_ROOT/slow/jq"
  bench VBW_BENCH_ONLY="$OFF" PATH="$TEST_ROOT/slow:$PATH"
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
  printf '%s\n' "$output" | grep -qi 'too busy to measure'
  if printf '%s\n' "$output" | grep -q '^status line (VBW off)'; then
    echo "a busy machine was judged:"
    printf '%s\n' "$output"
    false
  fi
}

@test "R224: the bench measures VBW's own cost in the hand-back outside a VBW project as 'status line (no project)', as it measures 'status line (VBW off)', against the 10 ms hand-back budget" {
  bench VBW_BENCH_ONLY='status line (no project)' VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 VBW_HANDBACK_BUDGET_MS=100000
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
  line '^status line \(no project\): -?[0-9.]+ ms own CPU per call \(a bash, a jq and a sh startup and the earlier status line: [0-9.]+ ms\); budget 100000 ms$' > /dev/null
  [[ "$output" != *"did not show"* ]]
  bench VBW_BENCH_ONLY='status line (no project)'
  quiet_or_skip
  line '^status line \(no project\): -?[0-9.]+ ms own CPU per call \(a bash, a jq and a sh startup and the earlier status line: [0-9.]+ ms\); budget 10 ms(: OVER|: slow \([^)]*\))?$' > /dev/null
}

@test "R224: a hand-back outside a VBW project that never shows the earlier status line fails the bench" {
  # A script that renders where there is no project: the setting never hands over.
  printf '#!/usr/bin/env bash\nwhile IFS= read -t 1 -r l; do :; done\necho "[VBW] no project here"\n' > "$SCRIPT"
  bench VBW_BENCH_ONLY='status line (no project)' VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  [[ "$output" == *"status line (no project): the earlier status line did not show"* ]] || {
    printf '%s\n' "$output"
    false
  }
}

@test "R224: VBW's script above 10 ms, though under the status line's 60 ms, makes the hand-back outside a VBW project fail the bench" {
  {
    sed -n 1p "$SCRIPT"
    burn 35
    echo
    sed -n '2,$p' "$SCRIPT"
  } > "$TEST_ROOT/sl.sh"
  cat "$TEST_ROOT/sl.sh" > "$SCRIPT"
  bench VBW_BENCH_REFERENCE_MS=1 VBW_BENCH_ONLY='status line (no project)'
  quiet_or_skip
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  line '^status line \(no project\): -?[0-9.]+ ms own CPU per call .*; budget 10 ms: OVER$' > /dev/null
}
