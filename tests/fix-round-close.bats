#!/usr/bin/env bats
# R182 (plugin/workflows/fixing.js, docs/workflows.md): the one vbw fix done a
# fix round runs, taken from the stubbed fixing workflow's prompts
# (tests/helpers/run-workflow.js) and run on a real project, closes each fix as
# it would close alone: a fix with uncommitted changes, one whose files serve a
# failing check of finished work, and a test-command fix whose test files still
# fail stay open and are named; the others close. vbw run confirm then counts
# every closed fix as recorded and names every open one, the next vbw prove
# reuses what the round saved, and the output keeps its form: one line per
# check or test file, then both count lines. Checks count their runs in $RUNS.
#
# F1 (R2) is served by C1 and C2, F2 (R3) by C1 and C3.

load helper
load fixture-helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows/fixing.js"
DONE='{"status":"done","summary":"s","notes":[]}'
BLOCKED='{"status":"blocked","summary":"needs a decision","notes":[]}'
OK='{"fixdone":"ran","closed":[],"open":[],"ended":true,"recorded":true,"report":"all recorded; run ended"}'

# The shop (three finished requirements, two open fixes, a fix run open) and a
# plain git project for the test-command round, each built once per file.
setup_file() {
  fixture_build shop shop_project
  fixture_build plain plain_project
}
setup() {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  fixture_copy shop
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

plain_project() {
  vbw_setup
  vbw_git_project
}

shop_project() {
  plain_project
  shop
}

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

# shop: three finished requirements, their checks, and two open fixes, F1 and F2.
shop() {
  export RUNS="$TEST_ROOT/runs"
  mkdir -p "$RUNS" tests src
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n- R3 [auto] A customer can be refunded\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'echo run >> "$RUNS/C1"\ngrep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'echo run >> "$RUNS/C2"\ngrep -qx sent src/receipt.txt\n' > tests/receipt.sh
  printf 'echo run >> "$RUNS/C3"\ngrep -qx refunded src/refund.txt\n' > tests/refund.sh
  jq -n '{phases: [{id: "P1", title: "Checkout", reqs: ["R1", "R2"], tier: "standard"},
                   {id: "P2", title: "After sales", reqs: ["R3"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt", "src/ledger.txt"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.txt", "src/pay.txt"]},
            {id: "P2.1", phase: "P2", title: "Refund", reqs: ["R3"], files: ["src/refund.txt", "src/ledger.txt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]},
             {id: "C3", req: "R3", run: ["sh", "tests/refund.sh"], files: ["tests/refund.sh"]}]}' | "$VBW" apply > /dev/null
  printf 'paid\n' > src/pay.txt && printf 'sent\n' > src/receipt.txt && printf 'refunded\n' > src/refund.txt
  printf 'l\n' > src/ledger.txt
  git add -A && git commit -q -m "feat: built"
  edit_record '.plans[].status = "done"
    | .fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "a"},
                {id: "F2", req: "R3", attempts: 0, status: "open", note: "b"}]'
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start fix F1 F2 > /dev/null
}

runs() { if [ -f "$RUNS/$1" ]; then wc -l < "$RUNS/$1" | tr -d ' '; else printf 0; fi; }

fix_status() { jq -r --arg f "$1" '.fixes[] | select(.id == $f) | .status' .vbw/record.json; }

# round_command GROUPS RESPONSES: the one vbw fix done the fixing workflow's prompts give for this round.
round_command() {
  local out
  out=$(node "$RUN" "$WF" "$(jq -nc --argjson g "$1" '{groups: $g, session: "s1"}')" "$2") || { echo "$out"; return 1; }
  printf '%s' "$out" | jq -er '[.calls[].prompt | scan("vbw fix done(?: F[0-9]+)+")] | if length == 1 then .[0] else error("not one vbw fix done: \(.)") end'
}

