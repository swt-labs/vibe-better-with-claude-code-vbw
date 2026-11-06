#!/usr/bin/env bats
# R205: docs/proof.md describes the `## Clean copy` section (one git-ignored path
# per line, relative to the project root), the refusals of vbw spec check and
# vbw spec sync (a path git does not ignore, a path that does not exist, a bad
# path), the contract line vbw show contract prints, that approval and vbw next
# compare the section with the record, and that every clean copy skips the listed
# paths while the rest of the ignored environment is copied in; docs/record.md
# documents project.leave_out. L1: the text of the docs (one line holds each
# fact; no exact wording).

load helper

PROOF="$REPO_ROOT/docs/proof.md"
RECORD="$REPO_ROOT/docs/record.md"

# section: the Clean copy section of docs/proof.md (its heading to the next heading of the same depth or higher).
section() {
  awk '/^#{2,3} .*Clean copy/ {p=1; print; next} p && /^#{1,3} / {exit} p' "$PROOF"
}

# has_line TEXT WORD...: one line of TEXT holds every WORD (case-insensitive).
has_line() {
  local lines="$1" w
  shift
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line holds all of: $*"; return 1; }; done
}

@test "R205: docs/proof.md has a Clean copy section naming the form: one git-ignored path per line, relative to the project root" {
  [ -n "$(section)" ] || { echo "docs/proof.md has no Clean copy section"; false; }
  section | grep -q '^- data/$' || { echo "the section shows no example line"; false; }
  has_line "$(section)" "git-ignored" "one" "per line"
  has_line "$(section)" "relative" "project root"
}

@test "R205 R214: the section states the refusals: not git-ignored (only ignored paths are copied in), the kernel's exact words for a listed path with nothing at it, and a bad path like a Test results folder" {
  has_line "$(section)" "is not git-ignored" "only ignored paths are copied in"
  has_line "$(section)" "spec.md line" "is not here now, so nothing is left out for it yet"
  ! section | grep -qi "does not exist here now" || { echo "the old wording 'does not exist here now' is still there"; false; }
  has_line "$(section)" "spec sync" "line"
  has_line "$(section)" ".." ".vbw/" ".git/"
}

@test "R205: the section states the contract line, the re-approval and that vbw show contract --changes names a changed path" {
  has_line "$(section)" "clean copy leaves out:"
  has_line "$(section)" "contract" "approv"
  has_line "$(section)" "--changes"
}

@test "R205: the section says every clean copy skips the listed paths and everything under them, while the other ignored paths are copied in" {
  has_line "$(section)" "prove" "fix done" "mutate"
  has_line "$(section)" "everything under"
  has_line "$(section)" "still copied"
  has_line "$(section)" "no longer exists"
}

@test "R205: the approval paragraph lists Clean copy among the sections compared with the record" {
  sed -n '/^## The contract and approval/,/^### /p' "$PROOF" | grep -q 'Clean copy' || { echo "the compared sections do not name Clean copy"; false; }
}

@test "R205: docs/record.md documents project.leave_out as the spec's Clean copy list, part of the contract, absent when none" {
  grep -q '^| `project.leave_out` |' "$RECORD" || { echo "no project.leave_out row"; false; }
  has_line "$(grep '^| `project.leave_out` |' "$RECORD")" "Clean copy" "contract" "absent"
}

@test "R214: the section says a listed path is one word per line: a path with a space cannot be listed and is refused with its line number, in the kernel's expected \"- <path>\" words" {
  has_line "$(section)" "one word" "line"
  has_line "$(section)" "space" "line number"
  section | grep -qF 'expected "- <path>"' || { echo "the refusal's wording (expected \"- <path>\" ...) is not quoted"; false; }
}

# kept: the Kept copies section of docs/proof.md (#738).
kept() { awk '/^#### Kept copies/ {p=1; print; next} p && /^#{1,4} / {exit} p' "$PROOF"; }
# prove_steps: the numbered steps of the vbw prove section.
prove_steps() { awk '/^## `vbw prove`/ {p=1; next} p && /^#{1,3} / {exit} p' "$PROOF"; }

@test "#738: vbw prove's step 2 says the copy is a kept slot claimed and brought up to date, and step 3 that it is handed back, removed when interrupted" {
  has_line "$(prove_steps)" "claims one an earlier command kept"
  has_line "$(prove_steps)" "proof.keep.1"
  has_line "$(prove_steps)" "hands the copy back"
  has_line "$(prove_steps)" "removes the copy"
}

@test "#738: the Kept copies section states the invariant, the slots, the owner, the change test, --full and where the figures are" {
  [ -n "$(kept)" ] || { echo "docs/proof.md has no Kept copies section"; false; }
  has_line "$(kept)" "pid" "process"
  has_line "$(kept)" "never touches a slot whose owner still runs"
  has_line "$(kept)" "interrupted" "removes the slots"
  has_line "$(kept)" "exactly" "fresh"
  has_line "$(kept)" "uncommitted, untracked or staged"
  has_line "$(kept)" "no longer ignored"
  has_line "$(kept)" "git clean -ffdx"
  has_line "$(kept)" "change time" "ctime"
  has_line "$(kept)" "vbw prove --full" "fresh"
  has_line "$(kept)" "evidence.own.copy_slots"
  has_line "$(kept)" "vbw doctor" "size"
}

@test "#738: Leftover proof copies names the sweep of kept slots: 24 hours, past check_jobs, never a running owner's" {
  local left
  left=$(awk '/^#### Leftover proof copies/ {p=1; next} p && /^#{1,4} / {exit} p' "$PROOF")
  has_line "$left" "24"
  has_line "$left" "check_jobs"
  has_line "$left" "never removes a slot whose owner still runs"
}

@test "#738: docs/record.md documents evidence.own.copy_slots with its four fields" {
  has_line "$(cat "$RECORD")" "copy_slots" "claimed, refreshed, made, refresh"
}
