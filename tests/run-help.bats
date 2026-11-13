#!/usr/bin/env bats
# R306 (docs/workflows.md): the help text lists vbw run state ID..., as the docs example shows. L1.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "R306: vbw run --help and vbw --help list run state ID..., as docs/workflows.md shows it" {
  doc=$(grep -m1 '^usage: vbw run start KIND' "$BATS_TEST_DIRNAME/../docs/workflows.md")
  [[ "$doc" == *"run state ID..."* ]]
  run "$VBW" run --help
  [[ "$output" == *"${doc#usage: }"* ]] || { echo "$output"; false; }
  run "$VBW" --help
  [[ "$output" == *"run state ID..."* ]] || { echo "$output"; false; }
}
