#!/usr/bin/env bats
# The hermetic helper itself: teardown must succeed in a test that needed no
# project (no vbw_setup), so such tests do not fail after their assertions.

load helper

@test "vbw_teardown succeeds when vbw_setup never ran" {
  unset TEST_ROOT
  run vbw_teardown
  [ "$status" -eq 0 ]
}
