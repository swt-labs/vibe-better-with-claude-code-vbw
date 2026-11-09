#!/usr/bin/env bats
# R292 (field report 2026-11-09, D685): red first is recorded and shown, never refused.
# Each vbw check --expect-red run is kept in the plan's evidence (plans[].red_runs: the
# checks it ran with each one's result, red or green, the commit it ran on and the time;
# schema 15, the row R286 opened). vbw plan done prints one line naming the plan's own
# checks that never ran red before its first code commit, or that every one did; a check
# another plan owns counts that plan's red run; a plan with no own checks prints no such
# line. plan done's exit status and what it records are unchanged by the line. QA gets,
# per plan, the checks that never ran red first (vbw next --json's round.red_first) and
# reports each as a deviation, not a failure. L1: R1 built by P1.1; R2 by P1.2 and P1.3,
# whose rules name no plan (C2 is both plans' own check); R3 [human] by P1.4.

load helper
load fixture-helper

shop() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n- R3 [human] The shop looks friendly\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests docs
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  printf 'grep -qx receipt src/receipt.txt\n' > tests/c2.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1", "R2", "R3"], goal: "shop", criteria: ["pays"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P1.2", phase: "P1", title: "Receipt text", reqs: ["R2"], files: ["src/receipt.txt"], after: [], role: "dev", tasks: ["receipt"]},
            {id: "P1.3", phase: "P1", title: "Receipt note", reqs: ["R2"], files: ["src/note.txt"], after: ["P1.2"], role: "dev", tasks: ["note"]},
            {id: "P1.4", phase: "P1", title: "Look", reqs: ["R3"], files: ["docs/look.md"], after: [], role: "docs", tasks: ["look"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]}],
    rules: [{req: "R1", text: "paid is written", check: "C1"}, {req: "R2", text: "the receipt is written", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  [ -z "$(git status --porcelain)" ] || { git add -A && git commit -q -m "chore(vbw): approve"; }
}
setup_file() { fixture_build shop shop; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# build PLAN FILE TEXT: a build run of PLAN writes FILE and commits it through vbw commit (its first code commit).
build() {
  printf '%s\n' "$3" > "$2"
  "$VBW" commit "$1" "feat(shop): $1" > /dev/null
}
# caught PLAN RULE FILE TEXT: the standard tier's break before plan done: FILE broken to TEXT, caught, then put back.
caught() {
  local good
  good=$(cat "$3")
  printf '%s\n' "$4" > "$3"
  "$VBW" mutate "$1" "$2" "breaks $3" "$3" > /dev/null < /dev/null
  printf '%s\n' "$good" > "$3"
}
start() { VBW_SESSION_ID=s1 "$VBW" run start build "$@" > /dev/null; }
finish() { VBW_SESSION_ID=s1 "$VBW" run end > /dev/null; }
plan_of() { jq -c --arg p "$1" '.plans[] | select(.id == $p)' .vbw/record.json; }

@test "R292 kept: each vbw check --expect-red run is kept in the plan's evidence with each check's result, the commit and the time; a green result too" {
  start P1.1
  vbw_run check --expect-red C1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  plan_of P1.1 | jq -e --arg h "$(git rev-parse HEAD)" '(.red_runs | length) == 1 and (.red_runs[0] | .checks == {C1: "red"} and .head == $h
    and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")))' || { plan_of P1.1; false; }
  printf 'paid\n' > src/pay.txt
  vbw_run check --expect-red C1
  [ "$status" -ne 0 ] || { echo "a green --expect-red run passed: $output"; false; }
  plan_of P1.1 | jq -e '(.red_runs | length) == 2 and .red_runs[1].checks == {C1: "green"}' || { plan_of P1.1; false; }
  jq -e '.schema == 15' .vbw/record.json || { jq .schema .vbw/record.json; false; }
}

@test "R292 plan done: a plan whose own check never ran red before its first code commit is done, with one line naming the check for QA" {
  start P1.1
  build P1.1 src/pay.txt paid
  caught P1.1 R1.1 src/pay.txt unpaid
  local before
  before=$(plan_of P1.1 | jq -c 'del(.status)')
  vbw_run plan done P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^Red first: ')" = 1 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qxF "Red first: C1 never ran red before this plan's first code commit; QA judges this" || { echo "$output"; false; }
  plan_of P1.1 | jq -e '.status == "done"' > /dev/null || { plan_of P1.1; false; }
  [ "$(plan_of P1.1 | jq -c 'del(.status)')" = "$before" ] || { echo "plan done recorded more: $(plan_of P1.1)"; false; }
}

@test "R292 plan done: a red run after the first code commit does not count; one before it does, and plan done says every check ran red first" {
  start P1.1
  build P1.1 src/pay.txt unpaid
  vbw_run check --expect-red C1
  printf 'paid\n' > src/pay.txt
  "$VBW" commit P1.1 "fix(shop): paid" > /dev/null
  caught P1.1 R1.1 src/pay.txt unpaid
  vbw_run plan done P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qxF "Red first: C1 never ran red before this plan's first code commit; QA judges this" || { echo "$output"; false; }
  finish
  # A fresh copy: the red run comes first.
  fixture_copy shop
  start P1.1
  vbw_run check --expect-red C1
  build P1.1 src/pay.txt paid
  caught P1.1 R1.1 src/pay.txt unpaid
  vbw_run plan done P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -E '^Red first: ' | grep -qF 'every check' || { echo "$output"; false; }
}

@test "R292 plan done: a check another plan owns counts that plan's red run; a plan with no own checks prints no Red first line" {
  start P1.2
  vbw_run check --expect-red C2
  build P1.2 src/receipt.txt receipt
  caught P1.2 R2.1 src/receipt.txt none
  "$VBW" plan done P1.2 > /dev/null
  finish
  start P1.3
  build P1.3 src/note.txt note
  vbw_run plan done P1.3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -E '^Red first: ' | grep -qF 'every check' || { echo "P1.2's red run of C2 did not count for P1.3: $output"; false; }
  finish
  start P1.4
  build P1.4 docs/look.md "friendly"
  vbw_run plan done P1.4
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"Red first"* ]] || { echo "$output"; false; }
}

