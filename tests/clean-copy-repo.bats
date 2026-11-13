#!/usr/bin/env bats
# R309 (T296, D727, docs/proof.md): every clean copy of the committed code (a proof
# copy, vbw mutate --run) is its own small repository: its files in the slot's tree/,
# its git folder inside the same slot under .vbw/runtime (never a folder named .git
# holding a repository), the project's objects borrowed (objects/info/alternates) and
# the project's settings read (include.path). Nothing is written under the project's
# .git but .git/vbw: no worktree entry, ref, config line or hook, for the project and
# for each checked-out submodule. Claude Code 2.1.323's sandbox refuses writes to
# .git/worktrees, .git/config, .git/hooks and to any file named .gitmodules; the
# stand-in here makes the first three unwritable and has git refuse .gitmodules in a
# copy. L1 only: no case runs under the real sandbox.

load helper
load fixture-helper

# repo_project: an approved project with an ignored node_modules/ and one check (C1 of
# R1, rule R1.1) that reads src/pay.txt and, when there is one, the submodule's
# pay.txt; HOLD keeps it running until $MARK/release exists.
repo_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf 'node_modules/\n' > .gitignore
  mkdir -p node_modules/pkg src tests
  printf 'v1\n' > node_modules/pkg/index.js
  printf 'paid\n' > src/pay.txt
  cat > tests/pay.sh << 'SH'
[ -z "${MARK:-}" ] || touch "$MARK/start.$$"
while [ -n "${HOLD:-}" ] && [ ! -e "$MARK/release" ]; do sleep 0.1; done
grep -qx paid src/pay.txt || exit 1
[ ! -d sub ] || grep -qx paid sub/pay.txt
SH
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

setup_file() { fixture_build repo repo_project; }
setup() {
  fixture_copy repo
  export MARK="$TEST_ROOT/mark"
  mkdir -p "$MARK"
}
teardown() {
  touch "$MARK/release" 2> /dev/null || true
  wait 2> /dev/null || true
  chmod -R u+rwx "$TEST_ROOT" 2> /dev/null || true
  vbw_teardown
}
teardown_file() { fixture_teardown; }

slot() { printf '.vbw/runtime/proof.keep.%s\n' "$1"; }
phys() { (cd -P "$1" 2> /dev/null && pwd -P); }

# add_sub: a submodule sub (pay.txt, an ignored deps/ folder), committed. Added per
# test: its folder in .git/modules names the source's path, which a fixture may not hold.
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

prove_ok() {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.evidence.passed' .vbw/record.json > /dev/null || { jq .evidence .vbw/record.json; return 1; }
}
counts() { jq -c '.evidence.own.copy_slots | {claimed, refreshed, made}' .vbw/record.json; }
# code_head: the commit the last proof ran on (the proof commits the record after it).
code_head() { git log -1 --format=%H --invert-grep --grep='^chore(vbw): proof'; }
bump() {
  printf 'paid\n%s\n' "$1" > src/pay.txt
  git add src/pay.txt && git commit -q -m "feat(shop): $1"
}

