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

@test "R167: a test file an approved check runs is not a test file of its own" {
  jq '.checks[0].run = ["sh","tests/t_a.sh"]' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): check runs t_a"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || true
  jq -e '.evidence.test_files | keys == ["tests/t_b.sh"]' .vbw/record.json
}
