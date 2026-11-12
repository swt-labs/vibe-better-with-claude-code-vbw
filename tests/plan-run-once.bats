#!/usr/bin/env bats
# R293 (field report 2026-11-11, docs/workflows.md): one kernel run per plan at a time.
# While a vbw plan done of a plan runs, a second vbw plan done of the same plan refuses at
# once, before any check runs: it names the running one's process id and the clock time it
# started (HH:MM, as the 'since HH:MM' wait line words it), tells to wait for that run and
# never start a second one (a Next: line), and leaves nothing at the check gate. A second
# vbw mutate PLAN --run of the same plan refuses the same way, its refusal naming the start
# time too. A plan done of another plan runs as before. A marker left by a process killed
# outright never refuses: the next run takes it over. The marker is given back however a run
# ends (passed, failed or interrupted). L1: the kernel on a two-plan fixture whose check C1
# can be held while it runs (R293_BAR/hold, released by R293_BAR/go).

load helper
load fixture-helper

shop() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo unpaid\n' > src/pay.sh
  printf 'echo unsent\n' > src/receipt.sh
  # C1 logs each run in R293_BAR/runs; with R293_BAR/hold it marks R293_BAR/started and
  # waits (up to 30 s) for R293_BAR/go; with R293_BAR/red it fails.
  cat > tests/pay.sh << 'SH'
if [ -n "${R293_BAR:-}" ]; then
  echo run >> "$R293_BAR/runs"
  if [ -f "$R293_BAR/hold" ]; then
    : > "$R293_BAR/started"
    i=0
    while [ ! -f "$R293_BAR/go" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
  fi
  [ ! -f "$R293_BAR/red" ] || exit 1
fi
[ "$(sh src/pay.sh)" = paid ]
SH
  printf '[ "$(sh src/receipt.sh)" = sent ]\n' > tests/receipt.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "pay", criteria: ["pays"], tier: "standard"},
                    {id: "P2", title: "Receipt", reqs: ["R2"], goal: "receipt", criteria: ["sends"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P2.1", phase: "P2", title: "Receipt", reqs: ["R2"], files: ["src/receipt.sh"], after: [], role: "dev", tasks: ["send"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]}],
    rules: [{req: "R1", text: "paid is printed", check: "C1"}, {req: "R2", text: "sent is printed", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  "$VBW" config set check_jobs 2 > /dev/null
  printf 'echo paid\n' > src/pay.sh
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  printf 'echo sent\n' > src/receipt.sh
  "$VBW" commit P2.1 "feat(receipt): send" > /dev/null
}

setup_file() { fixture_build shop shop; }
setup() {
  fixture_copy shop
  export TZ=Europe/Lisbon
  export R293_BAR="$TEST_ROOT/bar"
  mkdir -p "$R293_BAR"
  RUN1=
}
teardown() {
  touch "$R293_BAR/go" 2> /dev/null || true
  [ -z "${RUN1:-}" ] || wait "$RUN1" 2> /dev/null || true
  vbw_teardown
}
teardown_file() { fixture_teardown; }

# wait_for FILE: wait (up to 30 s) until FILE exists.
wait_for() {
  local i
  for ((i = 0; i < 300; i++)); do [ -e "$1" ] && return 0; sleep 0.1; done
  echo "never appeared: $1"
  return 1
}
runs() { [ -f "$R293_BAR/runs" ] && wc -l < "$R293_BAR/runs" | tr -d ' ' || echo 0; }
# held_start ARGS...: vbw ARGS in the background while C1 is held; RUN1 is its pid, T0 the
# clock time (HH:MM) just before it started.
held_start() {
  touch "$R293_BAR/hold"
  T0=$(date +%H:%M)
  "$VBW" "$@" > "$TEST_ROOT/run1.out" 2>&1 < /dev/null 3>&- &
  RUN1=$!
  wait_for "$R293_BAR/started" || { cat "$TEST_ROOT/run1.out"; return 1; }
}
# refused_naming_run1: the last run was refused at once naming RUN1's pid and the time it
# started (T0, or the minute after when the clock turned), with a Next: line to wait.
refused_naming_run1() {
  local t1 first
  t1=$(date +%H:%M)
  [ "$status" -ne 0 ] || { echo "not refused: $output"; return 1; }
  first=$(printf '%s\n' "$output" | head -n 1)
  [[ "$first" == "vbw: "*"$RUN1"* ]] || { echo "the refusal does not name pid $RUN1: $output"; return 1; }
  [[ "$first" =~ (^|[^0-9])($T0|$t1)([^0-9]|$) ]] || { echo "the refusal does not name the start time ($T0): $output"; return 1; }
  printf '%s\n' "$output" | grep -qE '^Next: wait' || { echo "no Next: line telling to wait: $output"; return 1; }
  printf '%s\n' "$output" | grep -qF 'never start a second' || { echo "the Next: line does not say never start a second one: $output"; return 1; }
}
# gate_only_run1: every registration at the check gate is RUN1's.
gate_only_run1() {
  local f
  for f in .vbw/runtime/gate/reg.* .vbw/runtime/gate/want.*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in reg."$RUN1".* | want."$RUN1".*) ;; *) echo "another registration at the gate: $f"; return 1 ;; esac
  done
}
# no_marker_of PID: no file under .vbw/runtime still names PID as its holder.
no_marker_of() {
  ! grep -rlx -- "$1" .vbw/runtime 2> /dev/null || { echo "a marker still names $1: $(grep -rlx -- "$1" .vbw/runtime)"; return 1; }
}

@test "R293 plan done: a second plan done of the same plan, while one runs, refuses at once naming its pid and start time, runs no check and registers nothing at the gate" {
  held_start plan "done" P1.1
  run "$VBW" plan "done" P1.1 < /dev/null
  refused_naming_run1
  [ "$(runs)" -eq 1 ] || { echo "a check ran for the second plan done: $(runs) runs"; false; }
  gate_only_run1
  touch "$R293_BAR/go"
  wait "$RUN1" || { cat "$TEST_ROOT/run1.out"; false; }
  RUN1=
}

@test "R293 plan done: a plan done of another plan, while one runs, is not refused and runs normally" {
  held_start plan "done" P1.1
  run "$VBW" plan "done" P2.1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"P2.1 done"* ]] || { echo "$output"; false; }
  touch "$R293_BAR/go"
  wait "$RUN1" || { cat "$TEST_ROOT/run1.out"; false; }
  RUN1=
}

