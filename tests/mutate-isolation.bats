#!/usr/bin/env bats
# R188 (P139; docs/proof.md): a mutation check never leaks into parallel work
# and shares the machine like any other check run. While one Dev's break is
# being checked, another Dev of the same wave running vbw check on its own
# checks gets the result it gets with no break applied, and the broken file
# already holds its last commit. vbw mutate takes a slot of the computer-wide
# limit for each check it runs (waiting, and saying so, when none is free), and
# check_jobs caps how many of its checks run at once. The core count is read
# with getconf, nproc or sysctl from PATH; the tests put stand-ins first on PATH
# that report the count in $TEST_ROOT/cores. L1: the kernel on a fixture project.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  local bin="$TEST_ROOT/bin" tool
  mkdir -p "$bin"
  for tool in getconf nproc sysctl; do
    printf '#!/bin/sh\ncat "$TEST_ROOT/cores"\n' > "$bin/$tool"
    chmod +x "$bin/$tool"
  done
  PATH="$bin:$PATH"
  export PATH
  printf '8\n' > "$TEST_ROOT/cores"
  CONC="$TEST_ROOT/conc"
  mkdir -p "$CONC"
  export CONC
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf 'echo receipt\n' > src/receipt.sh
  # tests/hold.sh PATH: when PATH is given, say so (PATH.in) and wait for PATH to exist.
  cat > tests/hold.sh << 'SH'
[ -z "$1" ] || { : > "$1.in"; while [ ! -e "$1" ]; do sleep 0.1; done; }
SH
  # C1 holds only on a broken payment, so the break is being checked while it waits.
  cat > tests/pay.sh << 'SH'
out=$(sh src/pay.sh)
[ "$out" = paid ] || sh tests/hold.sh "${HOLD_PAY:-}"
[ "$out" = paid ]
SH
  # C3: each run registers itself, notes how many run at once, waits, leaves.
  cat > tests/pay-conc.sh << 'SH'
touch "$CONC/run.$$"
ls "$CONC" | grep -c '^run\.' >> "$CONC/seen"
sleep 0.4
rm -f "$CONC/run.$$"
[ "$(sh src/pay.sh)" = paid ]
SH
  # C2, another plan's check, reads the payment too: a leaked break would fail it.
  cat > tests/receipt.sh << 'SH'
sh tests/hold.sh "${HOLD_RECEIPT:-}"
[ "$(sh src/pay.sh)" = paid ] && [ "$(sh src/receipt.sh)" = receipt ]
SH
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1", "R2"], goal: "g", criteria: ["c"], tier: "deep"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.sh"], after: [], role: "dev", tasks: ["receipt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh", "tests/hold.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh", "tests/hold.sh"]},
             {id: "C3", req: "R1", run: ["sh", "tests/pay-conc.sh"], files: ["tests/pay-conc.sh"]},
             {id: "C4", req: "R1", run: ["sh", "tests/pay-conc.sh"], files: ["tests/pay-conc.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R1", text: "paying is quick", check: "C3"},
            {req: "R1", text: "paying is quick twice", check: "C4"},
            {req: "R2", text: "a receipt is printed", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  "$VBW" config set check_jobs 4 > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown_file() { fixture_teardown; }

teardown() {
  # Release anything still waiting, so no runner outlives the test.
  : > "$TEST_ROOT/go-pay"
  : > "$TEST_ROOT/go-receipt"
  wait 2> /dev/null || true
  vbw_teardown
}

breaks() { jq -c '[.plans[] | select(.id == "P1.1") | .mutations // [] | .[]]' .vbw/record.json; }
# appears FILE PID: wait up to 60 seconds for FILE to exist while process PID runs.
appears() {
  local i=0
  while [ ! -e "$1" ]; do
    kill -0 "$2" 2> /dev/null || { echo "ended before $1 appeared"; return 1; }
    i=$((i + 1))
    [ "$i" -lt 600 ] || { echo "$1 never appeared"; return 1; }
    sleep 0.1
  done
}

@test "R188 R265: while a break is being checked, the verdict comes from the set-aside bytes and the working copy holds the break the whole time, so another Dev's vbw check of a test that reads that file sees the break" {
  local pid
  printf 'echo unpaid\n' > src/pay.sh
  HOLD_PAY="$TEST_ROOT/go-pay" "$VBW" mutate P1.1 R1.1 "prints unpaid" src/pay.sh < /dev/null > "$TEST_ROOT/mutate.out" 2>&1 &
  pid=$!
  appears "$TEST_ROOT/go-pay.in" "$pid" || { cat "$TEST_ROOT/mutate.out"; false; }
  # The break is being checked now, on the set-aside bytes: the working copy keeps the break.
  [ "$(cat src/pay.sh)" = "echo unpaid" ] || { echo "the working copy was changed: $(cat src/pay.sh)"; false; }
  run "$VBW" check C2 < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"C2 fail"* ]] || { echo "$output"; false; }
  : > "$TEST_ROOT/go-pay"
  wait "$pid" || { cat "$TEST_ROOT/mutate.out"; false; }
  breaks | jq -e '.[0].result == "red" and .[0].checks == {C1: "red"}' || { breaks; cat "$TEST_ROOT/mutate.out"; false; }
  [ "$(cat src/pay.sh)" = "echo unpaid" ] || { echo "the working copy was changed after the run: $(cat src/pay.sh)"; false; }
}

