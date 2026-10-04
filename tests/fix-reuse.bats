#!/usr/bin/env bats
# R43: vbw fix done does not rerun a check that already passed on the same
# project files under the same approved contract, and says so; vbw prove still
# runs every check (docs/proof.md). Checks count their runs in $RUNS.

load helper

setup() {
  vbw_setup
  vbw_git_project
  export RUNS="$TEST_ROOT/runs"
  mkdir -p "$RUNS" "$TEST_ROOT/bin"
  printf 'echo run >> "$RUNS/$1"\n' > "$TEST_ROOT/bin/count.sh"
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n- R3 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'echo run >> "$RUNS/C1"\ngrep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'echo run >> "$RUNS/C2"\ngrep -qx sent src/receipt.txt\n' > tests/receipt.sh
  PLAN=$(jq -n --arg c "$TEST_ROOT/bin/count.sh" '{phases: [{id: "P1", title: "Checkout", reqs: ["R1", "R2", "R3"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.txt", "src/pay.txt"]},
            {id: "P1.3", phase: "P1", title: "Look", reqs: ["R3"], files: ["src/ui.txt", "src/pay.txt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]},
             {id: "C3", req: "R1", run: ["sh", $c, "C3"]}]}')
  printf '%s' "$PLAN" | "$VBW" apply > /dev/null
  printf 'paid\n' > src/pay.txt && printf 'sent\n' > src/receipt.txt && printf 'ui\n' > src/ui.txt
  git add -A && git commit -q -m "feat: built"
  edit_record '.plans[].status = "done"
    | .fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "a"},
                {id: "F2", req: "R2", attempts: 0, status: "open", note: "b"},
                {id: "F3", req: "R3", attempts: 0, status: "open", note: "c"}]'
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# runs ID: how many times the check ran.
runs() { if [ -f "$RUNS/$1" ]; then wc -l < "$RUNS/$1" | tr -d ' '; else printf 0; fi; }

@test "a passing check is recorded with its time, the contract hash and a fingerprint of its files" {
  vbw_run fix done F1
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 1 ]
  jq -e --arg h "$(vbw_contract_hash)" '.passes.C1 | .contract == $h and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")) and (.tree | type == "string" and length >= 40)' .vbw/record.json
  jq -e '.passes.C2 != null and .schema == 1' .vbw/record.json
}

@test "an unchanged pass is not rerun, and the output says so with the date of the pass" {
  "$VBW" fix done F1 > /dev/null
  at=$(jq -r '.passes.C1.at' .vbw/record.json)
  vbw_run fix done F2
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ]
  [[ "$output" == *"C1 unchanged since its pass"*"$at"* ]]
  [[ "$output" == *"C2 unchanged since its pass"* ]]
  jq -e '(.fixes[] | select(.id == "F2")).status == "fixed"' .vbw/record.json
}

@test "a committed change to a served file reruns the check" {
  "$VBW" fix done F1 > /dev/null
  printf 'more\n' >> src/pay.txt && git commit -q -am "fix: pay"
  vbw_run fix done F2
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 2 ] && [ "$(runs C2)" = 2 ]
  [[ "$output" != *"C1 unchanged"* ]]
}

@test "a changed approved contract reruns the check" {
  "$VBW" fix done F1 > /dev/null
  printf '%s' "$PLAN" | jq '.checks[0].timeout = 100' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  vbw_run fix done F2
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 2 ]
  [[ "$output" != *"C1 unchanged"* ]]
}

@test "a check that last failed is rerun even when the files match an earlier pass" {
  "$VBW" fix done F1 > /dev/null
  printf 'broken\n' > src/pay.txt && git commit -q -am "fix: break"
  vbw_run fix done F2
  [ "$status" -eq 1 ]
  [[ "$output" == *"F2 broke finished work"*"C1 fail"* ]]
  [ "$(runs C1)" = 2 ]
  jq -e '.passes.C1 == null' .vbw/record.json
  printf 'paid\n' > src/pay.txt && git commit -q -am "fix: restore"
  vbw_run fix done F2
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 3 ]
  [[ "$output" != *"C1 unchanged"* ]]
}

