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

# lockers slots|steps: three processes each take the slot store's lock (slots)
# or the proof note's lock (steps) ten times, with the mkdir above first on
# PATH, writing "in PID" and "out PID" around a short hold to held.log.
lockers() {
  local k pids=()
  : > "$TEST_ROOT/held.log"
  mkdir -p "$TEST_ROOT/store" "$TEST_ROOT/runtime"
  for k in 1 2 3; do
    # shellcheck disable=SC2016 # expanded by the inner bash
    PATH="$TEST_ROOT/shim:$PATH" bash -c 'VBW_LIB="$1/lib"; . "$VBW_LIB/core.sh"; . "$VBW_LIB/record.sh"
      . "$VBW_LIB/slots.sh"; . "$VBW_LIB/proofsteps.sh"
      SLOTS_DIR="$2/store" VBW_RUNTIME="$2/runtime"
      for i in 1 2 3 4 5 6 7 8 9 10; do
        if [ "$3" = slots ]; then slots_lock || exit 1; else proofsteps_lock || exit 1; fi
        echo "in $$" >> "$2/held.log"; sleep 0.02; echo "out $$" >> "$2/held.log"
        if [ "$3" = slots ]; then slots_unlock; else proofsteps_unlock; fi
      done' _ "$PLUGIN_ROOT" "$TEST_ROOT" "$1" &
    pids+=("$!")
  done
  for k in "${pids[@]}"; do wait "$k"; done
}

# one_at_a_time: held.log alternates "in P" and "out P" of one process, 30 holds.
one_at_a_time() {
  awk 'NR % 2 == 1 { if ($1 != "in") bad = 1; p = $2 } NR % 2 == 0 { if ($1 != "out" || $2 != p) bad = 1 }
    END { exit (bad || NR != 60) }' "$TEST_ROOT/held.log" || { cat "$TEST_ROOT/held.log"; false; }
}

@test "R181: the slot store's lock lets one process in at a time when mkdir succeeds on an existing directory" {
  lockers slots
  one_at_a_time
}

@test "R190: the proof note's lock lets one process in at a time when mkdir succeeds on an existing directory" {
  lockers steps
  one_at_a_time
}