@test "R293 plan done: the marker is given back when a run passes, fails or is interrupted, so the next run is not refused" {
  # Passed.
  held_start plan "done" P1.1
  local pid=$RUN1
  touch "$R293_BAR/go"
  wait "$RUN1" || { cat "$TEST_ROOT/run1.out"; false; }
  RUN1=
  no_marker_of "$pid"
  # Failed.
  rm -f "$R293_BAR/go" "$R293_BAR/started"
  touch "$R293_BAR/red"
  held_start plan "done" P1.1
  pid=$RUN1
  touch "$R293_BAR/go"
  ! wait "$RUN1" || { echo "plan done passed with C1 red"; cat "$TEST_ROOT/run1.out"; false; }
  RUN1=
  no_marker_of "$pid"
  # Interrupted.
  rm -f "$R293_BAR/go" "$R293_BAR/started" "$R293_BAR/red"
  held_start plan "done" P1.1
  pid=$RUN1
  kill -TERM "$RUN1"
  wait "$RUN1" || true
  RUN1=
  no_marker_of "$pid"
  touch "$R293_BAR/go"
  rm -f "$R293_BAR/hold"
  run "$VBW" plan "done" P1.1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"P1.1 done"* ]] || { echo "$output"; false; }
}

@test "R293 plan done: a marker left by a process killed outright never refuses: the next plan done takes it over and runs" {
  held_start plan "done" P1.1
  kill -KILL "$RUN1"
  wait "$RUN1" 2> /dev/null || true
  RUN1=
  touch "$R293_BAR/go"
  rm -f "$R293_BAR/hold"
  run "$VBW" plan "done" P1.1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"P1.1 done"* ]] || { echo "$output"; false; }
}

# The mutate side: P1.1 is built in an open build run, with one break queued.
queue_one() {
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 --queue "prints unpaid" src/pay.sh > /dev/null < /dev/null
  git checkout -q -- src/pay.sh
}

@test "R293 mutate: a second --run of the same plan, while one runs, refuses naming its pid and the time it started, with the Next: line to wait" {
  queue_one
  held_start mutate P1.1 --run
  run "$VBW" mutate P1.1 --run < /dev/null
  refused_naming_run1
  [[ "$output" == *"vbw mutate P1.1 --run"* ]] || { echo "$output"; false; }
  [ "$(runs)" -eq 1 ] || { echo "a check ran for the second --run: $(runs) runs"; false; }
  touch "$R293_BAR/go"
  wait "$RUN1" || { cat "$TEST_ROOT/run1.out"; false; }
  RUN1=
}

@test "R293 mutate: a --run killed outright leaves a marker that never refuses: the next --run takes it over and runs the break" {
  queue_one
  held_start mutate P1.1 --run
  kill -KILL "$RUN1"
  wait "$RUN1" 2> /dev/null || true
  RUN1=
  touch "$R293_BAR/go"
  rm -f "$R293_BAR/hold"
  run "$VBW" mutate P1.1 --run < /dev/null
  [[ "$output" != *"still running"* ]] || { echo "$output"; false; }
  [[ "$output" == *"R1.1 red: prints unpaid"* ]] || { echo "$output"; false; }
}
