#!/usr/bin/env bats
# R52 (F33, docs/panel.md): /vbw-panel only opens the panel; the user closes it
# from the panel itself. The panel skill must not promise a toggle (L1, text).

load helper

@test "R52: the panel skill says /vbw-panel opens the panel and never that it closes it" {
  run grep -n '/vbw-panel' "$PLUGIN_ROOT/skills/panel/SKILL.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw-panel\` opens it"* ]] || { echo "$output"; false; }
  ! grep -niE '/vbw-panel[^.;]*(closes|toggle)' "$PLUGIN_ROOT/skills/panel/SKILL.md"
}
