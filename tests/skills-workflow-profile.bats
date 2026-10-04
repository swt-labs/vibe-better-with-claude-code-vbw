#!/usr/bin/env bats
# R39: every skill that starts a VBW workflow hands it the user's level,
# explanation depth and involvement as args.profile (docs/workflows.md), so
# Scouts, the Debugger and every other agent write at the user's level.

load helper

SKILLS="$PLUGIN_ROOT/skills"

@test "every skill other than the router that starts a workflow passes profile in its args" {
  local f n=0
  for f in "$SKILLS"/*/SKILL.md; do
    [ "$(basename "$(dirname "$f")")" = vibe ] && continue
    grep -q 'Workflow `vbw:' "$f" || continue
    n=$((n + 1))
    grep -q '"profile"' "$f" || { echo "no profile in the workflow args of $f"; false; }
  done
  [ "$n" -ge 3 ]
}

@test "the router's mapping step does not show args without the profile" {
  run grep -F 'vbw:mapping` (args `{"models": ...}`)' "$SKILLS/vibe/SKILL.md"
  [ "$status" -ne 0 ]
  grep -qi 'profile.*every workflow' "$SKILLS/vibe/SKILL.md"
}
