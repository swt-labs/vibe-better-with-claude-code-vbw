#!/usr/bin/env bats
# Kernel commands behind the user surface (M5): human acceptance, ship,
# settings and model profiles, and the autonomy gate.

load helper
load fixture-helper

# The initialised shop (one auto, one human requirement), built once per file.
setup_file() { fixture_build shop shop_project; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

shop_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] Pay\n- R2 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
}

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

# R244 (T215, D544): vbw ship blocks only on uncommitted changes to the milestone's own
# files, the files its plans name and the protected check files, resolved as vbw commit
# resolves them (vbw_plan_paths, vbw_in_repo, vbw_changed), in the project and in each
# checked-out submodule by project path; the user's own files never block and are never
# named. ship_uncommitted (cmd-ship.sh) is the one definition: it prints the whole refusal
# (each blocking file on its own line as "  FILE (plan P1.1)" or "  FILE (protected check
# file)", last line "Next: ..." naming vbw commit) and returns 1, or prints nothing and
# returns 0.

# ship_next_line OUTPUT: the refusal's last non-empty line starts "Next: " and names vbw commit.
ship_next_line() {
  local last
  last=$(printf '%s\n' "$1" | sed '/^[[:space:]]*$/d' | tail -n 1)
  [[ "$last" == "Next: "* && "$last" == *"vbw commit"* ]] || { printf 'no Next line naming vbw commit at the end of the refusal:\n%s\n' "$1"; return 1; }
}

@test "R244: a user's own untracked and staged files never block the ship, are never named by it, and are left as they were" {
  printf 'notes\n' > notes.txt
  printf 'mine\n' > mine.txt && git add mine.txt
  proven_project
  "$VBW" qa record P1 pass standard > /dev/null
  "$VBW" req accept R2 > /dev/null
  vbw_run ship
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"notes.txt"* && "$output" != *"mine.txt"* && "$output" != *"not committed"* ]] || { echo "$output"; false; }
  jq -e '.milestone.status == "shipped"' .vbw/record.json
  [ "$(git status --porcelain -- notes.txt)" = "?? notes.txt" ]
  [ "$(git status --porcelain -- mine.txt)" = "A  mine.txt" ]
}

