#!/usr/bin/env bats
# R53: where the panel cannot run, nothing breaks. The panel is a Claude Code mod
# (plugin/hooks/panel.js, named by hooks/hooks.json "modules"); Claude Code older
# than 2.1.287 does not load mods, and the status line never depends on it. These
# tests (L1) hold the plugin's structure and the status line's output; the
# behaviour of the module itself is tested in tests/panel/safe.test.mjs.

load helper

setup() {
  vbw_setup
  vbw_git_project
}
teardown() { vbw_teardown; }

cc_json() {
  jq -nc --arg d "$PROJECT" --arg v "${CC_VERSION:-2.1.289}" '{session_id: "s1", workspace: {project_dir: $d, current_dir: $d}, model: {display_name: "Sonnet 5.5"},
    version: $v, cost: {total_cost_usd: 1.4234, total_duration_ms: 622000, total_api_duration_ms: 355000, total_lines_added: 3, total_lines_removed: 1},
    context_window: {used_percentage: 31, total_input_tokens: 62000, context_window_size: 200000}}'
}

# A copy of the plugin as it was before the panel: no module, no "modules" key.
without_panel() {
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plain"
  rm -f "$TEST_ROOT"/plain/hooks/panel*.js
  jq 'del(.modules)' "$PLUGIN_ROOT/hooks/hooks.json" > "$TEST_ROOT/plain/hooks/hooks.json"
}

@test "R53: the panel is a mod named by hooks.json, next to the hooks it had, which are unchanged" {
  jq -e '.modules == ["./panel.js"]' "$PLUGIN_ROOT/hooks/hooks.json"
  # PostToolUse is R61's answer hook (tests/approve-choice-hook.bats pins it).
  jq -e '(.hooks | keys | sort) == ["PostToolUse", "PreToolUse", "SessionStart"] and (.hooks.PreToolUse | length) == 3 and (.hooks.SessionStart | length) == 1' "$PLUGIN_ROOT/hooks/hooks.json"
  [ -f "$PLUGIN_ROOT/hooks/panel.js" ] && [ -f "$PLUGIN_ROOT/hooks/panel-view.js" ]
  grep -q '^export function register' "$PLUGIN_ROOT/hooks/panel.js"
}

@test "R53: Claude Code's own validator reads the module and lists the hooks the panel registers" {
  command -v claude > /dev/null 2>&1 || skip "claude is not installed"
  run claude plugin validate "$PLUGIN_ROOT"
  [[ "$output" == *"Validation passed"* ]] || { echo "$output"; false; }
  [[ "$output" != *"with warnings"* ]] || { echo "$output"; false; }
  [[ "$output" == *"./panel.js hooks:"* ]] || { echo "$output"; false; }
  for ev in session.start ui.render ui.close command.run tool.call; do
    printf '%s\n' "$output" | grep -E '\./panel\.js hooks:' | grep -q "$ev" || { echo "missing hook $ev"; echo "$output"; false; }
  done
}

@test "R53: the status line is byte for byte what it is without the panel, in a VBW project" {
  without_panel
  [ -f "$PLUGIN_ROOT/hooks/panel.js" ]
  "$VBW" init > /dev/null
  printf '# x\n\n## Requirements\n\n- R1 [auto] One\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  for v in 2.1.289 2.1.286 2.0.1; do
    CC_VERSION=$v cc_json | NO_COLOR=1 bash "$PLUGIN_ROOT/scripts/vbw-statusline.sh" > "$TEST_ROOT/with.txt"
    CC_VERSION=$v cc_json | NO_COLOR=1 bash "$TEST_ROOT/plain/scripts/vbw-statusline.sh" > "$TEST_ROOT/without.txt"
    [ -s "$TEST_ROOT/with.txt" ]
    cmp "$TEST_ROOT/with.txt" "$TEST_ROOT/without.txt"
  done
}

@test "R53: the status line is byte for byte what it is without the panel, outside a VBW project, with colour too" {
  without_panel
  [ -f "$PLUGIN_ROOT/hooks/panel.js" ]
  for v in 2.1.289 2.1.286; do
    CC_VERSION=$v cc_json | bash "$PLUGIN_ROOT/scripts/vbw-statusline.sh" > "$TEST_ROOT/with.txt"
    CC_VERSION=$v cc_json | bash "$TEST_ROOT/plain/scripts/vbw-statusline.sh" > "$TEST_ROOT/without.txt"
    [ -s "$TEST_ROOT/with.txt" ]
    cmp "$TEST_ROOT/with.txt" "$TEST_ROOT/without.txt"
  done
  [ "$(cc_json | NO_COLOR=1 bash "$PLUGIN_ROOT/scripts/vbw-statusline.sh" | sed -n 1p)" = "[VBW] no project here · /vbw:vibe to start" ]
}

@test "R53: the status line and the kernel know nothing of the panel, so an older Claude Code prints nothing extra" {
  ! grep -rqiE 'panel|mods?\b' "$PLUGIN_ROOT/scripts"
  ! grep -qiE 'panel' "$PLUGIN_ROOT/hooks/session-start.sh"
}
