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
  jq -nc --arg d "$PROJECT" --arg sid "${SID:-s1}" '{session_id: $sid, workspace: {project_dir: $d, current_dir: $d}, model: {display_name: "Sonnet 5.5"},
    version: "2.1.286", cost: {total_cost_usd: 1.4234, total_duration_ms: 622000, total_api_duration_ms: 355000,
    total_lines_added: 303, total_lines_removed: 12},
    context_window: {used_percentage: 31, total_input_tokens: 62000, context_window_size: 200000}}'
}

render() { cc_json | NO_COLOR=1 bash "$SL"; }

@test "outside a VBW project it says how to start, and still shows the session" {
  run render
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [[ "${lines[0]}" == "[VBW] no project here · /vbw:vibe to start" ]]
  [[ "${lines[1]}" == "Context ▓▓▓░░░░░░░ 31% 62K/200K │ Cost \$1.42 │ +303 −12" ]]
  [[ "${lines[3]}" == "Sonnet 5.5 │ 10m22s (API 5m55s) │ main │ VBW "* ]]
}

@test "in a VBW project it shows progress and the last next step" {
  "$VBW" init > /dev/null
  printf '# x\n\n## Requirements\n\n- R1 [auto] One\n- R2 [human] Two\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" next > /dev/null
  run render
  [[ "${lines[0]}" == "[VBW] project with space │ M1 First milestone │ ░░░░░░░░░░ 0/2 done │ next: plan" ]]
  [[ "${lines[1]}" == "Team   sonnet ● architect ● lead ● dev ● qa ● scout ● debugger ● docs │ profile balanced · autonomy balanced" ]]
  [ "${#lines[@]}" -eq 5 ]
}

