#!/usr/bin/env bats
# R253 (T230, T186; docs/proof.md): a clean copy never carries a git worktree.
# Every copy (vbw prove here; vbw check and vbw mutate share proofcopy_make) leaves
# out the folder of every worktree of the project's repository that lies inside
# the project (git worktree list --porcelain, by physical path) and
# .claude/worktrees, whatever the Clean copy section says; a worktree nested under
# an ignored folder is skipped by descending around it (D509), and a worktree git
# still lists but whose folder is gone causes no error. vbw init and vbw doctor
# name each git-ignored folder over the threshold (500 MB, the plain-copy
# threshold VBW_PROOFCOPY_PLAIN_KB lowers in tests) as a candidate for the Clean
# copy section with its size: init as commented suggestions in the section's
# template, nothing uncommented (D54); doctor for the folders the section does not
# list yet; worktrees are never candidates and nothing is said when none is over.
# L1: the kernel on a shop fixture whose check lists the copy it runs in (PROBE).

load helper
load fixture-helper

# shop LISTED: an approved, built project with ignored folders data/ (a.bin), cache/,
# wt/ and .claude/; worktrees adds a worktree data/wt2 nested under data/, one at
# wt/feature holding a 1 MB ignored file and one at .claude/worktrees/w. With
# LISTED the spec leaves cache/ out of the clean copy.
shop() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf 'data/\ncache/\nwt/\n.claude/\n' > .gitignore
  mkdir -p data cache src tests
  printf 'big\n' > data/a.bin
  printf 'c\n' > cache/c.txt
  cat > tests/pay.sh << 'SH'
if [ -n "${PROBE:-}" ]; then
  find . -path ./.git -prune -o -print | sort > "$PROBE"
fi
grep -qx paid src/pay.txt
SH
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  [ "$1" != listed ] || printf '\n## Clean copy\n\n- cache/\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "express"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying works", check: "C1"}]}' | "$VBW" apply > /dev/null
  printf 'paid\n' > src/pay.txt
  jq '.plans[0].status = "done"' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

# worktrees: the three worktrees, added to the copy at hand (a fixture never holds
# its own path, and a worktree's .git file names the repository's).
worktrees() {
  git worktree add -q wt/feature -b feature > /dev/null 2>&1
  git worktree add -q .claude/worktrees/w -b w > /dev/null 2>&1
  git worktree add -q data/wt2 -b wt2 > /dev/null 2>&1
  mkdir -p wt/feature/data
  head -c 1048576 /dev/zero > wt/feature/data/blob.bin
  printf 'x\n' > .claude/worktrees/w/note.txt
  printf 'y\n' > data/wt2/note.txt
}

setup_file() {
  fixture_build listed shop listed
  fixture_build plain shop plain
}
setup() {
  fixture_copy listed
  worktrees
  export PROBE="$TEST_ROOT/probe"
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

copied() { grep -qx -- "$1" "$PROBE" || { echo "not in the copy: $1"; cat "$PROBE"; return 1; }; }
not_copied() { ! grep -q -- "^$1" "$PROBE" || { echo "in the copy: $1"; grep -- "^$1" "$PROBE"; return 1; }; }

@test "R253 copy: the clean copy skips every worktree inside the project and .claude/worktrees, with a Clean copy list and without, while the other ignored paths are still copied in" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -s "$PROBE" ]
  copied ./data/a.bin
  not_copied ./cache
  not_copied ./wt
  not_copied ./.claude/worktrees
  not_copied ./data/wt2
  fixture_copy plain
  worktrees
  export PROBE="$TEST_ROOT/probe"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  copied ./data/a.bin
  copied ./cache/c.txt
  not_copied ./wt
  not_copied ./.claude/worktrees
  not_copied ./data/wt2
  [[ "$output" != *"copied file by file"* ]] || { echo "$output"; false; }
}

@test "R253 copy: a worktree git still lists but whose folder is gone causes no error, and the copy is the same" {
  rm -rf data/wt2 wt/feature
  git worktree list --porcelain | grep -q 'prunable' || { git worktree list --porcelain; false; }
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"fatal"* && "$output" != *"error"* ]] || { echo "$output"; false; }
  copied ./data/a.bin
  not_copied ./wt
  not_copied ./.claude/worktrees
}

