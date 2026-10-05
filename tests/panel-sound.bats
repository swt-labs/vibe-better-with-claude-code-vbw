#!/usr/bin/env bats
# R57: the 'needs you' sound. The hook that plays it is part of the panel module
# and stays within the hook CPU budget (measured by tools/bench-panel.sh, the
# same bench as the refresh); Claude Code without mods gets a plain answer
# from /vbw:panel instead of an error; the owner's mp3 is the plugin's own file
# (D104). Behaviour is in tests/panel/sound.test.mjs. L1.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

BENCH="$BATS_TEST_DIRNAME/../tools/bench-panel.sh"

@test "R57: raising a need and playing the sound costs less than the hook CPU limit, 8 ms, measured" {
  command -v node > /dev/null 2>&1 || { echo "node is needed for the panel tests"; false; }
  [ -f "$BENCH" ]
  VBW_BENCH_RUNS=30 run bash "$BENCH"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ (^|$'\n')"sound, need raised: "([0-9.]+)" ms CPU" ]] || { echo "$output"; false; }
  [ "$(awk -v x="${BASH_REMATCH[2]}" 'BEGIN { print (x <= 8) ? "ok" : "over" }')" = "ok" ]
}

@test "R57: the sound is a file of the plugin, from the generated sound list, and nothing else is fetched" {
  grep -qF "panel-sounds.js" "$PLUGIN_ROOT/hooks/panel.js"
  run grep -nE 'url:|base64|https?://' "$PLUGIN_ROOT/hooks/panel.js" "$PLUGIN_ROOT/hooks/panel-sounds.js"
  [ "$status" -ne 0 ]
}

@test "R57: on Claude Code without mods /vbw:panel says plainly that the panel and its sound need 2.1.287 or newer" {
  local s="$PLUGIN_ROOT/skills/panel/SKILL.md"
  [ -f "$s" ]
  [ "$(sed -n 1p "$s")" = "---" ]
  grep -q '^name: panel$' "$s"
  grep -q '2\.1\.287' "$s"
  grep -q '/vbw-sound' "$s"
  grep -q '/vbw-panel' "$s"
  grep -qi 'claude --version' "$s"
}

@test "R57: the help and the README list the panel and the sound commands" {
  grep -q '/vbw:panel' "$PLUGIN_ROOT/skills/help/SKILL.md"
  grep -q '/vbw:panel' "$REPO_ROOT/README.md"
  grep -q '/vbw-sound' "$REPO_ROOT/README.md"
}

@test "R57: the sound preference is the user's own: docs say where it is kept and that it is never committed" {
  grep -qiE 'sound' "$REPO_ROOT/docs/panel.md"
  grep -qiE 'never (committed|in the record)|not (committed|in the record)|not in the project' "$REPO_ROOT/docs/panel.md"
}