@test "a check that never ran is run, and a check with no declared files is always rerun" {
  [ "$(runs C1)" = 0 ]
  "$VBW" fix done F1 > /dev/null
  vbw_run fix done F2
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 1 ] && [ "$(runs C3)" = 2 ]
  [[ "$output" != *"C3 unchanged"* ]]
  jq -e '.passes.C3 == null' .vbw/record.json
}

@test "a check whose served files cannot be fingerprinted is always rerun" {
  edit_record '(.plans[] | select(.id == "P1.1")).files = ["src/pay.txt", "src/missing.txt"]'
  vbw_consent_contract
  "$VBW" fix done F1 > /dev/null
  vbw_run fix done F2
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 2 ]
  [[ "$output" != *"C1 unchanged"* ]]
}

@test "a pass is not recorded while a served file has uncommitted changes" {
  printf 'x\n' > src/extra.txt
  edit_record '(.plans[] | select(.id == "P1.1")).files = ["src/pay.txt", "src/extra.txt"]'
  vbw_consent_contract
  vbw_run fix done F1
  [ "$status" -eq 0 ]
  jq -e '.passes.C1 == null' .vbw/record.json
  git add src/extra.txt && git commit -q -m "feat: extra"
  vbw_run fix done F2
  [ "$(runs C1)" = 2 ]
  jq -e '.passes.C1 != null' .vbw/record.json
}

@test "uncommitted changes in the fix's files still block closing, and nothing reruns" {
  "$VBW" fix done F1 > /dev/null
  printf 'dirty\n' >> src/receipt.txt
  vbw_run fix done F2
  [ "$status" -eq 1 ]
  [[ "$output" == *"F2 has uncommitted changes in: src/receipt.txt"* ]]
  [ "$(runs C1)" = 1 ]
}

@test "vbw prove runs every check and records the passes the fix reuses" {
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ]
  jq -e '.passes.C1 != null and .passes.C2 != null' .vbw/record.json
  vbw_run fix done F1
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 1 ]
  [[ "$output" == *"C1 unchanged since its pass"* ]]
  vbw_run prove
  [ "$(runs C1)" = 2 ] && [ "$(runs C2)" = 2 ] && [ "$(runs C3)" = 2 ]
}

@test "vbw prove still fails on a failing check whatever was recorded" {
  "$VBW" fix done F1 > /dev/null
  printf 'broken\n' > src/pay.txt && git commit -q -am "fix: break"
  vbw_run prove
  [ "$status" -eq 1 ]
  [[ "$output" == *"C1 fail"* ]]
  [ "$(runs C1)" = 2 ]
}

@test "closing outcomes are the same when a check is skipped: fixed for code, closed for a human requirement" {
  "$VBW" fix done F1 > /dev/null
  vbw_run fix done F3
  [ "$status" -eq 0 ]
  [[ "$output" == *"F3 closed: its requirement goes back to the user for acceptance"* ]]
  [ "$(runs C1)" = 1 ]
  jq -e '(.fixes[] | select(.id == "F3")).status == "closed" and (.requirements[] | select(.id == "R3")).status == "open"' .vbw/record.json
  jq -e '(.fixes[] | select(.id == "F1")).status == "fixed"' .vbw/record.json
}

@test "a record without recorded passes reads fine, and a malformed pass is refused by the record writer" {
  jq -e 'has("passes") | not' .vbw/record.json
  vbw_run status
  [ "$status" -eq 0 ]
  edit_record '.passes = {C1: {at: "2026-10-04T10:00:00Z", contract: "0000000000000000000000000000000000000000000000000000000000000000", tree: "1111111111111111111111111111111111111111111111111111111111111111"}}'
  vbw_run status
  [ "$status" -eq 0 ]
  edit_record '.passes = {C1: {at: "yesterday", contract: "x", tree: 5}}'
  vbw_run status
  [ "$status" -eq 3 ]
  [[ "$output" == *"passes"* ]]
  edit_record '.passes = {C99: {at: "2026-10-04T10:00:00Z", contract: "x", tree: "y"}}'
  vbw_run status
  [ "$status" -eq 3 ]
}
