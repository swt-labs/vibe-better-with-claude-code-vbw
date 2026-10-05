#!/usr/bin/env bats
# R55: the panel's node tests (tests/panel/*.test.mjs) run as part of the suite,
# so a regression in the panel fails `bash tools/test.sh`. Skipped without node.

load helper

@test "R55: node --test passes over tests/panel" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  cd "$BATS_TEST_DIRNAME/.."
  run node --test tests/panel/*.test.mjs
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
