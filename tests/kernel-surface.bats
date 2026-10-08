#!/usr/bin/env bats
# Kernel commands behind the user surface (M5): human acceptance, ship,
# settings and model profiles, and the autonomy gate.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] Pay\n- R2 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# A milestone whose auto requirement is proven on the current files.
proven_project() {
  mkdir -p src && printf 'paid\n' > src/pay.txt
  edit_record '.checks = [{id: "C1", req: "R1", run: ["grep", "-qx", "paid", "src/pay.txt"]}]
    | .phases = [{id: "P1", title: "Pay", reqs: ["R1", "R2"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], status: "done"}]'
  "$VBW" approve > /dev/null
  git add src/pay.txt && git commit -q -m "feat: pay" -- src/pay.txt
  "$VBW" prove > /dev/null
}

# --- acceptance --------------------------------------------------------------

@test "accept and reject apply only to human requirements" {
  vbw_run req accept R1
  [ "$status" -eq 1 ]
  [[ "$output" == *"R1 is proved by its checks"* ]]
  vbw_run req accept R9
  [[ "$output" == *"unknown requirement R9"* ]]
  vbw_run req accept R2
  [ "$status" -eq 0 ]
  jq -e '.requirements[1].status == "accepted"' .vbw/record.json
}

@test "a rejection opens a fix; when it is done the requirement returns for acceptance" {
  vbw_run req reject R2 "the logo is blurry"
  [ "$status" -eq 0 ]
  jq -e '.requirements[1].status == "rejected" and .fixes == [{id: "F1", req: "R2", attempts: 0, status: "open", note: "the logo is blurry"}]' .vbw/record.json
  vbw_run fix done F1
  [ "$status" -eq 0 ]
  [[ "$output" == *"goes back to the user"* ]]
  jq -e '.requirements[1].status == "open" and .fixes[0].status == "closed"' .vbw/record.json
}

# --- ship --------------------------------------------------------------------

@test "ship is refused while the working folder has uncommitted files, naming them" {
  printf 'notes\n' > notes.txt
  proven_project
  "$VBW" qa record P1 pass standard > /dev/null
  "$VBW" req accept R2 > /dev/null
  # Proof runs on the committed code: an untracked file does not change it, but
  # shipping still wants everything in git history.
  vbw_run ship
  [ "$status" -eq 1 ]
  [[ "$output" == *"not committed"* && "$output" == *"notes.txt"* ]]
  jq -e '.milestone.status != "shipped"' .vbw/record.json
  git add notes.txt
  vbw_run ship
  [ "$status" -eq 1 ]
  git commit -q -m "docs: notes" -- notes.txt
  # The committed notes were never part of a proof: prove again, then ship.
  vbw_run ship
  [ "$status" -eq 1 ]
  [[ "$output" == *"prove"* ]]
  "$VBW" prove > /dev/null
  vbw_run ship
  [ "$status" -eq 0 ]
}

@test "ship is refused until vbw next says ship, then marks the milestone shipped" {
  proven_project
  vbw_run ship
  [ "$status" -eq 1 ]
  [[ "$output" == *"not ready to ship: vbw next says qa"* ]]
  "$VBW" qa record P1 pass standard > /dev/null
  vbw_run ship
  [[ "$output" == *"not ready to ship: vbw next says accept"* ]]
  "$VBW" req accept R2 > /dev/null
  vbw_run ship
  [ "$status" -eq 0 ]
  jq -e '.milestone.status == "shipped" and (.decisions[-1].text | startswith("Shipped M1"))' .vbw/record.json
  vbw_run next --json
  echo "$output" | jq -e '.action == "milestone"'
}

# --- settings ------------------------------------------------------------------

