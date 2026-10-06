#!/usr/bin/env bats
# R45: a check marked alone never runs at the same time as another VBW check in
# the same project (docs/proof.md). Checks record their start and end times in
# a shared log; the tests compare the intervals.

load helper

setup() {
  vbw_setup
  export TIMES="$TEST_ROOT/times"
  mkdir -p "$TIMES" "$TEST_ROOT/bin" "$TEST_ROOT/tmp"
  : > "$TIMES/log"
  export TMPDIR="$TEST_ROOT/tmp"
  # mark.sh NAME SECONDS: log "PID NAME start|end TIME" around a sleep.
  cat > "$TEST_ROOT/bin/mark.sh" <<'SH'
#!/bin/sh
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
echo "$$ $1 start $(now)" >> "$TIMES/log"
sleep "$2"
echo "$$ $1 end $(now)" >> "$TIMES/log"
SH
  make_project "$PROJECT"
}

teardown() {
  wait 2> /dev/null || true
  vbw_teardown
}

# make_project DIR: a project with checks C1 (alone, 2s), C2 and C3 (2s, 1s) and
# C4 (3s), all approved. C5 times out alone; C6 sleeps alone.
make_project() {
  local mark="$TEST_ROOT/bin/mark.sh" plan
  mkdir -p "$1"
  cd "$1" || return 1
  [ -d .git ] || vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  plan=$(jq -n --arg m "$mark" '{phases: [{id: "P1", title: "Checkout", reqs: ["R1", "R2"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/a.txt"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/b.txt"], after: ["P1.1"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", $m, "C1", "2"], alone: true},
             {id: "C2", req: "R2", run: ["sh", $m, "C2", "2"]},
             {id: "C3", req: "R2", run: ["sh", $m, "C3", "1"]},
             {id: "C4", req: "R1", run: ["sh", $m, "C4", "3"]},
             {id: "C5", req: "R1", run: ["sleep", "30"], alone: true, timeout: 1},
             {id: "C6", req: "R1", run: ["sh", $m, "C6", "6"], alone: true},
             {id: "C7", req: "R2", run: ["sh", $m, "C7", "6"]}]}')
  printf '%s' "$plan" | "$VBW" apply > /dev/null
  git add -A > /dev/null && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

# bg OUTFILE ARGS...: run vbw in the background (not holding bats' descriptor).
bg() {
  local out="$1"
  shift
  "$VBW" "$@" > "$out" 2>&1 < /dev/null 3>&- &
  BG_PID=$!
}

# started NAME: wait (up to 10 s) until a check logged its start.
started() {
  local i
  for i in $(seq 1 200); do
    grep -q " $1 start " "$TIMES/log" && return 0
    sleep 0.05
  done
  return 1
}

# t NAME KIND: the time of the first start/end line of a check.
t() { awk -v n="$1" -v k="$2" '$2 == n && $3 == k {print $4; exit}' "$TIMES/log"; }

# before A B: A is not later than B (floats).
before() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 <= b + 0) }'; }

# overlaps ALONE...: lists every pair of intervals (by process) that share time
# when one of them is a check named in ALONE.
overlaps() {
  awk -v alone=" $* " '
    $3 == "start" { s[$1] = $4; n[$1] = $2 }
    $3 == "end" { e[$1] = $4 }
    END { for (a in s) for (b in s) if (a < b && e[a] != "" && e[b] != "" \
            && (index(alone, " " n[a] " ") || index(alone, " " n[b] " ")) \
            && s[a] < e[b] && s[b] < e[a]) print n[a], n[b] }' "$TIMES/log"
}

@test "an alone check and another check started together never overlap" {
  bg "$TEST_ROOT/o1" check C1
  p1=$BG_PID
  bg "$TEST_ROOT/o2" check C2
  p2=$BG_PID
  wait "$p1"
  wait "$p2"
  grep -q "C1 pass" "$TEST_ROOT/o1"
  grep -q "C2 pass" "$TEST_ROOT/o2"
  [ -n "$(t C1 end)" ] && [ -n "$(t C2 end)" ]
  [ -z "$(overlaps C1)" ]
  before "$(t C1 end)" "$(t C2 start)" || before "$(t C2 end)" "$(t C1 start)"
}

@test "an alone check waits for a running check, and checks wait while it runs" {
  bg "$TEST_ROOT/o1" check C4
  started C4
  "$VBW" check C1 > /dev/null
  before "$(t C4 end)" "$(t C1 start)"
  wait
  bg "$TEST_ROOT/o2" check C1
  started C1
  "$VBW" check C3 > /dev/null
  before "$(t C1 end)" "$(t C3 start)"
  wait
}

@test "checks that are not alone still run in parallel, with unchanged output" {
  bg "$TEST_ROOT/o1" check C2
  p1=$BG_PID
  bg "$TEST_ROOT/o2" check C4
  p2=$BG_PID
  wait "$p1"
  wait "$p2"
  [ "$(t C4 start)" != "" ]
  awk -v a="$(t C2 start)" -v b="$(t C2 end)" -v c="$(t C4 start)" -v d="$(t C4 end)" 'BEGIN { exit !(a < d && c < b) }'
  grep -Eq '^C2 pass [0-9]+s$' "$TEST_ROOT/o1"
}