@test "a running build and an armed autonomous run are visible" {
  "$VBW" init > /dev/null
  printf '# x\n\n## Requirements\n\n- R1 [auto] One\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id: "C1", req: "R1", run: ["true"]}] | .phases = [{id: "P1", title: "A", reqs: ["R1"], milestone: "M1"}]
      | .plans = [{id: "P1.1", phase: "P1", title: "A", reqs: ["R1"], files: ["a"], after: [], status: "planned"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" run start build P1.1 > /dev/null
  "$VBW" auto on s1 > /dev/null
  run render
  [[ "${lines[0]}" =~ "│ ▶ build: P1.1 "[0-9]+s" │ ⟳ auto 0/25"$ ]]
  # Another session of the project is not armed: its status line says nothing.
  SID=s2 run render
  [[ "${lines[0]}" != *"⟳ auto"* ]]
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

@test "workflows on turns Dynamic workflows on, keeps every other setting, and never overrides a deliberate off" {
  local s="$CLAUDE_CONFIG_DIR/settings.json"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  printf '{"model": "opus", "permissions": {"defaultMode": "auto"}}\n' > "$s"
  vbw_run workflows status
  [[ "$output" == "default:"* ]]
  vbw_run workflows on
  [ "$status" -eq 0 ]
  [[ "$output" == "on: Dynamic workflows turned on"* ]]
  jq -e '.enableWorkflows == true and .model == "opus" and .permissions.defaultMode == "auto"' "$s"
  vbw_run workflows on
  [ "$output" = "on: Dynamic workflows are enabled" ]
  # Turned off on purpose: told, never overridden.
  printf '{"disableWorkflows": true}\n' > "$s"
  vbw_run workflows on
  [[ "$output" == "off: Dynamic workflows are disabled on purpose"* ]]
  jq -e '.disableWorkflows == true and (has("enableWorkflows") | not)' "$s"
  # No settings file yet: it is created.
  rm -f "$s"
  vbw_run workflows on
  jq -e '.enableWorkflows == true' "$s"
}

@test "started in a subfolder it shows the project; a VBW 1 project is pointed to the conversion" {
  "$VBW" init > /dev/null
  "$VBW" milestone rename "A milestone title that is far too long to fit on one line" > /dev/null
  mkdir -p src/deep
  run bash -c 'jq -nc --arg d "$1/src/deep" "{workspace: {project_dir: \$d}}" | NO_COLOR=1 bash "$2"' _ "$PROJECT" "$SL"
  [[ "${lines[0]}" == "[VBW] project with space │ M1 A milestone title that is far too long… │"* ]]
  rm -rf .vbw && mkdir .vbw-planning
  run render
  [ "${lines[0]}" = "[VBW] VBW 1 plan here · /vbw:vibe to bring it into VBW 2" ]
}

@test "a running step shows how long it has run and how many agents are working" {
  "$VBW" init > /dev/null
  printf '# x\n\n## Requirements\n\n- R1 [auto] One\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" run start plan > /dev/null
  local t="$TEST_ROOT/session.jsonl" w="$TEST_ROOT/session/subagents/workflows/wf_1"
  mkdir -p "$w" && : > "$t"
  : > "$w/agent-a.jsonl" && : > "$w/agent-b.jsonl" && : > "$w/agent-c.jsonl"
  printf '{"agentType": "vbw:dev", "description": "dev P1.2", "model": "sonnet"}' > "$w/agent-a.meta.json"
  printf '{"agentType": "vbw:scout", "description": "scout risks", "model": "haiku"}' > "$w/agent-b.meta.json"
  printf '{"agentType": "vbw:qa", "description": "qa P1", "model": "opus"}' > "$w/agent-c.meta.json"
  touch -t 202001010000 "$w/agent-c.jsonl"
  run bash -c 'jq -nc --arg d "$1" --arg t "$2" "{workspace: {project_dir: \$d}, transcript_path: \$t}" | NO_COLOR=1 bash "$3"' _ "$PROJECT" "$t" "$SL"
  [[ "${lines[0]}" =~ "│ ▶ plan "[0-9]+s" · 2 agents working" ]]
  [ "${lines[1]}" = "Agents ● dev P1.2 sonnet  ● scout risks haiku" ]
  # No run open (a map or debug workflow): the agents alone.
  "$VBW" run end > /dev/null
  run bash -c 'jq -nc --arg d "$1" --arg t "$2" "{workspace: {project_dir: \$d}, transcript_path: \$t}" | NO_COLOR=1 bash "$3"' _ "$PROJECT" "$t" "$SL"
  [[ "${lines[0]}" == *"│ ▶ 2 agents working" ]]
}

@test "the team line follows the profile and per-role models; tokens and prompt cache are shown" {
  "$VBW" init > /dev/null
  "$VBW" config set profile budget > /dev/null
  "$VBW" config set model.dev opus > /dev/null
  run bash -c 'jq -nc --arg d "$1" "{workspace: {project_dir: \$d}, context_window: {used_percentage: 10, current_usage:
    {input_tokens: 2, output_tokens: 195, cache_creation_input_tokens: 3800, cache_read_input_tokens: 55500}}}" | NO_COLOR=1 bash "$2"' _ "$PROJECT" "$SL"
  [ "${lines[1]}" = "Team   sonnet ● architect ● lead ● qa ● debugger ● docs │ opus ● dev │ haiku ● scout │ profile budget · autonomy balanced" ]
  [[ "${lines[2]}" == *"│ Tokens 2 in 195 out │ Cache 93% hit 3.8K write 55.5K read │"* ]]
}

@test "statusline on asks Claude Code to refresh it every 5 seconds, and tops up a setting made without it" {
  vbw_run statusline on
  jq -e '.statusLine.type == "command" and (.statusLine.command | contains("vbw-statusline.sh")) and .statusLine.refreshInterval == 5' "$SETTINGS"
  # VBW's line set by an older VBW: on adds the interval and keeps every other setting.
  jq '.theme = "dark" | .statusLine.padding = 1 | del(.statusLine.refreshInterval)' "$SETTINGS" > "$TEST_ROOT/s.json" && cp "$TEST_ROOT/s.json" "$SETTINGS"
  vbw_run statusline status
  [[ "$output" == "on: the VBW status line"*"vbw statusline on"* ]]
  vbw_run statusline on
  [ "$status" -eq 0 ]
  [ "$output" = "on: the VBW status line" ]
  jq -e '.theme == "dark" and .statusLine.padding == 1 and .statusLine.refreshInterval == 5' "$SETTINGS"
  vbw_run statusline status
  [ "$output" = "on: the VBW status line" ]
  # An interval the user chose is theirs.
  jq '.statusLine.refreshInterval = 10' "$SETTINGS" > "$TEST_ROOT/s.json" && cp "$TEST_ROOT/s.json" "$SETTINGS"
  vbw_run statusline on
  jq -e '.statusLine.refreshInterval == 10' "$SETTINGS"
  vbw_run statusline off
  jq -e '.theme == "dark" and (has("statusLine") | not)' "$SETTINGS"
}
