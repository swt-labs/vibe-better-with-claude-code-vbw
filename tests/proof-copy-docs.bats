#!/usr/bin/env bats
# R92 and R93: docs/proof.md states that git-ignored files are copied into the
# proof copy, never linked (with the pnpm 11 example and the clone-or-copy
# fallback), and describes the warning about links into a proof copy and its
# repair. L1: the docs are read as text.

load helper

DOC="$BATS_TEST_DIRNAME/../docs/proof.md"

@test "R92: docs/proof.md says git-ignored files are copied, not linked, with the pnpm example and the clone-or-copy fallback" {
  grep -qi 'copied, not linked' "$DOC"
  grep -q 'pnpm' "$DOC"
  grep -qi 'copy-on-write' "$DOC"
  grep -qi 'plain.*copy' "$DOC"
  if grep -qiE 'links them in|files behind the links|linked in from the working folder' "$DOC"; then false; fi
}

@test "R93: docs/proof.md describes the warning about links into a proof copy and the repair" {
  grep -q 'proof\.\*' "$DOC"
  grep -qi 'pnpm install' "$DOC"
  grep -qi 'install command' "$DOC"
}
