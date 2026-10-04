#!/usr/bin/env bats
# R44: help text, docs, agents and skills show the multi-id form of vbw fix done;
# the kernel stays within budget.

load helper

@test "vbw help shows fix done with several ids" {
  run "$VBW" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"fix done ID [ID...]"* ]]
}

@test "docs/proof.md and docs/workflows.md show vbw fix done with several fixes" {
  grep -qE 'vbw fix done F[0-9]+ F[0-9]+' "$REPO_ROOT/docs/proof.md"
  grep -qE 'vbw fix done F[0-9]+ F[0-9]+' "$REPO_ROOT/docs/workflows.md"
}

@test "the dev agent closes several fixes in one vbw fix done" {
  grep -qE 'vbw fix done F[0-9]+ F[0-9]+' "$PLUGIN_ROOT/agents/dev.md"
}

@test "the kernel stays within its line budget" {
  run bats --filter 'kernel stays within' "$REPO_ROOT/tests/standards.bats"
  [ "$status" -eq 0 ]
}
