#!/usr/bin/env bats
# #738 (docs/proof.md, "Kept copies"): the clean copies are kept between
# commands in .vbw/runtime/proof.keep.N/ and brought up to date when the next
# command claims them, instead of being made again. A kept copy, when a command
# starts using it, holds exactly what a fresh copy made then would hold: the
# committed code of HEAD and nothing uncommitted or untracked; the git-ignored
# paths as the working folder has them now, less build folders and the ## Clean
# copy list; nothing a previous unit built or wrote. A slot is owned through its
# pid file; a dead owner's slot is free, a live owner's is left alone; a command
# that is interrupted removes the slots it holds; the sweep removes a slot unused
# for 24 hours or numbered past check_jobs. vbw prove --full makes fresh copies.
# The evidence's own.copy_slots counts the copies claimed, refreshed and made.
# L1: the kernel on a fixture project with ignored folders, whose check can list
# the copy it runs in (PROBE), write into it (WRITE) and be held (HOLD).

load helper
load fixture-helper

keep_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf 'node_modules/\ncache/\n.env\ndist/\n' > .gitignore
  mkdir -p node_modules/pkg node_modules/other cache src tests
  printf 'k\n' > node_modules/other/keep.js
  # 200 entries no test changes: few changed entries are copied one by one.
  mkdir -p node_modules/big
  for i in $(seq 1 200); do printf '%s\n' "$i" > "node_modules/big/f$i.js"; done
  printf 'v1\n' > node_modules/pkg/index.js
  printf 'a\n' > node_modules/pkg/a.js
  printf 'gone\n' > node_modules/pkg/gone.js
  printf 'c\n' > cache/c.txt
  printf 'SECRET=1\n' > .env
  printf 'paid\n' > src/pay.txt
  cat > tests/pay.sh << 'SH'
