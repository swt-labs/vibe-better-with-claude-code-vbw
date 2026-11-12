#!/usr/bin/env bats
# R167: the wiring of single-file test runs into vbw prove: what the evidence
# holds (one entry per test file, the test command's place taken by one
# aggregate), what vbw show evidence lists, and where a failing test file's
# output is kept. The behaviors themselves are in testfiles-form.bats and
# testfiles-run.bats. L1.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p tests
  printf 'exit 0\n' > tests/t_a.sh
  printf 'echo boom-b\nexit 1\n' > tests/t_b.sh
  printf 'exit 0\n' > tests/all.sh
  printf 'exit 0\n' > tests/c1.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["tests/c1.sh"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' \
    .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

@test "R167: the evidence holds one entry per test file and the test command's place is one aggregate that fails with them" {
  vbw_run prove
  [ "$status" -ne 0 ]
  jq -e '.evidence.test_files | (keys == ["tests/t_a.sh","tests/t_b.sh"]) and .["tests/t_a.sh"].status == "pass" and .["tests/t_b.sh"].status == "fail"' .vbw/record.json
  jq -e '.evidence.commands.test | .status == "fail" and .of_files == true' .vbw/record.json
  jq -e '.evidence.passed == false' .vbw/record.json
}

@test "R167: the summary names the failing test file and counts the test files" {
  vbw_run prove
  printf '%s\n' "$output" | grep -qE '^ +tests/t_b\.sh fail \(exit 1\)' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +test files: 2 ran, 0 reused$' || { echo "$output"; false; }
  ! printf '%s\n' "$output" | grep -q 'test command ran whole'
}

@test "R167: vbw show evidence lists the test files, not the aggregate" {
  "$VBW" prove > /dev/null || true
  vbw_run show evidence
  [[ "$output" == *"tests/t_a.sh pass"* ]] || { echo "$output"; false; }
  [[ "$output" == *"tests/t_b.sh fail"* ]] || { echo "$output"; false; }
  [[ "$output" == *"boom-b"* ]] || { echo "$output"; false; }
  [[ "$output" != *"  test "* ]] || { echo "$output"; false; }
}

@test "R167: a failing test file's complete output is kept under the runtime folder" {
  "$VBW" prove > /dev/null || true
  grep -rq 'boom-b' .vbw/runtime/output/
}

@test "R167: a test file inside a submodule is a test file of its own and runs in the proof copy" {
  git init -q "$TEST_ROOT/libsrc"
  mkdir -p "$TEST_ROOT/libsrc/tests"
  printf '[ -f lib/tests/t_lib.sh ]\n' > "$TEST_ROOT/libsrc/tests/t_lib.sh"
  git -C "$TEST_ROOT/libsrc" add tests
  git -C "$TEST_ROOT/libsrc" commit -q -m "chore: seed"
  git -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/libsrc" lib
  sed 's|^- files: tests/t_\*\.sh$|- files: tests/t_*.sh lib/tests/*.sh|' .vbw/spec.md > "$TEST_ROOT/spec.md" && cp "$TEST_ROOT/spec.md" .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore: lib"
  "$VBW" approve > /dev/null
  vbw_run prove
  jq -e '.evidence.test_files | keys == ["lib/tests/t_lib.sh","tests/t_a.sh","tests/t_b.sh"] and .["lib/tests/t_lib.sh"].status == "pass"' .vbw/record.json \
    || { echo "$output"; jq '.evidence.test_files' .vbw/record.json; false; }
  vbw_run prove
  jq -e '.evidence.test_files["lib/tests/t_lib.sh"].reused == true' .vbw/record.json || { echo "$output"; false; }
  # A commit in the submodule runs its test file again.
  printf '[ -f lib/tests/t_lib.sh ]\ntrue\n' > lib/tests/t_lib.sh
  git -C lib commit -q -am "test: lib"
  vbw_run prove
  jq -e '.evidence.test_files["lib/tests/t_lib.sh"] | .status == "pass" and (.reused | not)' .vbw/record.json || { echo "$output"; false; }
}

@test "R167: a pathspec reaches into a submodule only when it names it, and one level deep, as the proof copy holds them" {
  local s
  for s in lib vendor deep; do
    git init -q "$TEST_ROOT/${s}src"
    mkdir -p "$TEST_ROOT/${s}src/tests"
    printf 'true\n' > "$TEST_ROOT/${s}src/tests/t_$s.sh"
    printf 'true\n' > "$TEST_ROOT/${s}src/tests/t_skip.sh"
    git -C "$TEST_ROOT/${s}src" add tests
    git -C "$TEST_ROOT/${s}src" commit -q -m "chore: seed"
  done
  # deep is a submodule of lib: a second level.
  git -C "$TEST_ROOT/libsrc" -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/deepsrc" deep
  git -C "$TEST_ROOT/libsrc" commit -q -m "chore: deep"
  git -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/libsrc" lib
  git -C lib -c protocol.file.allow=always submodule update -q --init
  git -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/vendorsrc" vendor
  # */tests/t_*.sh matches vendor's test file but names no submodule; lib/deep/... names one two levels down;
  # the excludes that name lib, in each of git's spellings, reach into it.
  sed 's|^- files: tests/t_\*\.sh$|- files: tests/t_*.sh lib/tests/*.sh */tests/t_*.sh lib/deep/tests/*.sh :!lib/tests/t_skip.sh :(exclude)lib/tests/t_lib.sh|' .vbw/spec.md > "$TEST_ROOT/spec.md" && cp "$TEST_ROOT/spec.md" .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore: subs"
  "$VBW" approve > /dev/null
  vbw_run prove
  jq -e '.evidence.test_files | keys == ["tests/t_a.sh","tests/t_b.sh"]' .vbw/record.json \
    || { echo "$output"; jq '.evidence.test_files | keys' .vbw/record.json; false; }
}

# log_calls: git and jq on PATH log their names to $TEST_ROOT/calls, then run.
log_calls() {
  local t
  mkdir -p "$TEST_ROOT/logbin"
  for t in git jq; do
    printf '#!/bin/sh\necho %s >> "$TEST_ROOT/calls"\nexec %s "$@"\n' "$t" "$(command -v "$t")" > "$TEST_ROOT/logbin/$t"
    chmod +x "$TEST_ROOT/logbin/$t"
  done
}

@test "#737: without a submodule, listing a form's test files costs one git, as before submodules" {
  log_calls
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  PATH="$TEST_ROOT/logbin:$PATH" vbw_kernel '. "$VBW_LIB/testfiles.sh"; specs=()
    while IFS= read -r a; do specs+=("$a"); done < <(jq -r ".test_files.files[]" "$VBW_RECORD")
    : > "$TEST_ROOT/calls"
    testfiles_ls "${specs[@]}" | tr "\0" "\n" > "$TEST_ROOT/listed"'
  [ "$(tr '\n' ' ' < "$TEST_ROOT/listed")" = "tests/t_a.sh tests/t_b.sh " ] || { cat "$TEST_ROOT/listed"; false; }
  [ "$(sort "$TEST_ROOT/calls" | tr '\n' ' ')" = "git " ] || { cat "$TEST_ROOT/calls"; false; }
}

@test "R167: a test file an approved check runs is not a test file of its own" {
  jq '.checks[0].run = ["sh","tests/t_a.sh"]' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): check runs t_a"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || true
  jq -e '.evidence.test_files | keys == ["tests/t_b.sh"]' .vbw/record.json
}

