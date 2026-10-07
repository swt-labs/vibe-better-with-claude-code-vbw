#!/usr/bin/env bats
# R99 (L1): a fix for a failing project command commits the files it changed
# to make that command pass, even when no plan lists them: vbw commit --fix
# FIX MESSAGE FILE... The commit names the fix (VBW-Fix trailer). Files the fix
# did not change, and files the user staged, are not committed.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src
  printf 'one\n' > src/util.txt
  printf 'two\n' > src/other.txt
  printf 'three\n' > src/staged.txt
  git add src && git commit -q -m "chore(test): sources"
  jq '.fixes = [{id:"F1", command:"test", attempts:0, status:"open", note:"test fail"},
                {id:"F2", req:"R1", attempts:0, status:"open", note:"check fail"}]' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add .vbw && git commit -q -m "chore(vbw): fixes"
}
teardown() { vbw_teardown; }

@test "R99: a fix for a failing project command commits the files it changed, though no plan lists them" {
  printf 'fixed\n' >> src/util.txt
  run "$VBW" commit --fix F1 "fix(test): make the test command pass" src/util.txt < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = "src/util.txt" ]
  [ -z "$(git status --porcelain -- src/util.txt)" ]
}

@test "R99: the commit names the fix" {
  printf 'fixed\n' >> src/util.txt
  "$VBW" commit --fix F1 "fix(test): make the test command pass" src/util.txt > /dev/null < /dev/null
  git log -1 --format=%B | grep -q 'F1'
  git log -1 --format=%s | grep -q '^fix(test): make the test command pass'
}

@test "R99: a changed file the fix did not name is not committed, and a file the user staged stays staged" {
  printf 'fixed\n' >> src/util.txt
  printf 'unrelated\n' >> src/other.txt
  printf 'mine\n' >> src/staged.txt
  git add src/staged.txt
  "$VBW" commit --fix F1 "fix(test): make the test command pass" src/util.txt > /dev/null < /dev/null
  [ "$(git show --name-only --format= HEAD)" = "src/util.txt" ]
  [ "$(git diff --cached --name-only)" = "src/staged.txt" ]
  [ -n "$(git status --porcelain -- src/other.txt)" ]
}

@test "R99: a new file the fix created is committed" {
  printf 'new\n' > src/added.txt
  run "$VBW" commit --fix F1 "fix(test): add the missing file" src/added.txt < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = "src/added.txt" ]
}

@test "R99: a named file that did not change commits nothing and is refused" {
  local head
  head=$(git rev-parse HEAD)
  run "$VBW" commit --fix F1 "fix(test): nothing changed" src/other.txt < /dev/null
  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "R99: naming no file is refused" {
  run "$VBW" commit --fix F1 "fix(test): no files" < /dev/null
  [ "$status" -ne 0 ]
}

@test "R99: the plan of record is never committed this way" {
  local head
  head=$(git rev-parse HEAD)
  run "$VBW" commit --fix F1 "fix(test): record" .vbw/record.json < /dev/null
  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "R99: a fix for a requirement is not committed this way: it goes through its plan" {
  printf 'fixed\n' >> src/util.txt
  run "$VBW" commit --fix F2 "fix(test): by requirement" src/util.txt < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw commit"* ]]
}

@test "R99: an unknown fix is refused, and an invalid message is refused" {
  printf 'fixed\n' >> src/util.txt
  run "$VBW" commit --fix F99 "fix(test): x" src/util.txt < /dev/null
  [ "$status" -ne 0 ]
  run "$VBW" commit --fix F1 "make it pass" src/util.txt < /dev/null
  [ "$status" -ne 0 ]
}

@test "R99: after the commit the fix closes" {
  printf 'fixed\n' >> src/util.txt
  "$VBW" commit --fix F1 "fix(test): make the test command pass" src/util.txt > /dev/null < /dev/null
  run "$VBW" fix done F1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"F1 fixed"* ]]
}
