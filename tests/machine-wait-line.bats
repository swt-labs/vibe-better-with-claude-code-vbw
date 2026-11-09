#!/usr/bin/env bats
# R181 (docs/proof.md): a run of vbw prove, vbw fix done or vbw check whose
# units waited for a computer-wide slot ends its output with one line naming
# the total time they waited and the limit:
#   waited N s for other VBW runs on this computer (limit L of C cores)
# (under a minute the time is in seconds; with an unreadable core count the
# parenthesis reads "(limit 1, as this computer's core count could not be
# read)"). A run that never waited prints no such line, so the output of an
# unshared run is unchanged. L1: another project holds the only slot (2 cores:
# limit 1) while the run starts (tests/machine-helper.bash). The projects are
# built once per file (setup_file) and copied for each test.

load helper
load machine-helper
load fixture-helper

# pair: on 2 cores, project A of one check and project B, whose one unit works
# 5 s, to hold the slot (hold_start). For fixture_build.
pair() {
  machine_setup
  cores 2
  machine_project "$PROJECT" A 1 0
  machine_project "$OTHER" B 1 5
}

# alone_pair: pair, and beside it the alone project A of one check. For fixture_build.
alone_pair() {
  machine_setup
  cores 2
  ALONE="$TEST_ROOT/alone project"
  machine_project "$ALONE" A 1 0
  machine_project "$PROJECT" A 1 0
  machine_project "$OTHER" B 1 5
}

setup_file() {
  fixture_build base machine_setup
  fixture_build pair pair
  fixture_build alone alone_pair
}
setup() { fixture_copy base; }
teardown() { machine_teardown; }
teardown_file() { fixture_teardown; }

WAITED_RE='^waited ([0-9]+) s for other VBW runs on this computer \(limit 1 of 2 cores\)$'

# hold_start: project B (built by pair: its unit works 5 s) holds the only slot
# for those 5 s; HOLDER is its vbw.
hold_start() {
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  HOLDER=$BG_PID
  wait_starts 1 B-
}

# last_lines OUTPUT: its last two lines, in WAITED (the last) and BEFORE.
last_lines() {
  WAITED=$(printf '%s\n' "$1" | tail -n 1)
  BEFORE=$(printf '%s\n' "$1" | tail -n 2 | head -n 1)
}

# waited_ok MIN MAX [RE]: the last line matches RE (default WAITED_RE), its time from MIN to MAX seconds.
waited_ok() {
  local re="${3:-$WAITED_RE}"
  [[ "$WAITED" =~ $re ]] || { echo "last line: $WAITED"; return 1; }
  [ "${BASH_REMATCH[1]}" -ge "$1" ] && [ "${BASH_REMATCH[1]}" -le "$2" ] || { echo "waited ${BASH_REMATCH[1]} s, want $1 to $2"; return 1; }
}

@test "R181: vbw prove whose unit waited ends with the waited line, after its verdict" {
  fixture_copy pair
  hold_start
  run within 60 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  last_lines "$output"
  waited_ok 1 15 || { echo "$output"; false; }
  [ "$BEFORE" = proved ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'for other VBW runs')" = 1 ]
  wait_ok "$HOLDER"
}

@test "R181: vbw check whose unit waited ends with the waited line, after its results" {
  fixture_copy pair
  hold_start
  run within 60 "$VBW" check C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  last_lines "$output"
  waited_ok 1 15 || { echo "$output"; false; }
  [[ "$BEFORE" == "C1 pass "* ]] || { echo "$output"; false; }
  wait_ok "$HOLDER"
}

@test "R181: vbw fix done whose unit waited ends with the waited line, after its fixes" {
  fixture_copy pair
  hold_start
  run within 60 "$VBW" fix "done" F1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  last_lines "$output"
  waited_ok 1 15 || { echo "$output"; false; }
  [ "$BEFORE" = "F1 fixed: vbw prove decides" ] || { echo "$output"; false; }
  wait_ok "$HOLDER"
}

@test "R181: with an unreadable core count the waited line names limit 1 and why" {
  fixture_copy pair
  cores none
  hold_start
  run within 60 "$VBW" check C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  last_lines "$output"
  waited_ok 1 15 "^waited ([0-9]+) s for other VBW runs on this computer \\(limit 1, as this computer's core count could not be read\\)\$" || { echo "$output"; false; }
  wait_ok "$HOLDER"
}

@test "R181: a run that never waited prints no waited line: prove, check and fix done output is unchanged" {
  cores 4
  machine_project "$PROJECT" A 2 0 "$(peek_check C3 "$CLAUDE_CONFIG_DIR/vbw/slots.json")"
  run within 60 "$VBW" check < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | sed 's/ [0-9.]*s$/ Ns/')" = "$(printf 'C1 pass Ns\nC2 pass Ns\nC3 pass Ns')" ] || { echo "$output"; false; }
  run within 60 "$VBW" fix "done" F1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"for other VBW runs"* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "F1 fixed: vbw prove decides" ] || { echo "$output"; false; }
  run within 60 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"for other VBW runs"* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -n 1)" = proved ] || { echo "$output"; false; }
  # The store was in force (a unit saw it), and still nothing was said.
  seen_store
}

