#!/usr/bin/env bats
# R166 (docs/proof.md): the runner of units in plugin/lib/checks.sh. A unit (a
# check, a project command, later a test file) takes a free slot copy; at most
# check_jobs run at a time, units marked alone run by themselves, the read
# lists of units running together stay apart, and a runner that dies leaves a
# "skipped" result instead of taking the proof down. The passes cache and the
# served-files fingerprint are gone. The runner keeps its places busy (T179):
# the units' launch data and their results take one jq pass each, never one
# per unit; a unit's copy and place are free as soon as its slot and gate
# place are given back, while it still writes its result; the launcher waits
# for a freed place on the runners' wake-up (a FIFO), never on a fixed pause,
# unless no FIFO can be made; each run of units keeps its results apart from
# an earlier run's. L1: units are small shell scripts.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  CONC="$TEST_ROOT/conc"
  mkdir -p "$CONC"
  export CONC
  # conc.sh: registers itself in $CONC and records how many are registered.
  cat > tests/conc.sh << 'SH'
touch "$CONC/run.$$"
ls "$CONC" | grep -c '^run\.' >> "$CONC/seen"
[ -z "$(ls "$CONC" | grep '^alone\.')" ] || echo "started beside an alone unit" >> "$CONC/violation"
sleep "${NAP:-0.6}"
rm -f "$CONC/run.$$"
SH
  cat > tests/alone.sh << 'SH'
touch "$CONC/run.$$" "$CONC/alone.$$"
n=$(ls "$CONC" | grep -c '^run\.')
[ "$n" -eq 1 ] || echo "alone unit ran beside $n" >> "$CONC/violation"
sleep 0.6
rm -f "$CONC/run.$$" "$CONC/alone.$$"
SH
  # reads.sh FILE: reads one project file, waits for its partner, then ends.
  cat > tests/reads.sh << 'SH'