# fresh BIG: a git project, not yet a VBW project, with .gitignore big/, wt/ and
# .claude/, a 1 MB file under big/ when BIG is set, and 1 MB under a worktree wt/w.
fresh() {
  vbw_setup
  vbw_git_project
  printf 'big/\nwt/\n.claude/\n' > .gitignore
  git add .gitignore && git commit -q -m "chore: ignore"
  mkdir -p big
  [ -z "$1" ] || head -c 1048576 /dev/zero > big/blob.bin
  git worktree add -q wt/w -b w > /dev/null 2>&1
  mkdir -p wt/w/big
  head -c 1048576 /dev/zero > wt/w/big/blob.bin
}

@test "R253 candidates: vbw init prints one line per git-ignored folder over the threshold, with its size, and writes it as a commented suggestion in the Clean copy section, nothing uncommented; a worktree is never a candidate; nothing is printed when none is over" {
  fresh big
  VBW_PROOFCOPY_DISK=plain VBW_PROOFCOPY_PLAIN_KB=512 vbw_run init
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"big/ (1.0 MB)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"wt/"* ]] || { echo "a worktree is a candidate: $output"; false; }
  grep -q 'big/' .vbw/spec.md
  ! grep -qE '^- big/' .vbw/spec.md || { echo "an uncommented line was written"; false; }
  "$VBW" spec sync > /dev/null
  jq -e 'has("project") and (.project | has("leave_out") | not)' .vbw/record.json
  fresh big
  vbw_run init
  [ "$status" -eq 0 ] && [[ "$output" != *"big/"* ]] || { echo "$output"; false; }
  fresh ''
  VBW_PROOFCOPY_DISK=plain VBW_PROOFCOPY_PLAIN_KB=512 vbw_run init
  [ "$status" -eq 0 ] && [[ "$output" != *"big/"* && "$output" != *"wt/"* ]] || { echo "$output"; false; }
}

@test "R253 candidates: vbw doctor names each git-ignored folder over the threshold that the Clean copy section does not list yet, with its size, and says nothing when none is over or every one is listed" {
  fresh big
  "$VBW" init > /dev/null
  VBW_PROOFCOPY_DISK=plain VBW_PROOFCOPY_PLAIN_KB=512 vbw_run doctor
  [[ "$output" == *"big/ (1.0 MB)"* && "$output" != *"wt/"* ]] || { echo "$output"; false; }
  printf '\n## Clean copy\n\n- big/\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  VBW_PROOFCOPY_DISK=plain VBW_PROOFCOPY_PLAIN_KB=512 vbw_run doctor
  [[ "$output" != *"big/ (1.0 MB)"* ]] || { echo "$output"; false; }
  vbw_run doctor
  [[ "$output" != *"big/"* ]] || { echo "$output"; false; }
}

# R267 (T249; docs/proof.md): the large-folder suggestion asks the disk, never the folder's
# name. proofcopy_disk_kind answers clone when a copy-on-write clone of a small file under
# .vbw/runtime succeeds (cp -c on macOS, cp --reflink=always elsewhere) and plain otherwise,
# leaving nothing behind; VBW_PROOFCOPY_DISK=clone|plain injects the answer for tests. On a
# plain disk vbw doctor and vbw init print today's leave-out suggestion; on a cloning disk
# they print an info line (little cost, keeping can save rebuilds) with no leave-out step,
# and vbw init writes no commented leave-out line, keeping the section and its comment.
# fresh_named NAME: a git project with a 1 MB git-ignored folder NAME/ (no worktree).
fresh_named() {
  vbw_setup
  vbw_git_project
  printf '%s/\n' "$1" > .gitignore
  git add .gitignore && git commit -q -m "chore: ignore"
  mkdir -p "$1"
  head -c 1048576 /dev/zero > "$1/blob.bin"
}

