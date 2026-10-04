#!/usr/bin/env bats
# R44: vbw fix done closes several fixes in one command, running the checks
# their files serve once; each fix ends as if closed alone and a fix that cannot
# close is named (docs/proof.md). Checks count their runs in $RUNS.
#
# F1 (R2) is served by C1, C2; F2 (R3) by C1, C3 (C1 is shared); F3 is a
# [human] requirement's fix. One test adds C4, which runs alone, and C5.

load helper

setup() {
  vbw_setup
  vbw_git_project
  export RUNS="$TEST_ROOT/runs" TIMES="$TEST_ROOT/times"
  mkdir -p "$RUNS" "$TIMES" "$TEST_ROOT/bin" tests src
  : > "$TIMES/log"
  cat > "$TEST_ROOT/bin/mark.sh" <<'SH'
#!/bin/sh
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
echo "$$ $1 start $(now)" >> "$TIMES/log"
sleep "$2"
echo "$$ $1 end $(now)" >> "$TIMES/log"
SH
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n- R3 [auto] A customer can be refunded\n- R4 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'echo run >> "$RUNS/C1"\ngrep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'echo run >> "$RUNS/C2"\ngrep -qx sent src/receipt.txt\n' > tests/receipt.sh
  printf 'echo run >> "$RUNS/C3"\ngrep -qx refunded src/refund.txt\n' > tests/refund.sh
  PLAN=$(jq -n '{phases: [{id: "P1", title: "Checkout", reqs: ["R1", "R2"], tier: "standard"},
                                                           {id: "P2", title: "After sales", reqs: ["R3", "R4"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt", "src/ledger.txt"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.txt", "src/pay.txt"]},
            {id: "P2.1", phase: "P2", title: "Refund", reqs: ["R3"], files: ["src/refund.txt", "src/ledger.txt"]},
            {id: "P2.2", phase: "P2", title: "Look", reqs: ["R4"], files: ["src/ui.txt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]},
             {id: "C3", req: "R3", run: ["sh", "tests/refund.sh"], files: ["tests/refund.sh"]}]}')
  printf '%s' "$PLAN" | "$VBW" apply > /dev/null
  printf 'paid\n' > src/pay.txt && printf 'sent\n' > src/receipt.txt && printf 'refunded\n' > src/refund.txt
  printf 'l\n' > src/ledger.txt && printf 'ui\n' > src/ui.txt
  git add -A && git commit -q -m "feat: built"
  edit_record '.plans[].status = "done"
    | .fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "a"},
                {id: "F2", req: "R3", attempts: 0, status: "open", note: "b"},
                {id: "F3", req: "R4", attempts: 0, status: "open", note: "c"},
                {id: "F4", req: "R2", attempts: 0, status: "open", note: "d"}]'
  "$VBW" approve > /dev/null
}

teardown() {
  wait 2> /dev/null || true
  vbw_teardown
}

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

runs() { if [ -f "$RUNS/$1" ]; then wc -l < "$RUNS/$1" | tr -d ' '; else printf 0; fi; }

fix_status() { jq -r --arg f "$1" '.fixes[] | select(.id == $f) | .status' .vbw/record.json; }

@test "a single id behaves as it always did" {
  vbw_run fix done F1
  [ "$status" -eq 0 ]
  [[ "$output" == *"F1 fixed: vbw prove decides"* ]]
  [ "$(fix_status F1)" = fixed ] && [ "$(fix_status F2)" = open ]
  vbw_run fix done F1
  [ "$status" -eq 1 ]
  [[ "$output" == *"F1 is not open"* ]]
  vbw_run fix done F99
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown fix F99"* ]]
}

@test "several fixes close in one command and a shared check runs once" {
  vbw_run fix done F2 F1
  [ "$status" -eq 0 ]
  [[ "$output" == *"F1 fixed: vbw prove decides"* ]]
  [[ "$output" == *"F2 fixed: vbw prove decides"* ]]
  [ "$(fix_status F1)" = fixed ] && [ "$(fix_status F2)" = fixed ]
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ]
}

@test "a code fix and a human requirement's fix each end as if closed alone" {
  vbw_run fix done F1 F3
  [ "$status" -eq 0 ]
  [[ "$output" == *"F1 fixed: vbw prove decides"* ]]
  [[ "$output" == *"F3 closed: its requirement goes back to the user for acceptance"* ]]
  [ "$(fix_status F1)" = fixed ] && [ "$(fix_status F3)" = closed ]
  jq -e '(.requirements[] | select(.id == "R4")).status == "open"' .vbw/record.json
}

