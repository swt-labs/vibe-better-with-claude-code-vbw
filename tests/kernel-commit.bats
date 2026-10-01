#!/usr/bin/env bats
# vbw commit: commit one plan's declared files, with provenance trailers,
# never touching anything else in the working tree or the index.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  git add .vbw && git commit -q -m "chore(vbw): init"
  # A phase with one plan that owns two files (one with a space, one non-ASCII).
  jq '.requirements = [{id:"R1", text:"Pay", proof:"auto", status:"open", milestone: "M1"}]
      | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone: "M1"}]
      | .plans = [{id:"P1.1", phase:"P1", title:"Card", reqs:["R1"],
                   files:["src/pay form.js", "src/données.js"], after:[], status:"building"},
                  {id:"P1.2", phase:"P1", title:"Receipt", reqs:["R1"],
                   files:["src/receipt.js"], after:[], status:"building"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  git add .vbw/record.json && git commit -q -m "chore(vbw): plan"
  mkdir -p src
}

teardown() { vbw_teardown; }

@test "commits only the plan's declared files, with trailers" {
  printf 'pay\n' > "src/pay form.js"
  printf 'data\n' > "src/données.js"
  printf 'other\n' > src/other.js
  vbw_run commit P1.1 "feat(pay): card form"
  [ "$status" -eq 0 ]
  run git show --name-only --format= HEAD
  [[ "$output" == *"pay form.js"* ]]
  [ "$(git show --name-only --format= -z HEAD | tr '\0' '\n' | grep -c .)" -eq 2 ]
  [ "$(git log -1 --format='%(trailers:key=VBW-Plan,valueonly)' | tr -d '[:space:]')" = "P1.1" ]
  [ "$(git log -1 --format='%(trailers:key=VBW-Req,valueonly)' | tr -d '[:space:]')" = "R1" ]
  [ "$(git log -1 --format=%s)" = "feat(pay): card form" ]
  [ -f src/other.js ]
  git status --porcelain -- src/other.js | grep -q '^??'
}

@test "the user's staged work stays staged and out of the commit" {
  printf 'mine\n' > notes.txt
  git add notes.txt
  printf 'pay\n' > "src/pay form.js"
  vbw_run commit P1.1 "feat(pay): card form"
  [ "$status" -eq 0 ]
  ! git show --name-only --format= HEAD | grep -q notes.txt
  git diff --cached --name-only | grep -qx notes.txt
}

@test "a staged change to a declared file is committed exactly as in the working tree" {
  printf 'v1\n' > "src/pay form.js"
  git add "src/pay form.js"
  printf 'v2\n' > "src/pay form.js"
  vbw_run commit P1.1 "feat(pay): card form"
  [ "$status" -eq 0 ]
  [ "$(git show 'HEAD:src/pay form.js')" = "v2" ]
  [ -z "$(git status --porcelain -- 'src/pay form.js')" ]
}

@test "deleting a declared file is committed as a deletion" {
  printf 'pay\n' > "src/pay form.js"
  "$VBW" commit P1.1 "feat(pay): card form" > /dev/null
  rm "src/pay form.js"
  vbw_run commit P1.1 "refactor(pay): drop the form"
  [ "$status" -eq 0 ]
  ! git ls-files --error-unmatch "src/pay form.js" 2>/dev/null
}

@test "a plan's commits are found by their trailer, not stored in the record" {
  printf 'pay\n' > "src/pay form.js"
  vbw_run commit P1.1 "feat(pay): card form"
  [ "$status" -eq 0 ]
  [ "$(git log --format=%H --grep='^VBW-Plan: P1\.1$')" = "$(git rev-parse HEAD)" ]
  [ -z "$(git status --porcelain -- .vbw/record.json)" ]
}

@test "two plans committing at the same time both land, each with only its own files" {
  printf 'pay\n' > "src/pay form.js"
  printf 'receipt\n' > src/receipt.js
  "$VBW" commit P1.1 "feat(pay): card form" < /dev/null > "$TEST_ROOT/a.out" 2>&1 &
  "$VBW" commit P1.2 "feat(pay): receipt" < /dev/null > "$TEST_ROOT/b.out" 2>&1 &
  wait
  cat "$TEST_ROOT/a.out" "$TEST_ROOT/b.out"
  local a b
  a=$(git log --format=%H -1 --grep='^VBW-Plan: P1\.1$')
  b=$(git log --format=%H -1 --grep='^VBW-Plan: P1\.2$')
  [ "$(git show --name-only --format= -z "$a" | tr '\0' '\n')" = "src/pay form.js" ]
  [ "$(git show --name-only --format= -z "$b" | tr '\0' '\n')" = "src/receipt.js" ]
}

@test "every Conventional Commits type is accepted" {
  local t n=0
  for t in feat fix docs style refactor perf test build ci chore revert; do
    n=$((n + 1))
    printf '%s\n' "$n" > "src/pay form.js"
    vbw_run commit P1.1 "$t(pay): change $n"
    [ "$status" -eq 0 ] || { echo "rejected type $t: $output"; false; }
  done
}

@test "a malformed message is refused before anything is committed" {
  printf 'pay\n' > "src/pay form.js"
  local head
  head=$(git rev-parse HEAD)
  vbw_run commit P1.1 "added the form"
  [ "$status" -eq 2 ]
  [[ "$output" == *"type(scope): description"* ]]
  [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "an unknown plan or no declared change is an error" {
  vbw_run commit P9.9 "feat(x): y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown plan P9.9"* ]]
  vbw_run commit P1.1 "feat(pay): nothing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to commit for P1.1"* ]]
}

@test "the commit works from a subdirectory" {
  printf 'pay\n' > "src/pay form.js"
  cd src
  vbw_run commit P1.1 "feat(pay): card form"
  [ "$status" -eq 0 ]
  cd "$PROJECT"
  [ "$(git show 'HEAD:src/pay form.js')" = "pay" ]
}