cat "$1" > /dev/null
touch "$CONC/here.$(basename "$1")"
[ -n "$2" ] || exit 0
n=0
while [ "$(ls "$CONC" | grep -c '^here\.')" -lt 2 ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
SH
  git add src tests
  git commit -q -m "chore(test): units"
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# jobs N: set check_jobs.
jobs_set() { "$VBW" config set check_jobs "$1" > /dev/null; }

# lib SNIPPET: SNIPPET with the runner, the clean copies and the reads libraries loaded.
lib() {
  vbw_kernel 'set -u; . "$VBW_LIB/checks.sh"; . "$VBW_LIB/proofcopy.sh"; mkdir -p "$VBW_RUNTIME"
    CHECK_OUT=$(mktemp -d "$VBW_RUNTIME/run.XXXXXX"); CHECK_HELD=
    # unit NAME ALONE ARGV...: one unit as JSON.
    unit() { local n=$1 al=$2; shift 2; printf "%s\0" "$@" | jq -Rsc --arg n "$n" --argjson al "$al" "{name: \$n, out: (\$n + \".out\"), argv: (split(\"\\u0000\")[:-1]), timeout: 30, exit: 0, output: \"\", alone: \$al}"; }
    '"$1"
}

# peak: the most units registered together.
peak() { sort -n "$CONC/seen" | tail -1; }

# jq_counted: a jq first on PATH that counts its runs in $JQLOG, then runs the real one.
jq_counted() {
  JQLOG="$TEST_ROOT/jq.log"
  mkdir -p "$TEST_ROOT/jqbin"
  printf '#!/bin/sh\necho run >> "$JQLOG"\nexec "%s" "$@"\n' "$(command -v jq)" > "$TEST_ROOT/jqbin/jq"
  chmod +x "$TEST_ROOT/jqbin/jq"
  PATH="$TEST_ROOT/jqbin:$PATH"
  export JQLOG PATH
}

# jq_runs_for N: the jq processes checks_run_all takes for a record of N passing checks.
jq_runs_for() {
  # shellcheck disable=SC2016 # expanded by lib
  lib 'rec=$(jq -nc --argjson n '"$1"' "{checks: [range(1; \$n + 1) | {id: \"C\(.)\", req: \"R1\", run: [\"true\"]}]}")
    : > "$JQLOG"; checks_run_all "$rec" > "$CONC/res.json"; wc -l < "$JQLOG" | tr -d " "'
}

# paused BODY: run BODY with the runner library, sleep counted: "launcher N" (pauses of
# the launcher, this shell itself) and "results" (the statuses of $CONC/res).
paused() {
  # shellcheck disable=SC2016 # expanded by lib
  lib ': > "$CONC/pauses"; sleep() { sh -c "echo \$PPID" >> "$CONC/pauses"; command sleep "$@"; }
    '"$1"'
    echo "launcher $(grep -cx "$$" "$CONC/pauses" 2> /dev/null || true)"
    jq -r "[.[] | .status] | join(\",\")" "$CONC/res"'
}

@test "R166: at most check_jobs units run together, and they do run together" {
  jobs_set 2
  run lib 'units=$(jq -sc . <(for i in 1 2 3 4 5 6; do unit U$i false sh tests/conc.sh; done))
    checks_run_units "$units" | jq -r "[.[] | .status] | join(\",\")"'
  [ "$status" -eq 0 ]
  [ "$output" = "pass,pass,pass,pass,pass,pass" ]
  [ "$(wc -l < "$CONC/seen" | tr -d ' ')" -eq 6 ]
  [ "$(peak)" -eq 2 ]
}

@test "R166: with slot copies at most as many units run together as there are copies" {
  jobs_set 4
  run lib 'proofcopy_create_slots 2
    units=$(jq -sc . <(for i in 1 2 3 4 5; do unit U$i false sh tests/conc.sh; done))
    checks_run_units "$units" | jq -r "[.[] | .status] | join(\",\")"; proofcopy_remove'
  [ "$status" -eq 0 ]
  [ "$output" = "pass,pass,pass,pass,pass" ]
  [ "$(peak)" -eq 2 ]
}

@test "R166: an alone unit runs by itself and the others still run together" {
  jobs_set 3
  run lib 'units=$(jq -sc . <(unit A true sh tests/alone.sh; unit U1 false sh tests/conc.sh; unit U2 false sh tests/conc.sh; unit U3 false sh tests/conc.sh))
    checks_run_units "$units" | jq -r "[.[] | .status] | join(\",\")"'
  [ "$status" -eq 0 ]
  [ "$output" = "pass,pass,pass,pass" ]
  [ ! -e "$CONC/violation" ] || { cat "$CONC/violation"; false; }
  [ "$(peak)" -ge 2 ]
}

@test "R166: an alone unit stays alone when it runs in a slot copy" {
  jobs_set 3
  run lib 'proofcopy_create_slots 3
    units=$(jq -sc . <(unit U1 false sh tests/conc.sh; unit A true sh tests/alone.sh; unit U2 false sh tests/conc.sh))
    checks_run_units "$units" | jq -r "[.[] | .status] | join(\",\")"; proofcopy_remove'
  [ "$status" -eq 0 ]
  [ "$output" = "pass,pass,pass" ]
  [ ! -e "$CONC/violation" ] || { cat "$CONC/violation"; false; }
}

@test "R166: read lists of units running together in two copies stay apart" {
  jobs_set 2
  run lib 'proofcopy_create_slots 2
    units=$(jq -sc . <(unit RA false sh tests/reads.sh src/a.txt wait; unit RB false sh tests/reads.sh src/b.txt wait))
    checks_run_units "$units" | jq -c "{a: .RA.reads.files, b: .RB.reads.files, sa: .RA.status, sb: .RB.status}"; proofcopy_remove'
  [ "$status" -eq 0 ]
  # They really ran together (each waited for the other's marker).
  [ "$(ls "$CONC" | grep -c '^here\.')" -eq 2 ]
  [ "$(printf '%s' "$output" | jq -r '[.sa, .sb] | join(",")')" = "pass,pass" ]
  printf '%s' "$output" | jq -e '(.a | index("src/a.txt")) != null and (.a | index("src/b.txt")) == null
    and (.b | index("src/b.txt")) != null and (.b | index("src/a.txt")) == null' > /dev/null
}

@test "R166: units after one another in one copy get a list each, not the earlier one's" {
  jobs_set 1
  run lib 'proofcopy_create_slots 1
    units=$(jq -sc . <(unit RA false sh tests/reads.sh src/a.txt; unit RB false sh tests/reads.sh src/b.txt))
    checks_run_units "$units" | jq -c "{a: .RA.reads.files, b: .RB.reads.files}"; proofcopy_remove'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '(.a | index("src/a.txt")) != null and (.a | index("src/b.txt")) == null
    and (.b | index("src/b.txt")) != null and (.b | index("src/a.txt")) == null' > /dev/null
}

@test "R166: without slot copies a unit runs where the caller is and carries no read list" {
  jobs_set 2
  run lib 'checks_run_units "$(jq -sc . <(unit U1 false sh -c "pwd > $CONC/cwd"; unit U2 false true))" | jq -c "[.[] | has(\"reads\")]"'
  [ "$status" -eq 0 ]
  [ "$output" = "[false,false]" ]
  [ "$(cat "$CONC/cwd")" = "$(pwd -P)" ] || [ "$(cat "$CONC/cwd")" = "$PWD" ]
}

@test "R166: a unit in a slot copy runs inside that copy" {
  jobs_set 1
  run lib 'proofcopy_create_slots 1
    checks_run_units "$(jq -sc . <(unit U1 false sh -c "pwd > $CONC/cwd"))" > /dev/null; printf "%s\n" "$PROOF_COPY" > "$CONC/copy"; proofcopy_remove'
  [ "$status" -eq 0 ]
  [ "$(basename "$(cat "$CONC/cwd")")" = tree ]
  [[ "$(cat "$CONC/cwd")" == *"$(basename "$(dirname "$(cat "$CONC/copy")")")"* ]]
}

@test "R166: a failing unit and a timed out unit report their status and carry their read lists" {
  jobs_set 2
  run lib 'proofcopy_create_slots 2
    u2=$(unit T false sleep 30 | jq -c ".timeout = 1")
    checks_run_units "$(jq -sc . <(unit F false sh -c "cat src/a.txt; exit 3"; printf "%s\n" "$u2"))" | jq -c "{f: .F.status, fe: .F.exit, t: .T.status, fr: (.F.reads.files | index(\"src/a.txt\") != null), tr: (.T.reads != null)}"; proofcopy_remove'
  [ "$status" -eq 0 ]
  [ "$output" = '{"f":"fail","fe":3,"t":"timeout","fr":true,"tr":true}' ]
}

@test "R166: a runner that dies without a result leaves a skipped result and the others finish (in parallel)" {
  jobs_set 3
  run lib 'eval "real_$(declare -f checks_exec)"
    checks_exec() { case "$2" in *DIE.out) sh -c "kill -9 \$PPID" ;; esac; real_checks_exec "$@"; }
    checks_run_units "$(jq -sc . <(unit U1 false true; unit DIE false true; unit U3 false true))" | jq -c "[.U1.status, .DIE.status, .U3.status, (.DIE.tail | test(\"ended without a result\"))]"'
  [ "$status" -eq 0 ]
  [ "$output" = '["pass","skipped","pass",true]' ]
}

