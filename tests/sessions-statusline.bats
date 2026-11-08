#!/usr/bin/env bats
# R192, phase P153 (L1): the status line says who leads. In the session that
# holds the run the run cell ends with ` · leading`; in any other session with
# ` · held by <name>` (the name cut to 20 characters with an ellipsis; the first 8
# characters of the id when no name is known); nothing when the lease has no
# session. The name is the list's current one (one jq pass over
# <claude-config-dir>/sessions/*.json, only while a lease is open), else the one
# the glance's holder stores. With the list missing it renders as today.

load helper
load sessions-helper
load fixture-helper

sstat_project() {
  vbw_setup
  vbw_git_project
  SL="$PLUGIN_ROOT/scripts/vbw-statusline.sh"
  "$VBW" init > /dev/null
  printf '# x\n\n## Requirements\n\n- R1 [auto] One\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id: "C1", req: "R1", run: ["true"]}] | .phases = [{id: "P1", title: "A", reqs: ["R1"], milestone: "M1"}]
      | .plans = [{id: "P1.1", phase: "P1", title: "A", reqs: ["R1"], files: ["a"], after: [], status: "planned"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
}

setup_file() { fixture_build sstat sstat_project; }
setup() { fixture_copy sstat; }

teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

cc_json() {
  jq -nc --arg d "$PROJECT" --arg sid "$1" '{session_id: $sid, workspace: {project_dir: $d, current_dir: $d}, model: {display_name: "Sonnet 5.5"},
    version: "2.1.301", cost: {total_cost_usd: 1.4234, total_duration_ms: 622000, total_api_duration_ms: 355000,
    total_lines_added: 303, total_lines_removed: 12},
    context_window: {used_percentage: 31, total_input_tokens: 62000, context_window_size: 200000}}'
}
render() { cc_json "$1" | NO_COLOR=1 bash "$SL"; }
first() { render "$1" | head -n 1; }
start() { VBW_SESSION_ID="$1" "$VBW" run start build P1.1 > /dev/null; }

@test "R192: the holding session reads leading, another session held by the name, after the step's cell" {
  registry_entry 101 "$SESSION_A" "Payments work"
  start "$SESSION_A"
  local l
  l=$(first "$SESSION_A")
  [[ "$l" == *"● working: building P1.1 · 0 of 1 · leading" ]] || { echo "$l"; false; }
  l=$(first "$SESSION_B")
  [[ "$l" == *"● working: building P1.1 · 0 of 1 · held by Payments work" ]] || { echo "$l"; false; }
  [[ "$l" != *"leading"* ]]
}

@test "R192: a /rename during the run shows at once; with the list gone the stored name shows" {
  registry_entry 101 "$SESSION_A" "Payments work"
  start "$SESSION_A"
  registry_entry 101 "$SESSION_A" "Checkout fix" 1792300090000
  local l
  l=$(first "$SESSION_B")
  [[ "$l" == *"held by Checkout fix" ]] || { echo "$l"; false; }
  rm -r "$(registry_dir)"
  l=$(first "$SESSION_B")
  [[ "$l" == *"held by Payments work" ]] || { echo "$l"; false; }
}

@test "R192: no name known gives the first 8 characters of the id; a lease without a session shows no holder" {
  start "$SESSION_A"
  local l
  l=$(first "$SESSION_B")
  [[ "$l" == *"held by 01234567" ]] || { echo "$l"; false; }
  [[ "$l" != *"$SESSION_A"* ]]
  VBW_SESSION_ID="$SESSION_A" "$VBW" run end > /dev/null
  "$VBW" run start build P1.1 > /dev/null
  l=$(first "$SESSION_B")
  # The first run just ended is one run of history: the step now carries a rough end time (R270).
  [[ "$l" == *"● working: building P1.1 · 0 of 1 · until ~"* ]] || { echo "$l"; false; }
  [[ "$l" != *"held by"* && "$l" != *"leading"* ]]
}

@test "R192: a long name is cut to 20 characters with an ellipsis; escape sequences never reach the terminal" {
  local long="Payments work on the checkout flow"
  registry_entry 101 "$SESSION_A" "$long"
  start "$SESSION_A"
  local l
  l=$(first "$SESSION_B")
  [[ "$l" == *"held by ${long:0:19}…" ]] || { echo "$l"; false; }
  registry_entry 101 "$SESSION_A" "$(printf 'Pay\033[31mments\007 work')" 1792300090000
  l=$(first "$SESSION_B")
  [[ "$l" == *"held by Payments work" ]] || { echo "$l"; false; }
  [[ "$l" != *$'\033'* && "$l" != *$'\007'* ]]
}

@test "R192: with the list missing the status line renders exactly as with an empty list, and a malformed entry is skipped" {
  registry_entry 101 "$SESSION_A" "Payments work"
  start "$SESSION_A"
  mkdir -p "$(registry_dir)"
  printf '{"sessionId": "%s", "name": "Broken' "$SESSION_A" > "$(registry_dir)/100.json"
  local with without
  with=$(render "$SESSION_A")
  [[ "$with" == *"· leading"* ]] || { echo "$with"; false; }
  rm -r "$(registry_dir)"
  without=$(render "$SESSION_A")
  [ "$with" = "$without" ] || { echo "$with"; echo "$without"; false; }
  [ "$(printf '%s\n' "$without" | wc -l | tr -d ' ')" -eq 4 ]
}

@test "R192: a malformed file in the list does not cost the good entries their names" {
  registry_entry 101 "$SESSION_A" "Payments work"
  start "$SESSION_A"
  # A /rename after the start: only the list has the new name, the stored one is old.
  registry_entry 101 "$SESSION_A" "Renamed chat" 1792300009000
  printf '{"sessionId": "%s", "name": "Broken' "$SESSION_B" > "$(registry_dir)/100.json"
  printf 'not json at all' > "$(registry_dir)/99.json"
  local l
  l=$(render "$SESSION_B")
  [[ "$l" == *"· held by Renamed chat"* ]] || { echo "$l"; false; }
}

@test "R192: the list is read with one jq pass per render, only while a lease is open" {
  local real log="$TEST_ROOT/jq.log"
  real=$(command -v jq)
  mkdir -p "$TEST_ROOT/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$log" "$real" > "$TEST_ROOT/bin/jq"
  chmod +x "$TEST_ROOT/bin/jq"
  registry_entry 101 "$SESSION_A" "Payments work"
  registry_entry 102 "$SESSION_B" "Other chat"
  start "$SESSION_A"
  : > "$log"
  PATH="$TEST_ROOT/bin:$PATH" render "$SESSION_B" > /dev/null
  [ "$(grep -c '/sessions/' "$log")" -eq 1 ] || { cat "$log"; false; }
  VBW_SESSION_ID="$SESSION_A" "$VBW" run end > /dev/null
  : > "$log"
  PATH="$TEST_ROOT/bin:$PATH" render "$SESSION_B" > /dev/null
  [ "$(grep -c '/sessions/' "$log")" -eq 0 ] || { cat "$log"; false; }
}

@test "R192: the hook bench measures the status line with a lease open and a list of chats on disk" {
  local b="$REPO_ROOT/tools/bench-hooks.sh"
  # Code lines only: a comment that names them measures nothing.
  grep -vE '^[[:space:]]*#' "$b" | grep -qE '> *"[^"]*run-open"'
  grep -vE '^[[:space:]]*#' "$b" | grep -qE 'sessions/[^ ]*\.json'
}

@test "R192: with several entries for one session the newest updatedAt wins, whatever the file order" {
  start "$SESSION_A"
  registry_entry 101 "$SESSION_A" "Newest name" 1792300090000
  registry_entry 102 "$SESSION_A" "Older name" 1792300010000
  local l
  l=$(first "$SESSION_B")
  [[ "$l" == *"held by Newest name" ]] || { echo "$l"; false; }
  registry_entry 101 "$SESSION_A" "Older name" 1792300010000
  registry_entry 102 "$SESSION_A" "Newest name" 1792300090000
  l=$(first "$SESSION_B")
  [[ "$l" == *"held by Newest name" ]] || { echo "$l"; false; }
}
