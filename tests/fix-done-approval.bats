#!/usr/bin/env bats
# T174 (docs/proof.md, docs/workflows.md): a fix round never waits silently for an
# approval no agent can ask for. While check files wait for the user's approval
# (a fix changed or added them), nothing can be proven before the user approves,
# so vbw fix done starts no re-check: it names the files, says the user approves
# them first (vbw next asks) and that vbw prove then runs every check, and the
# fixes await that proof as after any fix done. Without such files it re-checks
# finished work as before. The fixing workflow carries the files the closing
# agent read (fixdone.approval) and says the approval comes next. L1: the kernel
# on a fixture project, and the workflow with stubbed agents.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows/fixing.js"

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

# shop: R1 (pay) and R2 (receipt) built and approved; C2 logs each run in $RUNS;
# F1 (R1) is open.
shop() {
  vbw_git_project
  export RUNS="$TEST_ROOT/runs"
  mkdir -p "$RUNS" tests src
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  printf 'echo run >> "$RUNS/C2"\ngrep -qx sent src/receipt.txt\n' > tests/c2.sh
  jq -n '{phases: [{id: "P1", title: "Checkout", reqs: ["R1", "R2"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.txt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]}]}' | "$VBW" apply > /dev/null
  printf 'paid\n' > src/pay.txt && printf 'sent\n' > src/receipt.txt
  git add -A && git commit -q -m "feat: built"
  edit_record '.plans[].status = "done" | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

@test "T174: with a check file waiting for approval, fix done runs no check, names the file and says the approval comes first" {
  vbw_setup
  shop
  printf 'grep -qx paid src/pay.txt && test -s src/pay.txt\n' > tests/c1.sh
  "$VBW" commit --fix F1 "test(pay): stricter" tests/c1.sh > /dev/null
  run "$VBW" fix done F1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"waiting for approval"*"tests/c1.sh"* ]] || { echo "$output"; false; }
  [[ "$output" == *"no check runs before"* && "$output" == *"vbw next asks"* && "$output" == *"vbw prove"* ]] || { echo "$output"; false; }
  [[ "$output" == *"F1 fixed"* ]] || { echo "$output"; false; }
  [[ "$output" == *"checks: 0 ran, 0 reused"* ]] || { echo "$output"; false; }
  [ ! -f "$RUNS/C2" ] || { echo "C2 ran: $(cat "$RUNS/C2")"; false; }
  jq -e '.fixes[0].status == "fixed"' .vbw/record.json
  "$VBW" next --json | jq -e '.action == "approve" and .detail.files == ["tests/c1.sh"]' || "$VBW" next --json
}

@test "T174: with no check file waiting, fix done re-checks finished work as before" {
  vbw_setup
  shop
  run "$VBW" fix done F1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$RUNS/C2" ] || { echo "C2 did not run: $output"; false; }
  [[ "$output" != *"no check runs before"* ]] || { echo "$output"; false; }
}

@test "T174: the fixing workflow asks the closing agent for the files waiting for approval and says the approval comes next" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  local out
  out=$(node "$RUN" "$WF" '{"groups":[["F1"]],"session":"s1"}' \
    '{"F1":{"status":"done","summary":"s","notes":[]},"close run":{"fixdone":"ran","closed":["F1"],"open":[],"approval":["tests/c1.sh"],"ended":true,"recorded":true,"report":"all recorded; run ended"}}')
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")][0] | (.prompt | test("approval")) and (.opts.schema.properties.approval.type == "array")' \
    || { printf '%s' "$out" | jq '.calls[] | select(.opts.label == "close run")'; false; }
  printf '%s' "$out" | jq -e '.result.fixdone.approval == ["tests/c1.sh"] and .result.complete == true' || { printf '%s' "$out" | jq .result; false; }
  printf '%s' "$out" | jq -e 'any(.logs[]; test("approval") and test("tests/c1.sh") and test("vbw next"))' || { printf '%s' "$out" | jq .logs; false; }
}