@test "R166: a runner that dies without a result leaves a skipped result (one at a time)" {
  jobs_set 1
  run lib 'eval "real_$(declare -f checks_exec)"
    checks_exec() { case "$2" in *DIE.out) sh -c "kill -9 \$PPID" ;; esac; real_checks_exec "$@"; }
    checks_run_units "$(jq -sc . <(unit DIE false true; unit U2 false true))" | jq -c "[.DIE.status, .U2.status]"'
  [ "$status" -eq 0 ]
  [ "$output" = '["skipped","pass"]' ]
}

@test "R166: a runner that dies in a slot copy leaves a skipped result and frees the copy" {
  jobs_set 2
  run lib 'proofcopy_create_slots 1
    eval "real_$(declare -f checks_exec)"
    checks_exec() { case "$2" in *DIE.out) sh -c "kill -9 \$PPID" ;; esac; real_checks_exec "$@"; }
    checks_run_units "$(jq -sc . <(unit DIE false true; unit U2 false true))" | jq -c "[.DIE.status, .U2.status]"; proofcopy_remove'
  [ "$status" -eq 0 ]
  [ "$output" = '["skipped","pass"]' ]
}

@test "R166: a second run of units in the same output folder never takes the result of an earlier run's runner for one that died" {
  jobs_set 2
  run lib 'eval "real_$(declare -f checks_exec)"
    checks_exec() { case "$2" in *DIE.out) sh -c "kill -9 \$PPID" ;; esac; real_checks_exec "$@"; }
    checks_run_units "$(jq -sc . <(unit P1 false true; unit P2 false true))" > /dev/null
    checks_run_units "$(jq -sc . <(unit DIE false true; unit Q false true))" | jq -c "[.DIE.status, .Q.status]"'
  [ "$status" -eq 0 ]
  [ "$output" = '["skipped","pass"]' ]
}

