#!/usr/bin/env bats
# The shared-fixture helper (tests/fixture-helper.bash): a project built once per
# test file in setup_file and copied for each test. A copy holds no path of the
# fixture, a test's writes never reach the fixture or another test, each test has
# its own HOME and Claude config folder, the build runs once per file under
# bats --jobs, a copied loop_project proves exactly as a freshly built one, a
# fixture keeps no kept proof copy (#738), and a fixture that holds its own path
# is refused at build time. L1.

load helper
load loop-helper
load fixture-helper

# marked: a small fixture whose builder sets variables of every kind a copy
# must restore, and ends in a folder below the project.
marked() {
  vbw_setup
  vbw_git_project
  MARK="$PROJECT/mark"
  export MARK
  PLAIN="$TEST_ROOT/plain"
  PHYS="$(cd "$TEST_ROOT" && pwd -P)/phys"
  KEEP=outside
  PATH="$TEST_ROOT/bin:$PATH"
  export PATH
  unset GONE
  mkdir sub
  cd sub || return 1
}

setup_file() {
  export GONE=here
  fixture_build loop loop_project
  fixture_build marked marked
  tree_sum "$(fixture_root loop)" > "$BATS_FILE_TMPDIR/loop.sum"
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# tree_sum DIR: one checksum of every path, file content and link target under DIR.
tree_sum() {
  (cd "$1" && { find . -print0 | LC_ALL=C sort -z | tr '\0' '\n'
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 cksum
    find . -type l -print0 | LC_ALL=C sort -z | xargs -0 -n1 readlink; } | cksum)
}

# no_trace DIR NEEDLE...: no file content, link target or git object under DIR holds any NEEDLE.
no_trace() {
  local dir=$1 n f g
  shift
  for n in "$@"; do
    f=$(grep -rlF -- "$n" "$dir" || true)
    [ -z "$f" ] || { echo "files hold $n:"; echo "$f"; return 1; }
    f=$(find "$dir" -type l -print0 | xargs -0 -n1 readlink | grep -F -- "$n" || true)
    [ -z "$f" ] || { echo "links point at $n: $f"; return 1; }
    while IFS= read -r -d '' g; do
      ! git --git-dir="${g%/objects}" cat-file --batch-all-objects --batch | grep -qaF -- "$n" || { echo "git history in $g holds $n"; return 1; }
    done < <(find "$dir" -type d -name objects -prune -print0)
  done
}

@test "a copy holds no path of the fixture, and its variables point into the copy" {
  local from from_phys root
  { IFS= read -r from; IFS= read -r from_phys; } < "$(fixture_store)/loop/from"
  root=$(fixture_root loop)
  fixture_copy loop
  no_trace "$TEST_ROOT" "$from" "$from_phys" "${from##*/}" "${from##*.}" "$root"
  # The place it was built at is gone: nothing can reach back to it.
  [ ! -e "$from" ]
  [ "$PROJECT" = "$TEST_ROOT/project with space" ] && [ "$PWD" = "$PROJECT" ]
  case $TEST_ROOT in "$(fixture_store)"*) false ;; esac
  [ "$(git rev-parse --show-toplevel)" = "$(cd "$PROJECT" && pwd -P)" ]
  # The variables the builder set come back re-pointed, exported or not as they were, and unset ones stay unset.
  fixture_copy marked
  [ "$PWD" = "$PROJECT/sub" ]
  [ "$MARK" = "$PROJECT/mark" ] && [ "$(bash -c 'printf %s "$MARK"')" = "$MARK" ]
  [ "$PLAIN" = "$TEST_ROOT/plain" ] && [ -z "$(bash -c 'printf %s "${PLAIN:-}"')" ]
  [ "$PHYS" = "$(cd "$TEST_ROOT" && pwd -P)/phys" ]
  [ "$KEEP" = outside ]
  [ "${PATH%%:*}" = "$TEST_ROOT/bin" ]
  [ -z "${GONE+x}" ]
  # The first copy of this test was removed when the second was made.
  [ -n "$_FIXTURE_COPY" ] && [ "$_FIXTURE_COPY" = "$TEST_ROOT" ]
}

