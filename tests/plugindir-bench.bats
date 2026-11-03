#!/usr/bin/env bats
# R185 (with R151): tools/bench-hooks.sh measures the status line of a session
# that loaded VBW from a working tree. The bench starts a session the way
# claude --plugin-dir does (the bench's plugin's own SessionStart hook, with
# the plugin data folder Claude Code gives a vbw@inline copy), with a stand-in
# installed release in a Claude config folder of its own, then runs the
# statusLine setting `vbw statusline on` writes, as Claude Code runs it, and
# judges its CPU per call against the status line's 60 ms limit, on a line of
# its own: 'status line (loaded copy)'. It fails when the loaded copy did not
# render, so the measure cannot leave that path out. The per-call hooks keep
# their 20 ms limit on the same run. A machine too busy to measure is
# reported, not failed. L1: the bench runs on a copy of the plugin, two calls
# per input.

load helper

setup() {
  vbw_setup
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  BENCH="$REPO_ROOT/tools/bench-hooks.sh"
}

teardown() { vbw_teardown; }

burn() { printf "perl -e '1 while (times)[0] + (times)[1] < %s / 1000'" "$1"; }

# The cases asserted on: the loaded copy's status line, and the six guard inputs (the hooks keep their limit on the same run).
# VBW_BENCH_ONLY joins selectors with '|'.
CASES='status line (loaded copy)|guard (git)|guard (npm)|guard (big)|guard (interp)|guard (read)|guard (answer)'
LOADED='status line (loaded copy)'

bench() {
  run env VBW_BENCH_ONLY="$CASES" VBW_HOOK_BUDGET_MS=20 VBW_STATUSLINE_BUDGET_MS=60 VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=2 "$@" bash "$BENCH"
}

quiet_or_skip() {
  if printf '%s\n' "$output" | grep -qi 'too busy to measure'; then
    skip "the machine is too busy to measure: $(printf '%s\n' "$output" | grep -i 'too busy to measure')"
  fi
}

line() {
  local l
  l=$(printf '%s\n' "$output" | grep -E -- "$1") || {
    echo "no line matches: $1"
    printf '%s\n' "$output"
    return 1
  }
  printf '%s\n' "$l"
}

@test "R185: the bench measures the loaded copy's status line against the 60 ms limit, and the hooks against 20 ms" {
  bench
  quiet_or_skip
  line '^status line \(loaded copy\): [0-9.]+ ms CPU per call; budget 60 ms(: OVER)?$' > /dev/null
  line '^guard \(.*\): [0-9.]+ ms own CPU per call .*; budget 20 ms(: OVER)?$' > /dev/null
  bench VBW_BENCH_ONLY="$LOADED" VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
  line '^status line \(loaded copy\): [0-9.]+ ms CPU per call; budget 100000 ms$' > /dev/null
  [[ "$output" != *"the loaded copy did not show"* ]]
}

@test "R185: a loaded copy's status line above 60 ms fails the bench, naming the cost and the limit" {
  # The reference is pinned under nominal (ratio 1 or less: the absolute budget, R222), so
  # a slow runner scaling the budget past the injected 100 ms cannot read it as slow (T214).
  local sl="$TEST_ROOT/plugin/scripts/vbw-statusline.sh"
  {
    sed -n 1p "$PLUGIN_ROOT/scripts/vbw-statusline.sh"
    burn 100
    echo
    sed -n '2,$p' "$PLUGIN_ROOT/scripts/vbw-statusline.sh"
  } > "$sl"
  bench VBW_BENCH_ONLY="$LOADED" VBW_BENCH_REFERENCE_MS=1
  quiet_or_skip
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  local l cost
  l=$(line '^status line \(loaded copy\): [0-9.]+ ms CPU per call; budget 60 ms: OVER$')
  cost=$(printf '%s\n' "$l" | sed -E 's/^.*: ([0-9.]+) ms CPU per call.*$/\1/')
  perl -e 'exit($ARGV[0] > 60 ? 0 : 1)' -- "$cost" || {
    echo "a 100 ms script measured $cost ms on the loaded copy's line: $l"
    false
  }
}

@test "R185: when the session start does not record the loaded copy, the bench fails instead of measuring the installed one" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_ROOT/plugin/hooks/session-start.sh"
  bench VBW_BENCH_ONLY="$LOADED" VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  [[ "$output" == *"status line (loaded copy): the loaded copy did not show"* ]] || {
    printf '%s\n' "$output"
    false
  }
}
