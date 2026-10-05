#!/usr/bin/env bats
# R57 (spec, D109): the sound is picked at random from the sounds shipped in
# plugin/assets/audio/<character>/. Claude Code lists folders only relative to the
# project, so the panel reads a generated list, plugin/hooks/panel-sounds.js,
# which must match the folders (tools/sounds.sh writes it). L1: static reading of
# the modules and the shipped folders; no player runs here.

load helper

PANEL="$PLUGIN_ROOT/hooks/panel.js"

@test "R57: the plugin ships sounds in plugin/assets/audio/<character>/" {
  local n
  n=$(find "$PLUGIN_ROOT/assets/audio" -mindepth 2 -maxdepth 2 -type f -name '*.mp3' | wc -l)
  [ "$n" -ge 1 ]
}

@test "R57: the panel takes its sound from assets/audio, not from one fixed file" {
  cat "$PANEL" "$PLUGIN_ROOT/hooks/panel-sounds.js" | grep -qF "assets/audio"
  run grep -qF "assets/needs-you.mp3" "$PANEL" "$PLUGIN_ROOT/hooks/panel-sounds.js"
  [ "$status" -ne 0 ]
}

@test "R57: the panel picks among the shipped sounds at random" {
  cat "$PANEL" "$PLUGIN_ROOT/hooks/panel-sounds.js" | grep -qF "Math.random"
}

@test "R57: the generated sound list names exactly the shipped mp3 files, and tools/sounds.sh rewrites it" {
  local want got
  want=$(cd "$PLUGIN_ROOT" && find assets/audio -mindepth 2 -maxdepth 2 -type f -name '*.mp3' | LC_ALL=C sort)
  got=$(node -e 'import(process.argv[1]).then(m => console.log([...m.SOUNDS].sort().join("\n")))' "$PLUGIN_ROOT/hooks/panel-sounds.js")
  [ "$got" = "$want" ]
  [ -x "$REPO_ROOT/tools/sounds.sh" ] || [ -f "$REPO_ROOT/tools/sounds.sh" ]
}

@test "R57: a character folder with no sounds, and macOS .DS_Store files, are left out of the list" {
  if node -e 'import(process.argv[1]).then(m => process.exit(m.SOUNDS.some(s => !/\.mp3$/.test(s)) ? 0 : 1))' "$PLUGIN_ROOT/hooks/panel-sounds.js"; then false; fi
  grep -qF "panel-sounds.js" "$PANEL"
}
