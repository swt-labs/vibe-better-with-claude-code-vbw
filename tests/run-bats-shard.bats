#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$REPO_ROOT/testing/run-bats-shard.sh"

@test "run-bats-shard prints modulo-selected files" {
  run bash "$SCRIPT" 1 4 --print-files \
    tests/a.bats tests/b.bats tests/c.bats tests/d.bats tests/e.bats tests/f.bats

  [ "$status" -eq 0 ]
  [ "$output" = $'tests/b.bats\ntests/f.bats' ]
}

@test "run-bats-shard prints nothing when shard receives no files" {
  run bash "$SCRIPT" 3 4 --print-files tests/a.bats tests/b.bats tests/c.bats

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "run-bats-shard rejects invalid shard parameters" {
  run bash "$SCRIPT" 4 4 --print-files tests/a.bats

  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: run-bats-shard.sh"* ]]
}