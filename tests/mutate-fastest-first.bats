#!/usr/bin/env bats
# T157 (R188; docs/proof.md): a task break with several checks (deep tier) runs
# them one at a time, fastest first by their last recorded time in the run store
# (.git/vbw/runs.json; a check never run counts as slowest), and stops at the
# first that goes red: one red check is the proof. A survivor still runs every
# check. Before, every check of the requirement ran on each task break, so a
# slow test suite paid its full time per break. A rule break runs its one check
# as before. L1: the kernel on a fixture project.

load helper
load fixture-helper

fastest_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  # Both checks catch a wrong price; the slow one marks that it ran.
  # The marker's place is read from TEST_ROOT when the check runs (a check keeps the environment), so the committed file holds no path.
  # shellcheck disable=SC2016 # expanded by the check, not here
  printf 'touch "$TEST_ROOT/slow.ran"; [ "$(sh src/pay.sh)" = paid ]\n' > tests/slow.sh
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/fast.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "deep"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/slow.sh"], files: ["tests/slow.sh"]},
             {id: "C2", req: "R1", run: ["sh", "tests/fast.sh"], files: ["tests/fast.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"}, {req: "R1", text: "paying is quick to check", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  # The run store says C1 took 300 s and C2 1 s last time.
  local store
  store="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"
  mkdir -p "$(dirname "$store")"
  jq -nc '{runs: {"check:C1": {status: "pass", seconds: 300}, "check:C2": {status: "pass", seconds: 1}}}' > "$store"
}

setup_file() { fixture_build fastest fastest_project; }
setup() { fixture_copy fastest; }

teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

marks() { jq -cS '.plans[0].mutations[-1].checks' .vbw/record.json; }

@test "T157: a task break runs the fastest check first and stops at the first red" {
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 task1 "prints unpaid" src/pay.sh < /dev/null > /dev/null
  rm -f "$TEST_ROOT/slow.ran"
  printf 'echo unpaid again\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 "prints unpaid again" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(marks)" = '{"C2":"red"}' ] || { marks; false; }
  [ ! -e "$TEST_ROOT/slow.ran" ] || { echo "the slow check ran on the broken code"; false; }
  jq -e '.plans[0].mutations[-1].result == "red"' .vbw/record.json
}

@test "T157: a survivor runs every check" {
  printf 'echo paid\n# a harmless change\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 "adds a comment" src/pay.sh < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [ "$(marks)" = '{"C1":"green","C2":"green"}' ] || { marks; false; }
  [ -e "$TEST_ROOT/slow.ran" ] || { echo "the slow check did not run, or cannot mark that it ran"; false; }
}