# R304 (T256): every test runs in some proof. A form may declare the options its approved checks
# use to select some of a file's tests (- filter: <option words>) and the run that leaves those
# tests out (- rest: <argv naming {file} and {filters} once each>; {filters} is the filters the
# approved checks give that file, joined by | or by the form's - join: text). A file named only
# by filtered checks is then a unit that runs that rest, so nothing runs twice (D179). The
# runner below (tests/run.sh) logs its arguments to $RANLOG and runs each "case NAME CODE" line
# of the file that --only selects or --skip leaves out (both regular expressions).

# filtered_form [REST] [JOIN]: the copied project with the runner, test files t_a (three
# passing cases), t_b and t_c, a form with a filter line (--only) and the rest line REST
# ("-": none; default: the runner with --skip {filters}), and four checks: C1 and C2 run
# t_a with a filter each, C3 runs t_b whole, C4 runs t_b with a filter; t_c has no check.
filtered_form() {
  # The default sits in a variable: bash ends ${1-...} at the first }, so {filters} cannot be inside it.
  local def='sh tests/run.sh --skip {filters} {file}'
  local rest="${1-$def}"
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  cat > tests/run.sh << 'SH'
echo "$*" >> "$RANLOG"
only='' skip=''
while [ $# -gt 1 ]; do
  case "$1" in
    --only) only=$2; shift 2 ;;
    --skip) skip=$2; shift 2 ;;
    *) shift ;;
  esac
