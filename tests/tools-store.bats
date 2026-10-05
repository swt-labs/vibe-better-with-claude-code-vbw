#!/usr/bin/env bats
# R62 (docs/tools.md): whether the user allowed VBW to look for tools is asked
# once per project. The kernel keeps the answer in the project record
# (project.tools), so a second pass through the interview step finds it and does
# not ask again, whatever the session or worktree. `vbw tools` works from any
# state of a VBW project. Hermetic projects (L1).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  git add -A && git commit -q -m "chore: init"
}

teardown() { vbw_teardown; }

@test "R62: a new project has not been asked: vbw tools --json says asked false with no answer" {
  run "$VBW" tools --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.asked == false and .answer == null'
  run "$VBW" tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"not asked"* ]]
}

@test "R62: the answer yes is remembered in the project record and any session or location sees it" {
  run "$VBW" tools answer yes
  [ "$status" -eq 0 ]
  jq -e '.project.tools.answer == "yes" and (.project.tools.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))' .vbw/record.json
  run "$VBW" tools --json
  printf '%s' "$output" | jq -e '.asked == true and .answer == "yes"'
  VBW_SESSION_ID=another-session run "$VBW" tools --json
  printf '%s' "$output" | jq -e '.asked == true and .answer == "yes"'
}

@test "R62: on no the record shows the answer was no, and the build flow is unchanged" {
  run "$VBW" tools answer no
  [ "$status" -eq 0 ]
  jq -e '.project.tools.answer == "no"' .vbw/record.json
  run "$VBW" tools --json
  printf '%s' "$output" | jq -e '.asked == true and .answer == "no"'
  run "$VBW" next --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "spec"'
  "$VBW" doctor > /dev/null 2>&1 || true
  run "$VBW" status
  [ "$status" -eq 0 ]
}

@test "R62: only yes or no is accepted; anything else is refused naming the choices and records nothing" {
  run "$VBW" tools answer maybe
  [ "$status" -ne 0 ]
  [[ "$output" == *"yes"* && "$output" == *"no"* && "$output" != *"unknown command"* ]]
  run "$VBW" tools answer
  [ "$status" -ne 0 ]
  jq -e '(.project.tools // null) == null' .vbw/record.json
}

@test "R62: the answer can be given again later (/vbw:skills after a no): the latest wins and the record stays valid" {
  "$VBW" tools answer no > /dev/null
  "$VBW" tools answer yes > /dev/null
  run "$VBW" tools --json
  printf '%s' "$output" | jq -e '.answer == "yes"'
  run "$VBW" status
  [ "$status" -eq 0 ]
}

@test "R62: a record holding another project.tools answer is refused as corrupt" {
  jq '.project.tools = {answer: "perhaps", at: "2026-01-01T00:00:00Z"}' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  run "$VBW" tools --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"project.tools"* ]]
}

@test "R62: vbw --help lists the tools command" {
  run "$VBW" --help
  [[ "$output" == *"tools"* ]]
}
