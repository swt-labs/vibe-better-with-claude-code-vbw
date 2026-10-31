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

@test "R224: outside a VBW project (no .vbw at or above) it prints nothing and exits 3, the hand-back signal, so the setting shows the user's earlier status line instead" {
  run render
  [ "$status" -eq 3 ] || { echo "exit $status, output:"; printf '%s\n' "$output"; false; }
  [ -z "$output" ] || { printf '%s\n' "$output"; false; }
}

@test "in a VBW project it shows progress and the last next step" {
  "$VBW" init > /dev/null
  printf '# x\n\n## Requirements\n\n- R1 [auto] One\n- R2 [human] Two\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" next > /dev/null
  run render
  [[ "${lines[0]}" == "[VBW] project with space │ M1 First milestone │ ░░░░░░░░░░ 0/2 done │ ✓ idle: plan is next" ]]
  [[ "${lines[1]}" == "Team   opus ● architect ● lead │ sonnet ● dev ● qa ● scout ● debugger ● docs │ profile balanced · autonomy balanced" ]]
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
  [[ "${lines[0]}" =~ "│ ● working: building P1.1 · 0 of 1 │ ⟳ auto 0/25"$ ]]
  # Another session of the project is not armed: its status line says nothing.
  SID=s2 run render
  [[ "${lines[0]}" != *"⟳ auto"* ]]
}

@test "a gate that needs the user says so" {
  "$VBW" init > /dev/null
  printf '%s\n' '{"action":"approve","gate":true,"instruction":"x","detail":{}}' > .vbw/runtime/next.json
  run render
  [[ "${lines[0]}" == *"│ ⚑ needs you: approve" ]]
}

@test "no data from Claude Code, or garbage, never breaks it" {
  mkdir -p .vbw
  run bash -c 'printf "" | NO_COLOR=1 bash "$1"' _ "$SL"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  run bash -c 'printf "not json" | NO_COLOR=1 bash "$1"' _ "$SL"
  [ "$status" -eq 0 ]
  [ "$output" = "[VBW] status line unavailable" ]
}

