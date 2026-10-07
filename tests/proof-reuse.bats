#!/usr/bin/env bats
# R103 (docs/proof.md): when the committed project files are identical to those
# of the last passing proof (only VBW's own record or spec changed), vbw prove
# reuses that proof's results for every check and command whose approved
# definition is unchanged, says so, and runs only the rest. Every check and
# command logs its own name to $RANLOG when it really runs, so a reused result
# shows as a missing line. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer can refund\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  # Each script logs "<name><argument>" when it runs. C2 fails when FAIL is set;
  # C1 sleeps when the file named by SLOW exists (the interrupted-proof test).
  cat > tests/c1.sh << 'SH'
echo "C1$1" >> "$RANLOG"
[ ! -e "${SLOW:-/nonexistent}" ] || sleep 4
grep -qx paid src/pay.txt
SH
  cat > tests/c2.sh << 'SH'
echo "C2$1" >> "$RANLOG"
[ -z "${FAIL:-}" ]
SH
  cat > tests/cmd.sh << 'SH'
echo "cmd-$1" >> "$RANLOG"
SH
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]},
      {id:"C2", req:"R2", run:["sh","tests/c2.sh"], files:["tests/c2.sh"]},
      {id:"C4", req:"R2", run:["sh","tests/c2.sh","b"], files:["tests/c2.sh"]}]
    | .commands = {lint: ["sh","tests/cmd.sh","lint"], test: ["sh","tests/cmd.sh","test"]}
    | .phases = [{id:"P1", title:"Pay", reqs:["R1","R2"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1","R2"], files:["src/pay.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null
  FIRST=$(jq -r '.evidence.at' .vbw/record.json)
  : > "$RANLOG"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1 | del(.requirements[]?.rules)" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# ran: what really ran since the log was last emptied, sorted, one line.
ran() { sort "$RANLOG" | tr '\n' ' '; }
ALL='C1 C2 C2b cmd-lint cmd-test '

# decide: record a decision (only VBW's own record changes).
decide() { "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null; }

@test "R103: after a passing proof, a recorded decision changes only the record: prove runs nothing" {
  decide
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  [[ "$output" == *proved* ]]
}

@test "R103: the output names each reused check and command and the time of the proof it came from" {
  decide
  vbw_run prove
  [ "$status" -eq 0 ]
  local id line
  for id in C1 C2 C4 lint test; do
    line=$(printf '%s\n' "$output" | grep -E "^ +$id " || true)
    [[ "$line" == *reused* ]] || { echo "$id: '$line'"; echo "$output"; false; }
    [[ "$line" == *"$FIRST"* ]] || { echo "$id does not name the proof time $FIRST: '$line'"; false; }
  done
}

@test "R103: a change to spec.md alone (a new human requirement, approved again) reuses every result" {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer can refund\n- R3 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R103: a check added since the proof runs, and only it; the others are reused" {
  decide
  edit_record '.checks += [{id:"C3", req:"R1", run:["sh","tests/c1.sh","n"], files:["tests/c1.sh"]}]'
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1n " ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.checks | keys == ["C1","C2","C3","C4"]' .vbw/record.json
}

@test "R103: changing one check's approved definition while the code is unchanged runs that check and reuses the rest" {
  edit_record '(.checks[] | select(.id == "C2")).run = ["sh","tests/c2.sh","x"]'
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C2x " ] || { echo "ran: $(ran)"; false; }
  local line
  line=$(printf '%s\n' "$output" | grep -E '^ +C1 ')
  [[ "$line" == *reused* ]]
  line=$(printf '%s\n' "$output" | grep -E '^ +C2 ')
  [[ "$line" != *reused* ]]
}

@test "R103: a project command whose approved argv changed runs, and the unchanged command is reused" {
  edit_record '.commands.lint = ["sh","tests/cmd.sh","lint2"]'
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "cmd-lint2 " ] || { echo "ran: $(ran)"; false; }
}

@test "R103: a check removed from the contract does not appear in the new proof, and the others are reused" {
  edit_record '.checks |= map(select(.id != "C4"))'
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.checks | keys == ["C1","C2"]' .vbw/record.json
  [[ "$output" != *C4* ]]
}

@test "R103: a committed project file that differs runs every check and command, and the next proof reuses that one" {
  printf 'more\n' >> README.md
  git add README.md && git commit -q -m "docs: more"
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "$ALL" ] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R103: uncommitted changes to a tracked project file reuse nothing; with the folder clean again, reuse resumes" {
  printf 'more\n' >> README.md
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "$ALL" ] || { echo "ran: $(ran)"; false; }
  git checkout -q README.md
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R103: an untracked project file in the working folder reuses nothing" {
  printf 'buy milk\n' > todos.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "$ALL" ] || { echo "ran: $(ran)"; false; }
  rm todos.txt
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R103: when the last proof did not pass, nothing is reused; a later passing proof is reused again" {
  FAIL=1 vbw_run prove
  [ "$status" -eq 1 ]
  jq -e '.evidence.passed == false' .vbw/record.json
  : > "$RANLOG"
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "$ALL" ] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R103: when the last proof was interrupted, nothing is reused" {
  touch "$TEST_ROOT/slow"
  export SLOW="$TEST_ROOT/slow"
  "$VBW" prove > /dev/null 2>&1 < /dev/null &
  local pid=$! i
  for i in $(seq 1 100); do
    grep -q C1 "$RANLOG" && break
    sleep 0.1
  done
  grep -q C1 "$RANLOG"
  kill -TERM "$pid"
  wait "$pid" || true
  # The check that was already running finishes by itself (nothing is killed).
  sleep 5
  rm -f "$TEST_ROOT/slow"
  unset SLOW
  : > "$RANLOG"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "$ALL" ] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R103: a proof that reused results is recorded as current: qa record accepts it and the requirements are proven" {
  decide
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ]
  [ "$(jq -r '.evidence.contract' .vbw/record.json)" = "$(vbw_contract_hash)" ]
  [ "$(jq -r '.evidence.tree' .vbw/record.json)" = "$(vbw_code_tree)" ]
  jq -e '.requirements | all(.[]; .status == "proven")' .vbw/record.json
  vbw_run status
  [[ "$output" == *"requirements: 2/2 proven"* ]]
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" != prove ]
}

@test "R103: a changed check that fails still fails the proof, while the unchanged checks are reused and stay passing" {
  edit_record '(.checks[] | select(.id == "C2")).run = ["sh","tests/c2.sh","y"]'
  "$VBW" approve > /dev/null
  FAIL=1 vbw_run prove
  [ "$status" -eq 1 ]
  [ "$(ran)" = "C2y " ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.passed == false and .evidence.checks.C2.status == "fail" and .evidence.checks.C1.status == "pass"' .vbw/record.json
}

@test "R103: docs/proof.md describes the reuse: when it applies, when nothing is reused, and how the output shows it" {
  grep -qi 'reuse' "$REPO_ROOT/docs/proof.md"
  grep -qi 'reused' "$REPO_ROOT/docs/proof.md"
  grep -qi 'interrupted' "$REPO_ROOT/docs/proof.md"
}
