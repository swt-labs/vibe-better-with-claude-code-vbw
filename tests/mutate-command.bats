#!/usr/bin/env bats
# R188 (P139; docs/proof.md, docs/workflows.md): vbw mutate, the mutation check
# of one rule or one task. A Dev breaks the plan's own code on purpose, then:
#
#   vbw mutate PLAN RULE WHAT FILE...    RULE is R1.2: rule 2 of R1, numbered as
#                                         vbw show plan lists them; runs its check
#   vbw mutate PLAN taskK [--check ID]... WHAT FILE...
#                                         task K of the plan; runs the checks of
#                                         the plan's requirements (only the named
#                                         ones with --check)
#   vbw mutate PLAN taskK --none REASON  task K has no testable behaviour
#
# FILE... are the plan's files that hold the break. VBW runs the checks on the
# unbroken code and on the break, records the result under the plan
# (.plans[].mutations[]: rule {req, text} or task K, what, checks {ID: red |
# green}, result red | survivor; none REASON for a task with nothing to break),
# and leaves the named files exactly as their last commit. A break no check
# notices is a survivor: named with its rule, exit non-zero. Refusals write
# nothing. Recording a break never changes the contract. L1: the kernel on a
# fixture project.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf 'echo receipt\n' > src/receipt.sh
  # C1 checks what is printed; C3 only that one line is printed; C2 cannot fail
  # on what the receipt says.
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  printf '[ "$(sh src/pay.sh | wc -l | tr -d " ")" = 1 ]\n' > tests/pay-once.sh
  printf 'sh src/receipt.sh > /dev/null\n' > tests/receipt.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1", "R2"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay", "print once"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.sh", "tests/receipt.sh", "tests/pay-once.sh"], after: [], role: "dev", tasks: ["receipt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]},
             {id: "C3", req: "R1", run: ["sh", "tests/pay-once.sh"], files: ["tests/pay-once.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R1", text: "paying prints one line", check: "C3"},
            {req: "R2", text: "a receipt is printed", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

record_sum() { cksum < .vbw/record.json; }
breaks() { jq -c --arg p "$1" '[.plans[] | select(.id == $p) | .mutations // [] | .[]]' .vbw/record.json; }
# same_as_head FILE: the working file is byte-identical to its last commit.
same_as_head() {
  [ -z "$(git status --porcelain -- "$1")" ] || { echo "$1 differs from HEAD: $(git status --porcelain -- "$1")"; return 1; }
  cmp -s "$1" <(git show "HEAD:$1") || { echo "$1 is not its last commit"; return 1; }
}
# refused: the last run failed and the record is byte-identical to SUM.
refused() {
  [ "$status" -ne 0 ] || { echo "not refused: $output"; return 1; }
  [[ "$output" != *"unknown command"* ]] || { echo "no such command: $output"; return 1; }
  [ "$(record_sum)" = "$1" ] || { echo "the record changed: $output"; breaks P1.1; return 1; }
}

@test "R188: a break the rule's check notices is recorded as red under the plan: rule, description, checks run, each red or green" {
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *red* ]] || { echo "$output"; false; }
  breaks P1.1 | jq -e 'length == 1 and (.[0] | .rule == {req: "R1", text: "paying prints paid"}
    and .what == "prints unpaid instead of paid" and .checks == {C1: "red"} and .result == "red" and (has("task") | not))' \
    || { breaks P1.1; false; }
}

# with_sub_pay: P1.1's file is pay.sh in a submodule at sub/ (on branch main), and C1 checks it.
with_sub_pay() {
  git init -q -b main "$TEST_ROOT/subsrc"
  printf 'echo paid\n' > "$TEST_ROOT/subsrc/pay.sh"
  git -C "$TEST_ROOT/subsrc" add pay.sh
  git -C "$TEST_ROOT/subsrc" commit -q -m "chore: seed"
  git -c protocol.file.allow=always submodule add -q -b main "file://$TEST_ROOT/subsrc" sub
  git -C sub checkout -q main
  printf '[ "$(sh sub/pay.sh)" = paid ]\n' > tests/pay.sh
  jq '(.plans[] | select(.id == "P1.1")).files = ["sub/pay.sh"]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore: sub"
  "$VBW" approve > /dev/null
}

@test "R188: a break in a plan file inside a submodule runs on the submodule's code, is recorded red, and leaves the file as the submodule's last commit" {
  with_sub_pay
  printf 'echo unpaid\n' > sub/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" sub/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks P1.1 | jq -e 'length == 1 and .[0].checks == {C1: "red"} and .[0].result == "red"' || { breaks P1.1; false; }
  [ -z "$(git -C sub status --porcelain -- pay.sh)" ] || { git -C sub status --porcelain; false; }
  cmp -s sub/pay.sh <(git -C sub show HEAD:pay.sh)
  # A proof copy reused for the next break (mutate_clean) gets the file back from the
  # submodule's last commit, in the submodule's folder of the copy.
  mkdir -p "$TEST_ROOT/copy/sub"
  printf 'echo broken\n' > "$TEST_ROOT/copy/sub/pay.sh"
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  COPY="$TEST_ROOT/copy" vbw_kernel '. "$VBW_LIB/cmd-mutate.sh"; mutate_clean "$COPY" sub/pay.sh'
  cmp -s "$TEST_ROOT/copy/sub/pay.sh" <(git -C sub show HEAD:pay.sh) || { ls -la "$TEST_ROOT/copy/sub"; false; }
}

