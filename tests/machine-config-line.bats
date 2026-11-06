#!/usr/bin/env bats
# R181 (docs/proof.md): vbw config prints the computer-wide limit on the line
# right after check_jobs, in plain words: the number, that it is three quarters
# of the computer's processor cores, that every VBW project on this computer
# shares it, and that it is not a setting. When check_jobs is above it, the
# line says the machine limit is the one that applies. L1: the core count is
# faked (tests/machine-helper.bash). The project is built once per file
# (setup_file) and copied for each test.

load helper
load machine-helper
load fixture-helper

# one_check: the project of every test, one check. For fixture_build.
one_check() {
  machine_setup
  machine_project "$PROJECT" A 1 0
}

setup_file() { fixture_build one one_check; }
setup() {
  fixture_copy one
  # This file tests the machine default: a proof marks its own units (VBW_PROOF_UNIT, R257),
  # which would make the kernel under test read 1 instead.
  unset VBW_PROOF_UNIT
}
teardown() { machine_teardown; }
teardown_file() { fixture_teardown; }

# limit_line: the line of vbw config right after its check_jobs line.
limit_line() { "$VBW" config < /dev/null | grep -A 1 '^check_jobs:' | sed -n 2p; }

SAID="; shared by every VBW project on this computer; not a setting)"

@test "R181: vbw config names the machine limit after check_jobs: three quarters of the cores, shared, not a setting" {
  cores 4
  [ "$("$VBW" config < /dev/null | grep '^check_jobs:')" = "check_jobs: 3 (machine default)" ]
  [ "$(limit_line)" = "machine limit: 3 (three quarters of this computer's processor cores (4), rounded down, at least 1 and at most 64$SAID" ] || { limit_line; false; }
  cores 128
  [ "$(limit_line)" = "machine limit: 64 (three quarters of this computer's processor cores (128), rounded down, at least 1 and at most 64$SAID" ] || { limit_line; false; }
}

@test "R181: with check_jobs at or below the machine limit, the line says nothing more" {
  cores 8
  "$VBW" config set check_jobs 2 > /dev/null
  [ "$(limit_line)" = "machine limit: 6 (three quarters of this computer's processor cores (8), rounded down, at least 1 and at most 64$SAID" ] || { limit_line; false; }
  "$VBW" config set check_jobs 6 > /dev/null
  [ "$(limit_line)" = "machine limit: 6 (three quarters of this computer's processor cores (8), rounded down, at least 1 and at most 64$SAID" ] || { limit_line; false; }
}

@test "R181: with check_jobs above the machine limit, the line says the machine limit applies" {
  cores 4
  "$VBW" config set check_jobs 8 > /dev/null
  [ "$(limit_line)" = "machine limit: 3 (three quarters of this computer's processor cores (4), rounded down, at least 1 and at most 64$SAID - it applies, not check_jobs 8" ] || { limit_line; false; }
}

@test "R181: with an unreadable core count the line names limit 1 and why" {
  cores none
  [ "$(limit_line)" = "machine limit: 1 (this computer's processor core count could not be read$SAID" ] || { limit_line; false; }
  "$VBW" config set check_jobs 4 > /dev/null
  [ "$(limit_line)" = "machine limit: 1 (this computer's processor core count could not be read$SAID - it applies, not check_jobs 4" ] || { limit_line; false; }
}
