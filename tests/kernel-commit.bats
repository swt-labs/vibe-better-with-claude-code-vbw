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
  ! git show --name-only --format= HEAD | grep -q notes.txt || false
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

@test "named files commit alone; the other changed files stay uncommitted" {
  printf 'pay\n' > "src/pay form.js"
  printf 'data\n' > "src/données.js"
  vbw_run commit P1.1 "feat(pay): card form" "src/pay form.js"
  [ "$status" -eq 0 ]
  [ "$(git show --name-only --format= -z HEAD | tr '\0' '\n' | grep -c .)" -eq 1 ]
  git status --porcelain -- src/données.js | grep -q '^??'
}

# with_sub: a submodule at sub/ (its own repository, on branch main, holding
# a.js), committed in the project, and a plan P1.3 whose files lie in it, one
# in a folder that does not exist yet, and one in the project's own repository.
with_sub() {
  git init -q "$TEST_ROOT/subsrc"
  printf 'a\n' > "$TEST_ROOT/subsrc/a.js"
  git -C "$TEST_ROOT/subsrc" add a.js
  git -C "$TEST_ROOT/subsrc" commit -q -m "chore: seed"
  git -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/subsrc" sub
  jq '.plans += [{id:"P1.3", phase:"P1", title:"Sub", reqs:["R1"], files:["sub/a.js", "sub/new dir/b.js", "src/root.js"], after:[], status:"building"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  git add .gitmodules sub .vbw/record.json
  git commit -q -m "chore: add sub"
}

@test "a plan file inside a submodule is committed in the submodule, with trailers; the project and both indexes stay as they were" {
  with_sub
  local root_head sub_before
  root_head=$(git rev-parse HEAD)
  sub_before=$(git -C sub rev-parse HEAD)
  printf 'mine\n' > notes.txt
  git add notes.txt
  printf 'theirs\n' > sub/other.js
  git -C sub add other.js
  printf 'a2\n' > sub/a.js
  mkdir -p "sub/new dir"
  printf 'b\n' > "sub/new dir/b.js"
  vbw_run commit P1.3 "feat(sub): a and b"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "committed "*" in sub for P1.3 (2 files)" ]] || { echo "$output"; false; }
  [ "$(git rev-parse HEAD)" = "$root_head" ]
  [ "$(git -C sub rev-parse HEAD^)" = "$sub_before" ]
  [ "$(git -C sub show --name-only --format= -z HEAD | tr '\0' '\n' | LC_ALL=C sort | paste -sd , -)" = "a.js,new dir/b.js" ]
  [ "$(git -C sub log -1 --format='%(trailers:key=VBW-Plan,valueonly)' | tr -d '[:space:]')" = "P1.3" ]
  [ "$(git -C sub log -1 --format='%(trailers:key=VBW-Req,valueonly)' | tr -d '[:space:]')" = "R1" ]
  [ "$(git -C sub log -1 --format=%s)" = "feat(sub): a and b" ]
  # No pointer bump: the project's index holds the user's file and nothing else.
  [ "$(git diff --cached --name-only)" = "notes.txt" ]
  [ "$(git -C sub diff --cached --name-only)" = "other.js" ]
}

@test "a plan spanning the project and a submodule makes one commit in each" {
  with_sub
  printf 'r\n' > src/root.js
  printf 'a2\n' > sub/a.js
  vbw_run commit P1.3 "feat(sub): both"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"in sub for P1.3 (1 file)"* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^committed ')" -eq 2 ]
  [ "$(git show --name-only --format= -z HEAD | tr '\0' '\n')" = "src/root.js" ]
  [ "$(git -C sub show --name-only --format= -z HEAD | tr '\0' '\n')" = "a.js" ]
  [ "$(git log -1 --format='%(trailers:key=VBW-Plan,valueonly)' | tr -d '[:space:]')" = "P1.3" ]
  [ "$(git -C sub log -1 --format='%(trailers:key=VBW-Plan,valueonly)' | tr -d '[:space:]')" = "P1.3" ]
}

@test "a submodule on no branch is refused before anything is committed" {
  with_sub
  git -C sub checkout -q --detach
  local root_head sub_head
  root_head=$(git rev-parse HEAD)
  sub_head=$(git -C sub rev-parse HEAD)
  printf 'r\n' > src/root.js
  printf 'a2\n' > sub/a.js
  vbw_run commit P1.3 "feat(sub): both"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sub is on no branch"* ]] || { echo "$output"; false; }
  [ "$(git rev-parse HEAD)" = "$root_head" ]
  [ "$(git -C sub rev-parse HEAD)" = "$sub_head" ]
}

@test "vbw commit run inside a submodule commits for the project above it" {
  with_sub
  printf 'a2\n' > sub/a.js
  cd sub
  vbw_run commit P1.3 "feat(sub): from inside"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cd "$PROJECT"
  [ "$(git -C sub log -1 --format='%(trailers:key=VBW-Plan,valueonly)' | tr -d '[:space:]')" = "P1.3" ]
}

@test "a named file outside the plan is refused with its name" {
  printf 'x\n' > src/other.js
  printf 'pay\n' > "src/pay form.js"
  vbw_run commit P1.1 "feat(pay): x" "src/pay form.js" src/other.js
  [ "$status" -ne 0 ]
  [[ "$output" == *"src/other.js"* ]]
  git status --porcelain -- "src/pay form.js" | grep -q '^??'
}