# say WAITS: the lines slots_say prints when the units' waits files hold WAITS (one per line).
say() {
  local out="$TEST_ROOT/say-out"
  mkdir -p "$out"
  printf '%s' "$1" > "$out/waits"
  bash -c 'VBW_LIB="$1/lib"; . "$VBW_LIB/core.sh"; . "$VBW_LIB/slots.sh"; SLOTS_LIMIT=1; CHECK_OUT=$2; slots_total; slots_say' _ "$PLUGIN_ROOT" "$out"
}

@test "R181: the waited line names seconds under a minute and whole minutes from 60 s up" {
  cores 2
  [ "$(say $'59\n')" = "waited 59 s for other VBW runs on this computer (limit 1 of 2 cores)" ]
  [ "$(say $'60\n')" = "waited 1 min for other VBW runs on this computer (limit 1 of 2 cores)" ]
  [ "$(say $'240\n')" = "waited 4 min for other VBW runs on this computer (limit 1 of 2 cores)" ]
  [ "$(say $'0\n')" = "" ]
  cores none
  [ "$(say $'59\n')" = "waited 59 s for other VBW runs on this computer (limit 1, as this computer's core count could not be read)" ]
  [ "$(say $'240\n')" = "waited 4 min for other VBW runs on this computer (limit 1, as this computer's core count could not be read)" ]
}

@test "R181: the waits of several units are added, not the longest taken" {
  cores 2
  [ "$(say $'3\n4\n')" = "waited 7 s for other VBW runs on this computer (limit 1 of 2 cores)" ]
  [ "$(say $'30\n31\n')" = "waited 1 min for other VBW runs on this computer (limit 1 of 2 cores)" ]
}

# shape FILE FILTER: the sorted set of key paths (array positions as *) of FILTER applied to the JSON in FILE.
shape() {
  jq -c "$2 | [paths | map(if type == \"number\" then \"*\" else . end)] | unique" "$1"
}

@test "R181: a wait never reaches the evidence, the record or the stored runs: they have the shape of an alone run" {
  fixture_copy alone
  ALONE="$TEST_ROOT/alone project"
  (cd "$ALONE" && "$VBW" prove < /dev/null > /dev/null)
  A_EVIDENCE=$(shape "$ALONE/.vbw/record.json" .evidence)
  A_RECORD=$(shape "$ALONE/.vbw/record.json" 'del(.evidence)')
  A_RUNS=$(shape "$(git -C "$ALONE" rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json" .)
  [ "$A_EVIDENCE" != null ] && [ "$A_RUNS" != null ]
  hold_start
  run within 60 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  [[ "$output" == *"for other VBW runs"* ]] || { echo "the unit did not wait: $output"; false; }
  wait_ok "$HOLDER"
  [ "$(shape "$PROJECT/.vbw/record.json" .evidence)" = "$A_EVIDENCE" ]
  [ "$(shape "$PROJECT/.vbw/record.json" 'del(.evidence)')" = "$A_RECORD" ]
  [ "$(shape "$(git -C "$PROJECT" rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json" .)" = "$A_RUNS" ]
  ! grep -rqi 'wait' "$PROJECT/.vbw/record.json" || { grep -i 'wait' "$PROJECT/.vbw/record.json"; false; }
}

# R288 (field report 2026-11-09, D685): a vbw check, vbw mutate or fix done that waits
# says once, when the wait starts, what it waits for and since when, in local time:
# 'waiting for a free slot of the computer-wide limit since HH:MM'. The waited line at
# the end stays (R181).
@test "R288: vbw check whose unit waits for a slot says once, when the wait starts, what it waits for and since when in local time" {
  fixture_copy pair
  hold_start
  local since
  since=$(TZ=Europe/Lisbon date +%H:%M)
  TZ=Europe/Lisbon run within 60 "$VBW" check C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'waiting for a free slot of the computer-wide limit since ')" = 1 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -E 'waiting for a free slot of the computer-wide limit since [0-9]{2}:[0-9]{2}$' | grep -qE "since ($since|$(TZ=Europe/Lisbon date +%H:%M))$" || { echo "not the local time of the wait's start ($since): $output"; false; }
  # Told when it starts: before the check's result.
  [ "$(printf '%s\n' "$output" | grep -n 'waiting for a free slot' | cut -d: -f1)" -lt "$(printf '%s\n' "$output" | grep -n '^C1 pass ' | cut -d: -f1)" ] || { echo "$output"; false; }
  wait_ok "$HOLDER"
}

@test "R288: a run that never waits prints no waiting line" {
  fixture_copy pair
  run within 60 "$VBW" check C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"waiting for"* ]] || { echo "$output"; false; }
}