@test "R244: an uncommitted edit to a plan-named file refuses the ship in one message naming the file with its plan and vbw commit on the Next line; once committed and proved again, it ships" {
  proven_project
  # The edit is proved while uncommitted: the proof reads the files on disk.
  printf 'paid\nmore\n' > src/pay.txt
  "$VBW" prove > /dev/null
  "$VBW" qa record P1 pass standard > /dev/null
  "$VBW" req accept R2 > /dev/null
  vbw_run ship
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"not committed"* ]] || { echo "$output"; false; }
  [[ "$output" == *"  src/pay.txt (plan P1.1)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"the proven work is not committed"* && "$output" != *"commit it, then vbw ship"* ]] || { echo "$output"; false; }
  ship_next_line "$output"
  [[ "$output" == *"vbw commit P1.1"* ]] || { echo "$output"; false; }
  jq -e '.milestone.status != "shipped"' .vbw/record.json
  "$VBW" commit P1.1 "feat(pay): more" > /dev/null
  # The committed edit was never proved or judged as committed code: prove and
  # record QA again (QA reads the files as committed), then ship.
  vbw_run ship
  [ "$status" -eq 1 ]
  [[ "$output" == *"prove"* ]]
  "$VBW" prove > /dev/null
  "$VBW" qa record P1 pass standard > /dev/null
  vbw_run ship
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R244: the blocking set is the milestone's plan files and protected check files: a deleted plan file and an edited protected check file are named, a shipped milestone's plan file and the user's files are not" {
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  printf 'true\n' > tests/pay.sh
  printf 'old\n' > src/old.txt
  git add src tests && git commit -q -m "feat: seed" -- src tests
  edit_record '.checks = [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}] | .protected = ["tests/pay.sh"]
    | .requirements += [{id: "R3", text: "Old", proof: "auto", status: "proven", milestone: "M0"}]
    | .shipped = [{id: "M0", title: "Old", at: "2026-01-01T00:00:00Z"}]
    | .phases = [{id: "P0", title: "Old", reqs: ["R3"], milestone: "M0"}, {id: "P1", title: "Pay", reqs: ["R1", "R2"], milestone: "M1"}]
    | .plans = [{id: "P0.1", phase: "P0", title: "Old", reqs: ["R3"], files: ["src/old.txt"], after: [], status: "done"},
                {id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], status: "done"}]'
  rm src/pay.txt
  printf 'false\n' > tests/pay.sh
  printf 'older\n' > src/old.txt
  printf 'notes\n' > notes.txt
  printf 'mine\n' > mine.txt && git add mine.txt
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  run vbw_kernel '. "$VBW_LIB/cmd-ship.sh"; ship_uncommitted'
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"  src/pay.txt (plan P1.1)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"  tests/pay.sh (protected check file)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"old.txt"* && "$output" != *"notes.txt"* && "$output" != *"mine.txt"* ]] || { echo "$output"; false; }
  ship_next_line "$output"
  git checkout -q -- src/pay.txt tests/pay.sh
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  run vbw_kernel '. "$VBW_LIB/cmd-ship.sh"; ship_uncommitted'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R244: in submodules, by project path: an uncommitted plan file in sub and in 'sub/inner dir' each refuse the ship, a user's file in sub never blocks, and the pointer stays moved" {
  git init -q "$TEST_ROOT/subsrc"
  printf 'paid\n' > "$TEST_ROOT/subsrc/pay.txt"
  git -C "$TEST_ROOT/subsrc" add pay.txt
  git -C "$TEST_ROOT/subsrc" commit -q -m "chore: seed"
  # The submodule holds a submodule of its own; an exact plan entry reaches into it.
  git init -q "$TEST_ROOT/innersrc"
  printf 'i\n' > "$TEST_ROOT/innersrc/i.txt"
  git -C "$TEST_ROOT/innersrc" add i.txt
  git -C "$TEST_ROOT/innersrc" commit -q -m "chore: seed"
  git -C "$TEST_ROOT/subsrc" -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/innersrc" "inner dir"
  git -C "$TEST_ROOT/subsrc" commit -q -m "chore: inner"
  git -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/subsrc" sub
  git -c protocol.file.allow=always submodule update -q --init --recursive
  git commit -q -m "chore: sub"
  edit_record '.checks = [{id: "C1", req: "R1", run: ["grep", "-qx", "paid", "sub/pay.txt"]}]
    | .phases = [{id: "P1", title: "Pay", reqs: ["R1", "R2"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["sub/pay.txt", "sub/inner dir/i.txt"], after: [], status: "done"}]'
  "$VBW" approve > /dev/null
  printf 'paid\nagain\n' > sub/pay.txt
  "$VBW" commit P1.1 "feat(pay): again" > /dev/null
  printf 'scratch\n' > sub/scratch.txt
  "$VBW" prove > /dev/null
  "$VBW" qa record P1 pass standard > /dev/null
  "$VBW" req accept R2 > /dev/null
  printf 'paid\nmore\n' > sub/pay.txt
  printf 'i2\n' > "sub/inner dir/i.txt"
  vbw_run ship
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"  sub/pay.txt (plan P1.1)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"  sub/inner dir/i.txt (plan P1.1)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"scratch.txt"* ]] || { echo "$output"; false; }
  ship_next_line "$output"
  [[ "$output" == *"vbw commit P1.1"* ]] || { echo "$output"; false; }
  git -C sub checkout -q -- pay.txt
  git -C "sub/inner dir" checkout -q -- i.txt
  vbw_run ship
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"scratch.txt"* ]] || { echo "$output"; false; }
  [ -f sub/scratch.txt ]
  git status --porcelain -- sub | grep -q '^ M sub$'
}