@test "R188: a commit in a submodule makes the checks run on the unbroken code again: a check it broke is refused, never a kill" {
  with_sub_pay
  printf 'echo unpaid\n' > sub/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" sub/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # A bug committed in the submodule: the project's HEAD does not move.
  local head sum
  head=$(git rev-parse HEAD)
  printf 'echo nope\n' > sub/pay.sh
  git -C sub commit -q -am "feat(pay): a bug"
  [ "$(git rev-parse HEAD)" = "$head" ]
  sum=$(record_sum)
  printf 'echo unpaid\n' > sub/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid again" sub/pay.sh < /dev/null
  refused "$sum"
  [[ "$output" == *"do not pass on the unbroken code"*C1* ]] || { echo "$output"; false; }
}

@test "R188: a rule's own check is the one that runs, even when the requirement has others" {
  printf 'echo paid\necho paid\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.2 "prints paid twice" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks P1.1 | jq -e '.[0].rule == {req: "R1", text: "paying prints one line"} and .[0].checks == {C3: "red"} and .[0].result == "red"' \
    || { breaks P1.1; false; }
}

@test "R188: nothing differs from the plan's last commit: refused, nothing written" {
  local sum
  sum=$(record_sum)
  run "$VBW" mutate P1.1 R1.1 "no break at all" src/pay.sh < /dev/null
  refused "$sum"
  [[ "$output" =~ nothing|no\ break ]] || { echo "$output"; false; }
}

@test "R188: a break in a file outside the plan's files is refused, nothing written" {
  local sum
  sum=$(record_sum)
  printf 'echo nothing\n' > src/receipt.sh
  run "$VBW" mutate P1.1 R1.1 "breaks the receipt" src/receipt.sh < /dev/null
  refused "$sum"
  [[ "$output" == *src/receipt.sh* ]] || { echo "$output"; false; }
}

@test "R188: a break that touches a check file is refused, nothing written: named, or left changed beside the break" {
  local sum
  sum=$(record_sum)
  # P1.2 lists its own check file among its files: breaking it is still refused.
  printf 'true\n' > tests/receipt.sh
  run "$VBW" mutate P1.2 R2.1 "the test passes on anything" tests/receipt.sh < /dev/null
  refused "$sum"
  [[ "$output" == *tests/receipt.sh* ]] || { echo "$output"; false; }
  git checkout -q -- tests/receipt.sh
  # A plan file that is the check file of a check this break does not run is named alone: still refused.
  printf 'true\n' > tests/pay-once.sh
  run "$VBW" mutate P1.2 R2.1 "the other test passes on anything" tests/pay-once.sh < /dev/null
  refused "$sum"
  [[ "$output" == *tests/pay-once.sh* ]] || { echo "$output"; false; }
  git checkout -q -- tests/pay-once.sh
  # A check file of the checks to run changed and not committed: the run would not test what was approved.
  printf 'echo unpaid\n' > src/pay.sh
  printf 'true\n' > tests/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid" src/pay.sh < /dev/null
  refused "$sum"
  [[ "$output" == *tests/pay.sh* ]] || { echo "$output"; false; }
}

@test "R188: checks that do not pass on the unbroken code are refused, nothing written" {
  printf 'echo nope\n' > src/pay.sh
  git commit -q -am "feat(pay): a bug"
  local sum
  sum=$(record_sum)
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid" src/pay.sh < /dev/null
  refused "$sum"
  [[ "$output" == *C1* ]] || { echo "$output"; false; }
}

@test "R188: a break no check notices is recorded as a survivor, named with its rule, and the command fails" {
  printf 'echo nothing\n' > src/receipt.sh
  run "$VBW" mutate P1.2 R2.1 "prints nothing useful" src/receipt.sh < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *survivor* && "$output" == *R2.1* && "$output" == *"a receipt is printed"* ]] || { echo "$output"; false; }
  breaks P1.2 | jq -e 'length == 1 and .[0].result == "survivor" and .[0].checks == {C2: "green"}
    and .[0].rule == {req: "R2", text: "a receipt is printed"}' || { breaks P1.2; false; }
}

