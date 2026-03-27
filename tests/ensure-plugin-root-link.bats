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