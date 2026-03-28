#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/ensure-plugin-root-link.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
  rm -f /tmp/.vbw-plugin-root-link-test-$$-*
}

@test "creates a fresh session symlink" {
  local target="$TEST_DIR/target"
  local link="/tmp/.vbw-plugin-root-link-test-$$-fresh"

  mkdir -p "$target"

  run bash "$SCRIPT" "$link" "$target"

  [ "$status" -eq 0 ]
  [ -L "$link" ]
  [ "$(readlink "$link")" = "$target" ]
}

@test "succeeds when the correct symlink already exists" {
  local target="$TEST_DIR/target"
  local link="/tmp/.vbw-plugin-root-link-test-$$-idempotent"

  mkdir -p "$target"
  ln -s "$target" "$link"

  run bash "$SCRIPT" "$link" "$target"

  [ "$status" -eq 0 ]
  [ -L "$link" ]
  [ "$(readlink "$link")" = "$target" ]
}

@test "replaces a stale directory at the session link path" {
  local target="$TEST_DIR/target"
  local link="/tmp/.vbw-plugin-root-link-test-$$-dir"

  mkdir -p "$target" "$link"
  printf 'stale' > "$link/stale.txt"

  run bash "$SCRIPT" "$link" "$target"

  [ "$status" -eq 0 ]
  [ -L "$link" ]
  [ "$(readlink "$link")" = "$target" ]
}

@test "replaces a symlink pointing at the wrong target" {
  local target="$TEST_DIR/target"
  local wrong="$TEST_DIR/wrong"
  local link="/tmp/.vbw-plugin-root-link-test-$$-wrongtgt"

  mkdir -p "$target" "$wrong"
  ln -s "$wrong" "$link"

  run bash "$SCRIPT" "$link" "$target"

  [ "$status" -eq 0 ]
  [ -L "$link" ]
  [ "$(readlink "$link")" = "$target" ]
}

@test "replaces a stale regular file at the link path" {
  local target="$TEST_DIR/target"
  local link="/tmp/.vbw-plugin-root-link-test-$$-file"

  mkdir -p "$target"
  printf 'not-a-symlink' > "$link"

  run bash "$SCRIPT" "$link" "$target"

  [ "$status" -eq 0 ]
  [ -L "$link" ]
  [ "$(readlink "$link")" = "$target" ]
}

@test "rejects missing arguments" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]

  run bash "$SCRIPT" "/tmp/.vbw-plugin-root-link-test-$$-x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "rejects link path without .vbw-plugin-root-link- prefix" {
  local target="$TEST_DIR/target"
  mkdir -p "$target"

  run bash "$SCRIPT" "/tmp/bad-link-name" "$target"

  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected link path basename"* ]]
}

@test "rejects nonexistent target directory" {
  run bash "$SCRIPT" "/tmp/.vbw-plugin-root-link-test-$$-nodir" "$TEST_DIR/nonexistent"

  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}