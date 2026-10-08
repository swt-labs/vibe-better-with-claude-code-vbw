#!/usr/bin/env bats
# R111 (docs/proof.md): a project may name a quick test command (a Commands
# entry called quick); a plain vbw prove runs it in place of the test command,
# vbw prove --full runs every check and every full project command and reuses
# nothing, and the evidence records whether the proof was full. Every check and
# command logs its own name to $RANLOG when it really runs. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer can refund\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  printf 'refunded\n' > src/refund.txt
  cat > tests/c1.sh << 'SH'
echo "C1" >> "$RANLOG"
grep -qx paid src/pay.txt
SH
  cat > tests/c2.sh << 'SH'
echo "C2" >> "$RANLOG"
SH
  # The quick command fails when QUICKFAIL is set.
  cat > tests/cmd.sh << 'SH'
echo "cmd-$1" >> "$RANLOG"
[ -z "${QUICKFAIL:-}" ] || [ "$1" != quick ]
SH
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]},
      {id:"C2", req:"R2", run:["sh","tests/c2.sh"], files:["tests/c2.sh"]}]
    | .commands = {lint: ["sh","tests/cmd.sh","lint"], test: ["sh","tests/cmd.sh","test"]}
    | .phases = [{id:"P1", title:"Shop", reqs:["R1","R2"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"},
                {id:"P1.2", phase:"P1", title:"Refund", reqs:["R2"], files:["src/refund.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null
  : > "$RANLOG"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1 | del(.requirements[]?.rules)" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

ran() { sort "$RANLOG" | tr '\n' ' '; }

# change FILE...: commit a change to the project files.
change() {
  local f
  for f in "$@"; do printf 'more\n' >> "$f"; done
  git add "$@" && git commit -q -m "feat: change"
}

# named_quick: the project names a quick command and the user approves it.
named_quick() {
  edit_record '.commands.quick = ["sh","tests/cmd.sh","quick"]'
  "$VBW" approve > /dev/null
}

line() { printf '%s\n' "$output" | grep -E "^ +$1 " || true; }

@test "R111: a project without a quick command runs its test command as before, and a proof that ran everything is full" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 cmd-lint cmd-test " ] || { echo "ran: $(ran)"; false; }
  printf '%s\n' "$output" | grep -qE '^ +proof: full$' || { echo "$output"; false; }
  jq -e '.evidence.full == true' .vbw/record.json
  [ -z "$(line quick)" ]
}

@test "R111: a named and approved quick command runs in place of the test command; every other command still runs" {
  named_quick
  change src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 cmd-lint cmd-quick " ] || { echo "ran: $(ran)"; false; }
  [[ "$(line quick)" == *pass* ]] || { echo "$output"; false; }
  [ -z "$(line test)" ] || { echo "$output"; false; }
  jq -e '.evidence.commands | has("quick") and has("lint") and (has("test") | not)' .vbw/record.json
}

@test "R111: a proof that used the quick command in place of the test command is partial, in the summary and in the evidence" {
  named_quick
  change src/pay.txt src/refund.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 cmd-lint cmd-quick " ] || { echo "ran: $(ran)"; false; }
  printf '%s\n' "$output" | grep -qE '^ +proof: partial' || { echo "$output"; false; }
  jq -e '.evidence.full == false' .vbw/record.json
}

@test "R111: a quick command named but not approved is skipped, the full test command runs instead, and the summary says so" {
  edit_record '.commands.quick = ["sh","tests/cmd.sh","quick"]'
  change src/pay.txt src/refund.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 cmd-lint cmd-test " ] || { echo "ran: $(ran)"; false; }
  [[ "$(line quick)" == *"not approved"* ]] || { echo "$output"; false; }
  jq -e '.evidence.commands.quick.status == "skipped" and .evidence.commands.test.status == "pass"' .vbw/record.json
  # The quick command is not a full project command: this proof ran everything else.
  printf '%s\n' "$output" | grep -qE '^ +proof: full$' || { echo "$output"; false; }
}

@test "R111: vbw prove --full reuses nothing and runs every check, the test command and every other command, but not the quick command" {
  named_quick
  "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 cmd-lint cmd-test " ] || { echo "ran: $(ran)"; false; }
  [[ "$output" != *reused* ]] || { echo "$output"; false; }
  [ -z "$(line quick)" ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +proof: full$' || { echo "$output"; false; }
  jq -e '.evidence.full == true and (.evidence.commands | has("quick") | not)' .vbw/record.json
}

@test "R111: vbw prove with any other argument is refused with the usage line and runs nothing" {
  local before arg
  before=$(shasum .vbw/record.json)
  for arg in --quick --fast extra "--full extra"; do
    # shellcheck disable=SC2086 # "--full extra" is two arguments on purpose
    vbw_run prove $arg
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: vbw prove [--full]"* ]] || { echo "$arg: $output"; false; }
  done
  [ "$(ran)" = "" ]
  [ "$(shasum .vbw/record.json)" = "$before" ]
}

@test "R111: a proof is full only when nothing was reused: a plain proof that reused a result is partial" {
  change src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 cmd-lint cmd-test " ] || { echo "ran: $(ran)"; false; }
  printf '%s\n' "$output" | grep -qE '^ +proof: partial' || { echo "$output"; false; }
  jq -e '.evidence.full == false' .vbw/record.json
}

@test "R111: a full proof is not full when a project command was not approved and so did not run" {
  edit_record '.commands.extra = ["sh","tests/cmd.sh","extra"]'
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(line extra)" == *"not approved"* ]] || { echo "$output"; false; }
  jq -e '.evidence.full == false' .vbw/record.json
  printf '%s\n' "$output" | grep -qE '^ +proof: partial' || { echo "$output"; false; }
}

@test "R111: a failing quick command opens a fix for it, and a passing full proof closes that fix" {
  named_quick
  change src/pay.txt
  QUICKFAIL=1 vbw_run prove
  [ "$status" -eq 1 ]
  jq -e '.fixes | any(.[]; .command == "quick" and .status == "open")' .vbw/record.json
  local id
  id=$(jq -r '[.fixes[] | select(.command == "quick")][0].id' .vbw/record.json)
  vbw_run fix "done" "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e --arg id "$id" '.fixes | any(.[]; .id == $id and .status == "closed")' .vbw/record.json
}
