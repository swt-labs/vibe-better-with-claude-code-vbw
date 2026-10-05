#!/usr/bin/env bats
# R64: every real-app test project is marked as a VBW test session, so the panel
# plays no sound aloud there and keeps its choices apart from the user's.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"

@test "R64: new_project marks every scenario project with .vbw/runtime/test-mode" {
  sed -n '/^new_project()/,/^}/p' "$SUITE" | grep -qF '.vbw/runtime/test-mode'
}

@test "R64: scenarios read only the test keys, and never write into Claude Code's store" {
  # Every mention of the panel's choices names the test keys.
  run bash -c 'grep -hnE "vbw-panel\.(closed|sound)" "$1" "$2" | grep -vF "test.vbw-panel."' _ "$SUITE" "$REPO_ROOT/tools/l3.sh"
  [ -z "$output" ]
  # Nothing is redirected or copied into the store.
  run grep -nE '(>|cp |mv |tee ).*plugins/store' "$SUITE" "$REPO_ROOT/tools/l3.sh"
  [ "$status" -ne 0 ]
}
