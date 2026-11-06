#!/usr/bin/env bats
# R147 (docs/proof.md): with no check_jobs setting, VBW runs at most three
# quarters of the machine's processor cores' worth of checks at once, rounded
# down, at least 1 and at most 64; a core count it cannot read means 1. The
# check_jobs setting (1 to 64) still overrides it, default returns to it, and
# vbw config shows the value in use and where it comes from. The core count is
# read with getconf, nproc or sysctl from PATH; the tests put stand-ins first
# on PATH that report the count in $TEST_ROOT/cores ("none": they fail). L1.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  local bin="$TEST_ROOT/bin" tool
  mkdir -p "$bin"
  for tool in getconf nproc sysctl; do
    cat > "$bin/$tool" << 'SH'
#!/bin/sh
n=$(cat "$TEST_ROOT/cores")
[ "$n" != none ] || exit 1
printf '%s\n' "$n"
SH
    chmod +x "$bin/$tool"
  done
  PATH="$bin:$PATH"
  export PATH
  cores 10
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  CONC="$TEST_ROOT/conc"
  mkdir -p "$CONC"
  export CONC
  # Each check registers itself, records how many are registered, waits and leaves.
  cat > tests/conc.sh << 'SH'
touch "$CONC/run.$$"
ls "$CONC" | grep -c '^run\.' >> "$CONC/seen"
sleep 0.4
rm -f "$CONC/run.$$"
SH
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
  # This file tests the machine default: a proof marks its own units (VBW_PROOF_UNIT, R257),
  # which would make the kernel under test read 1 instead.
  unset VBW_PROOF_UNIT
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# cores N: the machine reports N processor cores ("none": it cannot be read).
cores() { printf '%s\n' "$1" > "$TEST_ROOT/cores"; }

# jobs_line: the check_jobs line of vbw config.
jobs_line() { "$VBW" config < /dev/null | grep '^check_jobs:'; }

# project N: N approved checks C1..CN of R1, each running tests/conc.sh.
project() {
  local i checks='[]'
  for i in $(seq 1 "$1"); do
    checks=$(printf '%s' "$checks" | jq -c --arg id "C$i" '. + [{id: $id, req: "R1", run: ["sh", "tests/conc.sh"], files: ["tests/conc.sh"]}]')
  done
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq --argjson c "$checks" '.checks = $c
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

peak() { sort -n "$CONC/seen" | tail -n 1; }

@test "R147: with no setting, the limit is three quarters of the cores, rounded down, at least 1" {
  local pair
  for pair in 10:7 8:6 6:4 4:3 3:2 2:1 1:1; do
    cores "${pair%%:*}"
    [[ "$(jobs_line)" == "check_jobs: ${pair##*:} (machine default"* ]] || { echo "${pair%%:*} cores: $(jobs_line)"; false; }
  done
}

@test "R147: the machine default is never more than 64" {
  cores 128
  [[ "$(jobs_line)" == "check_jobs: 64 (machine default"* ]] || { jobs_line; false; }
  cores 86
  [[ "$(jobs_line)" == "check_jobs: 64 (machine default"* ]] || { jobs_line; false; }
}

@test "R147: when the core count cannot be read, VBW uses 1 and keeps working" {
  local v
  for v in none "" abc 0 -4 2.5; do
    cores "$v"
    vbw_run config
    [ "$status" -eq 0 ] || { echo "'$v': $output"; false; }
    [[ "$(jobs_line)" == "check_jobs: 1 (machine default"* ]] || { echo "'$v': $(jobs_line)"; false; }
  done
  cores none
  project 3
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(peak)" = 1 ]
}

@test "R147: a proof with no setting runs at most the machine default at once" {
  cores 4
  project 12
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(wc -l < "$CONC/seen" | tr -d ' ')" = 12 ]
  [ "$(peak)" -le 3 ] || { echo "peak $(peak) with 4 cores"; false; }
  [ "$(peak)" -ge 2 ] || { echo "peak $(peak): not parallel"; false; }
}

@test "R147: on a one-core machine checks run one at a time" {
  cores 1
  project 6
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(peak)" = 1 ]
}

@test "R147: check_jobs N overrides the machine default, is shown as set, and default returns to the machine's value" {
  cores 10
  "$VBW" config set check_jobs 2 > /dev/null
  [[ "$(jobs_line)" == "check_jobs: 2 (set"* ]] || { jobs_line; false; }
  "$VBW" config set check_jobs 12 > /dev/null
  [[ "$(jobs_line)" == "check_jobs: 12 (set"* ]] || { jobs_line; false; }
  "$VBW" config set check_jobs default > /dev/null
  [[ "$(jobs_line)" == "check_jobs: 7 (machine default"* ]] || { jobs_line; false; }
}

@test "R147: a set value is used by the proof in place of the machine default" {
  cores 10
  "$VBW" config set check_jobs 1 > /dev/null
  project 6
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(peak)" = 1 ]
}

@test "R147: values outside 1 to 64 are still refused and change nothing" {
  "$VBW" config set check_jobs 3 > /dev/null
  local v
  for v in 0 65 abc; do
    vbw_run config set check_jobs "$v"
    [ "$status" -ne 0 ] || { echo "accepted: '$v'"; false; }
  done
  [[ "$(jobs_line)" == "check_jobs: 3 (set"* ]] || { jobs_line; false; }
}
