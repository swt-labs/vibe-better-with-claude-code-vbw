#!/usr/bin/env bats
# R147, F106 (docs/proof.md): a core count VBW cannot read as a whole number
# (10.5, 12abc, 08, 1e3) means the count cannot be read: the check limit is 1
# and VBW keeps working, with no arithmetic error from the shell. Regression
# test for the fix of vbw_cores (whole numbers only). The core count is read
# with getconf, nproc or sysctl from PATH; stand-ins first on PATH report the
# count in $TEST_ROOT/cores. L1.

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
cat "$TEST_ROOT/cores"
SH
    chmod +x "$bin/$tool"
  done
  PATH="$bin:$PATH"
  export PATH
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  CONC="$TEST_ROOT/conc"
  mkdir -p "$CONC"
  export CONC
  # Each check registers itself, records how many are registered, waits and leaves.
  cat > tests/conc.sh << 'SH'
touch "$CONC/run.$$"
ls "$CONC" | grep -c '^run\.' >> "$CONC/seen"
sleep 0.3
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

# cores VALUE: every core-count tool on PATH reports VALUE.
cores() { printf '%s\n' "$1" > "$TEST_ROOT/cores"; }

# no_shell_error: $output carries no arithmetic or syntax error from the shell.
no_shell_error() {
  if printf '%s\n' "$output" | grep -qiE 'arithmetic|syntax error|value too great|invalid number|bad number'; then
    echo "shell error: $output"
    return 1
  fi
}

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

@test "R147: a core count that is not a whole number gives a check limit of 1 and vbw config keeps working" {
  local v line
  for v in 10.5 12abc 08 1e3; do
    cores "$v"
    vbw_run config
    [ "$status" -eq 0 ] || {
      echo "'$v': $output"
      false
    }
    no_shell_error || {
      echo "core count '$v'"
      false
    }
    line=$(printf '%s\n' "$output" | grep '^check_jobs:')
    [[ "$line" == "check_jobs: 1 (machine default"* ]] || {
      echo "'$v': $line"
      false
    }
  done
}

@test "R147: with a core count that is not a whole number, a proof runs one check at a time without a shell error" {
  local v
  project 3
  for v in 10.5 12abc; do
    cores "$v"
    : > "$CONC/seen"
    vbw_run prove --full
    [ "$status" -eq 0 ] || {
      echo "'$v': $output"
      false
    }
    no_shell_error || {
      echo "core count '$v'"
      false
    }
    [ "$(wc -l < "$CONC/seen" | tr -d ' ')" = 3 ] || {
      echo "'$v': not every check ran"
      false
    }
    [ "$(peak)" = 1 ] || {
      echo "'$v': peak $(peak)"
      false
    }
  done
}