@test "an unknown id and a fix that is not open are named and the others still close" {
  "$VBW" fix done F4 > /dev/null
  vbw_run fix done F1 F99 F4 F2
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown fix F99"* ]]
  [[ "$output" == *"F4 is not open"* ]]
  [ "$(fix_status F1)" = fixed ] && [ "$(fix_status F2)" = fixed ]
}

@test "a fix with uncommitted changes is named and the others still close" {
  printf 'dirty\n' >> src/refund.txt
  vbw_run fix done F1 F2
  [ "$status" -ne 0 ]
  [[ "$output" == *"F2 has uncommitted changes in: src/refund.txt"* ]]
  [ "$(fix_status F1)" = fixed ] && [ "$(fix_status F2)" = open ]
}

@test "a failing check fails only the fixes it serves, and is named" {
  printf 'broken\n' > src/refund.txt && git commit -q -am "fix: break refund"
  cp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run fix done F1 F2
  [ "$status" -ne 0 ]
  [[ "$output" == *"F2 broke finished work"*"C3 fail"* ]]
  [[ "$output" != *"F1 broke"* ]]
  [ "$(fix_status F1)" = fixed ] && [ "$(fix_status F2)" = open ]
  [ "$(runs C1)" = 1 ]
  jq -e '(.fixes[] | select(.id == "F2")) == ({id: "F2", req: "R3", attempts: 0, status: "open", note: "b"})' .vbw/record.json
  [ "$(jq -S 'del(.fixes, .passes)' .vbw/record.json)" = "$(jq -S 'del(.fixes, .passes)' "$TEST_ROOT/before.json")" ]
  vbw_run status
  [ "$status" -eq 0 ]
}

@test "a shared check that fails fails each fix it serves, not the fix of a human requirement" {
  printf 'broken\n' > src/pay.txt && git commit -q -am "fix: break pay"
  vbw_run fix done F1 F2 F3
  [ "$status" -ne 0 ]
  [[ "$output" == *"F1 broke finished work"*"C1 fail"* ]]
  [[ "$output" == *"F2 broke finished work"*"C1 fail"* ]]
  [ "$(fix_status F1)" = open ] && [ "$(fix_status F2)" = open ] && [ "$(fix_status F3)" = closed ]
  [ "$(runs C1)" = 1 ]
}

@test "the same id twice is closed once, without error" {
  vbw_run fix done F1 F1
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'F1 fixed')" -eq 1 ]
  [ "$(runs C1)" = 1 ]
}

@test "checks that passed on unchanged files are reused across the named fixes" {
  "$VBW" fix done F1 > /dev/null
  vbw_run fix done F4 F2
  [ "$status" -eq 0 ]
  [[ "$output" == *"C1 unchanged since its pass"* ]]
  [[ "$output" == *"C2 unchanged since its pass"* ]]
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ]
  [ "$(fix_status F4)" = fixed ] && [ "$(fix_status F2)" = fixed ]
}

@test "checks marked alone still run alone while several fixes close" {
  printf '%s' "$PLAN" | jq --arg m "$TEST_ROOT/bin/mark.sh" '.checks += [
    {id: "C4", req: "R1", run: ["sh", $m, "C4", "1"], alone: true}, {id: "C5", req: "R2", run: ["sh", $m, "C5", "3"]}]' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  "$VBW" check C5 > /dev/null 2>&1 &
  sleep 0.2
  vbw_run fix done F1 F2
  wait
  [ "$status" -eq 0 ]
  [ -n "$(awk '$2 == "C4" && $3 == "end"' "$TIMES/log")" ]
  run awk '
    $3 == "start" { s[$1] = $4; n[$1] = $2 }
    $3 == "end" { e[$1] = $4 }
    END { for (a in s) for (b in s) if (a < b && e[a] != "" && e[b] != "" && (n[a] == "C4" || n[b] == "C4") && s[a] < e[b] && s[b] < e[a]) print n[a], n[b] }' "$TIMES/log"
  [ -z "$output" ]
}

@test "fix retry still takes exactly one id, and fix done needs at least one" {
  vbw_run fix retry F1 F2
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
  vbw_run fix done
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
}
