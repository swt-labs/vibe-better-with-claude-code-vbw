#!/usr/bin/env bats
# R181 (docs/proof.md, D339): runs take equal turns at the computer-wide limit.
# A freed slot goes to the waiting run that holds the fewest slots; between
# runs holding the same number, to the one that has waited longest. A check
# marked alone keeps its per-project meaning (R45) and takes one machine slot;
# a unit passes its project's gate before it asks for a machine slot, so two
# projects never block each other. A vbw run started inside a unit's command,
# on the same store, takes no slot of its own (the unit's slot covers it, D340)
# and never waits for its parent. Waiting changes no result: a unit's timeout
# counts from its command's start. A unit that waits takes the store's lock
# once, to join the wait, and then only looks at the store: the step that frees
# a slot hands it to the waiter whose turn it is, and a waiter that finds the
# holder's run gone takes over its slot (T175: waiters polling under the lock
# kept it held and starved the releases). L1: unit commands log their start
# and end to $LOG (tests/machine-helper.bash); the lock and hand-over cases
# drive the store's functions in bash processes of their own (in_store).
# Project B of one quick check, which three tests share, is built once per
# file (setup_file) and copied; the core count is read when a run starts, so
# each test sets it after the copy.

load helper
load machine-helper
load fixture-helper

# other_one: project B of one quick check. For fixture_build.
other_one() {
  machine_setup
  machine_project "$OTHER" B 1 0
}

setup_file() {
  fixture_build base machine_setup
  fixture_build b other_one
}
setup() { fixture_copy base; }
teardown() { machine_teardown; }
teardown_file() { fixture_teardown; }

# in_store BODY [ARG...]: BODY run (stopped after 60 s) by a bash process of
# its own, so a run of its own ($$), with the slot store in $TEST_ROOT/store
# open at limit 1 as slots_open leaves it; the ARGs are its $1, $2...
in_store() {
  local body="$1"
  shift
  mkdir -p "$TEST_ROOT/store"
  # shellcheck disable=SC2016 # expanded by the inner bash
  within 60 bash -c 'VBW_LIB="$PLUGIN_ROOT/lib"; . "$VBW_LIB/core.sh"; . "$VBW_LIB/record.sh"; . "$VBW_LIB/slots.sh"
    SLOTS_DIR="$TEST_ROOT/store" SLOTS_FILE="$TEST_ROOT/store/slots.json" SLOTS_LIMIT=1 SLOTS_STATE=on CHECK_OUT="$TEST_ROOT/store"
    body=$1; shift; eval "$body"' _ "$body" "$@"
}

# wait_file PATH: wait (up to 30 s) until PATH exists.
wait_file() {
  local i
  for ((i = 0; i < 300; i++)); do [ ! -e "$1" ] || return 0; sleep 0.1; done
  echo "$1 never appeared"
  return 1
}

@test "R181: a unit that waits takes the store's lock once, to join the wait, and the step that frees the slot hands it over" {
  local holder
  # The holder, a run of its own, holds the only slot until it is told to give it back.
  # shellcheck disable=SC2016 # expanded by in_store
  in_store 'slots_hold B || exit 1; : > "$SLOTS_DIR/holding"
    until [ -e "$SLOTS_DIR/release" ]; do sleep 0.05; done
    slots_release B' &
  holder=$!
  wait_file "$TEST_ROOT/store/holding"
  # The waiter counts the times it takes the lock (each locked step of the store)
  # and the pauses of its wait, which take no time; at the 20th pause it tells
  # the holder to give the slot back.
  # shellcheck disable=SC2016 # expanded by in_store
  run in_store 'locks=0 pauses=0
    eval "orig_$(declare -f slots_apply)"
    slots_apply() { locks=$((locks + 1)); orig_slots_apply "$@"; }
    sleep() { pauses=$((pauses + 1)); [ "$pauses" -ne 20 ] || : > "$SLOTS_DIR/release"; }
    slots_hold A 2> /dev/null || { echo "no slot"; exit 1; }
    jq -c "[.held[].id]" "$SLOTS_FILE"
    echo "locks $locks pauses $pauses"'
  wait "$holder" || { echo "the holder failed"; false; }
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${lines[0]}" = '["A"]' ] || { echo "$output"; false; }
  [[ "${lines[1]}" =~ ^locks\ 1\ pauses\ ([0-9]+)$ ]] || { echo "want the lock taken once while waiting: $output"; false; }
  [ "${BASH_REMATCH[1]}" -ge 20 ] || { echo "the slot came before the holder gave it back: $output"; false; }
}

