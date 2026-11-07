#!/usr/bin/env bats
# R223 (D523, #709): jq 1.7 is the floor. vbw doctor fails a jq below 1.7, naming the
# installed version and the floor, with the jq releases page and Debian 12's
# bookworm-backports package as the fix; 1.7.0, 1.7.1 and 1.8.x pass as "jq <version>";
# a missing jq keeps the "jq is missing" line. Every other vbw command refuses up front
# with doctor's one-line message and its fix on stderr, exits non-zero and writes
# nothing: one jq --version per kernel command, none in the hooks or the status line.
# tools/check-jq-builtins.sh refuses, in plugin/**/*.jq and in the jq programs inside
# plugin/**/*.sh, the builtins added after 1.7.0 unless the file defines the name itself.
# README.md and docs/diagnostics.md state the floor and the fix; every CI shard prints
# jq --version beside bash --version. L1: a stand-in jq first on PATH answers the version
# asked for and hands every other call to the real jq.

bats_require_minimum_version 1.5.0

load helper

setup() {
  vbw_setup
  vbw_git_project
}

teardown() { vbw_teardown; }

RELEASES='github.com/jqlang/jq/releases'
BACKPORTS='apt install -t bookworm-backports jq'

# fake_jq VERSION: a jq first on PATH (FAKE_PATH) that answers "jq-VERSION" to --version,
# logging each such call to $TEST_ROOT/versions, and runs the real jq for anything else.
# With VERSION "none" it answers nothing to --version (a jq that is not there).
fake_jq() {
  local real
  real=$(command -v jq)
  mkdir -p "$TEST_ROOT/fake"
  {
    printf '#!/bin/sh\n'
    printf 'case "$1" in --version) echo x >> "%s/versions"; ' "$TEST_ROOT"
    if [ "$1" = none ]; then printf 'exit 127 ;; esac\n'; else printf 'echo "jq-%s"; exit 0 ;; esac\n' "$1"; fi
    printf 'exec "%s" "$@"\n' "$real"
  } > "$TEST_ROOT/fake/jq"
  chmod +x "$TEST_ROOT/fake/jq"
  FAKE_PATH="$TEST_ROOT/fake:$PATH"
}

# fix_after REGEX: the fix line that follows the doctor line matching REGEX.
fix_after() { printf '%s\n' "$output" | awk -v re="$1" '$0 ~ re { keep = 1; next } /^    fix: / && keep { print; exit } { keep = 0 }'; }

