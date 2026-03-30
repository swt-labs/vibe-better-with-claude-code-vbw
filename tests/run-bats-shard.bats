#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$REPO_ROOT/testing/run-bats-shard.sh"
LIST_SCRIPT="$REPO_ROOT/testing/list-bats-files.sh"

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

@test "list-bats-files shardable omits serial-only bats file and is sorted" {
  run bash "$LIST_SCRIPT" --shardable

  [ "$status" -eq 0 ]
  [[ "$output" == *"$REPO_ROOT/tests/adaptive-governance.bats"* ]]
  [[ "$output" != *"$REPO_ROOT/tests/statusline-cache-isolation.bats"* ]]

  first_line=$(printf '%s\n' "$output" | head -1)
  [ "$first_line" = "$REPO_ROOT/tests/adaptive-governance.bats" ]
}

@test "list-bats-files serial returns statusline-cache-isolation only" {
  run bash "$LIST_SCRIPT" --serial

  [ "$status" -eq 0 ]
  [ "$output" = "$REPO_ROOT/tests/statusline-cache-isolation.bats" ]
}

@test "list-bats-files rejects invalid mode" {
  run bash "$LIST_SCRIPT" --wat

  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: list-bats-files.sh --shardable|--serial"* ]]
}