@test "vbw prove holds the exclusion too" {
  bg "$TEST_ROOT/o1" prove
  p1=$BG_PID
  bg "$TEST_ROOT/o2" check C4
  p2=$BG_PID
  wait "$p1" || true
  wait "$p2"
  [ -n "$(t C1 end)" ] && [ -n "$(t C4 end)" ]
  [ -z "$(overlaps C1)" ]
}

@test "the checks vbw fix done runs hold the exclusion too" {
  mkdir -p src
  printf 'a\n' > src/a.txt && printf 'b\n' > src/b.txt
  git add src && git commit -q -m "feat: built"
  jq '.checks |= map(select(.id | IN("C5", "C6", "C7") | not))
      | .plans[0].files = ["src/a.txt", "src/b.txt"] | .plans[].status = "done"
      | .fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "x"}]' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_consent_contract
  bg "$TEST_ROOT/o1" fix done F1
  p1=$BG_PID
  bg "$TEST_ROOT/o2" check C4
  p2=$BG_PID
  wait "$p1"
  wait "$p2"
  [ -n "$(t C1 end)" ] && [ -n "$(t C4 end)" ]
  [ -z "$(overlaps C1)" ]
}

@test "a check that times out while alone releases the exclusion" {
  vbw_run check C5
  [ "$status" -eq 1 ]
  [[ "$output" == *"C5 timeout"* ]]
  SECONDS=0
  VBW_CHECK_WAIT_SECONDS=3 vbw_run check C3
  # A held exclusion would make C3 fail after the 3 s limit, naming what it waited on.
  [ "$status" -eq 0 ]
  [[ "$output" != *"waited"* ]]
}

@test "a crashed vbw process leaves no lock that blocks later checks" {
  bg "$TEST_ROOT/o1" check C6
  started C6
  kill -9 "$BG_PID"
  wait "$BG_PID" 2> /dev/null || true
  SECONDS=0
  VBW_CHECK_WAIT_SECONDS=3 vbw_run check C3
  # A stale lock would make C3 fail after the 3 s limit, naming what it waited on.
  [ "$status" -eq 0 ]
  [[ "$output" == *"C3 pass"* ]]
  [[ "$output" != *"waited"* ]]
}

@test "a wait beyond the limit fails naming the check being waited on" {
  bg "$TEST_ROOT/o1" check C6
  started C6
  SECONDS=0
  VBW_CHECK_WAIT_SECONDS=2 vbw_run check C3
  [ "$status" -ne 0 ]
  [[ "$output" == *"C6"* ]]
  # The 2 s limit is honoured, not the 900 s default; the bound allows a loaded machine.
  [ "$SECONDS" -lt 60 ]
  wait
  bg "$TEST_ROOT/o2" check C7
  started C7
  VBW_CHECK_WAIT_SECONDS=2 vbw_run check C1
  [ "$status" -ne 0 ]
  [[ "$output" == *"C7"* ]]
  wait
}

@test "checks of two different projects do not block each other" {
  local other="$TEST_ROOT/other"
  make_project "$other"
  cd "$PROJECT" || return 1
  bg "$TEST_ROOT/o1" check C6
  started C6
  cd "$other" || return 1
  SECONDS=0
  VBW_CHECK_WAIT_SECONDS=3 vbw_run check C3
  [ "$status" -eq 0 ]
  [ "$SECONDS" -lt 5 ]
  wait
  before "$(t C3 end)" "$(t C6 end)"
}

@test "the exclusion lives under .vbw/runtime and nothing is written outside the project" {
  find "$HOME" "$TMPDIR" -type f > "$TEST_ROOT/outside-before"
  bg "$TEST_ROOT/o1" check C1
  started C1
  [ -n "$(find .vbw/runtime -mindepth 1 -not -name 'run.*' -not -name 'index.*' -not -name 'record.*')" ]
  wait
  [ -z "$(find "$TMPDIR" -mindepth 1)" ]
  find "$HOME" "$TMPDIR" -type f > "$TEST_ROOT/outside-after"
  cmp "$TEST_ROOT/outside-before" "$TEST_ROOT/outside-after"
}

@test "without an alone marker behaviour is unchanged: no waiting, no lock left behind" {
  jq 'del(.checks[].alone) | .schema = 1' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_consent_contract
  bg "$TEST_ROOT/o1" check C2
  p1=$BG_PID
  bg "$TEST_ROOT/o2" check C3
  p2=$BG_PID
  wait "$p1"
  wait "$p2"
  awk -v a="$(t C2 start)" -v b="$(t C2 end)" -v c="$(t C3 start)" -v d="$(t C3 end)" 'BEGIN { exit !(a < d && c < b) }'
}