@test "R188: a mutation check takes machine slots: with the computer-wide limit taken, it waits its turn and says so" {
  local holder pid
  local other="$TEST_ROOT/other" store="$CLAUDE_CONFIG_DIR/vbw/slots.json" i=0
  # 2 cores: the computer-wide limit is 1 slot, held by a check of another project (another
  # run of the same project would hold the mutation check at the project's own gate instead).
  printf '2\n' > "$TEST_ROOT/cores"
  git clone -q . "$other"
  (cd "$other" && "$VBW" approve > /dev/null)
  (cd "$other" && HOLD_RECEIPT="$TEST_ROOT/go-receipt" exec "$VBW" check C2 < /dev/null > "$TEST_ROOT/check.out" 2>&1) &
  holder=$!
  appears "$TEST_ROOT/go-receipt.in" "$holder" || { cat "$TEST_ROOT/check.out"; false; }
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 task1 --check C3 "prints unpaid" src/pay.sh < /dev/null > "$TEST_ROOT/mutate.out" 2>&1 &
  pid=$!
  # It waits its turn once the store lists it as a waiter (a fixed sleep lost the race on a busy machine).
  until jq -e --argjson p "$pid" 'any(.waiting[]; .run == $p)' "$store" > /dev/null 2>&1; do
    kill -0 "$pid" 2> /dev/null || { echo "the mutation check did not wait for a slot"; cat "$TEST_ROOT/mutate.out"; false; }
    i=$((i + 1))
    [ "$i" -lt 600 ] || { echo "the mutation check never waited for a slot"; cat "$store"; false; }
    sleep 0.1
  done
  [ ! -s "$CONC/seen" ] || { echo "its check ran beside the held slot"; false; }
  : > "$TEST_ROOT/go-receipt"
  wait "$holder" || true
  wait "$pid" || { cat "$TEST_ROOT/mutate.out"; false; }
  grep -q 'waited' "$TEST_ROOT/mutate.out" || { cat "$TEST_ROOT/mutate.out"; false; }
  breaks | jq -e '.[0].result == "red"' || { breaks; false; }
}

@test "R188: check_jobs caps how many of a mutation check's checks run at once" {
  "$VBW" config set check_jobs 1 > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 --check C3 --check C4 "prints unpaid" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(sort -n "$CONC/seen" | tail -n 1)" = 1 ] || { cat "$CONC/seen"; false; }
  breaks | jq -e '.[0].checks == {C3: "red"}' || { breaks; false; }
}