@test "after each build, setup_file's own variables and directory are back as they were" {
  local f from
  [ -z "${TEST_ROOT:-}" ] && [ -z "${PROJECT:-}" ] && [ -z "${MARK+x}" ] && [ -z "${PLAIN+x}" ] && [ -z "${KEEP+x}" ]
  [ "$GONE" = here ]
  for f in loop marked; do
    from=$(head -1 "$(fixture_store)/$f/from")
    [[ "$PATH" != *"$from"* && "$HOME" != "$from"* && "$PWD" != "$from"* ]]
    [[ "${CLAUDE_CONFIG_DIR:-}" != "$from"* && "${GIT_CONFIG_GLOBAL:-}" != "$from"* && "${CLAUDE_PLUGIN_DATA:-}" != "$from"* ]]
  done
  [[ "$PWD" != "$(fixture_store)"* ]]
  [ -z "$(compgen -A variable _fx_)" ]
}

isolated_writes() {
  local other=$1 sum
  fixture_copy loop
  # The copy is the fixture, byte for byte; nothing the other test wrote is in it.
  [ "$(tree_sum "$TEST_ROOT")" = "$(cat "$BATS_FILE_TMPDIR/loop.sum")" ]
  [ ! -e "mark.$other" ] && [ ! -e "$HOME/mark.$other" ] && [ ! -e "$CLAUDE_CONFIG_DIR/mark.$other" ]
  [ "$(jq '.todos | length' .vbw/record.json)" = 2 ]
  # Writes everywhere a test can write: the project, its git history, the record, HOME, the Claude config, git's global config.
  printf '%s\n' "$2" > "mark.$2"
  git add "mark.$2" && git commit -q -m "test: mark $2"
  "$VBW" todo add "Visitors can read mark $2" > /dev/null
  printf 'x\n' > "$HOME/mark.$2"
  printf 'x\n' > "$CLAUDE_CONFIG_DIR/mark.$2"
  git config --global user.name "Writer $2"
  [ "$(jq '.todos | length' .vbw/record.json)" = 3 ]
  # None of it reached the fixture.
  sum=$(tree_sum "$(fixture_root loop)")
  [ "$sum" = "$(cat "$BATS_FILE_TMPDIR/loop.sum")" ]
}

@test "copy isolation (1 of 2): a test's writes never reach the fixture or the next test" {
  isolated_writes two one
}

@test "copy isolation (2 of 2): a test's writes never reach the fixture or the next test" {
  isolated_writes one two
}

@test "each test gets its own HOME, Claude config folder, plugin data and git identity, holding the fixture's" {
  local root
  root=$(fixture_root loop)
  fixture_copy loop
  [ "$HOME" = "$TEST_ROOT/home" ] && [ "$CLAUDE_CONFIG_DIR" = "$HOME/.claude" ]
  [ "$CLAUDE_PLUGIN_DATA" = "$TEST_ROOT/plugin-data" ] && [ "$GIT_CONFIG_GLOBAL" = "$TEST_ROOT/gitconfig" ]
  [ "$GIT_CONFIG_NOSYSTEM" = 1 ] && [ "$LC_ALL" = C ]
  [ -d "$CLAUDE_CONFIG_DIR/vbw" ] && [ -d "$CLAUDE_PLUGIN_DATA" ]
  [ "$(git config --global --get user.email)" = test@example.com ]
  [ "$(git config --global --get gc.auto)" = 0 ]
  [ "$(git config --show-origin --global --get user.email | cut -f1)" = "file:$GIT_CONFIG_GLOBAL" ]
  case $TEST_ROOT in "$root"*) false ;; esac
  [ "$(cd "$TEST_ROOT" && ls -A)" = "$(cd "$root" && ls -A)" ]
}

