#!/usr/bin/env bats
# The VBW status line (docs/statusline.md): the renderer and the setting.

load helper

setup() {
  vbw_setup
  vbw_git_project
  SL="$PLUGIN_ROOT/scripts/vbw-statusline.sh"
  SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
}

teardown() { vbw_teardown; }

cc_json() {
  jq -nc --arg d "$PROJECT" '{workspace: {project_dir: $d, current_dir: $d}, model: {display_name: "Sonnet 5.5"},
    version: "2.1.286", cost: {total_cost_usd: 1.4234, total_duration_ms: 622000, total_api_duration_ms: 355000,
    total_lines_added: 303, total_lines_removed: 12},
    context_window: {used_percentage: 31, total_input_tokens: 62000, context_window_size: 200000}}'
}

render() { cc_json | NO_COLOR=1 bash "$SL"; }

@test "outside a VBW project it says how to start, and still shows the session" {
  run render
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [[ "${lines[0]}" == "[VBW] no project here · /vbw:init to start" ]]
  [[ "${lines[1]}" == "Context ▓▓▓░░░░░░░ 31% 62K/200K │ Cost \$1.42 │ +303 −12" ]]
  [[ "${lines[3]}" == "Sonnet 5.5 │ 10m22s (API 5m55s) │ main │ VBW "* ]]
}

@test "in a VBW project it shows progress and the last next step" {
  "$VBW" init > /dev/null
  printf '# x\n\n## Requirements\n\n- R1 [auto] One\n- R2 [human] Two\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" next > /dev/null
  run render
  [[ "${lines[0]}" == "[VBW] project with space │ M1 First milestone │ 0/2 done │ next: plan" ]]
}

@test "a running build and an armed autonomous run are visible" {
  "$VBW" init > /dev/null
  printf '# x\n\n## Requirements\n\n- R1 [auto] One\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id: "C1", req: "R1", run: ["true"]}] | .phases = [{id: "P1", title: "A", reqs: ["R1"]}]
      | .plans = [{id: "P1.1", phase: "P1", title: "A", reqs: ["R1"], files: ["a"], after: [], status: "planned"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" run start build P1.1 > /dev/null
  "$VBW" auto on s1 > /dev/null
  run render
  [[ "${lines[0]}" == *"│ ▶ build: P1.1 │ ⟳ auto 0/25" ]]
}

@test "a gate that needs the user says so" {
  "$VBW" init > /dev/null
  printf '%s\n' '{"action":"approve","gate":true,"instruction":"x","detail":{}}' > .vbw/runtime/next.json
  run render
  [[ "${lines[0]}" == *"│ needs you: approve" ]]
}

@test "no data from Claude Code, or garbage, never breaks it" {
  run bash -c 'printf "" | NO_COLOR=1 bash "$1"' _ "$SL"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  run bash -c 'printf "not json" | NO_COLOR=1 bash "$1"' _ "$SL"
  [ "$status" -eq 0 ]
  [ "$output" = "[VBW] status line unavailable" ]
}

@test "the branch is read in a linked worktree too" {
  git worktree add -q "$TEST_ROOT/wt" -b feature
  run bash -c 'jq -nc --arg d "$2" "{workspace: {project_dir: \$d}}" | NO_COLOR=1 bash "$1"' _ "$SL" "$TEST_ROOT/wt"
  [[ "${lines[3]}" == *"│ feature │"* ]]
}

@test "statusline on sets it without asking, and keeps the user's own to restore" {
  vbw_run statusline status
  [[ "$output" == "off:"* ]]
  vbw_run statusline on
  [ "$status" -eq 0 ]
  jq -e '.statusLine.command | contains("vbw-statusline.sh")' "$SETTINGS"
  vbw_run statusline on
  [ "$output" = "on: the VBW status line" ]

  printf '{"theme": "dark", "statusLine": {"type": "command", "command": "my-line.sh"}}' > "$SETTINGS"
  vbw_run statusline on
  [[ "$output" == *"replaced yours, which is saved"* ]]
  jq -e '.theme == "dark" and (.statusLine.command | contains("vbw-statusline.sh"))' "$SETTINGS"
  vbw_run statusline off
  [[ "$output" == *"your previous status line is back"* ]]
  jq -e '.theme == "dark" and .statusLine.command == "my-line.sh"' "$SETTINGS"
}

@test "the setting finds the newest installed VBW and renders it" {
  local cache="$CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw"
  mkdir -p "$cache/1.37.1/scripts" "$cache/2.0.0"
  printf 'echo old\n' > "$cache/1.37.1/scripts/vbw-statusline.sh"
  cp -R "$PLUGIN_ROOT/." "$cache/2.0.0/"
  "$VBW" statusline on > /dev/null
  run bash -c "$(jq -r .statusLine.command "$SETTINGS")" < <(cc_json)
  [[ "${lines[0]}" == *"[VBW]"* ]]
  [ "${#lines[@]}" -eq 4 ]
}
