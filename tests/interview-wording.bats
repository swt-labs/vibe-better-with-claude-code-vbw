#!/usr/bin/env bats
# R112 (L1): the interview skill names both the spec and the convert step it runs before, as the router does.

load helper

@test "R112: the interview skill says it runs before any spec or convert work" {
  grep -q 'before any spec or convert work' "$PLUGIN_ROOT/skills/interview/SKILL.md"
  ! grep -q 'before any spec work' "$PLUGIN_ROOT/skills/interview/SKILL.md"
}
