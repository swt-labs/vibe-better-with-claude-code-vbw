#!/usr/bin/env bats
# R43: vbw fix done does not rerun a check that already passed on the same
# project files under the same approved contract, and says so; vbw prove still
# runs every check (docs/proof.md). Checks count their runs in $RUNS. Passes are
# a cache of this clone, kept in its git directory, never in the record: an
# older VBW still reads the record, and closing a fix leaves no record change.

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

# passes: this clone's recorded passes ({} when there are none).
passes() { cat "$(git rev-parse --git-common-dir)/vbw/passes.json" 2> /dev/null || printf '{}'; }

# runs ID: how many times the check ran.
runs() { if [ -f "$RUNS/$1" ]; then wc -l < "$RUNS/$1" | tr -d ' '; else printf 0; fi; }

@test "a passing check is recorded with its time, the contract hash and a fingerprint of its files" {
  vbw_run fix done F1
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 1 ]
  passes | jq -e --arg h "$(vbw_contract_hash)" '.C1 | .contract == $h and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")) and (.tree | type == "string" and length >= 40)'
  passes | jq -e '.C2 != null'
  jq -e 'has("passes") | not' .vbw/record.json
}

@test "an unchanged pass is not rerun, and the output says so with the date of the pass" {
  "$VBW" fix done F1 > /dev/null
  at=$(passes | jq -r '.C1.at')
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
  passes | jq -e '.C1 == null'
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
  passes | jq -e '.C3 == null'
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
  passes | jq -e '.C1 == null'
  git add src/extra.txt && git commit -q -m "feat: extra"
  vbw_run fix done F2
  [ "$(runs C1)" = 2 ]
  passes | jq -e '.C1 != null'
}

@test "uncommitted changes in the fix's files still block closing, and nothing reruns" {
  "$VBW" fix done F1 > /dev/null
  printf 'dirty\n' >> src/receipt.txt
  vbw_run fix done F2
  [ "$status" -eq 1 ]
  [[ "$output" == *"F2 has uncommitted changes in: src/receipt.txt"* ]]
  [ "$(runs C1)" = 1 ]
}

@test "vbw prove records the passes a fix reuses, and reuses its own on unchanged code" {
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 1 ]
  passes | jq -e '.C1 != null and .C2 != null'
  jq -e 'has("passes") | not' .vbw/record.json
  # A passing proof closes the open fixes; a fix found afterwards reuses its passes.
  edit_record '.fixes += [{id: "F4", req: "R2", attempts: 0, status: "open", note: "d"}]'
  vbw_run fix done F4
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 1 ]
  [[ "$output" == *"C1 unchanged since its pass"* ]]
  vbw_run prove
  # C3 declares no files, so closing F4 ran it too. Only the record changed since
  # the passing proof, so the proof reuses every result (R103) and runs nothing.
  [ "$(runs C1)" = 1 ] && [ "$(runs C2)" = 1 ] && [ "$(runs C3)" = 2 ]
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

@test "a missing or damaged passes file only means the checks run again" {
  "$VBW" fix done F1 > /dev/null
  printf 'not json' > "$(git rev-parse --git-common-dir)/vbw/passes.json"
  vbw_run fix done F2
  [ "$status" -eq 0 ]
  [ "$(runs C1)" = 2 ]
  [[ "$output" != *"C1 unchanged"* ]]
  passes | jq -e '.C1 != null'
  rm "$(git rev-parse --git-common-dir)/vbw/passes.json"
  vbw_run status
  [ "$status" -eq 0 ]
}

@test "the record never holds passes, so VBW 2.0.16 still reads it, and closing a fix leaves no record change to commit" {
  vbw_run prove
  [ "$status" -eq 0 ]
  jq -e 'has("passes") | not' .vbw/record.json
  passes | jq -e '.C1 != null'
  edit_record '.fixes += [{id: "F4", req: "R2", attempts: 0, status: "open", note: "d"}]'
  before=$(jq -S 'del(.fixes)' .vbw/record.json)
  vbw_run fix done F4
  [ "$status" -eq 0 ]
  [ "$(jq -S 'del(.fixes)' .vbw/record.json)" = "$before" ]
}

@test "a pass of a check the contract no longer has is never used, and the record stays readable" {
  vbw_run prove
  [ "$status" -eq 0 ]
  printf '%s' "$PLAN" | jq '.checks |= map(select(.id != "C1"))' | "$VBW" apply > /dev/null
  vbw_run status
  [ "$status" -eq 0 ]
  jq -e 'has("passes") | not' .vbw/record.json
}
