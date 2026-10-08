#!/usr/bin/env bats
# R110 (docs/proof.md): vbw prove runs again only the approved checks whose
# served files (the check's own files and the files of the plans serving its
# requirement) changed since their last pass, every check that declares no
# files, and every check whose definition changed; it reuses every other
# result and says so. Every check and command logs its own name to $RANLOG when
# it really runs, so a reused result shows as a missing line. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer can refund\n- R3 [auto] A customer can see an invoice\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  printf 'refunded\n' > src/refund.txt
  printf 'invoiced\n' > src/invoice.txt
  # Each script logs "<name><argument>" when it runs. C2 (no argument) fails
  # when FAIL is set; C5 sleeps past its timeout when the file named by SLOW5 exists.
  cat > tests/c1.sh << 'SH'
echo "C1$1" >> "$RANLOG"
grep -qx paid src/pay.txt
SH
  cat > tests/c2.sh << 'SH'
echo "C2$1" >> "$RANLOG"
[ -z "${FAIL:-}" ] || [ -n "$1" ]
SH
  cat > tests/c5.sh << 'SH'
echo "C5" >> "$RANLOG"
[ ! -e "${SLOW5:-/nonexistent}" ] || sleep 6
SH
  cat > tests/c6.sh << 'SH'
echo "C6" >> "$RANLOG"
SH
  cat > tests/cmd.sh << 'SH'
echo "cmd-$1" >> "$RANLOG"
SH
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]},
      {id:"C2", req:"R2", run:["sh","tests/c2.sh"], files:["tests/c2.sh"]},
      {id:"C4", req:"R2", run:["sh","tests/c2.sh","b"], files:["tests/c2.sh"]},
      {id:"C5", req:"R3", run:["sh","tests/c5.sh"], files:["tests/c5.sh"], timeout:2}]
    | .commands = {lint: ["sh","tests/cmd.sh","lint"], test: ["sh","tests/cmd.sh","test"]}
    | .phases = [{id:"P1", title:"Shop", reqs:["R1","R2","R3"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"},
                {id:"P1.2", phase:"P1", title:"Refund", reqs:["R2"], files:["src/refund.txt"], after:[], status:"done"},
                {id:"P1.3", phase:"P1", title:"Invoice", reqs:["R3"], files:["src/invoice.txt"], after:[], status:"done"}]'
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
ALL='C1 C2 C2b C5 cmd-lint cmd-test '
CMDS='cmd-lint cmd-test '

# change FILE: commit a change to one project file.
change() {
  printf 'more\n' >> "$1"
  git add "$1" && git commit -q -m "feat: change $1"
}

# decide: record a decision (only VBW's own record changes).
decide() { "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null; }

# line ID: the proof summary line of one check or command.
line() { printf '%s\n' "$output" | grep -E "^ +$1 " || true; }

@test "R110: a commit that changes only a file served by one requirement runs that requirement's checks and reuses the rest" {
  change src/refund.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C2 C2b $CMDS" ] || { echo "ran: $(ran)"; false; }
  local id l
  for id in C1 C5; do
    l=$(line "$id")
    [[ "$l" == *reused* && "$l" == *"$FIRST"* ]] || { echo "$id: '$l'"; echo "$output"; false; }
  done
  for id in C2 C4 lint test; do
    l=$(line "$id")
    [[ -n "$l" && "$l" != *reused* ]] || { echo "$id: '$l'"; echo "$output"; false; }
  done
}

@test "R110: the output says in one line how many checks ran and how many were reused, and vbw show evidence marks the reused ones" {
  change src/refund.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^ +checks: 2 ran, 2 reused$' || { echo "$output"; false; }
  vbw_run show evidence
  [ "$status" -eq 0 ]
  local l
  l=$(line C1)
  [[ "$l" == *reused* && "$l" == *"$FIRST"* ]] || { echo "C1: '$l'"; echo "$output"; false; }
  l=$(line C2)
  [[ -n "$l" && "$l" != *reused* ]] || { echo "C2: '$l'"; false; }
  # A reused result keeps the time it really ran.
  [ "$(jq -r '.evidence.checks.C1.at' .vbw/record.json)" = "$FIRST" ]
  jq -e '.evidence.checks.C1.reused == true and (.evidence.checks.C2.reused // false) == false' .vbw/record.json
}

@test "R110: a commit that changes a file of a plan serving the requirement runs that requirement's check only" {
  change src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 $CMDS" ] || { echo "ran: $(ran)"; false; }
}

@test "R110: a commit that changes a check's own file, approved again, runs the checks that file belongs to" {
  printf '# edited\n' >> tests/c1.sh
  git add tests/c1.sh && git commit -q -m "test: edit c1"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 $CMDS" ] || { echo "ran: $(ran)"; false; }
}

@test "R110: a check whose last result failed runs again though none of its files changed; the other passes are reused" {
  change src/refund.txt
  FAIL=1 vbw_run prove
  [ "$status" -eq 1 ]
  jq -e '.evidence.passed == false and .evidence.checks.C2.status == "fail" and .evidence.checks.C4.status == "pass"' .vbw/record.json
  : > "$RANLOG"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C2 $CMDS" ] || { echo "ran: $(ran)"; false; }
  [[ "$(line C4)" == *reused* ]] || { echo "$output"; false; }
  [[ "$(line C1)" == *reused* ]] || { echo "$output"; false; }
}

@test "R110: after a proof in which one check failed, the next one runs the failed check and the checks with changed files, and reuses the other passes" {
  change src/refund.txt
  FAIL=1 vbw_run prove
  [ "$status" -eq 1 ]
  : > "$RANLOG"
  change src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 $CMDS" ] || { echo "ran: $(ran)"; false; }
  [[ "$(line C4)" == *reused* ]] || { echo "$output"; false; }
  [[ "$(line C5)" == *reused* ]] || { echo "$output"; false; }
  jq -e '.evidence.passed == true' .vbw/record.json
}

@test "R110: a check whose last result timed out runs again though none of its files changed" {
  touch "$TEST_ROOT/slow5"
  change src/invoice.txt
  SLOW5="$TEST_ROOT/slow5" vbw_run prove
  [ "$status" -eq 1 ]
  jq -e '.evidence.checks.C5.status == "timeout"' .vbw/record.json
  : > "$RANLOG"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C5 $CMDS" ] || { echo "ran: $(ran)"; false; }
}

@test "R110: a check that declares no files runs on every proof and is never reused" {
  edit_record '.checks += [{id:"C6", req:"R3", run:["sh","tests/c6.sh"]}]'
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C6 " ] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C6 " ] || { echo "ran: $(ran)"; false; }
  [[ "$(line C6)" != *reused* ]] || { echo "$output"; false; }
  [[ "$(line C1)" == *reused* ]] || { echo "$output"; false; }
  : > "$RANLOG"
  change README.md
  vbw_run prove
  [ "$(ran)" = "C6 $CMDS" ] || { echo "ran: $(ran)"; false; }
}

@test "R110: a check with a served path that is not in the committed code runs on every proof" {
  git rm -q src/invoice.txt
  git commit -q -m "chore: drop the invoice file"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C5 $CMDS" ] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C5 " ] || { echo "ran: $(ran)"; false; }
  [[ "$(line C5)" != *reused* ]] || { echo "$output"; false; }
}

@test "R110: a changed approved definition runs that check, and a check whose definition and files are unchanged is reused though the contract changed" {
  edit_record '(.checks[] | select(.id == "C2")).run = ["sh","tests/c2.sh","x"]'
  "$VBW" approve > /dev/null
  change README.md
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C2x $CMDS" ] || { echo "ran: $(ran)"; false; }
  [[ "$(line C1)" == *reused* ]] || { echo "$output"; false; }
  [[ "$(line C4)" == *reused* ]] || { echo "$output"; false; }
}

@test "R110: a served file changed in the working folder but not committed runs nothing again, and the commit that follows makes the proof stale" {
  printf 'more\n' >> src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "$CMDS" ] || { echo "ran: $(ran)"; false; }
  [[ "$(line C1)" == *reused* ]] || { echo "$output"; false; }
  git add src/pay.txt && git commit -q -m "feat: pay more"
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" = prove ] || { echo "$output"; false; }
  : > "$RANLOG"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 $CMDS" ] || { echo "ran: $(ran)"; false; }
}

