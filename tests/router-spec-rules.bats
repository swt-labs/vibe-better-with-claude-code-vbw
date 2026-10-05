#!/usr/bin/env bats
# R60 (P45.2 regression): shortening the router for the stop line must not drop
# the spec step's rules: recommend instead of interrogating, and check that the
# project commands fit the right sub-project and interpreter (L1: the text).

load helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

spec_step() { sed -n '/^\*\*spec\*\*/,/^\*\*plan\*\*/p' "$ROUTER"; }

@test "R60: the spec step still says to recommend, not interrogate" {
  spec_step | grep -qF "Recommend; don't interrogate."
}

@test "R60: the spec step still checks the commands fit the right sub-project and interpreter" {
  spec_step | tr '\n' ' ' | grep -qF '(right sub-project, right interpreter)'
}