@test "R267 helper: proofcopy_disk_kind answers clone or plain by trying a clone under .vbw/runtime, leaves nothing there, and takes VBW_PROOFCOPY_DISK as the answer" {
  fresh_named data
  "$VBW" init > /dev/null
  local kind
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  kind=$(vbw_kernel '. "$VBW_LIB/proofcopy.sh"; proofcopy_disk_kind')
  [ "$kind" = clone ] || [ "$kind" = plain ] || { echo "proofcopy_disk_kind answered: $kind"; false; }
  [ -z "$(find .vbw/runtime -name 'disk*' -print 2> /dev/null)" ] || { echo "the probe left something: $(find .vbw/runtime -name 'disk*')"; false; }
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  [ "$(VBW_PROOFCOPY_DISK=plain vbw_kernel '. "$VBW_LIB/proofcopy.sh"; proofcopy_disk_kind')" = plain ]
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  [ "$(VBW_PROOFCOPY_DISK=clone vbw_kernel '. "$VBW_LIB/proofcopy.sh"; proofcopy_disk_kind')" = clone ]
  grep -q 'VBW_PROOFCOPY_DISK' "$PLUGIN_ROOT/lib/proofcopy.sh" || { echo "the override is not documented in proofcopy.sh"; false; }
  ! grep -nE 'PROOFCOPY_BUILD_DIRS' <(awk '/^proofcopy_disk_kind\(\)/, /^}/' "$PLUGIN_ROOT/lib/proofcopy.sh") || { echo "proofcopy_disk_kind reads the build-folder names"; false; }
}

@test "R267 doctor: a build-named folder (target/) on a plain disk gets the leave-out line; a data-named folder on a cloning disk gets the info line with no leave-out step: the disk decides, never the name" {
  fresh_named target
  "$VBW" init > /dev/null
  VBW_PROOFCOPY_DISK=plain VBW_PROOFCOPY_PLAIN_KB=512 vbw_run doctor
  [[ "$output" == *"target/ (1.0 MB)"* && "$output" == *"list target/ under Clean copy"* ]] || { echo "$output"; false; }
  fresh_named data
  "$VBW" init > /dev/null
  VBW_PROOFCOPY_DISK=clone VBW_PROOFCOPY_PLAIN_KB=512 vbw_run doctor
  [[ "$output" == *"data/ (1.0 MB)"* && "$output" == *"little cost"* ]] || { echo "$output"; false; }
  [[ "$output" != *"list data/ under Clean copy"* && "$output" != *"leave"* ]] || { echo "a leave-out step on a cloning disk: $output"; false; }
}

@test "R267 init: target/ on a plain disk gets the commented leave-out line; data/ on a cloning disk gets the info line and no commented line, the section and its comment stay, and an existing spec is never rewritten" {
  fresh_named target
  VBW_PROOFCOPY_DISK=plain VBW_PROOFCOPY_PLAIN_KB=512 vbw_run init
  [ "$status" -eq 0 ] && [[ "$output" == *"target/ (1.0 MB)"* && "$output" == *"uncomment"* ]] || { echo "$output"; false; }
  grep -qF '<!-- - target/ -->' .vbw/spec.md || { echo "no commented leave-out line for target/"; false; }
  fresh_named data
  VBW_PROOFCOPY_DISK=clone VBW_PROOFCOPY_PLAIN_KB=512 vbw_run init
  [ "$status" -eq 0 ] && [[ "$output" == *"data/ (1.0 MB)"* && "$output" == *"little cost"* ]] || { echo "$output"; false; }
  [[ "$output" != *"uncomment"* ]] || { echo "a leave-out step on a cloning disk: $output"; false; }
  ! grep -qF '<!-- - data/ -->' .vbw/spec.md || { echo "a commented leave-out line was written on a cloning disk"; false; }
  grep -q '^## Clean copy' .vbw/spec.md && grep -q "Git-ignored paths the proof's clean copy leaves out" .vbw/spec.md || { echo "the Clean copy section or its comment is gone"; false; }
  local sum
  sum=$(cksum < .vbw/spec.md)
  VBW_PROOFCOPY_DISK=clone VBW_PROOFCOPY_PLAIN_KB=512 vbw_run init
  [ "$(cksum < .vbw/spec.md)" = "$sum" ] || { echo "vbw init rewrote an existing spec"; false; }
}