@test "R110: an interrupted proof (its unfinished marker is left behind) reuses nothing" {
  decide
  : > .vbw/runtime/prove.unfinished
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "$ALL" ] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R110: a second proof with no commit since the passing proof still runs everything fresh" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "$ALL" ] || { echo "ran: $(ran)"; false; }
  printf '%s\n' "$output" | grep -qE '^ +checks: 4 ran, 0 reused$' || { echo "$output"; false; }
}

@test "R110: project commands keep the R103 rule: they run when the committed code differs, whatever the checks reuse" {
  change src/refund.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  [[ "$(line lint)" != *reused* && "$(line test)" != *reused* ]] || { echo "$output"; false; }
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  [[ "$(line lint)" == *reused* ]] || { echo "$output"; false; }
}

@test "R110: selective reuse adds no ledger or state file: the record's evidence is the only source" {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  { git ls-files .vbw; find "$common/vbw" -type f; } | sort > "$TEST_ROOT/before.txt"
  change src/refund.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  { git ls-files .vbw; find "$common/vbw" -type f; } | sort > "$TEST_ROOT/after.txt"
  diff "$TEST_ROOT/before.txt" "$TEST_ROOT/after.txt"
  [ "$(find .vbw/runtime -maxdepth 1 -type f \( -name '*reuse*' -o -name '*ledger*' -o -name 'served*' \) | wc -l | tr -d ' ')" = 0 ]
}