@test "R292 QA: vbw next --json gives QA, per plan, the checks that never ran red first, and the QA brief reports each as a deviation, not a failure" {
  start P1.1 P1.2 P1.4
  vbw_run check --expect-red C2
  build P1.1 src/pay.txt paid
  build P1.2 src/receipt.txt receipt
  build P1.4 docs/look.md friendly
  caught P1.1 R1.1 src/pay.txt unpaid
  caught P1.2 R2.1 src/receipt.txt none
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" plan done P1.2 > /dev/null
  "$VBW" plan done P1.4 > /dev/null
  finish
  start P1.3
  build P1.3 src/note.txt note
  "$VBW" plan done P1.3 > /dev/null
  finish
  "$VBW" prove > /dev/null || { "$VBW" prove; false; }
  local n
  n=$(VBW_SESSION_ID=s1 "$VBW" next --json < /dev/null)
  printf '%s' "$n" | jq -e '.action == "qa" and .round.red_first == {"P1.1": ["C1"]}' > /dev/null || { printf '%s' "$n" | jq -c '{action, red_first: .round.red_first}'; false; }
  grep -q 'red_first' "$PLUGIN_ROOT/workflows/verifying.js" || { echo "the QA workflow does not pass red_first to QA"; false; }
  grep -iE 'red first|red_first' "$PLUGIN_ROOT/agents/qa.md" | grep -qiE 'deviation' || { echo "qa.md does not say a check that never ran red first is a deviation"; false; }
}

@test "R292 docs: docs/workflows.md describes the Red first line at plan done, that it never refuses, and that QA judges it as a deviation" {
  local d="$REPO_ROOT/docs/workflows.md"
  grep -qF 'Red first:' "$d" || { echo "docs/workflows.md does not show the Red first line"; false; }
  grep -iE 'red first' "$d" | grep -qiE 'never refuses|does not refuse' || { echo "docs/workflows.md does not say plan done never refuses on it"; false; }
  grep -iE 'red first' "$d" | grep -qiE 'deviation' || { echo "docs/workflows.md does not say QA judges it as a deviation"; false; }
}