@test "R244 docs: docs/workflows.md (Submodules, the refusal table's vbw ship row) and docs/next.md (the ship row) say only the milestone's own files must be committed and the user's own files never block" {
  local wf="$REPO_ROOT/docs/workflows.md" nx="$REPO_ROOT/docs/next.md" table row
  sed -n '/^## Submodules/,/^## /p' "$wf" | grep -i "vbw ship" | grep -qi "milestone's own files" || { echo "the Submodules section does not say vbw ship wants only the milestone's own files"; false; }
  ! grep -qF 'wants every file committed' "$wf" || { echo "docs/workflows.md still says vbw ship wants every file committed"; false; }
  table=$(sed -n '/^### Every refusal and its next step/,/^### Refusals reach the user/p' "$wf")
  row=$(printf '%s\n' "$table" | grep -E '^\| `vbw ship`:')
  [ -n "$row" ] || { echo "the refusal table has no vbw ship row"; false; }
  [[ "$row" == *"vbw commit"* ]] || { echo "the vbw ship row does not name vbw commit as the next step: $row"; false; }
  printf '%s\n' "$row" | grep -qi "own file" || { echo "the vbw ship row does not say the user's own files never block: $row"; false; }
  row=$(grep -E '^\| 12 \|' "$nx")
  [[ "$row" == *"vbw ship"* ]] || { echo "docs/next.md has no ship row"; false; }
  printf '%s\n' "$row" | grep -i "own file" | grep -qi "never block" || { echo "the ship row of docs/next.md does not say a user's own file never blocks: $row"; false; }
  ! grep -qF 'refuses while the proven work is not committed' "$nx" || { echo "docs/next.md still says the ship refuses while the proven work is not committed"; false; }
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

@test "docs/rigor.md's balanced tier table gives the Lead, Scout, Dev and QA their profile models" {
  local doc="$REPO_ROOT/docs/rigor.md" row
  jq -e '.balanced.lead == "opus" and .balanced.scout == "sonnet"' "$PLUGIN_ROOT/lib/profiles.json"
  jq -e '[.balanced.standard.models, .balanced.deep.models] | all(.dev == "sonnet" and .qa == "sonnet")' "$PLUGIN_ROOT/lib/tiers.json"
  row=$(grep -E '^\| `standard` \|' "$doc")
  [[ "$row" == *"| Lead on Opus; Dev and QA on Sonnet |"* ]] || { echo "$row"; false; }
  row=$(grep -E '^\| `deep` \|' "$doc")
  [[ "$row" == *"| Lead on Opus; Scout, Dev and QA on Sonnet |"* ]] || { echo "$row"; false; }
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

@test "R225: doctor names the branch the next VBW commit lands on, the checked-out branch or the detached commit; outside a VBW project it says nothing of it" {
  vbw_run doctor
  local l
  l=$(printf '%s\n' "$output" | grep -E '^· .*branch' || true)
  [ "$(printf '%s\n' "$l" | grep -c . )" -eq 1 ] || { echo "doctor's info lines naming a branch: $l"; echo "$output"; false; }
  [[ "$l" =~ (^|[^a-zA-Z0-9_-])main($|[^a-zA-Z0-9_-]) ]] || { echo "the line does not name main: $l"; false; }
  git checkout -q -b feature/xyz
  vbw_run doctor
  [[ "$output" == *"lands on branch feature/xyz"* ]] || { echo "doctor does not name feature/xyz:"; echo "$output"; false; }
  git checkout -q --detach
  vbw_run doctor
  l=$(printf '%s\n' "$output" | grep -E '^· .*detached HEAD at ' || true)
  [[ "$l" == *"detached HEAD at $(git rev-parse HEAD | cut -c1-12)"* ]] || { echo "doctor does not name the detached commit:"; echo "$output"; false; }
  mkdir -p "$TEST_ROOT/other" && cd "$TEST_ROOT/other" && git init -q
  vbw_run doctor
  [[ "$output" == *"not a VBW project yet"* ]]
  [[ "$output" != *branch* && "$output" != *"detached HEAD"* ]] || { echo "outside a VBW project doctor names a branch:"; echo "$output"; false; }
}