@test "fixture_copy refuses a fixture that was not built, naming it" {
  run fixture_copy nosuch
  [ "$status" -ne 0 ]
  [[ "$output" == *"nosuch"*"setup_file"* ]] || { echo "$output"; false; }
  run fixture_copy
  [ "$status" -ne 0 ]
  [[ "$output" == *"several"* ]] || { echo "$output"; false; }
}

@test "the build runs once per file, even with bats --jobs 4: every test gets its own copy of the variant it names" {
  command -v parallel > /dev/null || { echo "bats --jobs needs GNU parallel, as tools/test.sh does"; false; }
  vbw_setup
  local dir="$TEST_ROOT/inner"
  mkdir -p "$dir/tests" "$dir/sync"
  cp "$REPO_ROOT/tests/helper.bash" "$REPO_ROOT/tests/fixture-helper.bash" "$dir/tests/"
  cp "$REPO_ROOT/tests/fixtures/fixture-helper-inner.bats.in" "$dir/tests/inner.bats"
  run env COUNT="$dir/count" SYNC="$dir/sync" VBW_TEST_PLUGIN_ROOT="$PLUGIN_ROOT" bats --jobs 4 "$dir/tests/inner.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # All eight inner tests ran (a bats that reads no test reports 1..0 and exits 0).
  [[ "$output" == "1..8"* ]] || { echo "$output"; false; }
  [ "$(grep -cx one "$dir/count")" = 1 ] && [ "$(grep -cx two "$dir/count")" = 1 ] || { cat "$dir/count"; false; }
  # Eight tests, eight copies of their own, four of each variant, and some ran at the same time.
  [ "$(cut -d' ' -f2- "$dir/sync/roots" | sort -u | wc -l | tr -d ' ')" = 8 ] || { cat "$dir/sync/roots"; false; }
  [ "$(awk '$1 == "one"' "$dir/sync/roots" | wc -l | tr -d ' ')" = 4 ]
  [ -s "$dir/sync/overlaps" ]
  # The nested file kept its fixtures to itself: this file's are still here.
  [ -d "$(fixture_root loop)" ] && [ -d "$(fixture_root marked)" ]
}

# prove_story: three proofs as session s1, the first on the project as given, then after a
# commit no check reads, then after a commit to a file C1 reads; for each its verdict, its
# output (times left out), its evidence and the run store's decisions, without times and commit ids.
# Times left out of the output: dates, each unit's seconds, and the two lines that are only
# times (VBW's own work; the slowest units, ordered by their seconds). A unit's seconds are
# whole wall-clock seconds, so the same sub-second run reads 0 s or 1 s depending on whether
# it crossed a second (one flake, 2026-10-21, under load).
prove_story() {
  local i=1
  while [ "$i" -le 3 ]; do
    case $i in
      2) printf 'more\n' >> README.md; git add README.md; git commit -q -m "docs: more" ;;
      3) printf 'more notes\n' >> src/notes.txt; git add src/notes.txt; git commit -q -m "feat(notes): more" ;;
    esac
    run env VBW_SESSION_ID=s1 "$VBW" prove < /dev/null
    printf 'proof %s: status %s\n' "$i" "$status"
    printf '%s\n' "$output" | grep -vE "^(VBW's own work|slowest units):" \
      | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z/TIME/g; s/ [0-9]+(\.[0-9]+)?s( |$)/ Ns\2/g'
    jq -S '.evidence | {passed, full, causes, scope, undone, test_files, contract,
      checks: (.checks | map_values({status, exit, reused})), commands: (.commands | map_values({status, exit, reused}))}' .vbw/record.json
    jq -S '.runs | map_values({status, reads, dirs, git})' "$(git rev-parse --git-dir)/vbw/runs.json"
    i=$((i + 1))
  done
}

