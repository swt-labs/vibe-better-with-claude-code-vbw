#!/usr/bin/env bats
# R110: docs/proof.md explains, in plain words, which checks run again, which
# are reused, and why a check with no declared files always runs. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R110: docs/proof.md says which checks run again: changed served files, a changed definition, a last result that was not a pass" {
  grep -qi 'served files' "$DOC"
  grep -qi "files of every plan that serves" "$DOC"
  grep -qi 'approved definition' "$DOC"
  grep -qi 'fail, timeout or lost' "$DOC"
}

@test "R110: docs/proof.md says which checks are reused, and that a reused result keeps the time it really ran" {
  grep -qi 'checks: [0-9N]* ran, [0-9N]* reused' "$DOC"
  grep -qi 'keeps the time' "$DOC"
}

@test "R110: docs/proof.md says why a check with no declared files always runs" {
  grep -qi 'declares no files' "$DOC"
  grep -qi 'always runs' "$DOC"
  grep -qi 'cannot know' "$DOC"
}

@test "R110: docs/proof.md says uncommitted changes change nothing, an interrupted proof reuses nothing, and a second proof is fresh" {
  grep -qi 'does not make a check run again' "$DOC"
  grep -qi 'uncommitted' "$DOC"
  grep -qi 'interrupted' "$DOC"
  grep -qi 'second `vbw prove`' "$DOC"
}

@test "R110: docs/proof.md no longer says a changed committed file reruns every check" {
  ! grep -q 'a committed project file differs from the last passing proof' "$DOC"
}
