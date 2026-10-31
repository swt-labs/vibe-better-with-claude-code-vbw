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
  vbw_submodule sub
  jq '.plans += [{id:"P1.3", phase:"P1", title:"Sub", reqs:["R1"], files:["sub/a.js", "sub/new dir/b.js", "sub/auth/login.js", "src/root.js"], after:[], status:"building"}]' \
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
  [[ "$output" == *"Next: put it on a branch (git -C sub switch BRANCH), then commit again"* ]] || { echo "$output"; false; }
  [ "$(git rev-parse HEAD)" = "$root_head" ]
  [ "$(git -C sub rev-parse HEAD)" = "$sub_head" ]
}

@test "a risk-path file inside a submodule raises the plan's phase by its project path" {
  with_sub
  mkdir -p sub/auth
  printf 'login\n' > sub/auth/login.js
  vbw_run commit P1.3 "feat(sub): login"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.phases[0].tier == "deep" and (.phases[0].escalations[-1].reason | contains("(sub/auth/login.js)"))' .vbw/record.json \
    || { jq '.phases[0]' .vbw/record.json; false; }
}

@test "a commit that fails in one repository after another committed names what was committed, escalates it, and a second run commits only the rest" {
  with_sub
  mkdir -p sub/auth
  printf 'login\n' > sub/auth/login.js
  printf 'r\n' > src/root.js
  # The project's own pre-commit hook refuses; the submodule (first in the plan) has none.
  printf '#!/bin/sh\necho "hook says no" >&2\nexit 1\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  local root_head sub_head
  root_head=$(git rev-parse HEAD)
  vbw_run commit P1.3 "feat(sub): login"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  sub_head=$(git -C sub rev-parse --short HEAD)
  [ "$(git rev-parse HEAD)" = "$root_head" ]
  [ "$(git -C sub log -1 --format='%(trailers:key=VBW-Plan,valueonly)' | tr -d '[:space:]')" = "P1.3" ]
  [[ "$output" == *"git commit failed in the project"* ]] || { echo "$output"; false; }
  [[ "$output" == *"already committed: $sub_head in sub (1 file)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"Next: "*"vbw commit P1.3"*"only the files still changed"* ]] || { echo "$output"; false; }
  jq -e '.phases[0].tier == "deep" and (.phases[0].escalations[-1].reason | contains("(sub/auth/login.js)"))' .vbw/record.json \
    || { jq '.phases[0]' .vbw/record.json; false; }
  rm .git/hooks/pre-commit
  vbw_run commit P1.3 "feat(sub): login"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "committed $(git rev-parse --short HEAD) for P1.3 (1 file)" ] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = "src/root.js" ]
  [ "$(git -C sub rev-parse --short HEAD)" = "$sub_head" ]
}

@test "a plan's folder entry that holds a submodule covers the submodule's files: they are committed there and count as uncommitted until then" {
  mkdir -p apps
  vbw_submodule "apps/mobile app"
  jq '.plans += [{id:"P1.4", phase:"P1", title:"Apps", reqs:["R1"], files:["apps/"], after:[], status:"building"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  git add .gitmodules "apps/mobile app" .vbw/record.json
  git commit -q -m "chore: add apps"
  local root_head
  root_head=$(git rev-parse HEAD)
  printf 'a2\n' > "apps/mobile app/a.js"
  vbw_run plan done P1.4
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted changes in: apps/mobile app/a.js"* ]] || { echo "$output"; false; }
  printf 'w\n' > apps/web.js
  vbw_run commit P1.4 "feat(apps): both"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"in apps/mobile app for P1.4 (1 file)"* ]] || { echo "$output"; false; }
  [ "$(git -C "apps/mobile app" show --name-only --format= HEAD)" = "a.js" ]
  [ "$(git show --name-only --format= HEAD)" = "apps/web.js" ]
  # The pointer is never moved.
  [ "$(git rev-parse HEAD^)" = "$root_head" ]
  [ "$(git ls-tree HEAD "apps/mobile app" | cut -d' ' -f3 | cut -f1)" = "$(git ls-tree "$root_head" "apps/mobile app" | cut -d' ' -f3 | cut -f1)" ]
}

@test "a plan of every file (*) covers each submodule's files: they count as uncommitted and are committed there" {
  vbw_submodule sub
  jq '.plans += [{id:"P1.5", phase:"P1", title:"All", reqs:["R1"], files:["*"], after:[], status:"building"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  git add .gitmodules sub .vbw/record.json
  git commit -q -m "chore: add sub"
  local root_head
  root_head=$(git rev-parse HEAD)
  printf 'a2\n' > sub/a.js
  vbw_run plan done P1.5
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted changes in: sub/a.js"* ]] || { echo "$output"; false; }
  vbw_run commit P1.5 "feat(sub): all"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "committed "*" in sub for P1.5 (1 file)" ]] || { echo "$output"; false; }
  [ "$(git -C sub show --name-only --format= HEAD)" = "a.js" ]
  [ "$(git rev-parse HEAD)" = "$root_head" ]
}