@test "the branch is read in a linked worktree too" {
  git worktree add -q "$TEST_ROOT/wt" -b feature
  mkdir -p "$TEST_ROOT/wt/.vbw"
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
  mkdir -p .vbw
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

@test "R224: started in a subfolder it shows the project; a .vbw-planning folder with no .vbw at or above is outside a VBW project, so no VBW 1 line shows" {
  "$VBW" init > /dev/null
  "$VBW" milestone rename "A milestone title that is far too long to fit on one line" > /dev/null
  mkdir -p "src/Sub Folder With Spaces"
  run bash -c 'jq -nc --arg d "$1/src/Sub Folder With Spaces" "{workspace: {project_dir: \$d}}" | NO_COLOR=1 bash "$2"' _ "$PROJECT" "$SL"
  [[ "${lines[0]}" == "[VBW] project with space │ M1 A milestone title that is far too long… │"* ]]
  # A git repository inside the project is a project of its own: the record above its git top is not its record.
  mkdir -p "inner repo/deep" && git -C "inner repo" init -q
  run bash -c 'jq -nc --arg d "$1/inner repo/deep" "{workspace: {project_dir: \$d}}" | NO_COLOR=1 bash "$2"' _ "$PROJECT" "$SL"
  [ "${lines[0]}" = "[VBW] no project here · /vbw:vibe to start" ]
  rm -rf .vbw && mkdir .vbw-planning
  run render
  [ "$status" -eq 3 ] && [ -z "$output" ] || { echo "exit $status, output:"; printf '%s\n' "$output"; false; }
}

@test "R224: a .vbw folder without a record shows the no-project line and writes no cost side file; with a record the side file is written" {
  mkdir -p .vbw
  run render
  [[ "${lines[0]}" == "[VBW] no project here"* ]] || { printf '%s\n' "$output"; false; }
  [ ! -e .vbw/runtime ] || { ls -R .vbw; false; }
  "$VBW" init > /dev/null
  run render
  [ -f .vbw/runtime/cost.s1.json ]
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
  [[ "${lines[0]}" =~ "│ ● working: planning · 2 agents working" ]]
  [ "${lines[1]}" = "Agents ● dev P1.2 sonnet  ● scout risks haiku" ]
  # No run open (a map or debug workflow): the agents alone.
  "$VBW" run end > /dev/null
  run bash -c 'jq -nc --arg d "$1" --arg t "$2" "{workspace: {project_dir: \$d}, transcript_path: \$t}" | NO_COLOR=1 bash "$3"' _ "$PROJECT" "$t" "$SL"
  [[ "${lines[0]}" == *"│ ● working: 2 agents" ]]
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

@test "from Claude Code 2.1.287 the agents and team line is dropped; line 1 keeps the agent count" {
  "$VBW" init > /dev/null
  "$VBW" run start plan > /dev/null
  local t="$TEST_ROOT/session.jsonl" w="$TEST_ROOT/session/subagents/workflows/wf_1" v
  mkdir -p "$w" && : > "$t"
  : > "$w/agent-a.jsonl"
  printf '{"agentType": "vbw:dev", "description": "dev P1.2", "model": "sonnet"}' > "$w/agent-a.meta.json"
  for v in 2.1.287 2.1.291 2.2.0 3.0.0; do
    run bash -c 'jq -nc --arg d "$1" --arg t "$2" --arg v "$4" "{workspace: {project_dir: \$d}, transcript_path: \$t, version: \$v}" | NO_COLOR=1 bash "$3"' _ "$PROJECT" "$t" "$SL" "$v"
    [ "${#lines[@]}" -eq 4 ]
    [[ "${lines[0]}" =~ "│ ● working: planning · 1 agent working" ]]
    [[ "${lines[1]}" == "Context "* ]]
  done
  # Older, or not reported: the line stays as it was.
  for v in 2.1.286 2.1.29 2.0.300 "" garbage; do
    run bash -c 'jq -nc --arg d "$1" --arg t "$2" --arg v "$4" "{workspace: {project_dir: \$d}, transcript_path: \$t, version: \$v}" | NO_COLOR=1 bash "$3"' _ "$PROJECT" "$t" "$SL" "$v"
    [ "${#lines[@]}" -eq 5 ]
    [ "${lines[1]}" = "Agents ● dev P1.2 sonnet" ]
  done
  # No agents: no team line either.
  rm -f "$w/agent-a.jsonl"
  run bash -c 'jq -nc --arg d "$1" "{workspace: {project_dir: \$d}, version: \"2.1.290\"}" | NO_COLOR=1 bash "$2"' _ "$PROJECT" "$SL"
  [ "${#lines[@]}" -eq 4 ]
  [[ "${lines[1]}" == "Context "* ]]
}

@test "a session in a VBW project tops up the refresh interval of VBW's status line, and leaves any other status line alone" {
  "$VBW" init > /dev/null
  "$VBW" statusline on > /dev/null
  jq 'del(.statusLine.refreshInterval)' "$SETTINGS" > "$TEST_ROOT/s.json" && cp "$TEST_ROOT/s.json" "$SETTINGS"
  CLAUDE_PROJECT_DIR="$PROJECT" bash "$PLUGIN_ROOT/hooks/session-start.sh" < /dev/null > /dev/null
  jq -e '.statusLine.refreshInterval == 5' "$SETTINGS"
  printf '{"statusLine": {"type": "command", "command": "my-line"}}\n' > "$SETTINGS"
  CLAUDE_PROJECT_DIR="$PROJECT" bash "$PLUGIN_ROOT/hooks/session-start.sh" < /dev/null > /dev/null
  jq -e '.statusLine == {type: "command", command: "my-line"}' "$SETTINGS"
}

@test "doctor warns when VBW's status line has no refresh interval" {
  "$VBW" init > /dev/null
  "$VBW" statusline on > /dev/null
  jq 'del(.statusLine.refreshInterval)' "$SETTINGS" > "$TEST_ROOT/s.json" && cp "$TEST_ROOT/s.json" "$SETTINGS"
  run "$VBW" doctor
  [[ "$output" == *"refreshes on events only"*"vbw statusline on"* ]]
}

# R235 (T205): a render that fails is not silent. jq's stderr of the render goes to
# .vbw/runtime/statusline.err (overwritten each call, inside the project), so a miss of
# the step on a runner names its cause; after a good render the file is empty. No new
# process: one redirection, so the 60 ms budget holds (tools/bench-hooks.sh).

# render_with SCRIPT: the render through another copy of the status line script.
render_with() { cc_json | NO_COLOR=1 bash "$1"; }

@test "R235: when the render fails, .vbw/runtime/statusline.err holds jq's error and the fallback line is printed" {
  "$VBW" init > /dev/null
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  printf '\n| ) (\n' >> "$TEST_ROOT/plugin/scripts/statusline.jq"
  run render_with "$TEST_ROOT/plugin/scripts/vbw-statusline.sh"
  [ "${lines[0]}" = "[VBW] status line unavailable" ] || { echo "$output"; false; }
  [ -s .vbw/runtime/statusline.err ] || { echo "no .vbw/runtime/statusline.err written"; ls -la .vbw/runtime; false; }
  grep -q 'jq: error' .vbw/runtime/statusline.err || { echo "the file does not hold jq's error:"; cat .vbw/runtime/statusline.err; false; }
}

@test "R235: a good render leaves .vbw/runtime/statusline.err empty, overwritten each call" {
  "$VBW" init > /dev/null
  printf 'stale error from an earlier call\n' > .vbw/runtime/statusline.err
  run render
  [[ "${lines[0]}" == "[VBW] project with space"* ]] || { echo "$output"; false; }
  [ -f .vbw/runtime/statusline.err ] || { echo "the file was not written"; false; }
  [ ! -s .vbw/runtime/statusline.err ] || { echo "a good render left text in it:"; cat .vbw/runtime/statusline.err; false; }
}

@test "R235: without a runtime folder the render still prints and writes nothing outside the project" {
  "$VBW" init > /dev/null
  rm -rf .vbw/runtime
  run render
  [[ "${lines[0]}" == "[VBW] project with space"* ]] || { echo "$output"; false; }
  [ ! -e .vbw/runtime/statusline.err ] || { echo "the render made the runtime folder for its error file"; false; }
}

# R235 (P189.2): the bench reads the first line through `| head -n 1` under pipefail; a
# reader that leaves before the answer is written must not fail the status line
# (bash 5.2 on Linux writes in pieces: the late piece killed it with SIGPIPE, status 141).
@test "R235: a reader that has left does not fail the render, a good one or the fallback (status 0, no SIGPIPE)" {
  "$VBW" init > /dev/null
  local st
  # The pipeline runs in a fresh bash: on bash 3.2 bats' DEBUG trap resets PIPESTATUS,
  # in the test body and in its subshells alike.
  # shellcheck disable=SC2016 # expanded by the inner bash
  st=$(cc_json | bash -c 'NO_COLOR=1 bash "$1" | true; echo "${PIPESTATUS[0]}"' _ "$PLUGIN_ROOT/scripts/vbw-statusline.sh")
  [ "$st" = 0 ] || { echo "status line exited $st under a reader that left"; false; }
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  printf '\n| ) (\n' >> "$TEST_ROOT/plugin/scripts/statusline.jq"
  # shellcheck disable=SC2016 # expanded by the inner bash
  st=$(cc_json | bash -c 'NO_COLOR=1 bash "$1" | true; echo "${PIPESTATUS[0]}"' _ "$TEST_ROOT/plugin/scripts/vbw-statusline.sh")
  [ "$st" = 0 ] || { echo "fallback render exited $st under a reader that left"; false; }
}
