#!/usr/bin/env bats
# R94 (docs/proof.md): in one proof, a check waiting for an alone check keeps
# waiting as long as that check is still running; a proof never aborts because a
# check waited. A check that cannot run is reported as not run (status skipped,
# the reason in its tail) and counts as not passed; every other result stands;
# the proof prints no shell job warnings, in bash 3.2 and bash 5. L1: fixtures
# whose checks mark when they start and end.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  MARK="$TEST_ROOT/mark"
  mkdir -p "$MARK"
  export MARK
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  # alone.sh: the long alone check; it marks its end.
  cat > tests/alone.sh << 'SH'
touch "$MARK/alone.start"
sleep "${NAP:-6}"
touch "$MARK/alone.end"
SH
  # shared.sh: a quick check that must run after the alone check has ended.
  cat > tests/shared.sh << 'SH'
touch "$MARK/shared.$$"
[ -e "$MARK/alone.end" ]
SH
  # quick.sh: ends at once.
  printf 'true\n' > tests/quick.sh
  # killrunner.sh: kills the runner vbw prove started for this check (the
  # ancestor just below the process that holds all runners), so the check ends
  # without a result.
  cat > tests/killrunner.sh << 'SH'
for i in $(seq 1 50); do [ -s "$MARK/main" ] && break; sleep 0.1; done
main=$(cat "$MARK/main")
p=$$
prev=
while :; do
  pp=$(ps -o ppid= -p "$p" | tr -d ' ')
  [ -n "$pp" ] || exit 0
  [ "$pp" != "$main" ] || break
  prev=$p
  p=$pp
done
[ -z "$prev" ] || kill -9 "$prev"
sleep 1
SH
}

teardown() {
  wait 2> /dev/null || true
  vbw_teardown
}

# project CHECKS_JSON: approve a record with these checks (each on R1).
project() {
  jq --argjson c "$1" '.checks = $c
    | .schema = (if any($c[]; .alone) then 2 else 1 end)
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules)' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A > /dev/null
  git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

check() { printf '{"id":"%s","req":"R1","run":["sh","tests/%s.sh"],"files":["tests/%s.sh"]%s}' "$1" "$2" "$2" "${3:-}"; }

noise() {
  [[ "$1" != *"did not finish"* ]] && [[ "$1" != *"waited"* ]] && [[ "$1" != *"not a child"* ]] \
    && [[ "$1" != *"Killed"* ]] && [[ "$1" != *"wait:"* ]] && ! printf '%s\n' "$1" | grep -qE 'line [0-9]+:'
}

@test "R94: shared checks wait for a long alone check beyond any time limit, then run and report; the proof prints no warning" {
  project "[$(check C1 alone ',"alone":true'), $(check C2 shared), $(check C3 shared), $(check C4 shared)]"
  VBW_CHECK_WAIT_SECONDS=2 vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.passed == true and (.evidence.checks | map(.status) | unique == ["pass"])' .vbw/record.json
  noise "$output" || { echo "$output"; false; }
  [ -e "$MARK/alone.end" ]
}

@test "R94: the wait setting VBW_CHECK_WAIT_SECONDS is gone from the code and the docs no longer say it ends a wait" {
  if grep -rq 'VBW_CHECK_WAIT_SECONDS' "$PLUGIN_ROOT"; then false; fi
  if grep -qE 'waits at most|at most 900' "$REPO_ROOT/docs/proof.md"; then false; fi
  ! grep -n 'VBW_CHECK_WAIT_SECONDS' "$REPO_ROOT/docs/proof.md" | grep -vi 'no longer'
}

@test "R94: when the holder dies a waiting check takes over the gate and runs, with no time limit ending its wait first" {
  project "[$(check C1 alone ',"alone":true'), $(check C2 quick)]"
  NAP=12 "$VBW" check C1 > "$TEST_ROOT/o1" 2>&1 < /dev/null 3>&- &
  local holder=$! i
  for i in $(seq 1 100); do [ -e "$MARK/alone.start" ] && break; sleep 0.1; done
  [ -e "$MARK/alone.start" ]
  VBW_CHECK_WAIT_SECONDS=1 "$VBW" check C2 > "$TEST_ROOT/o2" 2>&1 < /dev/null 3>&- &
  local waiter=$!
  sleep 3
  # Still waiting after the old limit, while the holder is alive.
  kill -0 "$waiter"
  kill -9 "$holder"
  wait "$holder" 2> /dev/null || true
  local code=0
  wait "$waiter" || code=$?
  [ "$code" -eq 0 ] || { cat "$TEST_ROOT/o2"; false; }
  grep -q 'C2 pass' "$TEST_ROOT/o2"
  noise "$(cat "$TEST_ROOT/o2")" || { cat "$TEST_ROOT/o2"; false; }
}

@test "R94: a check whose runner ends without a result is reported not run with the reason; every other result stands; the proof fails without dying" {
  project "[$(check C1 quick), $(check C2 killrunner), $(check C3 quick)]"
  "$VBW" prove > "$TEST_ROOT/out" 2>&1 < /dev/null 3>&- &
  local pid=$!
  printf '%s\n' "$pid" > "$MARK/main"
  local code=0
  wait "$pid" || code=$?
  local out
  out=$(cat "$TEST_ROOT/out")
  [ "$code" -eq 1 ] || { echo "exit $code: $out"; false; }
  jq -e '.evidence.checks.C1.status == "pass" and .evidence.checks.C3.status == "pass"' .vbw/record.json
  jq -e '.evidence.checks.C2.status == "skipped" and (.evidence.checks.C2.tail | startswith("not run")) and (.evidence.checks.C2.tail | length) > 8' .vbw/record.json
  jq -e '.evidence.passed == false' .vbw/record.json
  [[ "$out" == *"C2 skipped"* ]]
  noise "$out" || { echo "$out"; false; }
}

@test "R94: many quick checks run a few at a time print no shell job warning, in bash 3.2 and bash 5" {
  local list="" n sh
  for n in $(seq 1 14); do list="$list$(check "C$n" quick),"; done
  project "[${list%,}]"
  "$VBW" config set check_jobs 2 > /dev/null
  for sh in /bin/bash "$(command -v bash)"; do
    run "$sh" "$VBW" prove
    [ "$status" -eq 0 ] || { echo "$sh: $output"; false; }
    noise "$output" || { echo "$sh: $output"; false; }
  done
}

@test "R94: an interrupt during a wait removes the wait registration and leaves no gate file behind" {
  project "[$(check C1 alone ',"alone":true'), $(check C2 quick)]"
  NAP=5 "$VBW" check C1 > "$TEST_ROOT/o1" 2>&1 < /dev/null 3>&- &
  local holder=$! i
  for i in $(seq 1 100); do [ -e "$MARK/alone.start" ] && break; sleep 0.1; done
  "$VBW" check C2 > "$TEST_ROOT/o2" 2>&1 < /dev/null 3>&- &
  local waiter=$!
  sleep 1
  kill -TERM "$waiter"
  wait "$waiter" 2> /dev/null || true
  wait "$holder" || true
  [ -z "$(find .vbw/runtime/gate -mindepth 1 2> /dev/null)" ]
}
