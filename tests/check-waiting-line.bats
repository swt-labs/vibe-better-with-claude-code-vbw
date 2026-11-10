#!/usr/bin/env bats
# R288 (field report 2026-11-09, D685): a check or a break never waits on a check file
# waiting for approval, and says so only where it matters. vbw check and vbw mutate name
# a waiting check file only when a check they run has it as its file, in one line:
# '<file> is waiting for approval: <check ids> run now on its working content; vbw next
# asks the approval before the proof'. Another plan's waiting file, or one no running
# check reads, is not mentioned. Their exit status and the checks they run are as before.
# Every wait (a slot of the computer-wide limit, the project's check gate) is told by one
# function, once, with what it waits for and since when (tests/machine-wait-line.bats
# shows it on a real wait). The Dev's specification says the approval line is
# information, not a block. L1: two plans, each with its own check file; plan B's waits.

load helper
load fixture-helper

two_plans() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  printf 'receipt\n' > src/receipt.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  printf 'grep -qx receipt src/receipt.txt\n' > tests/c2.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1", "R2"], goal: "shop", criteria: ["pays"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.txt"], after: [], role: "dev", tasks: ["receipt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]}],
    rules: [{req: "R1", text: "paid is written", check: "C1"}, {req: "R2", text: "the receipt is written", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  [ -z "$(git status --porcelain)" ] || { git add -A && git commit -q -m "chore(vbw): approve"; }
  # Plan B's check file changes an approved line: it waits for approval.
  printf 'grep -qx "receipt" src/receipt.txt\n' > tests/c2.sh
}
setup_file() { fixture_build two two_plans; }
setup() { fixture_copy two; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

LINE='tests/c2.sh is waiting for approval: C2 run now on its working content; vbw next asks the approval before the proof'

@test "R288 check: a check of plan A, while plan B's test file waits, says nothing of the waiting file and runs as before" {
  vbw_run check C1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"tests/c2.sh"* && "$output" != *"waiting for approval"* ]] || { echo "$output"; false; }
  [[ "$output" == *"C1 pass"* ]] || { echo "$output"; false; }
}

@test "R288 check: a check of the waiting file says exactly the new line once, then runs on the file's working content with its own result" {
  vbw_run check C2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # Information, not a refusal: the line does not start with vbw: (a refusal's mark).
  [ "$(printf '%s\n' "$output" | grep -cxF "$LINE")" = 1 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'waiting for approval')" = 1 ] || { echo "$output"; false; }
  [[ "$output" == *"C2 pass"* ]] || { echo "$output"; false; }
  # The working content runs: a broken working file makes the check fail, and the exit says so.
  printf 'exit 1\n' > tests/c2.sh
  vbw_run check C2
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"C2 fail"* ]] || { echo "$output"; false; }
}

@test "R288 check: vbw check with no check named names the waiting file once, with only the checks that read it" {
  vbw_run check
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'waiting for approval')" = 1 ] && printf '%s\n' "$output" | grep -qF "$LINE" || { echo "$output"; false; }
  [[ "$output" == *"C1 pass"* && "$output" == *"C2 pass"* ]] || { echo "$output"; false; }
}

@test "R288 mutate: a break of plan A says nothing of plan B's waiting file; a break caught by C2 names it in the line" {
  # A break runs on a copy of the last commit, and vbw mutate refuses an uncommitted check
  # file, so plan B's changed file is committed first: it still waits for approval.
  git commit -q -m "test(receipt): quote the receipt" -- tests/c2.sh
  printf 'unpaid\n' > src/pay.txt
  vbw_run mutate P1.1 R1.1 "writes unpaid" src/pay.txt
  [[ "$output" != *"tests/c2.sh"* && "$output" != *"waiting for approval"* ]] || { echo "$output"; false; }
  [[ "$output" == *"red"* ]] || { echo "$output"; false; }
  git checkout -q -- src/pay.txt
  printf 'no receipt\n' > src/receipt.txt
  vbw_run mutate P1.2 R2.1 "writes no receipt" src/receipt.txt
  printf '%s\n' "$output" | grep -qF "$LINE" || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'is waiting for approval')" = 1 ] || { echo "$output"; false; }
}

@test "R288 check: fix done of a fix on plan A's requirement, while plan B's test file waits, runs no check and does not name plan B's file" {
  jq '.plans[].status = "done" | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  vbw_run fix done F1
  [[ "$output" == *"check files are waiting for approval, so no check runs before it"* ]] || { echo "$output"; false; }
  [[ "$output" != *"tests/c2.sh"* ]] || { echo "$output"; false; }
}

@test "R288 wording: every wait is told by one function with what it waits for and since when, and the Dev's specification says the approval line is information, not a block" {
  local defs
  defs=$(grep -rnE '^vbw_wait_say\(\)' "$PLUGIN_ROOT/lib" | wc -l | tr -d ' ')
  [ "$defs" = 1 ] || { echo "vbw_wait_say is defined $defs times"; false; }
  ! grep -rnE "(printf|echo|vbw_out)[^#]*waiting for [^#]*since" "$PLUGIN_ROOT/lib" | grep -v 'vbw_wait_say' || { echo "a wait line is worded outside vbw_wait_say"; false; }
  grep -qE 'slots_hold|computer-wide limit' <(grep -rn 'vbw_wait_say' "$PLUGIN_ROOT/lib/slots.sh") || { echo "the slot wait does not use vbw_wait_say"; false; }
  grep -rn 'vbw_wait_say' "$PLUGIN_ROOT/lib/checks.sh" > /dev/null || { echo "the check gate's wait does not use vbw_wait_say"; false; }
  grep -iE 'waiting for approval' "$PLUGIN_ROOT/agents/dev.md" | grep -qiE 'information, not a block' || { echo "dev.md does not say the approval line is information, not a block"; false; }
}

@test "R288 docs: docs/proof.md shows the waiting-for-approval line and the waiting line with its start time" {
  grep -qF 'is waiting for approval:' "$REPO_ROOT/docs/proof.md" || { echo "docs/proof.md does not show the approval line"; false; }
  grep -qE 'waiting for a free slot of the computer-wide limit since [0-9]{2}:[0-9]{2}' "$REPO_ROOT/docs/proof.md" || { echo "docs/proof.md does not show the waiting line"; false; }
}
