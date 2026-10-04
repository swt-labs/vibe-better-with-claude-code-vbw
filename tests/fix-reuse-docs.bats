#!/usr/bin/env bats
# R43: the docs describe the reuse rule and its wording; the kernel stays within budget.

load helper

@test "docs/proof.md describes when vbw fix done skips a check and what it says" {
  grep -q 'unchanged since its pass' "$REPO_ROOT/docs/proof.md"
  grep -qi 'vbw prove.*every check\|every check.*vbw prove' "$REPO_ROOT/docs/proof.md"
}

@test "docs/record.md describes the recorded passes" {
  grep -E '^\| `passes`' "$REPO_ROOT/docs/record.md"
}

@test "the kernel stays within its line budget" {
  run bats --filter 'kernel stays within' "$REPO_ROOT/tests/standards.bats"
  [ "$status" -eq 0 ]
}