[ -z "${MARK:-}" ] || touch "$MARK/start.$$"
while [ -n "${HOLD:-}" ] && [ ! -e "$MARK/release" ]; do sleep 0.1; done
[ -z "${PROBE:-}" ] || find . -name .git -prune -o -print | LC_ALL=C sort > "$PROBE"
grep -qx paid src/pay.txt
cat node_modules/pkg/index.js > /dev/null
if [ -n "${WRITE:-}" ]; then
  mkdir -p dist node_modules/.cache
  echo out > dist/out
  echo stray > stray
  echo cache > node_modules/.cache/x
  echo edited >> node_modules/pkg/a.js
  rm -f node_modules/pkg/gone.js
  [ "$WRITE" != most ] || for f in node_modules/big/*; do echo w >> "$f"; done
  echo edited >> src/pay.txt
fi
SH
  printf 'grep -qx paid src/pay.txt\n' > tests/two.sh
  printf 'grep -qx paid src/pay.txt\n' > tests/three.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying works", check: "C1"}]}' | "$VBW" apply > /dev/null
  jq '.plans[0].status = "done"' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build keep keep_project; }
setup() {
  fixture_copy keep
  LIVE=()
  export MARK="$TEST_ROOT/mark" PROBE="$TEST_ROOT/probe"
  mkdir -p "$MARK"
}
teardown() {
  local p
  for p in ${LIVE[@]+"${LIVE[@]}"}; do kill "$p" 2> /dev/null || true; done
  touch "$MARK/release" 2> /dev/null || true
  wait 2> /dev/null || true
  chmod -R u+rwx "$TEST_ROOT" 2> /dev/null || true
  vbw_teardown
}
teardown_file() { fixture_teardown; }

slot() { printf '.vbw/runtime/proof.keep.%s\n' "$1"; }
# mark: make a reference file now and wait, without sleeping, until the clock has moved past its
# change time. After the next proof, an entry copied again is strictly newer than the reference
# (find -newercm, the test the refresh itself uses) and an untouched one is not; a new file cannot
# inherit an older change time on any file system. Never mark the copy's own entries: a link, an
# attribute or a write changes their change time.
mark() {
  local i=0
  : > "$TEST_ROOT/ref"
  : > "$TEST_ROOT/ref.tick"
  while [ -z "$(find "$TEST_ROOT/ref.tick" -newercm "$TEST_ROOT/ref" -print)" ] && [ "$i" -lt 5000 ]; do
    : > "$TEST_ROOT/ref.tick"
    i=$((i + 1))
  done
  rm -f "$TEST_ROOT/ref.tick"
}
# copied_again PATH: succeeds when PATH was written after the reference of mark.
copied_again() { [ -n "$(find "$1" -newercm "$TEST_ROOT/ref" -print -quit)" ]; }
# counts: what the last proof did with its copies.
counts() { jq -c '.evidence.own.copy_slots | {claimed, refreshed, made}' .vbw/record.json; }
# bump TEXT: commit a change to the file C1 reads, so the next proof runs it.
bump() {
  printf 'paid\n%s\n' "$1" > src/pay.txt
  git add src/pay.txt && git commit -q -m "feat(shop): $1"
}
prove_ok() {
  vbw_run prove "$@"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.evidence.passed' .vbw/record.json > /dev/null || { jq .evidence .vbw/record.json; return 1; }
}
# snap DIR: every file with its checksum, every link with its target and every
# folder of DIR, sorted; the worktree's own .git file and .vbw (the record, which each proof commits) left out.
snap() {
  (cd "$1" && find . \( -name .git -o -path ./.vbw \) -prune -o \( -type f -exec cksum {} + \) -o \( -type l -exec sh -c 'for l; do printf "%s -> %s\n" "$l" "$(readlink "$l")"; done' sh {} + \) -o -type d -print) | LC_ALL=C sort
}
dead_pid() {
  local p
  sh -c 'exit 0' &
  p=$!
  wait "$p" || true
  printf '%s\n' "$p"
}
live_pid() {
  sleep 300 &
  PID_LIVE=$!
  LIVE+=("$PID_LIVE")
}
count() { find "$MARK" -name "$1.*" | wc -l | tr -d ' '; }
# code_head: the commit the last proof ran on (the proof commits the record after it).
code_head() { git log -1 --format=%H --invert-grep --grep='^chore(vbw): proof'; }
# add_sub: a submodule sub with an ignored deps/ folder, committed.
add_sub() {
  git init -q "$TEST_ROOT/subsrc"
  printf 'paid\n' > "$TEST_ROOT/subsrc/pay.txt"
  printf 'deps/\n' > "$TEST_ROOT/subsrc/.gitignore"
  git -C "$TEST_ROOT/subsrc" add pay.txt .gitignore
  git -C "$TEST_ROOT/subsrc" commit -q -m "chore: seed"
  git -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/subsrc" sub
  mkdir -p sub/deps && printf 'd1\n' > sub/deps/d.txt
  git add -A && git commit -q -m "chore: sub"
}

@test "#738: a proof leaves its copy in proof.keep.1 with no owner; the next proof claims it and makes none; --full makes a fresh one" {
  prove_ok
  [ -d "$(slot 1)/tree" ] && [ -f "$(slot 1)/tree/src/pay.txt" ]
  [ ! -e "$(slot 1)/pid" ] || { echo "the slot is still owned by $(cat "$(slot 1)/pid")"; false; }
  [ "$(find .vbw/runtime -maxdepth 1 -name 'proof.*' | wc -l | tr -d ' ')" -eq 1 ] || { ls .vbw/runtime; false; }
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  git worktree list --porcelain | grep -qF "/proof.keep.1/tree" || { git worktree list; false; }
  bump two
  prove_ok
  # The claimed copy was not made again: made is 0. A folder's change time is no judge here, as a
  # claim may rewrite entries in it on some file systems.
  [ "$(counts)" = '{"claimed":1,"refreshed":0,"made":0}' ] || { counts; false; }
  [ ! -e "$(slot 2)" ] || { ls .vbw/runtime; false; }
  prove_ok --full
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  [ ! -e "$(slot 2)" ] || { ls .vbw/runtime; false; }
  [ ! -e "$(slot 1)/pid" ]
}

@test "#738: an uncommitted edit, an untracked file and a staged file reach no kept copy; the claimed copy runs on the new commit" {
  prove_ok
  bump two
  printf 'paid\nUNCOMMITTED\n' > src/pay.txt
  printf 'u\n' > src/untracked.txt
  printf 's\n' > src/staged.txt
  git add src/staged.txt
  prove_ok
  [ "$(counts)" = '{"claimed":1,"refreshed":0,"made":0}' ] || { counts; false; }
  [ "$(cat "$(slot 1)/tree/src/pay.txt")" = "$(printf 'paid\ntwo')" ] || { cat "$(slot 1)/tree/src/pay.txt"; false; }
  [ ! -e "$(slot 1)/tree/src/untracked.txt" ] && [ ! -e "$(slot 1)/tree/src/staged.txt" ] || { ls "$(slot 1)/tree/src"; false; }
  [ "$(git -C "$(slot 1)/tree" rev-parse HEAD)" = "$(code_head)" ]
  if grep -qE 'untracked|staged' "$PROBE"; then cat "$PROBE"; false; fi
}

@test "#738: ignored paths added, edited, renamed and deleted are brought up to date, and only they are copied again; a newly listed or no longer ignored path leaves the copy; the copy equals a fresh one" {
  prove_ok
  mark
  printf 'new\n' > node_modules/pkg/new.js
  # An edit that keeps an old modification time is still seen.
  printf 'v2\n' > node_modules/pkg/index.js
  touch -t 202001010000 node_modules/pkg/index.js
  mv node_modules/pkg/a.js node_modules/pkg/b.js
  rm node_modules/pkg/gone.js
  # .env is no longer ignored; cache/ is left out of every clean copy.
  printf 'node_modules/\ncache/\ndist/\n' > .gitignore
  printf '\n## Clean copy\n\n- cache/\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  rm -f .vbw/runtime/glance.json
  git add .gitignore .vbw && git commit -q -m "chore: leave cache out"
  "$VBW" approve > /dev/null
  bump two
  prove_ok
  [ "$(counts)" = '{"claimed":1,"refreshed":1,"made":0}' ] || { counts; false; }
  local t
  t=$(slot 1)/tree
  [ "$(cat "$t/node_modules/pkg/new.js")" = new ] && [ "$(cat "$t/node_modules/pkg/index.js")" = v2 ] || { ls -la "$t/node_modules/pkg"; false; }
  [ -f "$t/node_modules/pkg/b.js" ] && [ ! -e "$t/node_modules/pkg/a.js" ] && [ ! -e "$t/node_modules/pkg/gone.js" ] || { ls -la "$t/node_modules/pkg"; false; }
  [ ! -e "$t/cache" ] || { echo "the listed cache/ is still in the copy"; false; }
  [ ! -e "$t/.env" ] || { echo ".env, no longer ignored, is still in the copy"; false; }
  ! copied_again "$t/node_modules/other/keep.js" || { echo "an unchanged file of node_modules was copied again"; false; }
  local kept
  kept=$(snap "$t")
  prove_ok --full
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  diff <(printf '%s\n' "$kept") <(snap "$(slot 1)/tree")
}

@test "#738 (R253): a worktree added after the copy was kept, nested in a kept ignored folder, leaves the copy when it is brought up to date; the copy equals a fresh one" {
  prove_ok
  git worktree add -q node_modules/wt -b wt > /dev/null 2>&1
  printf 'w\n' > node_modules/wt/note.txt
  bump two
  prove_ok
  [ "$(counts)" = '{"claimed":1,"refreshed":1,"made":0}' ] || { counts; false; }
  local t=$(slot 1)/tree kept
  [ ! -e "$t/node_modules/wt" ] || { echo "the worktree is in the kept copy"; ls -la "$t/node_modules"; false; }
  [ -f "$t/node_modules/other/keep.js" ] && [ -f "$t/node_modules/pkg/index.js" ] || { ls -la "$t/node_modules"; false; }
  kept=$(snap "$t")
  prove_ok --full
  diff <(printf '%s\n' "$kept") <(snap "$(slot 1)/tree")
}

@test "#738: what a unit wrote (a build folder, a stray file, a file in a kept ignored folder, an edited or deleted one there, an edited tracked file) is undone when the next command claims the copy, and nothing else is copied again" {
  WRITE=1 prove_ok
  [ -f "$(slot 1)/tree/dist/out" ] && [ -f "$(slot 1)/tree/node_modules/.cache/x" ] && [ ! -e "$(slot 1)/tree/node_modules/pkg/gone.js" ] || { echo "the unit wrote nothing"; false; }
  mark
  bump two
  prove_ok
  local t
  t=$(slot 1)/tree
  [ ! -e "$t/dist" ] && [ ! -e "$t/stray" ] && [ ! -e "$t/node_modules/.cache" ] || { ls -la "$t" "$t/node_modules"; false; }
  if grep -qE '^\./(dist|stray|node_modules/\.cache)' "$PROBE"; then cat "$PROBE"; false; fi
  [ "$(cat "$t/src/pay.txt")" = "$(printf 'paid\ntwo')" ] || { cat "$t/src/pay.txt"; false; }
  [ "$(cat "$t/node_modules/pkg/index.js")" = v1 ] && [ "$(cat "$t/node_modules/pkg/a.js")" = a ] && [ "$(cat "$t/node_modules/pkg/gone.js")" = gone ] \
    || { ls -la "$t/node_modules/pkg"; false; }
  ! copied_again "$t/node_modules/other/keep.js" || { echo "an unchanged file of node_modules was copied again"; false; }
  [ "$(counts)" = '{"claimed":1,"refreshed":1,"made":0}' ] || { counts; false; }
}

@test "#738: when a unit wrote into most of a kept ignored path, the path is copied again whole, as cloning it costs less than entry by entry" {
  WRITE=most prove_ok
  mark
  bump two
  prove_ok
  copied_again "$(slot 1)/tree/node_modules/other/keep.js" || { echo "node_modules was brought up to date entry by entry"; false; }
  [ "$(cat "$(slot 1)/tree/node_modules/big/f7.js")" = 7 ] && [ "$(cat "$(slot 1)/tree/node_modules/pkg/a.js")" = a ] || { echo "the unit's writes are still there"; false; }
}

@test "#738: a slot whose owner has ended, or whose pid file stayed empty for 5 s, is claimed; one whose owner runs, or whose empty pid file is new, is left alone and another is made" {
  prove_ok
  dead_pid > "$(slot 1)/pid"
  bump two
  prove_ok
  [ "$(counts)" = '{"claimed":1,"refreshed":0,"made":0}' ] || { counts; false; }
  [ ! -e "$(slot 1)/pid" ]
  # An owner that died before it wrote its id, as the alone-check gate judges one.
  : > "$(slot 1)/pid"
  touch -t 202001010000 "$(slot 1)/pid"
  bump empty
  prove_ok
  [ "$(counts)" = '{"claimed":1,"refreshed":0,"made":0}' ] || { counts; false; }
  [ ! -e "$(slot 1)/pid" ]
  : > "$(slot 1)/pid"
  bump fresh
  prove_ok
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  [ -e "$(slot 1)/pid" ] && [ -d "$(slot 2)/tree" ]
  rm -rf "$(slot 2)" "$(slot 1)/pid"
  git worktree prune
  live_pid
  printf '%s\n' "$PID_LIVE" > "$(slot 1)/pid"
  printf 'mine\n' > "$(slot 1)/tree/held.txt"
  bump three
  prove_ok
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  [ -d "$(slot 2)/tree" ] && [ ! -e "$(slot 2)/pid" ]
  [ "$(cat "$(slot 1)/tree/held.txt")" = mine ] && [ "$(cat "$(slot 1)/pid")" = "$PID_LIVE" ]
}

@test "#738: an interrupted proof removes the copy it holds; the next proof makes it again at the same place" {
  prove_ok
  bump two
  rm -f "$MARK"/start.*
  HOLD=1 "$VBW" prove > "$TEST_ROOT/out" 2>&1 < /dev/null &
  local pid=$! i
  for i in $(seq 1 100); do [ "$(count start)" -ge 1 ] && break; sleep 0.1; done
  [ "$(count start)" -ge 1 ]
  [ -f "$(slot 1)/pid" ] && [ "$(cat "$(slot 1)/pid")" = "$pid" ] || { ls -la "$(slot 1)"; false; }
  kill -TERM "$pid"
  wait "$pid" || true
  touch "$MARK/release"
  [ ! -e "$(slot 1)" ] || { echo "the interrupted proof left its copy"; ls -la "$(slot 1)"; false; }
  prove_ok
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  [ -f "$(slot 1)/tree/src/pay.txt" ]
  [ "$(git worktree list --porcelain | grep -c '/proof.keep.1/tree')" -eq 1 ] || { git worktree list; false; }
}

@test "#738: a kept copy whose refresh fails, or that has no manifest, is removed and made fresh" {
  prove_ok
  printf 'gitdir: /nowhere\n' > "$(slot 1)/tree/.git"
  bump two
  prove_ok
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  [ "$(git -C "$(slot 1)/tree" rev-parse HEAD)" = "$(code_head)" ]
  rm "$(slot 1)/manifest"
  bump three
  prove_ok
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  [ -f "$(slot 1)/manifest" ]
}

@test "#738: in a copy of the project folder, a kept copy that still belongs to the original is made fresh and the original's copy is not touched" {
  prove_ok
  local orig=$PWD head
  head=$(git -C "$(slot 1)/tree" rev-parse HEAD)
  # The commit is in both repositories, so git could bring the original's copy to it.
  bump two
  cp -Rp "$orig" "$TEST_ROOT/moved"
  cd "$TEST_ROOT/moved"
  prove_ok
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  [ "$(git -C "$(slot 1)/tree" rev-parse --path-format=absolute --git-common-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] \
    || { echo "the copy still belongs to the original"; false; }
  [ "$(git -C "$orig/$(slot 1)/tree" rev-parse HEAD)" = "$head" ] || { echo "the original's kept copy was moved"; false; }
  [ -z "$(git -C "$orig/$(slot 1)/tree" status --porcelain)" ] || { git -C "$orig/$(slot 1)/tree" status; false; }
}

@test "#738: no command makes more copies than it has units" {
  "$VBW" config set check_jobs 4 > /dev/null
  prove_ok --full
  [ "$(jq '.evidence.own.copy_slots | .claimed + .made' .vbw/record.json)" -eq 1 ] || { counts; false; }
  [ "$(find .vbw/runtime -maxdepth 1 -name 'proof.keep.*' | wc -l | tr -d ' ')" -eq 1 ] || { ls .vbw/runtime; false; }
  jq '.checks += [{id: "C2", req: "R1", run: ["sh", "tests/two.sh"], files: ["tests/two.sh"]}, {id: "C3", req: "R1", run: ["sh", "tests/three.sh"], files: ["tests/three.sh"]}]
    | .protected = ([.checks[].files[]] | unique)' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore: two more checks"
  "$VBW" approve > /dev/null
  "$VBW" config set check_jobs 2 > /dev/null
  prove_ok --full
  [ "$(jq '.evidence.own.copy_slots | .claimed + .made' .vbw/record.json)" -eq 2 ] || { counts; false; }
  [ "$(find .vbw/runtime -maxdepth 1 -name 'proof.keep.*' | wc -l | tr -d ' ')" -eq 2 ] || { ls .vbw/runtime; false; }
  jq '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): fix"
  "$VBW" approve > /dev/null
  "$VBW" config set check_jobs 4 > /dev/null
  vbw_run fix "done" F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(find .vbw/runtime -maxdepth 1 -name 'proof.keep.*' | wc -l | tr -d ' ')" -le 3 ] || { ls .vbw/runtime; false; }
}

@test "#738: the sweep removes a slot unused for 24 hours and one numbered past check_jobs, never one whose owner runs" {
  "$VBW" config set check_jobs 2 > /dev/null
  prove_ok
  # Slot 2 is idle for 24 hours, slot 1 is not: the proof claims slot 1, and slot
  # 2 is gone. (An inode check cannot tell: ext4 hands a new folder the inode of
  # the one just removed.)
  mkdir -p "$(slot 2)" "$(slot 3)" "$(slot 4)"
  git worktree add -q --detach "$(slot 2)/tree" HEAD
  touch -t 202001010000 "$(slot 2)"
  # Past the cap: one free, one whose owner runs.
  git worktree add -q --detach "$(slot 3)/tree" HEAD
  git worktree add -q --detach "$(slot 4)/tree" HEAD
  live_pid
  printf '%s\n' "$PID_LIVE" > "$(slot 4)/pid"
  bump two
  prove_ok
  [ "$(counts)" = '{"claimed":1,"refreshed":0,"made":0}' ] || { counts; false; }
  [ ! -e "$(slot 2)" ] || { echo "the idle slot is still there"; false; }
  ! git worktree list --porcelain | grep -qF '/proof.keep.2/tree' || { git worktree list; false; }
  [ ! -e "$(slot 3)" ] || { echo "the slot past the cap is still there"; false; }
  ! git worktree list --porcelain | grep -qF '/proof.keep.3/tree' || { git worktree list; false; }
  [ -d "$(slot 4)/tree" ] || { echo "a slot whose owner runs was removed"; false; }
}

@test "#738: a submodule's committed code and ignored paths are brought up to date in a kept copy" {
  add_sub
  prove_ok --full
  [ "$(cat "$(slot 1)/tree/sub/deps/d.txt")" = d1 ] || { ls -la "$(slot 1)/tree/sub"; false; }
  printf 'paid\nsub2\n' > sub/pay.txt
  git -C sub commit -q -am "feat: sub2"
  printf 'd2\n' > sub/deps/d.txt
  printf 'junk\n' > "$(slot 1)/tree/sub/junk.txt"
  bump two
  prove_ok
  [ "$(counts)" = '{"claimed":1,"refreshed":1,"made":0}' ] || { counts; false; }
  [ "$(git -C "$(slot 1)/tree/sub" rev-parse HEAD)" = "$(git -C sub rev-parse HEAD)" ]
  [ "$(cat "$(slot 1)/tree/sub/deps/d.txt")" = d2 ] && [ ! -e "$(slot 1)/tree/sub/junk.txt" ] || { ls -la "$(slot 1)/tree/sub"; false; }
}

@test "#738: a branch a unit checked out in a kept copy, of the project or of a submodule, never moves when the copy is brought up to date" {
  add_sub
  prove_ok --full
  git branch feature
  git -C sub branch subfeature
  local f s
  f=$(git rev-parse feature)
  s=$(git -C sub rev-parse subfeature)
  git -C "$(slot 1)/tree" checkout -q feature
  git -C "$(slot 1)/tree/sub" checkout -q subfeature
  printf 'paid\nsub2\n' > sub/pay.txt
  git -C sub commit -q -am "feat: sub2"
  bump two
  prove_ok
  [ "$(counts)" = '{"claimed":1,"refreshed":0,"made":0}' ] || { counts; false; }
  [ "$(git rev-parse feature)" = "$f" ] && [ "$(git -C sub rev-parse subfeature)" = "$s" ] || { git log --oneline --all; false; }
  ! git -C "$(slot 1)/tree" symbolic-ref -q HEAD && ! git -C "$(slot 1)/tree/sub" symbolic-ref -q HEAD || { echo "a copy is on a branch"; false; }
  [ "$(git -C "$(slot 1)/tree" rev-parse HEAD)" = "$(code_head)" ] && [ "$(git -C "$(slot 1)/tree/sub" rev-parse HEAD)" = "$(git -C sub rev-parse HEAD)" ]
}

@test "#738: an exported GIT_DIR naming the project's repository never reaches its index through a kept copy" {
  prove_ok
  bump two
  printf 's\n' > src/staged.txt
  git add src/staged.txt
  GIT_DIR="$PWD/.git" prove_ok
  [ "$(counts)" = '{"claimed":1,"refreshed":0,"made":0}' ] || { counts; false; }
  [ "$(git diff --cached --name-only)" = src/staged.txt ] || { git status; false; }
}

@test "#738: proofcopy_own refuses a copy's folder that is a link (to another worktree of the submodule, which every other check accepts) and a copy whose .git names another copy's git dir" {
  add_sub
  "$VBW" config set check_jobs 2 > /dev/null
  mkdir -p "$(slot 1)" "$(slot 2)"
  git worktree add -q --detach "$(slot 1)/tree" HEAD
  git worktree add -q --detach "$(slot 2)/tree" HEAD
  git -C sub worktree add -q --detach "$PWD/$(slot 1)/tree/sub.real" HEAD
  # The worktree add left an empty tree/sub (the gitlink): replace it, or the link lands inside it.
  rmdir "$(slot 1)/tree/sub"
  ln -s "$PWD/$(slot 1)/tree/sub.real" "$(slot 1)/tree/sub"
  [ -L "$(slot 1)/tree/sub" ] || { ls -la "$(slot 1)/tree"; false; }
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  run vbw_kernel '. "$VBW_LIB/proofcopy.sh"; t=$VBW_RUNTIME/proof.keep.1/tree
    proofcopy_own "$t" "$VBW_ROOT" && echo own
    proofcopy_own "$t/sub.real" "$VBW_ROOT/sub" && echo real
    proofcopy_own "$t/sub" "$VBW_ROOT/sub" && echo link
    cp "$VBW_RUNTIME/proof.keep.2/tree/.git" "$t/.git"
    proofcopy_own "$t" "$VBW_ROOT" && echo other
    true'
  [ "$output" = "$(printf 'own\nreal')" ] || { echo "$output"; false; }
}

@test "#738: an ignored path gone from the working folder leaves the copy, and the copy counts as refreshed" {
  prove_ok
  rm -rf cache
  bump two
  prove_ok
  [ ! -e "$(slot 1)/tree/cache" ] || { ls -la "$(slot 1)/tree"; false; }
  [ "$(counts)" = '{"claimed":1,"refreshed":1,"made":0}' ] || { counts; false; }
}

@test "#738: a sweep that cannot move a slot aside hands it back instead of keeping it" {
  prove_ok
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/proofcopy.sh"; d=$VBW_RUNTIME/proof.keep.1
    mkdir "$VBW_RUNTIME/proof.$$.swept-proof.keep.1"
    proofcopy_take "$d" && vbw_guard_forget "$d" && proofcopy_sweep_rm "$d"'
  [ -d "$(slot 1)/tree" ] && [ ! -e "$(slot 1)/pid" ] || { ls -la "$(slot 1)"; false; }
}

@test "#738: proofcopy_tick returns only once a change made after it is newer than the file it waited on" {
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  run vbw_kernel '. "$VBW_LIB/proofcopy.sh"; mkdir -p "$VBW_RUNTIME"; f=$VBW_RUNTIME/t
    : > "$f"; touch -A 01 "$f" 2> /dev/null || touch -d "+1 second" "$f"
    proofcopy_tick "$f"; : > "$f.after"; [ -z "$(find "$f.after" -newercm "$f" -print)" ] || echo newer'
  [ "$output" = newer ] || { echo "status $status: $output"; false; }
}

@test "#738: vbw show evidence names the copies claimed, refreshed and made; vbw doctor names each kept copy with its size" {
  prove_ok
  bump two
  prove_ok
  vbw_run show evidence
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE 'copies: 1 kept copy claimed \(0 refreshed\), 0 made' || { echo "$output"; false; }
  vbw_run doctor
  printf '%s\n' "$output" | grep -qE 'kept clean cop(y|ies).*proof\.keep\.1 [0-9.]+ [KMG]?B' || { echo "$output"; false; }
  # du counts a clone's blocks in full: on APFS six 9.5 GB copies held 7 GB of disk in all.
  printf '%s\n' "$output" | grep -q 'shares with the working folder' || { echo "$output"; false; }
}

@test "#738: a proof's copy_slots makes the record schema 11; evidence whose own has no copy_slots still reads; a malformed copy_slots makes the record corrupt" {
  prove_ok
  jq -e '.schema == 11' .vbw/record.json || { echo "schema $(jq .schema .vbw/record.json), not 11"; false; }
  jq -L "$PLUGIN_ROOT/lib" 'include "record-schema"; del(.evidence.own.copy_slots) | .schema = schema_of' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  jq -e '.schema < 10' .vbw/record.json
  vbw_run show evidence
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq '.evidence.own.copy_slots = {claimed: -1, refreshed: 0, made: 0, refresh: 0}' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  vbw_run show evidence
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"evidence.own"* ]] || { echo "$output"; false; }
}