@test "R181: a unit waiting without the lock takes over the slot of a holder whose run died while it waited" {
  # The holder holds the only slot until it is killed; an orphan, so its end is reaped at once.
  # shellcheck disable=SC2016 # expanded by in_store
  ( in_store 'slots_hold B || exit 1; printf "%s\n" "$$" > "$SLOTS_DIR/holder.tmp"; mv "$SLOTS_DIR/holder.tmp" "$SLOTS_DIR/holder"; exec sleep 60' > /dev/null 2>&1 < /dev/null & )
  wait_file "$TEST_ROOT/store/holder"
  # The waiter kills the holder at the 5th pause of its wait, which takes no time.
  # shellcheck disable=SC2016 # expanded by in_store
  run in_store 'pauses=0
    sleep() { pauses=$((pauses + 1)); [ "$pauses" -ne 5 ] || kill -KILL "$(cat "$SLOTS_DIR/holder")"; }
    slots_hold A 2> /dev/null || { echo "no slot"; exit 1; }
    jq -c "[.held[].id]" "$SLOTS_FILE"
    echo "pauses $pauses"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${lines[0]}" = '["A"]' ] || { echo "$output"; false; }
  [[ "${lines[1]}" =~ ^pauses\ ([0-9]+)$ ]] && [ "${BASH_REMATCH[1]}" -ge 5 ] || { echo "the slot came before the holder died: $output"; false; }
}

@test "R181: a freed slot goes to the waiting run holding the fewest: B holds one before A's fourth unit gets its slot" {
  # The store decides the turn; when each run then notices and starts its command is the
  # runs' own timing (a run that takes a slot in its own step starts at once, a waiter at
  # its next look). So the turn is judged where it is decided: A's fourth unit copies the
  # store as it starts, and B (waiting since A's first three started, 3 s of work) holds a
  # slot in it.
  cores 4
  machine_project "$PROJECT" A 3 6 "$(peek_check C4 "$CLAUDE_CONFIG_DIR/vbw/slots.json")"
  machine_project "$OTHER" B 1 3
  (cd "$PROJECT" && "$VBW" config set check_jobs 6 > /dev/null)
  local pa pb
  bg "$PROJECT" "$TEST_ROOT/a.out" check
  pa=$BG_PID
  wait_starts 3 A-
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  pb=$BG_PID
  wait_in_store "$pb" || { show; false; }
  [ -z "$(end_line A-C1)$(end_line A-C2)$(end_line A-C3)" ] || { echo "A's units ended before B was waiting: the machine is too slow for this test"; show; false; }
  wait_ok "$pa" "$pb" || { show; false; }
  seen_store || { show; false; }
  jq -e '[.held[].run] | unique | length == 2' "$TEST_ROOT/seen.json" > /dev/null \
    || { echo "when A's fourth unit started, B held no slot:"; cat "$TEST_ROOT/seen.json"; show; false; }
  [ "$(starts B-)" = 1 ] || { show; false; }
  [ "$(peak)" -le 3 ] || { echo "peak $(peak) with 4 cores (limit 3)"; show; false; }
}

@test "R181: between waiting runs holding the same number of slots, the one that waited longest goes first" {
  fixture_copy b
  cores 2
  machine_project "$PROJECT" A 1 8
  machine_project "$THIRD" T 1 0
  local pa pb pt
  bg "$PROJECT" "$TEST_ROOT/a.out" check C1
  pa=$BG_PID
  wait_starts 1 A-
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  pb=$BG_PID
  wait_in_store "$pb" || { show; false; }
  bg "$THIRD" "$TEST_ROOT/t.out" check C1
  pt=$BG_PID
  wait_ok "$pa" "$pb" "$pt" || { show; false; }
  [ "$(end_line A-C1)" -lt "$(start_line B-C1)" ] || { echo "B did not wait for the only slot"; show; false; }
  [ "$(start_line B-C1)" -lt "$(start_line T-C1)" ] || { echo "T, which waited less, went first"; show; false; }
  [ "$(peak)" = 1 ] || { echo "peak $(peak) with 2 cores (limit 1)"; show; false; }
}

