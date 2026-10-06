#!/usr/bin/env bats
# R68: the review of a VBW 1 folder works on Linux. GNU stat reads `stat -f` as
# "file system status" and succeeds with other output, so a file's time must
# come from the kernel's one portable reader, vbw_mtime. Found by CI (Linux,
# bash 5) on the 2.0.19 push: every untracked or non-git review gave up.
# A GNU-like stat on PATH reproduces Linux on macOS (L1).

load helper

setup() {
  vbw_setup
  vbw_git_project
  export GIT_CEILING_DIRECTORIES="$TEST_ROOT"
  # A stat that answers like GNU coreutils: -c %Y is the time; -f is file
  # system status, printed and successful whatever follows it.
  mkdir -p "$TEST_ROOT/gnu"
  cat > "$TEST_ROOT/gnu/stat" <<'EOS'
#!/bin/sh
case "$1" in
  -c) shift 2; exec /usr/bin/env perl -e 'print((stat($ARGV[0]))[9], "\n")' "$1" ;;
  -f) printf '  File: "%s"\n    ID: 0 Namelen: 255 Type: ext2/ext3\n' "$3"; exit 0 ;;
esac
exit 1
EOS
  chmod +x "$TEST_ROOT/gnu/stat"
}

teardown() { vbw_teardown; }

untracked_folder() {
  mkdir -p .vbw-planning/phases/01-a src
  printf -- '---\nphase: 1\nfiles_modified:\n  - src/a.sh\n---\n# Plan\n' > .vbw-planning/phases/01-a/01-01-PLAN.md
  printf '# Done\n' > .vbw-planning/phases/01-a/01-01-SUMMARY.md
  printf 'a\n' > src/a.sh
}

@test "R68: with GNU stat, an untracked folder is reviewed: readable, last use from its newest file" {
  untracked_folder
  PATH="$TEST_ROOT/gnu:$PATH" run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.readable == true and (.last_used | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and .days_ago <= 1 and .finished == {done: 1, total: 1}' \
    || { echo "$output"; false; }
}

@test "R68: file times in the kernel come only from vbw_mtime" {
  run grep -rnE 'stat -[fc] ' "$PLUGIN_ROOT/lib" "$PLUGIN_ROOT/bin" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts"
  # The one reader, vbw_mtime in core.sh, is the only line allowed.
  [ -z "$(printf '%s\n' "$output" | grep -v 'core.sh:[0-9]*:  t=\$(stat -c %Y')" ] || { echo "$output"; false; }
}
