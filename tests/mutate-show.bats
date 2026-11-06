#!/usr/bin/env bats
# R188 (P139; docs/workflows.md): vbw show plan gives a Dev what the mutation
# check needs and shows what it found. It names the phase's tier and what the
# mutation check asks at that tier, lists the rules of the plan's requirements
# numbered as vbw mutate takes them (R1.1) with their check, and lists each
# recorded break: its rule or task, the description, red or survivor, each
# check's red or green, the check files strengthened after a survivor, and the
# reason of a task with no testable behaviour. --json carries the breaks. L1.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay", "log the payment"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R1", text: "nothing but paid is printed", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
show() { "$VBW" show plan P1.1 < /dev/null; }
# line REGEX: show plan has a line matching REGEX (extended, case-insensitive).
line() { show | grep -Eiq -- "$1" || { echo "no line matches $1:"; show; return 1; }; }

@test "R188: show plan lists the rules numbered as vbw mutate takes them, each with its check" {
  line 'R1\.1.*paying prints paid.*C1'
  line 'R1\.2.*nothing but paid is printed.*C1'
}

@test "R188: show plan names the tier and what the mutation check asks at it; at express it asks nothing" {
  line '^tier: standard.*mutation'
  edit_record '.phases[0].tier = "deep"'
  line '^tier: deep.*mutation.*task'
  edit_record '.phases[0].tier = "express"'
  line '^tier: express'
  ! show | grep -i '^tier:' | grep -qi mutation || { show; false; }
}

@test "R188: show plan lists each break: target, description, result, and each check red or green" {
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh < /dev/null > /dev/null
  line 'R1\.1.*prints unpaid instead of paid.*red'
  line 'C1[: ]+red'
}

@test "R188: a survivor is listed as such, and the check file strengthened before its red break is named" {
  printf 'echo paid\necho oops >&2\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.2 "prints oops on stderr" src/pay.sh < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  line 'R1\.2.*prints oops on stderr.*survivor'
  line 'C1[: ]+green'
  git checkout -q -- src/pay.sh
  printf '[ "$(sh src/pay.sh 2>&1)" = paid ]\n' > tests/pay.sh
  git commit -q -am "test(pay): nothing but paid, on either stream"
  "$VBW" approve > /dev/null
  printf 'echo paid\necho oops >&2\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.2 "prints oops on stderr" src/pay.sh < /dev/null > /dev/null
  line 'R1\.2.*prints oops on stderr.*red'
  line 'strengthened.*tests/pay\.sh'
}

@test "R188: a task with no testable behaviour is shown with its reason" {
  "$VBW" mutate P1.1 task2 --none "only writes a log line nothing reads" < /dev/null > /dev/null
  line 'task2.*only writes a log line nothing reads'
}

@test "R188: show plan --json carries the recorded breaks" {
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 task1 "prints unpaid" src/pay.sh < /dev/null > /dev/null
  "$VBW" show plan P1.1 --json < /dev/null | jq -e '.plan.mutations | length == 1 and .[0].task == 1 and .[0].result == "red"'
}