@test "config resolves VBW 1's seven roles from the profile and per-role overrides" {
  vbw_run config
  [[ "$output" == *"profile: balanced"* ]]
  [[ "$output" == *"model.dev: sonnet"* ]]
  vbw_run config models
  [ "$output" = '{"architect":"opus","lead":"opus","dev":"sonnet","qa":"sonnet","scout":"sonnet","debugger":"sonnet","docs":"sonnet"}' ]
  "$VBW" config set profile budget > /dev/null
  "$VBW" config set model.dev claude-opus-5-5 > /dev/null
  vbw_run config models
  [ "$output" = '{"architect":"sonnet","lead":"sonnet","dev":"claude-opus-5-5","qa":"sonnet","scout":"haiku","debugger":"sonnet","docs":"sonnet"}' ]
  "$VBW" config set model.dev default > /dev/null
  jq -e '.settings | has("models") | not' .vbw/record.json
}

@test "overrides saved under the earlier role names move to VBW 1's names" {
  jq '.settings.models = {planner: "opus", critic: "haiku", builder: "opus"}' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run config models
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.lead == "opus" and .qa == "sonnet" and .dev == "opus"'
  jq -e '.settings.models == {lead: "opus", qa: "haiku", dev: "opus"}' .vbw/record.json
}

@test "config refuses unknown keys and invalid values, and changes nothing" {
  cp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run config set profile turbo
  [ "$status" -eq 2 ]
  vbw_run config set autonomy_cap many
  [ "$status" -eq 2 ]
  vbw_run config set autonomy_cap 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"settings.autonomy_cap must be an integer 1-500"* ]]
  vbw_run config set colour blue
  [ "$status" -eq 2 ]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}

# --- autonomy ------------------------------------------------------------------

gate() {
  jq -nc --arg s "$1" '{hook_event_name: "Stop", session_id: $s, stop_hook_active: false}' | "$VBW" auto gate
}

