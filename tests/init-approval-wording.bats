#!/usr/bin/env bats
# R109 (L1): vbw init's notice about detected project commands points to the
# approval menu and never tells the user to type /vbw:approve (R83).

load helper

setup() {
  vbw_setup
  vbw_git_project
  printf '{"scripts":{"test":"node test.js"}}\n' > package.json
  git add package.json && git commit -q -m "chore: package"
}
teardown() { vbw_teardown; }

@test "R109: the detected-commands notice names the approval menu, not /vbw:approve" {
  run "$VBW" init < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"Detected project commands"* ]] || { echo "$output"; false; }
  [[ "$output" != *"/vbw:approve"* ]] || { echo "$output"; false; }
  [[ "$output" == *"approval menu"* ]] || { echo "$output"; false; }
}