@test "R1: every lock folder of the kernel is taken by its owner file (vbw_lock_dir), never by mkdir's answer" {
  run grep -nE '(^|[^-[:alnum:]_])mkdir "[^"]*(lock|mutex)[^"]*"' "$PLUGIN_ROOT"/lib/*.sh "$PLUGIN_ROOT"/hooks/*.sh "$PLUGIN_ROOT/bin/vbw"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  # The slot store's lock and the gate's are files, made by the exclusive create alone (no mkdir).
  grep -q 'vbw_lock_create "\$lock"' "$PLUGIN_ROOT/lib/slots.sh"
  grep -q 'vbw_lock_create "\$g/mutex"' "$PLUGIN_ROOT/lib/checks.sh"
  grep -q 'vbw_lock_dir "\$l"' "$PLUGIN_ROOT/lib/proofsteps.sh"
}

# in_runtime BODY ARGS...: BODY with the kernel's locks loaded and VBW_RUNTIME at $TEST_ROOT/runtime.
in_runtime() {
  mkdir -p "$TEST_ROOT/runtime"
  # shellcheck disable=SC2016 # expanded by the inner bash
  bash -c 'VBW_LIB="$1/lib"; . "$VBW_LIB/core.sh"; . "$VBW_LIB/record.sh"; . "$VBW_LIB/proofsteps.sh"
    VBW_RUNTIME="$2/runtime"; l="$VBW_RUNTIME/step.lock"; body=$3; shift 3; eval "$body"' _ "$PLUGIN_ROOT" "$TEST_ROOT" "$@"
}

@test "R190: the proof note's lock is never taken from a live owner: a waiter gives up and its caller skips the update" {
  sleep 120 & local live=$!
  mkdir -p "$TEST_ROOT/runtime/step.lock"
  printf '%s\n' "$live" > "$TEST_ROOT/runtime/step.lock/pid"
  # shellcheck disable=SC2016 # expanded by in_runtime
  run in_runtime 'sleep() { :; }; if proofsteps_lock; then echo "taken"; else echo "gave up"; fi; cat "$l/pid"'
  kill "$live"; wait "$live" 2> /dev/null || true
  [ "${lines[0]}" = "gave up" ] && [ "${lines[1]}" = "$live" ] || { echo "$output"; false; }
}

@test "R190: a live owner's id missing for a moment never lets a long waiter in: only 5 s without an id counts" {
  sleep 120 & local live=$!
  mkdir -p "$TEST_ROOT/runtime/step.lock"
  printf '%s\n' "$live" > "$TEST_ROOT/runtime/step.lock/pid"
  # The waiter has waited 7 s when the owner's file is gone for one look (another waiter
  # renamed it to check it, as vbw_lock_takeover does, and links it back at once).
  # The seconds are the injected clock (R236, VBW_LOCK_CLOCK), one per look, never real time.
  # shellcheck disable=SC2016 # expanded by in_runtime
  run in_runtime 'tries=0 VBW_LOCK_CLOCK=0
    sleep() {
      tries=$((tries + 1))
      VBW_LOCK_CLOCK=$((VBW_LOCK_CLOCK + 1))
      if [ "$tries" -eq 7 ]; then mv "$l/pid" "$l/pid.away"; fi
      if [ "$tries" -eq 8 ]; then mv "$l/pid.away" "$l/pid"; fi
    }
    if proofsteps_lock; then echo "taken at try $tries"; else echo "gave up"; fi; cat "$l/pid"'
  kill "$live"; wait "$live" 2> /dev/null || true
  [ "${lines[0]}" = "gave up" ] && [ "${lines[1]}" = "$live" ] || { echo "$output"; false; }
}

@test "R190: a note lock folder left 5 s without an owner's id is taken over" {
  mkdir -p "$TEST_ROOT/runtime/step.lock"
  # The 5 s are counted on the injected clock (R236, T206: on Ubuntu 26.04 bash's real
  # SECONDS ticked during the case and the lock was taken after 4 tries). Each look
  # advances the injected clock by one second and the real SECONDS by a hundred: a lock
  # that still read SECONDS would be taken after the first look, never the fifth.
  # shellcheck disable=SC2016 # expanded by in_runtime
  run in_runtime 'tries=0 VBW_LOCK_CLOCK=0
    sleep() { tries=$((tries + 1)); VBW_LOCK_CLOCK=$((VBW_LOCK_CLOCK + 1)); SECONDS=$((SECONDS + 100)); }
    if proofsteps_lock; then echo "taken after $tries tries"; else echo "gave up"; fi; [ "$(cat "$l/pid")" = "$$" ] && echo "mine"'
  [ "${lines[0]}" = "taken after 5 tries" ] && [ "${lines[1]}" = "mine" ] || { echo "$output"; false; }
}

# R236 (T206): the three locks that count 5 s without an owner's id (the note lock in
# proofsteps.sh, the slot store's lock in slots.sh, the alone-check gate in checks.sh)
# read their seconds from one function, vbw_lock_seconds in record.sh: the injected
# clock VBW_LOCK_CLOCK when set, bash's SECONDS otherwise. No test here writes SECONDS.

@test "R236: vbw_lock_seconds returns the injected clock when VBW_LOCK_CLOCK is set, and otherwise a count of seconds that never goes down" {
  # shellcheck disable=SC2016 # expanded by in_runtime
  run in_runtime 'VBW_LOCK_CLOCK=42 vbw_lock_seconds; unset VBW_LOCK_CLOCK; a=$(vbw_lock_seconds); b=$(vbw_lock_seconds); echo "$a $b"'
  [ "${lines[0]}" = "42" ] || { echo "$output"; false; }
  local a b
  read -r a b <<< "${lines[1]}"
  [[ "$a" =~ ^[0-9]+$ ]] && [[ "$b" =~ ^[0-9]+$ ]] && [ "$b" -ge "$a" ] || { echo "$output"; false; }
}

@test "R236: the note lock, the slot lock and the alone-check gate read vbw_lock_seconds and never SECONDS directly" {
  local f fn body
  for f in proofsteps.sh:proofsteps_lock slots.sh:slots_lock checks.sh:checks_gate_enter; do
    fn=${f#*:}
    body=$(sed -n "/^$fn()/,/^}/p" "$PLUGIN_ROOT/lib/${f%%:*}")
    [ -n "$body" ] || { echo "no $fn in ${f%%:*}"; false; }
    ! printf '%s\n' "$body" | grep -q 'SECONDS' || { echo "$fn still reads SECONDS:"; printf '%s\n' "$body" | grep -n 'SECONDS'; false; }
    printf '%s\n' "$body" | grep -q 'vbw_lock_seconds' || { echo "$fn does not read vbw_lock_seconds"; false; }
  done
  grep -q '^vbw_lock_seconds()' "$PLUGIN_ROOT/lib/record.sh" || { echo "vbw_lock_seconds is not defined in record.sh"; false; }
  # No test in this file advances SECONDS as its clock; the one write left is the decoy of a hundred.
  [ "$(grep -cE 'SECONDS=\$\(\(SECONDS \+ 1\)\)' "$BATS_TEST_FILENAME")" -eq 0 ] || { echo "a test still advances SECONDS by one"; false; }
}

@test "R236: the slot store's lock counts its 5 s without an owner's id on the same injected clock" {
  mkdir -p "$TEST_ROOT/runtime/slots.lock"
  # shellcheck disable=SC2016 # expanded by in_runtime
  run in_runtime '. "$VBW_LIB/slots.sh"; SLOTS_DIR="$VBW_RUNTIME"; tries=0 VBW_LOCK_CLOCK=0
    sleep() { tries=$((tries + 1)); VBW_LOCK_CLOCK=$((VBW_LOCK_CLOCK + 1)); SECONDS=$((SECONDS + 100)); }
    if slots_lock; then echo "taken after $tries tries"; else echo "gave up $?"; fi; [ "$(cat "$VBW_RUNTIME/slots.lock/pid")" = "$$" ] && echo "mine"'
  [ "${lines[0]}" = "taken after 5 tries" ] && [ "${lines[1]}" = "mine" ] || { echo "$output"; false; }
}

@test "R190: a note lock whose dead owner two waiters find is never taken from the waiter that took it over first" {
  sleep 0 & local dead=$!
  wait "$dead"
  sleep 120 & local live=$!
  mkdir -p "$TEST_ROOT/runtime/step.lock"
  printf '%s\n' "$dead" > "$TEST_ROOT/runtime/step.lock/pid"
  # The other waiter takes the lock over while this one judges the owner gone, and holds it.
  # shellcheck disable=SC2016 # expanded by in_runtime
  run in_runtime 'dead=$1 live=$2 tries=0 fired=
    kill() {
      if [ "$1" = -0 ] && [ "$2" = "$dead" ] && [ -z "$fired" ]; then
        fired=1; rm -rf "$l"; mkdir "$l"; printf "%s\n" "$live" > "$l/pid"; return 1
      fi
      command kill "$@"
    }
    sleep() {
      local p=
      tries=$((tries + 1))
      { IFS= read -r p < "$l/pid"; } 2> /dev/null || true
      [ "$p" = "$live" ] || { echo "the waiter that held the lock lost it at try $tries"; exit 1; }
      [ "$tries" -lt 3 ] || rm -rf "$l"
    }
    proofsteps_lock || { echo "no lock"; exit 1; }
    echo "locked after $tries tries"' "$dead" "$live"
  kill "$live"; wait "$live" 2> /dev/null || true
  [ "$status" -eq 0 ] && [ "$output" = "locked after 3 tries" ] || { echo "$output"; false; }
}