# own_kind COPY: COPY's .git is a file naming a git folder inside COPY's slot (the
# folder above tree/, or for a submodule's copy the slot of the tree it lies in),
# never COPY/.git; no folder named .git holds a repository anywhere in the slot.
own_kind() {
  local c=$1 s gd
  s=$(phys "${c%%/tree*}") || { echo "no slot for $c"; return 1; }
  [ -f "$c/.git" ] || { echo "$c/.git is not a file"; ls -la "$c"; return 1; }
  gd=$(git -C "$c" rev-parse --absolute-git-dir 2> /dev/null) || { echo "git cannot read $c"; return 1; }
  gd=$(phys "$gd")
  case "$gd" in "$s"/tree | "$s"/tree/*) echo "$c's git folder $gd lies in the copy's tree"; return 1 ;; "$s"/*) ;;
    *) echo "$c's git folder $gd is not in its slot $s"; return 1 ;; esac
  [ -z "$(find "$s" -name .git -type d -print)" ] || { echo "a folder named .git in the slot:"; find "$s" -name .git -type d; return 1; }
}

# alt_of GITDIR: the objects folder GITDIR borrows (the first line of its
# objects/info/alternates, a relative one read from its objects folder), physical.
alt_of() {
  local l
  l=; read -r l < "$1/objects/info/alternates" || :
  [ -n "$l" ] || return 1
  case "$l" in /*) ;; *) l="$1/objects/$l" ;; esac
  phys "$l"
}

# gitsnap DIR [LOOSE]: every file of the git folder DIR with its checksum and size, and
# every other entry, sorted; .git/vbw left out. With LOOSE, what a proof's own record
# commit and git's index refresh legitimately change is left out too: the objects, the
# logs, every index, COMMIT_EDITMSG, ORIG_HEAD and the current branch's ref.
gitsnap() {
  local b
  b=$(git symbolic-ref --short HEAD)
  if [ -n "${2:-}" ]; then
    (cd "$1" && find . \( -path ./vbw -o -name objects -o -name logs -o -path "./refs/heads/$b" \) -prune \
      -o \( -type f ! -name index ! -name COMMIT_EDITMSG ! -name ORIG_HEAD -exec cksum {} + \) -o \( ! -type f -print \))
  else
    (cd "$1" && find . -path ./vbw -prune -o \( -type f -exec cksum {} + \) -o \( ! -type f -print \))
  fi | LC_ALL=C sort
}

# sandbox_on: the stand-in for Claude Code's sandbox. For the project's git folder and
# each submodule's: worktrees/ and hooks/ unwritable, config locked (a config.lock
# folder: git cannot take the lock, so no config line can be written; a read-only file
# alone would still be replaced through its folder; an empty worktrees/ would be removed
# and made again through .git). Git on PATH refuses to leave any
# file named .gitmodules in a proof copy, with the sandbox's message.
sandbox_on() {
  local g
  for g in .git .git/modules/*; do
    [ -d "$g/objects" ] || continue
    mkdir -p "$g/worktrees" "$g/hooks"
    # Not empty, so git worktree prune cannot remove the folder and make it again.
    : > "$g/worktrees/.sandbox"
    mkdir "$g/config.lock"
    chmod 555 "$g/worktrees" "$g/hooks"
  done
  mkdir -p "$TEST_ROOT/fakebin"
  cat > "$TEST_ROOT/fakebin/git" << 'SH'
#!/bin/sh
"$REAL_GIT" "$@"
rc=$?
if [ -n "$(find "$SANDBOX_RUNTIME" -path '*/proof.*' -name .gitmodules -print 2> /dev/null | head -n 1)" ]; then
  find "$SANDBOX_RUNTIME" -path '*/proof.*' -name .gitmodules -exec rm -f {} + 2> /dev/null
  echo "error: unable to create file .gitmodules: Operation not permitted" >&2
  exit 128
fi
exit $rc
SH
  chmod +x "$TEST_ROOT/fakebin/git"
  REAL_GIT=$(command -v git)
  SANDBOX_RUNTIME="$PWD/.vbw/runtime"
  export REAL_GIT SANDBOX_RUNTIME
  PATH="$TEST_ROOT/fakebin:$PATH"
}
sandbox_off() {
  local g
  for g in .git .git/modules/*; do
    [ -d "$g/objects" ] || continue
    chmod 755 "$g/worktrees" "$g/hooks"
    rmdir "$g/config.lock"
  done
  PATH=${PATH#"$TEST_ROOT/fakebin:"}
}

# orphans: each git folder under .vbw/runtime (a folder holding HEAD and objects/) that
# no .git file of a copy there names.
orphans() {
  local f l d named=''
  while IFS= read -r -d '' f; do
    l=; read -r l < "$f" || :
    l=${l#gitdir: }
    case "$l" in /*) ;; *) l="$(dirname "$f")/$l" ;; esac
    named="$named$(phys "$l")"$'\n'
  done < <(find .vbw/runtime -name .git -type f -print0)
  while IFS= read -r -d '' f; do
    d=$(phys "$(dirname "$f")")
    [ -d "$d/objects" ] || continue
    printf '%s' "$named" | grep -qxF "$d" || printf '%s\n' "$d"
  done < <(find .vbw/runtime -name HEAD -type f -print0)
}

@test "R309 layer: making, releasing, claiming and refreshing, removing and sweeping a copy each leave the project's .git byte-identical but .git/vbw, a submodule's git folder included" {
  add_sub
  local before
  before=$(gitsnap .git)
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  run vbw_kernel '. "$VBW_LIB/proofcopy.sh"
    snap() { (cd "$VBW_ROOT/.git" && find . -path ./vbw -prune -o \( -type f -exec cksum {} + \) -o \( ! -type f -print \)) | LC_ALL=C sort; }
    step() { [ "$(snap)" = "$1" ] || { echo "the project'"'"'s .git changed after $2:"; diff <(printf "%s\n" "$1") <(snap); exit 1; }; }
    b=$(snap)
    proofcopy_create_slots 1; step "$b" "making a copy"
    proofcopy_release; step "$b" "releasing it"
    proofcopy_create_slots 1; step "$b" "claiming and refreshing it"
    [ "$PROOFCOPY_CLAIMED" -eq 1 ] || { echo "the kept copy was not claimed"; exit 1; }
    proofcopy_remove; step "$b" "removing it"
    proofcopy_create_slots 1; proofcopy_release
    touch -t 202001010000 "$VBW_RUNTIME/proof.keep.1"
    proofcopy_sweep; step "$b" "sweeping it"
    [ ! -e "$VBW_RUNTIME/proof.keep.1" ] || { echo "the sweep left the slot"; exit 1; }
    echo done'
  [ "$status" -eq 0 ] && [ "${lines[${#lines[@]}-1]}" = "done" ] || { echo "$output"; false; }
  [ "$(gitsnap .git)" = "$before" ]
}

@test "R309 commands: vbw prove and vbw mutate --run on a project with a submodule add no worktree entry, ref, config line or hook to the project's .git or the submodule's, and start no git worktree add, prune or remove" {
  add_sub
  local before
  before=$(gitsnap .git loose)
  mkdir -p "$TEST_ROOT/logbin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$GIT_LOG"\nexec "%s" "$@"\n' "$(command -v git)" > "$TEST_ROOT/logbin/git"
  chmod +x "$TEST_ROOT/logbin/git"
  export GIT_LOG="$TEST_ROOT/git.log"
  : > "$GIT_LOG"
  PATH="$TEST_ROOT/logbin:$PATH" prove_ok
  [ "$(gitsnap .git loose)" = "$before" ] || { diff <(printf '%s\n' "$before") <(gitsnap .git loose); false; }
  bump two
  PATH="$TEST_ROOT/logbin:$PATH" prove_ok
  [ "$(counts)" = '{"claimed":1,"refreshed":0,"made":0}' ] || { counts; false; }
  printf 'unpaid\n' > src/pay.txt
  "$VBW" mutate P1.1 R1.1 --queue "unpaid" src/pay.txt > /dev/null
  PATH="$TEST_ROOT/logbin:$PATH" vbw_run mutate P1.1 --run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  git checkout -q -- src/pay.txt
  [ "$(gitsnap .git loose)" = "$before" ] || { diff <(printf '%s\n' "$before") <(gitsnap .git loose); false; }
  ! grep -E '(^| )worktree (add|prune|remove)( |$)' "$GIT_LOG" || { echo "a git worktree command ran"; false; }
}

@test "R309 sandbox: with .git/worktrees, .git/config and .git/hooks unwritable and .gitmodules refused, vbw prove passes on a project with a submodule, a kept copy is claimed again, and vbw mutate --run completes" {
  add_sub
  sandbox_on
  prove_ok
  [ ! -e "$(slot 1)/tree/.gitmodules" ] || { echo "the copy holds .gitmodules"; false; }
  own_kind "$(slot 1)/tree"
  own_kind "$(slot 1)/tree/sub"
  [ -z "$(git -C "$(slot 1)/tree" status --porcelain)" ] || { git -C "$(slot 1)/tree" status; false; }
  # The #737 way: .gitmodules is read from the index, marked skip-worktree, and the copy's git folder says so.
  [[ "$(git -C "$(slot 1)/tree" ls-files -v .gitmodules)" == "S "* ]] || { git -C "$(slot 1)/tree" ls-files -v .gitmodules; false; }
  [ -f "$(git -C "$(slot 1)/tree" rev-parse --absolute-git-dir)/vbw-gitmodules-index" ] || { echo "no vbw-gitmodules-index in the copy's git folder"; false; }
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  run vbw_kernel 'VBW_ROOT=$VBW_RUNTIME/proof.keep.1/tree vbw_subs | tr "\0" "\n"'
  [ "$output" = sub ] || { echo "vbw_subs in the copy: $output"; false; }
  bump two
  prove_ok
  printf 'unpaid\n' > src/pay.txt
  "$VBW" mutate P1.1 R1.1 --queue "unpaid" src/pay.txt > /dev/null
  vbw_run mutate P1.1 --run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"Operation not permitted"* && "$output" != *"could not"* ]] || { echo "$output"; false; }
  sandbox_off
}

@test "R309 inside: in a copy git status is clean, HEAD is the project's (a submodule's copy is at the submodule's HEAD), ls-files, log and diff work, and a commit made there lands only in the copy" {
  add_sub
  prove_ok
  local t new refs objs
  t=$(slot 1)/tree
  own_kind "$t"
  own_kind "$t/sub"
  [ "$(alt_of "$(git -C "$t" rev-parse --absolute-git-dir)")" = "$(phys .git/objects)" ] || { echo "the copy does not borrow the project's objects"; false; }
  [ "$(alt_of "$(git -C "$t/sub" rev-parse --absolute-git-dir)")" = "$(phys "$(git -C sub rev-parse --absolute-git-dir)/objects")" ] || { echo "the submodule's copy does not borrow the submodule's objects"; false; }
  [ -z "$(git -C "$t" status --porcelain)" ] || { git -C "$t" status; false; }
  [ -z "$(git -C "$t/sub" status --porcelain)" ] || { git -C "$t/sub" status; false; }
  [ "$(git -C "$t" rev-parse HEAD)" = "$(code_head)" ]
  [ "$(git -C "$t/sub" rev-parse HEAD)" = "$(git -C sub rev-parse HEAD)" ]
  git -C "$t" ls-files | grep -qx src/pay.txt
  [ "$(git -C "$t" log -1 --format=%H)" = "$(code_head)" ]
  git -C "$t" diff --quiet HEAD
  printf 'paid\nin the copy\n' > "$t/src/pay.txt"
  if git -C "$t" diff --quiet HEAD; then echo "git diff sees no change in the copy"; false; fi
  refs=$(git for-each-ref; git -C sub for-each-ref)
  objs=$(find .git/objects -type f | LC_ALL=C sort)
  git -C "$t" commit -q -am "feat: only in the copy"
  new=$(git -C "$t" rev-parse HEAD)
  [ "$(git -C "$t" cat-file -t "$new")" = commit ]
  ! git cat-file -e "$new" 2> /dev/null || { echo "the copy's commit reached the project's objects"; false; }
  [ "$(git for-each-ref; git -C sub for-each-ref)" = "$refs" ]
  [ "$(find .git/objects -type f | LC_ALL=C sort)" = "$objs" ]
}

@test "R309 own: proofcopy_own accepts a copy of the new kind made for its place and refuses a worktree, a copy naming another slot's git folder, a copy put elsewhere, a linked slot, a git folder borrowing other objects and a folder with its own .git folder" {
  add_sub
  prove_ok
  mkdir -p "$(slot 3)"
  cp -Rp "$(slot 1)" "$(slot 2)"
  git worktree add -q --detach "$(slot 3)/tree" HEAD
  mkdir -p "$(slot 4)" && git init -q "$(slot 4)/tree"
  ln -s "$PWD/$(slot 1)" "$(slot 5)"
  cp -Rp "$(slot 1)/tree/sub" "$(slot 1)/tree/sub.moved"
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  run vbw_kernel '. "$VBW_LIB/proofcopy.sh"; r=$VBW_RUNTIME
    proofcopy_own "$r/proof.keep.1/tree" "$VBW_ROOT" && echo own
    proofcopy_own "$r/proof.keep.1/tree/sub" "$VBW_ROOT/sub" && echo sub
    proofcopy_own "$r/proof.keep.1/tree/sub" "$VBW_ROOT" && echo "sub against the project"
    proofcopy_own "$r/proof.keep.1/tree/sub.moved" "$VBW_ROOT/sub" && echo moved
    proofcopy_own "$r/proof.keep.2/tree" "$VBW_ROOT" && echo "other slot"
    proofcopy_own "$r/proof.keep.3/tree" "$VBW_ROOT" && echo worktree
    proofcopy_own "$r/proof.keep.4/tree" "$VBW_ROOT" && echo "own .git folder"
    proofcopy_own "$r/proof.keep.5/tree" "$VBW_ROOT" && echo link
    # The submodule copy reached through a link: its target passes every other test.
    mv "$r/proof.keep.1/tree/sub" "$r/proof.keep.1/tree/sub.real"
    ln -s "$r/proof.keep.1/tree/sub.real" "$r/proof.keep.1/tree/sub"
    proofcopy_own "$r/proof.keep.1/tree/sub" "$VBW_ROOT/sub" && echo "sub link"
    g=$(git -C "$r/proof.keep.1/tree" rev-parse --absolute-git-dir)
    printf "%s\n" "$(git -C "$VBW_ROOT/sub" rev-parse --absolute-git-dir)/objects" > "$g/objects/info/alternates" || echo "no alternates to change"
    proofcopy_own "$r/proof.keep.1/tree" "$VBW_ROOT" && echo "other objects"
    true'
  [ "$output" = "$(printf 'own\nsub')" ] || { echo "$output"; false; }
}

@test "R309 upgrade: a kept slot an older VBW made (a git worktree) is made fresh in its slot with nothing said; under the sandbox its worktree entry stays, silently, and outside it the entry is cleaned up" {
  prove_ok
  rm -rf "$(slot 1)/tree"
  git worktree add -q -f --detach "$(slot 1)/tree" HEAD
  local d
  d=$(git worktree list --porcelain | grep -c '/proof.keep.1/tree$')
  [ "$d" -eq 1 ]
  bump two
  sandbox_on
  prove_ok
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  own_kind "$(slot 1)/tree"
  [[ "$output" != *worktree* && "$output" != *fatal* && "$output" != *"not permitted"* && "$output" != *"could not"* ]] || { echo "$output"; false; }
  sandbox_off
  bump three
  prove_ok
  [[ "$output" != *worktree* && "$output" != *fatal* ]] || { echo "$output"; false; }
  ! git worktree list --porcelain | grep -q '/\.vbw/runtime/proof\.' || { git worktree list; false; }
}

@test "R309 gone: a kept copy whose commit can no longer be read (history rewritten, objects pruned) is made fresh, never a failed proof" {
  bump two
  prove_ok
  local old
  old=$(code_head)
  [ "$(git -C "$(slot 1)/tree" rev-parse HEAD)" = "$old" ]
  # Drop the commit and the proof's record commit on top of it, then prune everything unreachable.
  git reset -q --hard "$old~1"
  rm -f .git/ORIG_HEAD
  git reflog expire --expire=now --all
  git gc -q --prune=now
  ! git cat-file -e "$old" 2> /dev/null || { echo "the old commit is still in the project: a copy keeps it alive"; false; }
  bump three
  prove_ok
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  [ "$(git -C "$(slot 1)/tree" rev-parse HEAD)" = "$(code_head)" ]
  [ -z "$(git -C "$(slot 1)/tree" status --porcelain)" ] || { git -C "$(slot 1)/tree" status; false; }
}

@test "R309 cleanup: removing a slot removes its git folder: after a discard, a sweep, an interrupt and a vbw_die no git folder is left under .vbw/runtime" {
  "$VBW" config set check_jobs 1 > /dev/null
  prove_ok
  own_kind "$(slot 1)/tree"
  # Discard: a copy that fails its check is emptied and made fresh.
  printf 'gitdir: /nowhere\n' > "$(slot 1)/tree/.git"
  bump two
  prove_ok
  [ "$(counts)" = '{"claimed":0,"refreshed":0,"made":1}' ] || { counts; false; }
  [ -z "$(orphans)" ] || { echo "after a discard:"; orphans; false; }
  # Sweep: a slot numbered past check_jobs goes with its git folder.
  cp -Rp "$(slot 1)" "$(slot 2)"
  bump three
  prove_ok
  [ ! -e "$(slot 2)" ] || { ls -la "$(slot 2)"; false; }
  [ -z "$(orphans)" ] || { echo "after a sweep:"; orphans; false; }
  # Interrupt: the held slot goes.
  bump four
  rm -f "$MARK"/start.*
  HOLD=1 "$VBW" prove > "$TEST_ROOT/out" 2>&1 < /dev/null &
  local pid=$! i=0
  while [ -z "$(find "$MARK" -name 'start.*' -print -quit)" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  [ -n "$(find "$MARK" -name 'start.*' -print -quit)" ]
  kill -TERM "$pid"
  wait "$pid" || true
  touch "$MARK/release"
  [ ! -e "$(slot 1)" ] || { echo "the interrupted proof left its slot"; ls -la "$(slot 1)"; false; }
  [ -z "$(orphans)" ] || { echo "after an interrupt:"; orphans; false; }
  # vbw_die: a check file committed but not approved (the working folder still holds the
  # approved bytes) stops the proof once its copy is made.
  cp tests/pay.sh "$TEST_ROOT/pay.approved"
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  git add tests/pay.sh && git commit -q -m "chore: unapproved check"
  cp "$TEST_ROOT/pay.approved" tests/pay.sh
  vbw_run prove
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"not committed as approved"* ]] || { echo "$output"; false; }
  [ -z "$(find .vbw/runtime -maxdepth 1 -name 'proof.*' -print)" ] || { ls -la .vbw/runtime; false; }
  [ -z "$(orphans)" ] || { echo "after vbw_die:"; orphans; false; }
}

@test "R309 project: vbw run inside a copy, the project's or a submodule's, treats the copy as a project of its own, also when the project's path holds a folder named modules" {
  mkdir -p "$TEST_ROOT/modules"
  mv "$PROJECT" "$TEST_ROOT/modules/shop"
  cd "$TEST_ROOT/modules/shop"
  add_sub
  prove_ok
  own_kind "$(slot 1)/tree"
  # A project that keeps .vbw untracked: its copies hold no record.
  rm -rf "$(slot 1)/tree/.vbw"
  local d
  for d in "$(slot 1)/tree" "$(slot 1)/tree/sub"; do
    run sh -c 'cd "$1" && "$2" status < /dev/null' _ "$d" "$VBW"
    [ "$status" -ne 0 ] && [[ "$output" == *"not a VBW project"* ]] || { echo "in $d: $output"; false; }
    # The hooks and the status line find the project the same way (hooks/project.sh).
    run bash -c '. "$1/hooks/project.sh"; vbw_project_of "$2"; printf "%s\n" "$root"' _ "$PLUGIN_ROOT" "$PWD/$d"
    [ "$output" = "$PWD/$d" ] || { echo "the hooks take $d for $output"; false; }
  done
}

@test "R309 stores: kernel code run from inside a copy still finds this clone's settings and step history in the project's .git/vbw, never in the copy's git folder" {
  prove_ok
  local want
  want=$(phys "$(git rev-parse --path-format=absolute --git-common-dir)")/vbw
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  run vbw_kernel '. "$VBW_LIB/steps.sh"; cd "$VBW_RUNTIME/proof.keep.1/tree" || exit 1
    s=$(vbw_clone_settings_file) && h=$(step_history_file) || exit 1
    printf "%s\n%s\n" "$(cd -P "$(dirname "$s")" && pwd -P)/${s##*/}" "$(cd -P "$(dirname "$h")" && pwd -P)/${h##*/}"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$(printf '%s/settings.json\n%s/steps.json' "$want" "$want")" ] || { echo "$output"; false; }
}