@test "R223 kernel: vbw doctor with jq 1.6 on PATH fails naming the installed version and the 1.7 floor, with the releases page and the Debian 12 backports package as the fix" {
  fake_jq 1.6
  PATH="$FAKE_PATH" run "$VBW" doctor < /dev/null
  [ "$status" -eq 1 ] || { printf '%s\n' "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^✗ jq 1\.6 .*1\.7' || { echo "no fail line names jq 1.6 and the 1.7 floor:"; printf '%s\n' "$output"; false; }
  local fix
  fix=$(fix_after '^✗ jq 1\.6 ')
  [[ "$fix" == *"$RELEASES"* && "$fix" == *"$BACKPORTS"* ]] || { echo "the fix line lacks the releases page or the backports package: $fix"; printf '%s\n' "$output"; false; }
}

@test "R223 kernel: jq 1.7.0, 1.7.1 and 1.8.x each pass doctor as jq <version>" {
  local v
  for v in 1.7.0 1.7.1 1.8.1; do
    fake_jq "$v"
    PATH="$FAKE_PATH" run "$VBW" doctor < /dev/null
    [[ "$output" == *"✓ jq $v"* ]] || { echo "jq $v does not pass:"; printf '%s\n' "$output"; false; }
    [[ "$output" != *"✗ jq"* ]] || { printf '%s\n' "$output"; false; }
  done
}

@test "R223 kernel: a jq that is not there keeps today's 'jq is missing' line" {
  fake_jq none
  PATH="$FAKE_PATH" run "$VBW" doctor < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ jq is missing"* ]] || { printf '%s\n' "$output"; false; }
}

@test "R223 kernel: every vbw command but doctor refuses a jq below 1.7 before doing anything: doctor's message and fix on stderr, exit non-zero, nothing written, one jq --version per command" {
  fake_jq 1.6
  # Before init: init creates no .vbw folder.
  PATH="$FAKE_PATH" run --separate-stderr "$VBW" init < /dev/null
  [ "$status" -ne 0 ] || { printf '%s\n' "$output"; false; }
  [ ! -e .vbw ] || { echo "vbw init wrote .vbw with jq 1.6"; false; }
  [ -z "$output" ] || { echo "stdout is not empty: $output"; false; }
  [[ "$stderr" == *"jq 1.6"* && "$stderr" == *"1.7"* && "$stderr" == *"$RELEASES"* && "$stderr" == *"$BACKPORTS"* ]] || { echo "stderr: $stderr"; false; }
  # In a project: the record is untouched, and each command asks jq its version exactly once.
  "$VBW" init > /dev/null
  cp .vbw/record.json "$TEST_ROOT/before.json"
  local cmd
  for cmd in status next prove "show roadmap" "spec check" config "run end" "todo list"; do
    rm -f "$TEST_ROOT/versions"
    # shellcheck disable=SC2086 # the command's words
    PATH="$FAKE_PATH" run --separate-stderr "$VBW" $cmd < /dev/null
    [ "$status" -ne 0 ] || { echo "vbw $cmd ran with jq 1.6:"; printf '%s\n' "$output"; false; }
    [ -z "$output" ] || { echo "vbw $cmd printed to stdout with jq 1.6: $output"; false; }
    [[ "$stderr" == *"jq 1.6"* && "$stderr" == *"1.7"* && "$stderr" == *"$RELEASES"* ]] || { echo "vbw $cmd: $stderr"; false; }
    [ "$(wc -l < "$TEST_ROOT/versions" | tr -d ' ')" -eq 1 ] || { echo "vbw $cmd asked jq its version $(wc -l < "$TEST_ROOT/versions" | tr -d ' ') times"; false; }
  done
  cmp .vbw/record.json "$TEST_ROOT/before.json"
  [ ! -e .vbw/runtime/next.json ] || { echo "vbw next wrote its answer with jq 1.6"; false; }
  # doctor itself still runs its fuller report.
  PATH="$FAKE_PATH" run "$VBW" doctor < /dev/null
  [[ "$output" == *"✗ jq 1.6"* && "$output" == *"git "* ]] || { printf '%s\n' "$output"; false; }
}

@test "R223 kernel: the hooks and the status line gain no version check: none of them asks jq its version" {
  run grep -rnE 'jq (--version|-V)' "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts"
  [ -z "$output" ] || { printf '%s\n' "$output"; false; }
}

@test "R223 standards: tools/check-jq-builtins.sh refuses a jq program that uses a builtin newer than 1.7.0 unless the file defines the name, naming file and line, and passes the plugin" {
  local tool="$REPO_ROOT/tools/check-jq-builtins.sh"
  [ -f "$tool" ] || { echo "tools/check-jq-builtins.sh is missing"; false; }
  mkdir -p "$TEST_ROOT/fx"
  printf '.name | trim\n' > "$TEST_ROOT/fx/a.jq"
  printf 'def trim: sub("^\\\\s+"; "");\n.name | trim\n' > "$TEST_ROOT/fx/b.jq"
  printf '#!/bin/sh\nx=$(jq -r %s "$1")\n' "'.[] | abs'" > "$TEST_ROOT/fx/c.sh"
  printf '#!/bin/sh\nx=$(jq -r %s "$1")\n' "'.[] | ltrimstr(\"a\") | rtrimstr(\"b\") | add'" > "$TEST_ROOT/fx/d.sh"
  printf '[.[] | .n] | add(.[])\n' > "$TEST_ROOT/fx/e.jq"
  printf 'if has_decnum_like then 1 else toarray end\n' > "$TEST_ROOT/fx/f.jq"
  local f
  for f in a.jq c.sh e.jq f.jq; do
    run bash "$tool" "$TEST_ROOT/fx/$f"
    [ "$status" -eq 1 ] || { echo "$f passed:"; printf '%s\n' "$output"; false; }
    [[ "$output" == *"$f:"* ]] || { echo "$f: the refusal does not name the file and line: $output"; false; }
  done
  [[ "$(bash "$tool" "$TEST_ROOT/fx/a.jq" 2>&1 || true)" == *"a.jq:1:"*trim* ]]
  [[ "$(bash "$tool" "$TEST_ROOT/fx/c.sh" 2>&1 || true)" == *"c.sh:2:"*abs* ]]
  [[ "$(bash "$tool" "$TEST_ROOT/fx/e.jq" 2>&1 || true)" == *add* ]]
  [[ "$(bash "$tool" "$TEST_ROOT/fx/f.jq" 2>&1 || true)" == *toarray* ]]
  [[ "$(bash "$tool" "$TEST_ROOT/fx/f.jq" 2>&1 || true)" != *have_decnum* ]]
  for f in b.jq d.sh; do
    run bash "$tool" "$TEST_ROOT/fx/$f"
    [ "$status" -eq 0 ] || { echo "$f was refused:"; printf '%s\n' "$output"; false; }
    [ -z "$output" ] || { echo "$f: $output"; false; }
  done
  # The plugin itself passes: plugin/lib/failing-tests.jq defines its own trim.
  run bash "$tool"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
}

@test "R223 standards: tools/check-jq-builtins.sh refuses a call of one of jq's private builtins (a name starting with _, such as _nwise, which jq 1.8 removed) unless the file defines it; a shell variable named _x passes" {
  local tool="$REPO_ROOT/tools/check-jq-builtins.sh"
  mkdir -p "$TEST_ROOT/fx"
  printf '#!/bin/sh\njq -sc %s\n' "'[_nwise(2) | {key: .[0], value: .[1]}] | from_entries'" > "$TEST_ROOT/fx/g.sh"
  printf 'def _pair(f): [f, f];\n_pair(.a)\n' > "$TEST_ROOT/fx/h.jq"
  printf '#!/bin/sh\nlocal _u\n_u=$(printf %%s "$1" | jq -c .)\n' > "$TEST_ROOT/fx/i.sh"
  run bash "$tool" "$TEST_ROOT/fx/g.sh"
  [ "$status" -eq 1 ] || { echo "g.sh passed:"; printf '%s\n' "$output"; false; }
  [[ "$output" == *"g.sh:2: _nwise( is a private jq builtin"* ]] || { echo "the refusal does not name the file, line and builtin: $output"; false; }
  local f
  for f in h.jq i.sh; do
    run bash "$tool" "$TEST_ROOT/fx/$f"
    [ "$status" -eq 0 ] || { echo "$f was refused:"; printf '%s\n' "$output"; false; }
  done
  run bash "$tool"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
}

@test "R223 standards: each CI shard prints jq --version beside bash --version" {
  local ci="$REPO_ROOT/.github/workflows/ci.yml" b j
  b=$(grep -c 'bash --version' "$ci" || true)
  j=$(grep -c 'jq --version' "$ci" || true)
  [ "$b" -ge 1 ]
  [ "$j" -eq "$b" ] || { echo "ci.yml prints bash --version $b times and jq --version $j times"; false; }
  awk '/bash --version/ { want = NR + 1; next } NR == want && !/jq --version/ { bad = 1 } END { exit bad }' "$ci" || {
    echo "a jq --version does not follow its bash --version line"
    false
  }
}

@test "R223 docs: README.md and docs/diagnostics.md state jq 1.7 or newer, with the releases page and the Debian 12 backports package as the way to a current jq" {
  grep -q '1\.7 or newer' "$REPO_ROOT/README.md" || { echo "README.md does not state jq 1.7 or newer"; false; }
  grep -qF "$RELEASES" "$REPO_ROOT/README.md" || { echo "README.md does not name the jq releases page"; false; }
  grep -q '1\.7 or newer' "$REPO_ROOT/docs/diagnostics.md" || { echo "docs/diagnostics.md does not state jq 1.7 or newer"; false; }
  grep -qF "$RELEASES" "$REPO_ROOT/docs/diagnostics.md" || { echo "docs/diagnostics.md does not name the jq releases page"; false; }
  grep -qF "$BACKPORTS" "$REPO_ROOT/docs/diagnostics.md" || { echo "docs/diagnostics.md does not name the backports package"; false; }
}