@test "a plan path through a symlinked folder holding a repository outside the project is never committed or restored there" {
  local out="$TEST_ROOT/outside repo" out_head
  git init -q "$out"
  printf 'a\n' > "$out/a.js"
  git -C "$out" add a.js
  git -C "$out" commit -q -m "chore: seed"
  out_head=$(git -C "$out" rev-parse HEAD)
  ln -s "$out" link
  jq '.plans += [{id:"P1.6", phase:"P1", title:"Link", reqs:["R1"], files:["link/a.js"], after:[], status:"building"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  git add link .vbw/record.json
  git commit -q -m "chore: link"
  printf 'a2\n' > "$out/a.js"
  vbw_run commit P1.6 "feat(link): a"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [ "$(git -C "$out" rev-parse HEAD)" = "$out_head" ]
  [ "$(cat "$out/a.js")" = a2 ]
  # The one resolver every caller (commit, plan done, mutate's restore) uses: the
  # file is the project's, whose git refuses a path beyond a symbolic link.
  run vbw_kernel 'vbw_repos link/a.js; printf "[%s]" "${VBW_REPO_OF[0]}"'
  [ "$output" = "[]" ] || { echo "$output"; false; }
}

@test "each plan file is named relative to its repository with no subshell per file" {
  with_sub
  run vbw_kernel 'vbw_repos sub/a.js sub/ src/x.js; vbw_in_repo sub | tr "\0" ,; printf "|"; vbw_in_repo "" | tr "\0" ,'
  [ "$output" = "a.js,.,|src/x.js," ] || { echo "$output"; false; }
  # vbw_commit_paths, vbw_dirty_files and the QA tree run it per file on every vbw next.
  run vbw_kernel 'declare -f vbw_in_repo vbw_rel'
  local subs=${output//'$(('/}
  [[ "$subs" != *'$('* && "$subs" != *'`'* ]] || { echo "$output"; false; }
}

@test "a file reverted between the two reads of the changes commits nothing, the user's staged file included" {
  printf 'mine\n' > notes.txt
  git add notes.txt
  printf 'pay\n' > "src/pay form.js"
  local head
  head=$(git rev-parse HEAD)
  # The first read (which repositories have changes) sees the file; the second, none.
  run vbw_kernel 'eval "first_$(declare -f vbw_changed)"
    vbw_changed() { [ -e "$TEST_ROOT/read" ] && return 0; : > "$TEST_ROOT/read"; first_vbw_changed "$@"; }
    set -u; rc=0; vbw_commit_paths "feat(pay): x" "" "src/pay form.js" || rc=$?; echo "rc=$rc"'
  [ "$output" = "rc=1" ] || { echo "$output"; false; }
  [ "$(git rev-parse HEAD)" = "$head" ]
  [ "$(git diff --cached --name-only)" = "notes.txt" ]
}

@test "a nested clone that is not a submodule, under a plan's folder entry, is never committed as a pointer" {
  mkdir -p apps
  git init -q apps/lib
  printf 'l\n' > apps/lib/l.js
  git -C apps/lib add l.js
  git -C apps/lib commit -q -m "chore: seed"
  jq '.plans += [{id:"P1.4", phase:"P1", title:"Apps", reqs:["R1"], files:["apps/"], after:[], status:"building"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  git add .vbw/record.json
  git commit -q -m "chore: apps"
  printf 'w\n' > apps/web.js
  vbw_run commit P1.4 "feat(apps): web"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = "apps/web.js" ] || { git show --stat HEAD; false; }
  [ -z "$(git ls-tree HEAD apps/lib)" ]
  [ -z "$(git diff --cached --name-only)" ]
}

@test "a submodule folder swapped for a symlink to a repository outside the project is no submodule of it" {
  with_sub
  run vbw_kernel 'vbw_subs | tr "\0" "\n"'
  [ "$output" = sub ] || { echo "$output"; false; }
  mv sub "$TEST_ROOT/outside sub"
  ln -s "$TEST_ROOT/outside sub" sub
  # Proof copies, ship and reads list submodules through vbw_subs: none may reach
  # a repository outside the project.
  run vbw_kernel 'vbw_subs | tr "\0" "\n"'
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "vbw commit run inside a submodule commits for the project above it" {
  with_sub
  printf 'a2\n' > sub/a.js
  printf 'r\n' > src/root.js
  cd sub
  # Paths are the project's, as from its folder.
  vbw_run commit P1.3 "feat(sub): from inside" sub/a.js
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run commit P1.3 "feat(sub): the rest" src/root.js
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cd "$PROJECT"
  [ "$(git -C sub log -1 --format='%(trailers:key=VBW-Plan,valueonly)' | tr -d '[:space:]')" = "P1.3" ]
  [ "$(git show --name-only --format= HEAD)" = "src/root.js" ]
}

@test "a named file outside the plan is refused with its name" {
  printf 'x\n' > src/other.js
  printf 'pay\n' > "src/pay form.js"
  vbw_run commit P1.1 "feat(pay): x" "src/pay form.js" src/other.js
  [ "$status" -ne 0 ]
  [[ "$output" == *"src/other.js"* ]]
  git status --porcelain -- "src/pay form.js" | grep -q '^??'
}