done
rc=0
while read -r w name code; do
  [ "$w" = case ] || continue
  if [ -n "$only" ] && ! printf '%s\n' "$name" | grep -qE -- "$only"; then continue; fi
  if [ -n "$skip" ] && printf '%s\n' "$name" | grep -qE -- "$skip"; then continue; fi
  echo "ran $name"
  [ "$code" = 0 ] || { echo "$name failed"; rc=1; }
done < "$1"
exit $rc
SH
  printf 'case R1 0\ncase R2 0\ncase K1 0\n' > tests/t_a.sh
  printf 'case R3 0\ncase K2 0\n' > tests/t_b.sh
  printf 'case K3 0\n' > tests/t_c.sh
  {
    printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n'
    printf -- '- run: sh tests/run.sh {file}\n- files: tests/t_*.sh\n- filter: --only\n'
    [ "$rest" = - ] || printf -- '- rest: %s\n' "$rest"
    [ -z "${2:-}" ] || printf -- '- join: %s\n' "$2"
  } > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/run.sh","--only","R1","tests/t_a.sh"], files:["tests/c1.sh"]},
                 {id:"C2", req:"R1", run:["sh","tests/run.sh","--only","R2","tests/t_a.sh"], files:["tests/c1.sh"]},
                 {id:"C3", req:"R1", run:["sh","tests/run.sh","tests/t_b.sh"], files:["tests/c1.sh"]},
                 {id:"C4", req:"R1", run:["sh","tests/run.sh","--only","R3","tests/t_b.sh"], files:["tests/c1.sh"]}]' \
    .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): filtered checks"
  "$VBW" approve > /dev/null
}

# ran_line ARGS: how many times the runner was called with exactly ARGS.
ran_line() { grep -cxF -- "$1" "$RANLOG" || true; }

@test "R304: a test file named only by filtered checks is a unit that runs the tests no filter selects, and nothing runs twice" {
  filtered_form
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; cat "$RANLOG"; false; }
  jq -e '.evidence.test_files | has("tests/t_a.sh") and has("tests/t_c.sh")' .vbw/record.json || { jq '.evidence.test_files' .vbw/record.json; false; }
  [ "$(ran_line '--skip R1|R2 tests/t_a.sh')" -eq 1 ] || { echo "the rest of t_a did not run once:"; cat "$RANLOG"; false; }
  [ "$(ran_line '--only R1 tests/t_a.sh')" -eq 1 ] && [ "$(ran_line '--only R2 tests/t_a.sh')" -eq 1 ] || { cat "$RANLOG"; false; }
  [ "$(ran_line 'tests/t_a.sh')" -eq 0 ] || { echo "t_a ran whole, so its filtered tests ran twice:"; cat "$RANLOG"; false; }
  [ "$(ran_line 'tests/t_c.sh')" -eq 1 ] || { cat "$RANLOG"; false; }
}

@test "R304: a test file an approved check runs whole stays out of the units, also when a filtered check names it too" {
  filtered_form
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.test_files | has("tests/t_b.sh") | not' .vbw/record.json || { jq '.evidence.test_files' .vbw/record.json; false; }
  [ "$(ran_line 'tests/t_b.sh')" -eq 1 ] || { echo "t_b did not run once, as its check:"; cat "$RANLOG"; false; }
  ! grep -q -- '--skip R3' "$RANLOG" || { cat "$RANLOG"; false; }
}

@test "R304: the form's join line joins the filters of a rest run" {
  filtered_form 'sh tests/run.sh --skip {filters} {file}' ' or '
  "$VBW" prove > /dev/null || true
  [ "$(ran_line '--skip R1 or R2 tests/t_a.sh')" -eq 1 ] || { cat "$RANLOG"; false; }
}

@test "R304: with a filter line and no rest line a filtered-only file runs whole as a unit, and the proof says so once, naming the rest line" {
  filtered_form -
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran_line 'tests/t_a.sh')" -eq 1 ] || { cat "$RANLOG"; false; }
  [ "$(printf '%s\n' "$output" | grep -c -- '- rest:')" -eq 1 ] || { echo "the proof does not say once that a rest line would leave out the filtered tests:"; echo "$output"; false; }
}

@test "R304: without a filter line the units are as before: a file an approved check names is never a unit of its own" {
  filtered_form -
  grep -v -- '^- filter:' .vbw/spec.md > "$TEST_ROOT/spec.md" && cp "$TEST_ROOT/spec.md" .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore(vbw): no filter line"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || true
  jq -e '.evidence.test_files | keys == ["tests/t_c.sh"]' .vbw/record.json || { jq '.evidence.test_files' .vbw/record.json; false; }
}

