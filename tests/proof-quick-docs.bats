#!/usr/bin/env bats
# R111: the user docs explain the quick command, when a full proof is needed,
# and the two refusal messages. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R111: docs/proof.md explains how a project names its quick command, and that it needs approval and is never detected" {
  grep -qF -- '- quick:' "$DOC"
  grep -qi 'quick command' "$DOC"
  grep -qi 'never detects\|does not detect\|never suggests' "$DOC"
}

@test "R111: docs/proof.md says a plain proof runs the quick command in place of the test command, and the full test command when the quick one is not approved" {
  grep -qi 'in place of the test command' "$DOC"
  grep -qi 'quick command is not approved' "$DOC"
}

@test "R111: docs/proof.md explains vbw prove --full, when a full proof is needed, and what makes a proof full or partial" {
  grep -qF 'vbw prove --full' "$DOC"
  grep -qi 'QA and shipping' "$DOC"
  grep -qi 'full proof' "$DOC"
  grep -qi 'partial' "$DOC"
  grep -qF 'usage: vbw prove [--full]' "$DOC"
}

@test "R111: docs/proof.md quotes the two refusal messages" {
  grep -qF 'the last proof was partial: run vbw prove --full, then record the verdict again' "$DOC"
  grep -qF 'Run vbw prove --full' "$DOC"
}

@test "R111: docs/proof.md no longer says a proof that reuses results is a full proof" {
  ! grep -q 'A proof that reuses results is a full proof' "$DOC"
}

@test "R111: docs/next.md and docs/record.md describe the full-proof step and the evidence's full field" {
  grep -qF 'vbw prove --full' "$REPO_ROOT/docs/next.md"
  grep -qF '`full`' "$REPO_ROOT/docs/record.md"
}
