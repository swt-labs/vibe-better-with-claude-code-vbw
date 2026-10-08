#!/usr/bin/env bats
# R111: the agents and the router that reach QA and shipping say to run
# vbw prove --full, and the test result QA agents get is the full proof's. L1.

load helper

@test "R111: the QA agent's instruction for a refused verdict says to run vbw prove --full, then try the record once more" {
  grep -q 'vbw prove --full' "$PLUGIN_ROOT/agents/qa.md"
  ! grep -qE 'run `vbw prove`, then retry' "$PLUGIN_ROOT/agents/qa.md"
}

@test "R111: the verifying workflow tells each QA agent to run vbw prove --full after a refused verdict, then record once more" {
  grep -q 'vbw prove --full' "$PLUGIN_ROOT/workflows/verifying.js"
  ! grep -qE 'run vbw prove, then retry' "$PLUGIN_ROOT/workflows/verifying.js"
}

@test "R111: the verifying workflow gives QA agents the test result of the round, which comes from the full proof" {
  grep -q 'round.suite' "$PLUGIN_ROOT/workflows/verifying.js"
  ! grep -q 'commands.quick' "$PLUGIN_ROOT/workflows/verifying.js"
}

@test "R111: the router runs vbw prove --full when the next step marks the proof as full" {
  grep -q 'vbw prove --full' "$PLUGIN_ROOT/skills/vibe/SKILL.md"
  grep -q 'detail.full' "$PLUGIN_ROOT/skills/vibe/SKILL.md"
}

@test "R111: the QA skill proves with vbw prove --full" {
  grep -q 'vbw prove --full' "$PLUGIN_ROOT/skills/qa/SKILL.md"
}