@test "R304: a failing test the rest runs fails the proof, which names the file" {
  filtered_form
  printf 'case R1 0\ncase R2 0\ncase K1 1\n' > tests/t_a.sh
  git add -A && git commit -q -m "test: K1 fails"
  vbw_run prove
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +tests/t_a\.sh fail' || { echo "$output"; false; }
}

@test "R304: a rest unit follows the one reuse rule: reused when nothing it reads changed, run again with the others counted when a filter changes" {
  filtered_form
  "$VBW" prove > /dev/null
  : > "$RANLOG"
  "$VBW" prove > /dev/null
  [ "$(ran_line '--skip R1|R2 tests/t_a.sh')" -eq 0 ] || { echo "the rest unit ran again with nothing changed:"; cat "$RANLOG"; false; }
  jq '.checks |= map(if .id == "C1" then .run = ["sh","tests/run.sh","--only","K1","tests/t_a.sh"] else . end)' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): C1 selects K1"
  "$VBW" approve > /dev/null
  : > "$RANLOG"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran_line '--skip K1|R2 tests/t_a.sh')" -eq 1 ] || { echo "the rest unit did not run again on the changed filter:"; cat "$RANLOG"; false; }
  printf '%s\n' "$output" | grep -qE '^run again: 2 of 6 units' || { echo "the opening line does not count the rest unit:"; echo "$output"; false; }
}

@test "R304 spec: the spec refuses a rest line that does not name {file} and {filters} once each, and a rest line without a filter line, naming the line" {
  filtered_form
  local bad
  for bad in '- rest: sh tests/run.sh --skip x {file}' '- rest: sh tests/run.sh --skip {filters}' '- rest: sh tests/run.sh {filters} {filters} {file}'; do
    sed "s|^- rest: .*|$bad|" .vbw/spec.md > "$TEST_ROOT/spec.md"
    cp "$TEST_ROOT/spec.md" .vbw/spec.md
    vbw_run spec check
    [ "$status" -ne 0 ] && [[ "$output" == *"line "* ]] && [[ "$output" == *"{filters}"* ]] || { echo "accepted: $bad"; echo "$output"; false; }
  done
  sed -e 's|^- rest: .*|- rest: sh tests/run.sh --skip {filters} {file}|' -e '/^- filter:/d' .vbw/spec.md > "$TEST_ROOT/spec.md"
  cp "$TEST_ROOT/spec.md" .vbw/spec.md
  vbw_run spec check
  [ "$status" -ne 0 ] && [[ "$output" == *"filter"* ]] || { echo "a rest line without a filter line was accepted:"; echo "$output"; false; }
}

@test "R304 spec: the record validator refuses a form whose join is empty, whose rest lacks {filters}, or whose rest has no filter" {
  filtered_form 'sh tests/run.sh --skip {filters} {file}' ' or '
  local edit
  for edit in '.test_files[0].join = ""' '.test_files[0].rest = ["sh","tests/run.sh","{file}"]' 'del(.test_files[0].filter)'; do
    jq "$edit" .vbw/record.json > "$TEST_ROOT/edit.json"
    cp .vbw/record.json "$TEST_ROOT/keep.json"
    cp "$TEST_ROOT/edit.json" .vbw/record.json
    vbw_run doctor
    [[ "$output" == *"test_files must be"* ]] || { echo "accepted: $edit"; echo "$output"; false; }
    cp "$TEST_ROOT/keep.json" .vbw/record.json
  done
}

@test "R304 spec: a join line keeps the spaces of a quoted value, in single or double quotes, and reads a bare value as it is" {
  filtered_form 'sh tests/run.sh --skip {filters} {file}' ' or '
  grep -q '^- join:' .vbw/spec.md || { cat .vbw/spec.md; false; }
  local line want
  for line in "- join: ' or '" '- join: " or "' '- join: ,'; do
    want=' or '; [ "$line" != '- join: ,' ] || want=','
    sed "s|^- join: .*|$line|" .vbw/spec.md > "$TEST_ROOT/spec.md"
    cp "$TEST_ROOT/spec.md" .vbw/spec.md
    vbw_run spec sync
    [ "$status" -eq 0 ] || { echo "$line"; echo "$output"; false; }
    [ "$(jq -r '.test_files[0].join' .vbw/record.json)" = "$want" ] || { echo "$line gave $(jq -c '.test_files[0].join' .vbw/record.json)"; false; }
  done
}