@test "T179: the runner's own steps take no jq process per unit: only each unit's result is one" {
  jobs_set 2
  jq_counted
  local two eight
  two=$(jq_runs_for 2)
  eight=$(jq_runs_for 8)
  jq -e 'length == 8 and all(.[]; .status == "pass")' "$CONC/res.json" || { cat "$CONC/res.json"; false; }
  # Six checks more: at most six jq runs more (each one's result object).
  [ $((eight - two)) -le 6 ] || { echo "2 checks took $two jq runs, 8 checks $eight"; false; }
}

@test "T179: a unit's copy and place are free once its slot and gate place are given back: the next unit starts while the finished ones still write their results" {
  jobs_set 2
  run lib 'proofcopy_create_slots 2
    eval "real_$(declare -f checks_result)"
    # W1 and W2 write their results only once N3 has started (or after about 10 s).
    checks_result() { local i=0; case "$1" in */W*.out)
        while [ ! -e "$CONC/n3" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
        if [ -e "$CONC/n3" ]; then echo saw >> "$CONC/w.log"; else echo "never saw" >> "$CONC/w.log"; fi ;; esac
      real_checks_result "$@"; }
    units=$(jq -sc . <(unit W1 false true; unit W2 false true; unit N3 false sh -c "touch \"\$CONC/n3\""))
    checks_run_units "$units" | jq -r "[.[] | .status] | join(\",\")"; proofcopy_remove'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "pass,pass,pass" ]
  [ "$(cat "$CONC/w.log")" = "$(printf 'saw\nsaw')" ] || { cat "$CONC/w.log"; false; }
}

@test "T179: the launcher waits for a freed place on the runners' wake-up, never on a fixed pause; where no FIFO can be made it pauses and every unit still runs" {
  jobs_set 2
  local body='units=$(jq -sc . <(for i in 1 2 3 4 5; do unit U$i false sh tests/conc.sh; done))
    checks_run_units "$units" > "$CONC/res"'
  NAP=0.3 run paused "$body"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$(printf 'launcher 0\npass,pass,pass,pass,pass')" ] || { echo "$output"; false; }
  [ "$(peak)" -eq 2 ]
  # Without a FIFO (mkfifo fails) the launcher looks again after a short pause.
  mkdir -p "$TEST_ROOT/nofifo"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_ROOT/nofifo/mkfifo"
  chmod +x "$TEST_ROOT/nofifo/mkfifo"
  rm -f "$CONC/seen"
  PATH="$TEST_ROOT/nofifo:$PATH" NAP=0.3 run paused "$body"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "${lines[0]}" =~ ^launcher\ [1-9][0-9]*$ ]] || { echo "$output"; false; }
  [ "${lines[1]}" = pass,pass,pass,pass,pass ] || { echo "$output"; false; }
  [ "$(peak)" -eq 2 ]
}

@test "R166: checks_run_all runs the checks of a record in order and reports a held check as waiting" {
  jobs_set 2
  run lib 'rec=$(jq -nc "{checks: [{id: \"C1\", req: \"R1\", run: [\"true\"]}, {id: \"C2\", req: \"R1\", run: [\"false\"]}, {id: \"C3\", req: \"R1\", run: [\"true\"]}]}")
    CHECK_HELD=C3
    checks_run_all "$rec" | jq -c "[to_entries[] | \"\(.key) \(.value.status)\"]"'
  [ "$status" -eq 0 ]
  [ "$output" = '["C1 pass","C2 fail","C3 waiting"]' ]
}

@test "R166: the passes cache and the served-files fingerprint are gone from the runner" {
  run grep -En 'checks_unchanged|checks_record_passes|checks_passes_file|checks_served|checks_fingerprint|checks_served_dirty|passes\.json' "$PLUGIN_ROOT/lib/checks.sh"
  [ "$status" -ne 0 ]
}

@test "R166: vbw check runs in the working folder and records nothing" {
  printf '%s' "$(jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/b.txt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "-c", "pwd > conc-cwd"], files: ["src/a.txt"]}]}')" > "$TEST_ROOT/plan.json"
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" apply < "$TEST_ROOT/plan.json" > /dev/null
  git add -A > /dev/null && git commit -q -m "chore(vbw): plan" || true
  "$VBW" approve > /dev/null
  git add -A > /dev/null && git commit -q -m "chore(vbw): approved" || true
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  run "$VBW" check C1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "C1 pass"* ]]
  [ "$(cat conc-cwd)" = "$(pwd -P)" ] || [ "$(cat conc-cwd)" = "$PWD" ]
  [ ! -e "$common/vbw/passes.json" ]
  [ ! -e "$common/vbw/runs.json" ]
  rm -f conc-cwd
}