# round GROUPS RESPONSES: run the round's vbw fix done on the project, as the session's
# closing agent would; sets status, output (stdout and stderr) and CMD.
round() {
  CMD=$(round_command "$1" "$2") || { echo "$CMD"; return 1; }
  local argv
  read -r -a argv <<< "$CMD"
  [ "${argv[0]}" = vbw ] || { echo "not a vbw command: $CMD"; return 1; }
  run env VBW_SESSION_ID=s1 "$VBW" "${argv[@]:1}" < /dev/null
}

two_done() { jq -nc --argjson d "$DONE" --argjson k "$OK" '{"F1": $d, "F2": $d, "close run": $k}'; }

@test "R182: the round's one vbw fix done closes every clean fix, and vbw run confirm counts each as recorded" {
  round '[["F1"],["F2"]]' "$(two_done)"
  [ "$status" -eq 0 ] || { echo "$CMD: $output"; false; }
  [ "$(fix_status F1)" = fixed ] && [ "$(fix_status F2)" = fixed ]
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ]
  run env VBW_SESSION_ID=s1 "$VBW" run confirm F1 F2 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"F1: recorded"* && "$output" == *"F2: recorded"* ]] || { echo "$output"; false; }
}

@test "R182: a fix with uncommitted changes stays open and is named, the other closes, and vbw run confirm names it" {
  printf 'dirty\n' >> src/refund.txt
  round '[["F1"],["F2"]]' "$(two_done)"
  [ "$status" -ne 0 ] || { echo "$CMD: $output"; false; }
  [[ "$output" == *"F2 has uncommitted changes in: src/refund.txt"* ]] || { echo "$output"; false; }
  [ "$(fix_status F1)" = fixed ] && [ "$(fix_status F2)" = open ]
  run env VBW_SESSION_ID=s1 "$VBW" run confirm F1 F2 < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"F1: recorded"* && "$output" == *"F2: not recorded"* ]] || { echo "$output"; false; }
}

@test "R182: a fix whose files serve a failing check of finished work stays open and is named, the other closes" {
  printf 'broken\n' > src/refund.txt && git commit -q -am "fix: break refund"
  round '[["F1"],["F2"]]' "$(two_done)"
  [ "$status" -ne 0 ] || { echo "$CMD: $output"; false; }
  [[ "$output" == *"F2 broke finished work"*"C3 fail"* ]] || { echo "$output"; false; }
  [[ "$output" != *"F1 broke"* ]] || { echo "$output"; false; }
  [ "$(fix_status F1)" = fixed ] && [ "$(fix_status F2)" = open ]
  run env VBW_SESSION_ID=s1 "$VBW" run confirm F1 F2 < /dev/null
  [ "$status" -eq 1 ] && [[ "$output" == *"F2: not recorded"* ]] || { echo "$output"; false; }
}

@test "R182: a fix whose Dev was blocked is left out of the round's vbw fix done and stays open; vbw run confirm names it" {
  round '[["F1"],["F2"]]' "$(jq -nc --argjson d "$DONE" --argjson b "$BLOCKED" --argjson k "$OK" '{"F1": $d, "F2": $b, "close run": $k}')"
  [ "$status" -eq 0 ] || { echo "$CMD: $output"; false; }
  [ "$CMD" = "vbw fix done F1" ] || { echo "$CMD"; false; }
  [ "$(fix_status F1)" = fixed ] && [ "$(fix_status F2)" = open ]
  run env VBW_SESSION_ID=s1 "$VBW" run confirm F1 F2 < /dev/null
  [ "$status" -eq 1 ] && [[ "$output" == *"F2: not recorded"* ]] || { echo "$output"; false; }
}