@test "auto on needs a well-formed session id and arms only that session" {
  vbw_run auto on
  [ "$status" -eq 2 ]
  vbw_run auto on "x; rm -rf ~"
  [ "$status" -eq 2 ]
  [ -z "$(ls .vbw/runtime 2> /dev/null | grep "^auto\.")" ]
  vbw_run auto on s1
  [ "$status" -eq 0 ]
  jq -e '.session == "s1" and .steps == 0 and .cap == 25' .vbw/runtime/auto.s1.json
  run gate s2
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the gate is silent when no run is armed" {
  run gate s1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the gate blocks the stop with the next step and counts it" {
  edit_record '.checks = [{id: "C1", req: "R1", run: ["true"]}]
    | .phases = [{id: "P1", title: "Pay", reqs: ["R1", "R2"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["a.txt"], after: [], status: "planned"}]'
  "$VBW" approve > /dev/null
  "$VBW" auto on s1 > /dev/null
  run gate s1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block" and (.reason | contains("step 1 of 25")) and (.reason | contains("build: Run the build workflow for P1.1"))'
  jq -e '.steps == 1' .vbw/runtime/auto.s1.json
}

@test "the gate lets the session wait while a workflow runs" {
  "$VBW" auto on s1 > /dev/null
  "$VBW" run start plan > /dev/null
  run gate s1
  [ -z "$output" ]
  [ -f .vbw/runtime/auto.s1.json ]
}

@test "the gate stops and disarms at a decision that needs the user" {
  "$VBW" auto on s1 > /dev/null
  edit_record '.checks = [{id: "C1", req: "R1", run: ["true"]}]
    | .phases = [{id: "P1", title: "Pay", reqs: ["R1", "R2"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["a.txt"], after: [], status: "planned"}]'
  run gate s1
  echo "$output" | jq -e '(.decision // "allow") != "block" and (.systemMessage | contains("needs you. approve"))'
  [ ! -f .vbw/runtime/auto.s1.json ]
}

@test "the gate stops and disarms at the step cap" {
  "$VBW" config set autonomy_cap 1 > /dev/null
  edit_record '.checks = [{id: "C1", req: "R1", run: ["true"]}]
    | .phases = [{id: "P1", title: "Pay", reqs: ["R1", "R2"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["a.txt"], after: [], status: "planned"}]'
  "$VBW" approve > /dev/null
  "$VBW" auto on s1 > /dev/null
  run gate s1
  echo "$output" | jq -e '.decision == "block"'
  run gate s1
  echo "$output" | jq -e '(.decision // "allow") != "block" and (.systemMessage | contains("after 1 steps"))'
  [ ! -f .vbw/runtime/auto.s1.json ]
}


@test "an escalated fix can be retried once by the user's decision" {
  edit_record '.checks = [{id: "C1", req: "R1", run: ["false"]}] | .fixes = [{id: "F1", req: "R1", attempts: 3, status: "escalated", note: "C1 fail"}]'
  vbw_run fix retry F1
  [ "$status" -eq 0 ]
  jq -e '.fixes[0].status == "open" and .fixes[0].attempts == 3' .vbw/record.json
  vbw_run fix retry F1
  [ "$status" -eq 1 ]
  [[ "$output" == *"F1 is not escalated"* ]]
}

# --- todo -----------------------------------------------------------------------

@test "the backlog: add, list, done and drop" {
  vbw_run todo
  [ "$output" = "no open todos (vbw todo add TEXT)" ]
  "$VBW" todo add "Dark mode" > /dev/null
  "$VBW" todo add "CSV export" > /dev/null
  vbw_run todo list
  [ "$output" = "T1 Dark mode
T2 CSV export" ]
  "$VBW" todo done T1 > /dev/null
  "$VBW" todo drop T2 > /dev/null
  jq -e '[.todos[].status] == ["done", "dropped"]' .vbw/record.json
  vbw_run todo done T9
  [ "$status" -eq 1 ]
}

# --- doctor -------------------------------------------------------------------

@test "doctor checks the project and the guards, and changes nothing" {
  cp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run doctor
  [[ "$output" == *"✓ jq "* ]]
  [[ "$output" == *"✓ the plan of record is valid"* ]]
  [[ "$output" == *"✓ the spec is valid"* ]]
  [[ "$output" == *"✓ the guards work"* ]]
  [[ "$output" == *"! the VBW status line is not on"* ]]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}

@test "doctor fails on a corrupt record and names the fix" {
  printf '{"schema": "damaged"}' > .vbw/record.json
  vbw_run doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ the plan of record is corrupt"* ]]
  [[ "$output" == *"fix: restore .vbw/record.json from git"* ]]
}

@test "doctor reports disabled workflows" {
  printf '{"disableWorkflows": true}' > "$CLAUDE_CONFIG_DIR/settings.json"
  vbw_run doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ workflows are disabled in your settings"* ]]
  printf '{"enableWorkflows": true}' > "$CLAUDE_CONFIG_DIR/settings.json"
  vbw_run doctor
  [[ "$output" == *"✓ workflows enabled"* ]]
}

@test "doctor works where Claude Code is not installed (CI machines)" {
  mkdir -p "$TEST_ROOT/bin"
  printf '#!/bin/sh\nexit 127\n' > "$TEST_ROOT/bin/claude"
  chmod +x "$TEST_ROOT/bin/claude"
  PATH="$TEST_ROOT/bin:$PATH" vbw_run doctor
  [[ "$output" == *"! Claude Code version unknown"* ]]
  [[ "$output" == *"✓ the plan of record is valid"* ]]
}

@test "autonomy is balanced until set; guided and hands-off are the other levels" {
  vbw_run config autonomy
  [ "$output" = balanced ]
  vbw_run config
  [[ "$output" == *"autonomy: balanced"* ]]
  "$VBW" config set autonomy hands-off > /dev/null
  vbw_run config autonomy
  [ "$output" = hands-off ]
  cp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run config set autonomy reckless
  [ "$status" -eq 2 ]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}
