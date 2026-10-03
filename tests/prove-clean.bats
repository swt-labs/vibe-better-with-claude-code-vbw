#!/usr/bin/env bats
# R32 (docs/proof.md): vbw prove runs the approved checks and project commands
# on a clean copy of the committed code, so uncommitted changes and untracked
# files change no proof result; git-ignored files are linked in (D54); vbw check
# keeps running on the working folder.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  # C1 passes on the committed code; stray files or edits in the folder it runs
  # in flip it. It records where it ran, for the tests that ask.
  cat > tests/pay.sh << 'SH'
grep -qx paid src/pay.txt || exit 1
[ ! -e todos.txt ] || exit 1
[ -z "${PROBE:-}" ] || pwd -P > "$PROBE"
SH
  cat > tests/cmd.sh << 'SH'
[ ! -e todos.txt ]
SH
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]'
  printf 'node_modules/\n.env.local\n' > .gitignore
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

# The record as the Lead's apply leaves it: requirements without the rules
# marker are exempt, so the approval does not depend on a rules listing.
edit_record() {
  jq "$1 | del(.requirements[]?.rules)" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# The folder as a user would see it, apart from VBW's own files.
snapshot() {
  git status --porcelain -- . ':!.vbw'
  find . -path ./.git -prune -o -path ./.vbw -prune -o -type f -print | sort | while IFS= read -r f; do
    printf '%s %s\n' "$f" "$(cksum < "$f")"
  done
}

@test "R32: an untracked file that would flip a check changes no proof result" {
  vbw_run prove
  [ "$status" -eq 0 ]
  local before
  before=$(jq -c '.evidence | {passed, checks: (.checks | map_values(.status))}' .vbw/record.json)
  printf 'buy milk\n' > todos.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  [[ "$output" == *"C1 pass"* ]]
  [ "$(jq -c '.evidence | {passed, checks: (.checks | map_values(.status))}' .vbw/record.json)" = "$before" ]
}

@test "R32: an uncommitted edit to a tracked file is not proved; the committed version is" {
  printf 'nope\n' > src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  jq -e '.evidence.passed == true' .vbw/record.json
  git checkout -q src/pay.txt
  printf 'nope\n' > src/pay.txt
  git add src/pay.txt && git commit -q -m "feat(pay): break it"
  printf 'paid\n' > src/pay.txt
  vbw_run prove
  [ "$status" -eq 1 ]
  jq -e '.evidence.passed == false and .evidence.checks.C1.status == "fail"' .vbw/record.json
}

@test "R32: git-ignored files are linked into the copy, so a project that needs them proves" {
  mkdir -p node_modules/pkg
  printf 'dep\n' > node_modules/pkg/index.txt
  printf 'secret\n' > .env.local
  cat > tests/pay.sh << 'SH'
grep -qx paid src/pay.txt || exit 1
grep -qx dep node_modules/pkg/index.txt || exit 1
grep -qx secret .env.local || exit 1
[ ! -e todos.txt ] || exit 1
SH
  git add tests/pay.sh && git commit -q -m "test(pay): needs the project environment"
  "$VBW" approve > /dev/null
  printf 'buy milk\n' > todos.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  jq -e '.evidence.checks.C1.status == "pass"' .vbw/record.json
  # Removing the copy never reaches through its links into the working folder.
  [ "$(cat node_modules/pkg/index.txt)" = dep ]
  [ "$(cat .env.local)" = secret ]
}

@test "R32: project commands run on the clean copy too" {
  edit_record '.commands = {test: ["sh", "tests/cmd.sh"]}'
  git add -A && git commit -q -m "chore(vbw): command"
  "$VBW" approve > /dev/null
  printf 'buy milk\n' > todos.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  jq -e '.evidence.commands.test.status == "pass"' .vbw/record.json
}

@test "R32: vbw check still sees uncommitted and untracked files in the working folder" {
  vbw_run check C1
  [ "$status" -eq 0 ]
  printf 'buy milk\n' > todos.txt
  vbw_run check C1
  [ "$status" -eq 1 ]
  rm todos.txt
  printf 'nope\n' > src/pay.txt
  vbw_run check C1
  [ "$status" -eq 1 ]
  printf 'paid\n' > src/pay.txt
  vbw_run check C1
  [ "$status" -eq 0 ]
}

@test "R32: the copy lives inside the project, is gone after the proof, and the folder is unchanged" {
  export PROBE="$TEST_ROOT/where"
  printf 'buy milk\n' > todos.txt
  printf 'edited\n' >> README.md
  local before after real
  before=$(snapshot)
  vbw_run prove
  [ "$status" -eq 0 ]
  after=$(snapshot)
  [ "$before" = "$after" ]
  real=$(cd "$PROJECT" && pwd -P)
  [ -f "$PROBE" ]
  [[ "$(cat "$PROBE")" == "$real"/* ]]
  [ "$(cat "$PROBE")" != "$real" ]
  [ ! -e "$(cat "$PROBE")" ]
  [ -z "$(find .vbw/runtime -maxdepth 1 -name 'proof*' 2> /dev/null)" ]
}

@test "R32: an interrupted proof removes its copy and leaves the folder unchanged" {
  export PROBE="$TEST_ROOT/where"
  cat > tests/pay.sh << 'SH'
grep -qx paid src/pay.txt || exit 1
pwd -P > "$PROBE"
sleep 4
SH
  git add tests/pay.sh && git commit -q -m "test(pay): slow"
  "$VBW" approve > /dev/null
  printf 'buy milk\n' > todos.txt
  local before pid i
  before=$(snapshot)
  "$VBW" prove < /dev/null > "$TEST_ROOT/prove.out" 2>&1 &
  pid=$!
  for i in $(seq 1 100); do
    [ -s "$PROBE" ] && break
    sleep 0.1
  done
  [ -s "$PROBE" ]
  [ -d "$(cat "$PROBE")" ]
  kill -TERM "$pid"
  wait "$pid" || true
  [ ! -e "$(cat "$PROBE")" ]
  [ -z "$(find .vbw/runtime -maxdepth 1 -name 'proof*' 2> /dev/null)" ]
  [ "$before" = "$(snapshot)" ]
}

@test "R32: check files that are not committed as approved are refused, never run from the working folder" {
  printf 'echo changed\nexit 0\n' > tests/pay.sh
  printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  "$VBW" approve > /dev/null 2>&1 || true
  vbw_run prove
  [ "$status" -ne 0 ]
  [[ "$output" == *"tests/pay.sh"* ]]
}