@test "R181: an alone check in one project and shared checks in another both finish at limit 1, the alone one still by itself in its project" {
  cores 2
  machine_project "$PROJECT" A 2 1 '[{"id": "C3", "req": "R1", "run": ["sh", "tests/unit.sh", "A-alone", "1", "0"], "files": ["tests/unit.sh"], "alone": true}]'
  machine_project "$OTHER" B 3 1
  local pa pb pc
  bg "$PROJECT" "$TEST_ROOT/a.out" check
  pa=$BG_PID
  bg "$OTHER" "$TEST_ROOT/b.out" check
  pb=$BG_PID
  bg "$PROJECT" "$TEST_ROOT/c.out" check C3
  pc=$BG_PID
  wait_ok "$pa" "$pb" "$pc" || { show; false; }
  [ "$(starts A-)" = 4 ] && [ "$(starts B-)" = 3 ] || { show; false; }
  [ "$(peak)" = 1 ] || { echo "peak $(peak) with 2 cores (limit 1)"; show; false; }
}

@test "R181: a vbw run inside a unit's command, on the same store, takes no slot of its own and never waits for its parent" {
  fixture_copy b
  cores 2
  mkdir -p "$PROJECT/tests"
  printf 'cd "$OTHER" && "$VBW" check C1\n' > "$PROJECT/tests/nested.sh"
  machine_project "$PROJECT" A 0 0 "$(jq -c --argjson p "$(peek_check C2 "$CLAUDE_CONFIG_DIR/vbw/slots.json")" '. + $p' << 'JSON'
[{"id": "C1", "req": "R1", "run": ["sh", "tests/nested.sh"], "files": ["tests/nested.sh"]}]
JSON
)"
  run within 60 "$VBW" check C2 C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  [[ "$output" == *"C1 pass"* ]]
  [ "$(starts B-)" = 1 ]
  seen_store
}

@test "R181: a unit that waited reports what it would alone, and its timeout counts from its command's start" {
  cores 2
  machine_project "$OTHER" B 1 6
  machine_project "$PROJECT" A 0 0 '[{"id": "C1", "req": "R1", "run": ["sh", "tests/unit.sh", "A-ok", "1", "0"], "files": ["tests/unit.sh"], "timeout": 3},
    {"id": "C2", "req": "R1", "run": ["sh", "tests/unit.sh", "A-bad", "0", "3"], "files": ["tests/unit.sh"]}]'
  local alone shared pb
  run within 60 "$VBW" prove --full < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  alone=$(jq -c '.evidence.checks | map_values({status, exit, tail})' .vbw/record.json)
  [ "$alone" = '{"C1":{"status":"pass","exit":0,"tail":"unit A-ok done"},"C2":{"status":"fail","exit":3,"tail":"unit A-bad done"}}' ] || { echo "$alone"; false; }
  : > "$LOG"
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  pb=$BG_PID
  wait_starts 1 B-
  run within 60 "$VBW" prove --full < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; show; false; }
  shared=$(jq -c '.evidence.checks | map_values({status, exit, tail})' .vbw/record.json)
  [ "$shared" = "$alone" ] || { echo "alone: $alone"; echo "after waiting: $shared"; show; false; }
  # It did wait (longer than C1's timeout) for B's unit to end.
  [ "$(end_line B-C1)" -lt "$(start_line A-ok)" ] || { echo "A's units did not wait for the only slot"; show; false; }
  wait_ok "$pb" || { show; false; }
}

@test "R181: the store hands a free slot to the waiting run holding the fewest, ahead of an earlier waiter of a run that holds more" {
  sleep 120 & local ra=$!
  sleep 120 & local rb=$!
  # Run A holds two of three slots and has a unit waiting since before run B, which holds none.
  mkdir -p "$TEST_ROOT/store"
  jq -nc --argjson a "$ra" --argjson b "$rb" '{held: [{run: $a, id: "A1"}, {run: $a, id: "A2"}],
    waiting: [{run: $a, id: "A3", order: 1}, {run: $b, id: "B1", order: 2}], next: 3}' > "$TEST_ROOT/store/slots.json"
  # A step of a third party that changes nothing lets the store fill its free slot.
  # shellcheck disable=SC2016 # expanded by in_store
  run in_store 'SLOTS_LIMIT=3; slots_apply "$SLOTS_DROP" Z || exit 1; jq -c "[.held[].id]" "$SLOTS_FILE"'
  kill "$ra" "$rb"; wait "$ra" "$rb" 2> /dev/null || true
  [ "$status" -eq 0 ] && [ "$output" = '["A1","A2","B1"]' ] || { echo "$output"; cat "$TEST_ROOT/store/slots.json"; false; }
}