@test "R188: a red break after a survivor of the same rule is recorded when the check protects no files, under /bin/bash 3.2" {
  # A check's files list is optional: cfiles is then empty, and under set -u
  # bash 3.2 stops on an unguarded "${cfiles[@]}" after the checks ran.
  git rm -q --cached -r . > /dev/null 2>&1 || true
  rm -rf .git .vbw
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo receipt\n' > src/receipt.sh
  printf 'sh src/receipt.sh > /dev/null\n' > tests/receipt.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Receipt", reqs: ["R1"], files: ["src/receipt.sh"], after: [], role: "dev", tasks: ["receipt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/receipt.sh"]}],
    rules: [{req: "R1", text: "a receipt is printed", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  printf 'echo nothing\n' > src/receipt.sh
  run /bin/bash "$VBW" mutate P1.1 R1.1 "prints nothing useful" src/receipt.sh < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *survivor* ]] || { echo "$output"; false; }
  git checkout -q -- src/receipt.sh
  printf 'exit 1\n' > src/receipt.sh
  run /bin/bash "$VBW" mutate P1.1 R1.1 "fails outright" src/receipt.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"unbound variable"* ]] || { echo "$output"; false; }
  breaks P1.1 | jq -e 'length == 2 and .[1].result == "red"' || { breaks P1.1; false; }
}

@test "R188: after a mutation check the named files are byte-identical to their last commit, red or survivor" {
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 "prints unpaid" src/pay.sh < /dev/null > /dev/null
  same_as_head src/pay.sh
  printf 'echo nothing\n' > src/receipt.sh
  "$VBW" mutate P1.2 R2.1 "prints nothing useful" src/receipt.sh < /dev/null > /dev/null || true
  same_as_head src/receipt.sh
}

@test "R188: recording a break leaves the contract approved, its fingerprint unchanged" {
  local before
  before=$("$VBW" show contract < /dev/null | head -n 1)
  [[ "$before" == *"(approved)"* ]] || { echo "$before"; false; }
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 "prints unpaid" src/pay.sh < /dev/null > /dev/null
  [ "$(breaks P1.1 | jq length)" -eq 1 ]
  [ "$("$VBW" show contract < /dev/null | head -n 1)" = "$before" ]
}

@test "R188: a task break runs the checks of the plan's requirements; --check narrows it to the named ones" {
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 "prints unpaid" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks P1.1 | jq -e '.[0].task == 1 and .[0].checks == {C1: "red"} and .[0].result == "red" and (.[0] | has("rule") | not)' \
    || { breaks P1.1; false; }
  printf 'echo paid\necho paid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task2 --check C3 "prints paid twice" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks P1.1 | jq -e '.[1].task == 2 and .[1].checks == {C3: "red"}' || { breaks P1.1; false; }
  # A check of another requirement is not this plan's to run.
  local sum
  sum=$(record_sum)
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 --check C2 "prints unpaid" src/pay.sh < /dev/null
  refused "$sum"
}

@test "R188: a task marked as having no testable behaviour is recorded with its reason, and nothing runs" {
  run "$VBW" mutate P1.1 task2 --none "only renames a variable" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks P1.1 | jq -e 'length == 1 and .[0].task == 2 and .[0].none == "only renames a variable" and (.[0] | has("checks") | not)' \
    || { breaks P1.1; false; }
  # A rule always has behaviour to break, and a reason cannot be empty.
  local sum
  sum=$(record_sum)
  run "$VBW" mutate P1.1 R1.1 --none "nothing to test" < /dev/null
  refused "$sum"
  [[ "$output" == *"a rule"* ]] || { echo "$output"; false; }
  run "$VBW" mutate P1.1 task1 --none "" < /dev/null
  refused "$sum"
  [[ "$output" == *"needs a reason"* ]] || { echo "$output"; false; }
}

@test "R188: an unknown plan, rule or task, or a rule of a requirement the plan does not serve, is refused, nothing written" {
  local sum
  sum=$(record_sum)
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P9.9 R1.1 "prints unpaid" src/pay.sh < /dev/null
  refused "$sum"
  [[ "$output" == *"unknown plan P9.9"* ]] || { echo "$output"; false; }
  run "$VBW" mutate P1.1 R1.9 "prints unpaid" src/pay.sh < /dev/null
  refused "$sum"
  [[ "$output" == *"no rule 9"* ]] || { echo "$output"; false; }
  run "$VBW" mutate P1.1 R2.1 "prints unpaid" src/pay.sh < /dev/null
  refused "$sum"
  [[ "$output" == *"does not serve R2"* ]] || { echo "$output"; false; }
  run "$VBW" mutate P1.1 task9 "prints unpaid" src/pay.sh < /dev/null
  refused "$sum"
  [[ "$output" == *"no task 9"* ]] || { echo "$output"; false; }
}

@test "R188: the new kernel code is bash 3.2 code that passes JSON only through jq" {
  local f="$PLUGIN_ROOT/lib/cmd-mutate.sh"
  [ -f "$f" ] || { echo "missing $f"; false; }
  /bin/bash -n "$f"
  # Bash 3.2: no mapfile or readarray, no associative arrays, no case-modifying expansions; no data as code.
  ! grep -nE '^[^#]*(\b(mapfile|readarray|eval)\b|(declare|local|typeset) -[a-zA-Z]*A|\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^|,|\^)\})' "$f" || false
  # JSON only through jq.
  ! grep -nE '^[^#]*\b(grep|sed|awk|cut)\b[^|;]*(record\.json|\.json\b)' "$f" || false
}