@test "R182: the round's vbw fix done prints one line per check, then both count lines, as before" {
  CMD=$(round_command '[["F1"],["F2"]]' "$(two_done)") || { echo "$CMD"; false; }
  local argv
  read -r -a argv <<< "$CMD"
  run env VBW_SESSION_ID=s1 "$VBW" "${argv[@]:1}" 2> /dev/null < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The report: an optional cause line, one line per check, the two count lines; then one line per fix.
  local c
  c=$(printf '%s\n' "$output" | grep -nE '^checks: [0-9]+ ran, [0-9]+ reused$' | cut -d: -f1)
  [ -n "$c" ] || { echo "$output"; false; }
  printf '%s\n' "$output" | sed -n "$((c + 1))p" | grep -qE '^test files: [0-9]+ ran, [0-9]+ reused$' || { echo "$output"; false; }
  local before units
  before=$(printf '%s\n' "$output" | sed -n "1,$((c - 1))p" | grep -vE '^(every candidate check runs|run again): ')
  units=$(printf '%s\n' "$before" | grep -cE '^C[0-9]+ (pass|fail|timeout|unchanged since its pass)' || true)
  [ "$units" -eq 3 ] && [ "$(printf '%s\n' "$before" | grep -c .)" -eq 3 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^C1 pass ' && printf '%s\n' "$output" | grep -qE '^C3 pass ' || { echo "$output"; false; }
  printf '%s\n' "$output" | sed -n "$((c + 2)),\$p" | grep -qx 'F1 fixed: vbw prove decides' || { echo "$output"; false; }
  printf '%s\n' "$output" | sed -n "$((c + 2)),\$p" | grep -qx 'F2 fixed: vbw prove decides' || { echo "$output"; false; }
}

@test "R182: the next vbw prove reuses what the round's vbw fix done ran" {
  round '[["F1"],["F2"]]' "$(two_done)"
  [ "$status" -eq 0 ] || { echo "$CMD: $output"; false; }
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  run "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ] || { echo "C1 $(runs C1) C2 $(runs C2) C3 $(runs C3)"; echo "$output"; false; }
}

# testcmd: a project whose test command failed as test files (tests/t_a.sh fails
# while $TEST_ROOT/fail_a exists), so a fix for the test command is open: $FIX.
testcmd() {
  export RANLOG="$TEST_ROOT/ran.log"
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'echo t_a >> "$RANLOG"\n[ ! -e "$TEST_ROOT/fail_a" ] || { echo "t_a broken"; exit 1; }\n' > tests/t_a.sh
  printf 'echo t_b >> "$RANLOG"\ngrep -q . src/a.txt\n' > tests/t_b.sh
  printf 'echo C1 >> "$RANLOG"\ngrep -q . src/a.txt\n' > tests/c1.sh
  printf 'echo all >> "$RANLOG"\n' > tests/all.sh
  : > "$RANLOG"
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' \
    .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  : > "$TEST_ROOT/fail_a"
  run "$VBW" prove < /dev/null
  [ "$status" -eq 1 ] || { echo "the second proof did not fail: $output"; return 1; }
  FIX=$(jq -r '[.fixes[] | select(.command == "test" and .status == "open")][0].id // empty' .vbw/record.json)
  [ -n "$FIX" ] || { echo "no fix for the test command"; jq .fixes .vbw/record.json; return 1; }
  VBW_SESSION_ID=s1 "$VBW" run start fix "$FIX" > /dev/null
}

@test "R182: a test-command fix whose test files still fail stays open and is named; once they pass it closes" {
  fixture_copy plain
  testcmd
  local responses
  responses=$(jq -nc --arg f "$FIX" --argjson d "$DONE" --argjson k "$OK" '{($f): $d, "close run": $k}')
  round "$(jq -nc --arg f "$FIX" '[[$f]]')" "$responses"
  [ "$status" -ne 0 ] || { echo "$CMD: $output"; false; }
  [[ "$output" == *"$FIX: these test files still do not pass: tests/t_a.sh"* ]] || { echo "$output"; false; }
  [ "$(fix_status "$FIX")" = open ]
  rm -f "$TEST_ROOT/fail_a"
  round "$(jq -nc --arg f "$FIX" '[[$f]]')" "$responses"
  [ "$status" -eq 0 ] || { echo "$CMD: $output"; false; }
  [ "$(fix_status "$FIX")" = fixed ]
}
