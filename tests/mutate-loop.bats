#!/usr/bin/env bats
# R188 (P140; D315, D381; docs/loop.md): under the loop, the one approval a
# mutation check can add is given by the loop on the user's behalf. When vbw
# next asks for the approval of changed check files and every one of them is a
# check file a mutation check strengthened (a red break after a survivor of its
# rule) and is still exactly what that red break ran, the loop step approves
# them and records a decision naming them; vbw next then moves on to the proof.
# A changed check file no mutation check strengthened, or one edited again after
# its red break, still waits for the user as today. L1: the kernel's loop step
# on a fixture project.

load helper
load loop-helper
load fixture-helper

# loop_ready: the loop over T1 planned with a check that cannot fail on the greeting, at its build step.
loop_ready() {
  loop_project
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  "$VBW" spec add auto "Visitors can read a greeting" > /dev/null
  Q=$(item_req "Visitors can read a greeting")
  # C2 cannot fail on what the greeting says.
  printf 'test -f src/greet.txt\n' > tests/greet.sh
  jq -nc --arg q "$Q" '{phases: [{id: "P2", title: "Greeting", reqs: [$q], goal: "A greeting exists", criteria: ["it says hello"], tier: "standard"}],
    plans: [{id: "P2.1", phase: "P2", title: "Greeting", reqs: [$q], files: ["src/greet.txt"], after: [], tasks: ["write hello"]}],
    checks: [{id: "C2", req: $q, run: ["sh", "tests/greet.sh"], files: ["tests/greet.sh"]}],
    rules: [{req: $q, text: "it says hello", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "chore(test): planned"
  loop_next s1 > /dev/null
  [ "$(next_action)" = build ]
  export Q
}

setup_file() { fixture_build ready loop_ready; }
setup() { fixture_copy ready; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

contract_state() { "$VBW" show contract < /dev/null | sed -n '1s/^contract [0-9a-f]* (\(.*\))$/\1/p'; }
decisions() { jq '.decisions | length' .vbw/record.json; }

# build CHANGE: the Dev's work in a build run of session s1. With "mutation", a
# break of the greeting survives, the check is strengthened and committed, and
# the same break goes red; with "edited", the check file is changed and
# committed with no mutation check (the phase made express, which asks none).
# The plan is done and the run ended.
build() {
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  printf 'hello\n' > src/greet.txt
  "$VBW" commit P2.1 "feat(greet): hello" > /dev/null
  if [ "$1" = mutation ]; then
    printf 'bye\n' > src/greet.txt
    if "$VBW" mutate P2.1 "$Q.1" "says bye" src/greet.txt < /dev/null > /dev/null 2>&1; then return 1; fi
  else
    # No mutation check is asked of this build.
    edit_record '(.phases[] | select(.id == "P2")).tier = "express"'
  fi
  printf 'grep -qx hello src/greet.txt\n' > tests/greet.sh
  git add tests/greet.sh && git commit -q -m "test(greet): it says hello"
  if [ "$1" = mutation ]; then
    printf 'bye\n' > src/greet.txt
    "$VBW" mutate P2.1 "$Q.1" "says bye" src/greet.txt < /dev/null > /dev/null
    git checkout -q -- src/greet.txt
  fi
  "$VBW" plan done P2.1 > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
}

# asks_files: vbw next asks for the approval of exactly tests/greet.sh.
asks_files() {
  VBW_SESSION_ID=s1 "$VBW" next --json < /dev/null | jq -e '.action == "approve" and .detail.files == ["tests/greet.sh"]' > /dev/null \
    || { VBW_SESSION_ID=s1 "$VBW" next --json < /dev/null; return 1; }
}

@test "R188: under the loop, a check file strengthened by a mutation check is approved by the loop, with a decision naming it" {
  build mutation
  asks_files
  local n
  n=$(decisions)
  run loop_next s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.action == "prove"' || { echo "$output"; false; }
  [ "$(contract_state)" = approved ]
  [ "$(decisions)" -gt "$n" ]
  jq -e '.decisions[-1].text | test("loop") and test("strengthen"; "i") and contains("tests/greet.sh")' .vbw/record.json \
    || { jq '.decisions[-1]' .vbw/record.json; false; }
  [ "$(next_action)" = prove ]
}

@test "R188: under the loop, a check file changed with no mutation check still waits for the user" {
  build edited
  asks_files
  local n
  n=$(decisions)
  run loop_next s1
  printf '%s' "$output" | jq -e '.action == "stopped" and (.reason | test("approve"))' || { echo "$output"; false; }
  [ "$(contract_state)" != approved ]
  [ "$(decisions)" -eq "$n" ]
}

@test "R188: under the loop, a strengthened check file edited again after its red break waits for the user" {
  build mutation
  printf 'grep -qx hello src/greet.txt\ntest -s src/greet.txt\n' > tests/greet.sh
  git add tests/greet.sh && git commit -q -m "test(greet): and not empty"
  asks_files
  local n
  n=$(decisions)
  run loop_next s1
  printf '%s' "$output" | jq -e '.action == "stopped" and (.reason | test("approve"))' || { echo "$output"; false; }
  [ "$(contract_state)" != approved ]
  [ "$(decisions)" -eq "$n" ]
}
