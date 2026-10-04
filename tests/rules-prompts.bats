#!/usr/bin/env bats
# R31: the Lead, the Architect and the express router tell Claude to list rules.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "the Lead lists each [auto] requirement's rules, each with its check, and self-reviews them" {
  grep -q 'Rules' "$PLUGIN_ROOT/agents/lead.md"
  grep -q '"rules"' "$PLUGIN_ROOT/agents/lead.md"
  grep -qi 'every rule has a check' "$PLUGIN_ROOT/agents/lead.md"
}

@test "the Architect states conditions and edge cases in the criteria" {
  grep -qi 'edge case' "$PLUGIN_ROOT/agents/architect.md"
  grep -qi 'rules' "$PLUGIN_ROOT/agents/architect.md"
}

@test "the router's express apply example carries rules" {
  grep -q '"rules":\[{"req"' "$PLUGIN_ROOT/skills/vibe/SKILL.md"
}
