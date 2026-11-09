#!/usr/bin/env bats
# R276 (L1): docs/guards.md states the record rule as the guard applies it
# (writes refused, reads and other programs pass, inline programs refused) and
# the 512 KB script limit with its refusal.

load helper

@test "R276: docs/guards.md states the record rule as writes refused and reads passing, and the 512 KB script limit with its refusal" {
  local d="$REPO_ROOT/docs/guards.md"
  ! grep -q 'any program that is not a reader' "$d" || { echo "the old any-program rule is still described"; false; }
  grep -q 'only reads it' "$d" || { echo "no sentence that a read passes"; false; }
  grep -q 'cannot tell a read from a write' "$d" || { echo "no sentence on inline programs"; false; }
  grep -q 'above 512 KB' "$d" || { echo "no 512 KB limit"; false; }
  grep -q 'is too large to read before it runs' "$d" || { echo "no size refusal line"; false; }
  grep -q 'each under 512 KB' "$d" || { echo "no Next line"; false; }
}
