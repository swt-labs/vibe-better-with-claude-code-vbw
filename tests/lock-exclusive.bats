#!/usr/bin/env bats
# R1, R38 (L1): VBW's locks exclude each other whatever mkdir does. The Rust
# coreutils of Ubuntu 25.10 and 26.04 (uutils, up to 0.6 at least) report
# success for mkdir of a directory that already exists, so a lock taken with
# mkdir let two writers in at once and one write was lost (CI 2026-10-09,
# Ubuntu 26.04: consent grants and interview answers). The shim below is such
# a mkdir; the lock must not depend on it.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  git add .vbw && git commit -q -m "chore(vbw): init"
  real=$(command -v mkdir)
  mkdir -p "$TEST_ROOT/shim"
  printf '#!/bin/sh\n# like uutils mkdir: an existing directory is not an error\nexec "%s" -p "$@"\n' "$real" > "$TEST_ROOT/shim/mkdir"
  chmod +x "$TEST_ROOT/shim/mkdir"
}

teardown() { vbw_teardown; }

@test "R1: a held lock is not taken again when mkdir succeeds on an existing directory" {
  run env PATH="$TEST_ROOT/shim:$PATH" bash -c 'VBW_LIB="$1/lib"; . "$VBW_LIB/core.sh"; . "$VBW_LIB/record.sh"
    VBW_LOCK_STALE_SECONDS=1
    vbw_lock_take "$PWD/held.lock" first
    touch -t 209901010000 "$PWD/held.lock"
    ( vbw_guard_reset; vbw_lock_take "$PWD/held.lock" second && echo TAKEN-TWICE )' _ "$PLUGIN_ROOT"
  [[ "$output" != *TAKEN-TWICE* ]] || { echo "$output"; false; }
  [[ "$output" == *"second is locked by another vbw process"* ]] || { echo "$output"; false; }
}

@test "R1: concurrent consent grants are all kept when mkdir succeeds on an existing directory" {
  local round
  for round in 1 2 3; do
    rm -f .git/vbw/consent.json
    PATH="$TEST_ROOT/shim:$PATH" vbw_kernel 'for i in $(seq 1 25); do consent_grant command a$i "{}"; done' &
    local p1=$!
    PATH="$TEST_ROOT/shim:$PATH" vbw_kernel 'for i in $(seq 1 25); do consent_grant command b$i "{}"; done' &
    local p2=$!
    wait "$p1"; wait "$p2"
    [ "$(jq '.granted | length' .git/vbw/consent.json)" -eq 50 ]
  done
}

@test "R1: a lock left as a directory by an older VBW still excludes, and is broken only when stale" {
  run bash -c 'VBW_LIB="$1/lib"; . "$VBW_LIB/core.sh"; . "$VBW_LIB/record.sh"
    VBW_LOCK_STALE_SECONDS=1
    mkdir "$PWD/old.lock"; touch -t 209901010000 "$PWD/old.lock"
    ( vbw_guard_reset; vbw_lock_take "$PWD/old.lock" fresh && echo TAKEN-FRESH )
    touch -t 200001010000 "$PWD/old.lock"
    ( vbw_guard_reset; vbw_lock_take "$PWD/old.lock" stale && echo TAKEN-STALE )' _ "$PLUGIN_ROOT"
  [[ "$output" != *TAKEN-FRESH* ]] || { echo "$output"; false; }
  [[ "$output" == *TAKEN-STALE* ]] || { echo "$output"; false; }
}