@test "a copied loop_project proves exactly as a freshly built one: the same verdicts and the same reuse decisions" {
  fixture_copy loop
  prove_story > "$BATS_TEST_TMPDIR/copied"
  vbw_teardown
  loop_project
  prove_story > "$BATS_TEST_TMPDIR/fresh"
  diff "$BATS_TEST_TMPDIR/fresh" "$BATS_TEST_TMPDIR/copied"
  # Not a vacuous match: the copy reused the fixture's own results, then ran C1 again after its file changed.
  grep -q '^proof 1: status 0$' "$BATS_TEST_TMPDIR/copied"
  sed -n '/^proof 1:/,/^proof 2:/p' "$BATS_TEST_TMPDIR/copied" | grep -q 'C1 pass Ns reused'
  sed -n '/^proof 3:/,$p' "$BATS_TEST_TMPDIR/copied" | grep -E '^ +C1 ' | grep -vq reused
}

@test "#738: a fixture keeps no proof copy of its builder's proofs, and a copy makes its own" {
  local root
  root=$(fixture_root loop)
  [ -z "$(find "$root" -path '*/.vbw/runtime/proof.*' -prune -print)" ] || { find "$root" -path '*/.vbw/runtime/proof.*' -prune -print; false; }
  [ -z "$(find "$root" -path '*/.git/worktrees' -prune -print)" ] || { find "$root" -path '*/.git/worktrees/*' -prune -print; false; }
  fixture_copy loop
  vbw_run prove --full
  jq -e '.evidence.own.copy_slots | .claimed == 0 and .made >= 1' .vbw/record.json || { jq .evidence.own .vbw/record.json; false; }
  [ -z "$(git worktree list --porcelain | grep '^worktree ' | sed 1d | grep -vF "$(pwd -P)/.vbw/runtime/proof.keep.")" ] || { git worktree list; false; }
}

# Builders whose fixture holds its own path, each in another place.
in_file() { vbw_setup; vbw_git_project; printf '%s\n' "$TEST_ROOT" > "$BUILT"; printf '%s\n' "$PROJECT" > where.txt; }
in_history() {
  vbw_setup; vbw_git_project; printf '%s\n' "$TEST_ROOT" > "$BUILT"
  printf '%s\n' "$PROJECT" > where.txt; git add where.txt; git commit -q -m where; git rm -q where.txt; git commit -q -m gone
}
in_link() { vbw_setup; vbw_git_project; printf '%s\n' "$TEST_ROOT" > "$BUILT"; ln -s "$PROJECT/README.md" link; }
in_git_dir() { vbw_setup; vbw_git_project; printf '%s\n' "$TEST_ROOT" > "$BUILT"; (cd "$TEST_ROOT" && pwd -P) > .git/where; }
in_variable() { vbw_setup; vbw_git_project; printf '%s\n' "$TEST_ROOT" > "$BUILT"; MUNGED=$(printf '%s' "$TEST_ROOT" | tr '/.' '--'); export MUNGED; }
# shellcheck disable=SC2034 # the array is what the build must refuse
in_array() { vbw_setup; vbw_git_project; printf '%s\n' "$TEST_ROOT" > "$BUILT"; LIST=(a b); }

@test "the build is refused, naming the place, when the fixture holds its own path or an array; nothing of it is left" {
  local VBW_FIXTURE_STORE="$BATS_TEST_TMPDIR/store" BUILT="$BATS_TEST_TMPDIR/built" b
  local -a expect=("in_file:where.txt" "in_history:.git (git history)" "in_link:link -> " "in_git_dir:.git/where" "in_variable:MUNGED" "in_array:array")
  for b in "${expect[@]}"; do
    rm -f "$BUILT"
    run fixture_build bad "${b%%:*}"
    [ "$status" -ne 0 ] || { echo "${b%%:*} was not refused"; false; }
    [[ "$output" == *"fixture_build bad: "* && "$output" == *"${b#*:}"* ]] || { echo "${b%%:*}: $output"; false; }
    [ -s "$BUILT" ] && [ ! -e "$(cat "$BUILT")" ] || { echo "${b%%:*} left its build behind"; false; }
    [ ! -e "$VBW_FIXTURE_STORE/bad" ]
  done
  # The same builder without the path is accepted.
  plain() { vbw_setup; vbw_git_project; }
  run fixture_build good plain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -d "$VBW_FIXTURE_STORE/good/root" ]
}
