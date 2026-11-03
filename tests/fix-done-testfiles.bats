#!/usr/bin/env bats
# R176 (docs/proof.md): for a fix of the test command with an approved
# single-file form, vbw fix done judges every test file of the form by the one
# reuse rule: a file that did not pass in the last proof runs, a file whose
# definition, own content or read list changed since its recorded pass runs,
# every other file is reused (counted, not run). It prints one line per test
# file it ran, a passing one included; a failing one adds the last line of its
# output. Every test file it runs is saved in the clone's run store, so the next
# vbw prove reuses it. Scripts log their runs to $RANLOG. L1.

load helper
load fixture-helper

setup_file() { fixture_build shop fixdone_project; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# fixdone_project: the project every test starts from (a passing proof, then
# a failing one that opened a fix), built once per file.
fixdone_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'c\n' > src/c.txt
  printf 'echo t_a >> "$RANLOG"\n[ ! -e "$TEST_ROOT/fail_a" ] || { echo "t_a broken"; exit 1; }\n' > tests/t_a.sh
  printf 'echo t_b >> "$RANLOG"\ngrep -q . src/b.txt\n' > tests/t_b.sh
  printf 'echo t_c >> "$RANLOG"\ngrep -q . src/c.txt\n' > tests/t_c.sh
  printf 'echo C1 >> "$RANLOG"\ngrep -q . src/a.txt\n' > tests/c1.sh
  printf 'echo all >> "$RANLOG"\n' > tests/all.sh
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  # The second proof fails on tests/t_a.sh and opens a fix for the test command.
  : > "$TEST_ROOT/fail_a"
  run "$VBW" prove < /dev/null
  [ "$status" -eq 1 ] || { echo "the second proof did not fail: $output"; return 1; }
  jq -e '.fixes[0].command == "test" and .fixes[0].status == "open"' .vbw/record.json > /dev/null || { echo "no fix for the test command"; jq .fixes .vbw/record.json; return 1; }
  FIX=$(jq -r '.fixes[0].id' .vbw/record.json)
  FAILED_AT=$(jq -r '.evidence.at' .vbw/record.json)
  : > "$RANLOG"
}

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

ran() { sort "$RANLOG" | tr '\n' ' '; }

# proved_now: the record says a proof passed on the project exactly as it is now
# (trees and the record fingerprint, R175), the way a passing vbw prove leaves it.
proved_now() {
  local code head fp
  code=$(vbw_kernel 'vbw_code_tree'); head=$(vbw_kernel 'vbw_head_tree')
  edit_record '.evidence.passed = true | .evidence.tree = "'"$code"'" | .evidence.head = "'"$head"'"'
  fp=$(vbw_kernel 'jq -c "del(.evidence, .schema)" "$VBW_RECORD" | vbw_sha256')
  edit_record '.evidence.record = "'"$fp"'"'
}

# plan_why KIND: the reasons testfiles_plan gives the test files, for a run of KIND (fix or prove).
plan_why() {
  vbw_kernel '. "$VBW_LIB/checks.sh"; . "$VBW_LIB/testfiles.sh"; VBW_COMMAND_TIMEOUT=3600; mkdir -p "$VBW_RUNTIME"
    r=$(record_read); proofreuse_plan "$r" 0 '"$1"'; testfiles_plan "$r" 0 '"$1"'; printf "%s\n" "$TF_WHY"'
}

@test "R176 (F155): vbw fix done right after a passing proof of this very state reuses every unchanged test file: the nothing-committed reason is vbw prove's alone" {
  rm -f "$TEST_ROOT/fail_a"
  proved_now
  vbw_run fix done "$FIX"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"nothing committed"* && "$output" != *"every candidate"* ]] || { echo "$output"; false; }
  line '^tests/t_a\.sh pass [0-9.]+s ran: last result failed$'
  line "^tests/t_b\\.sh unchanged since its pass \\($FAILED_AT\\)\$"
  line "^tests/t_c\\.sh unchanged since its pass \\($FAILED_AT\\)\$"
  line '^test files: 1 ran, 2 reused$'
  [ "$(ran)" = "t_a " ] || { echo "ran: $(ran)"; false; }
}

@test "R176 (F152): for vbw fix done the test files never meet the proof's nothing-committed reason: with a passing proof of this very state, fix reuses them and prove would not" {
  proved_now
  run plan_why fix
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s' "$output" | tail -1 | jq -c 'to_entries | map(select(.value | test("nothing committed")))')" = "[]" ] || { echo "$output"; false; }
  run plan_why prove
  [ "$(printf '%s' "$output" | tail -1 | jq -c '[.[] | select(test("nothing committed"))] | length')" = "3" ] || { echo "$output"; false; }
}
store() { cat "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"; }

# line REGEX: exactly one line of $output matches REGEX.
line() {
  local n
  n=$(printf '%s\n' "$output" | grep -cE -- "$1" || true)
  [ "$n" -eq 1 ] || { echo "expected one line matching $1, found $n in:"; echo "$output"; false; }
}

@test "R176: the failed file and a file whose read list changed run and are named; the rest are reused and counted" {
  rm -f "$TEST_ROOT/fail_a"
  printf 'more\n' >> src/c.txt && git commit -q -am "fix: c"
  vbw_run fix done "$FIX"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  line '^tests/t_a\.sh pass [0-9.]+s ran: last result failed$'
  line '^tests/t_c\.sh pass [0-9.]+s ran: src/c\.txt changed$'
  line "^tests/t_b\\.sh unchanged since its pass \\($FAILED_AT\\)\$"
  line "^C1 unchanged since its pass \\($FAILED_AT\\)\$"
  line '^checks: 0 ran, 1 reused$'
  line '^test files: 2 ran, 1 reused$'
  line "^$FIX fixed: vbw prove decides\$"
  [ "$(ran)" = "t_a t_c " ] || { echo "ran: $(ran)"; false; }
  # Both count lines come after every per-unit line, checks and test files alike (F145).
  local last_unit counts
  last_unit=$(printf '%s\n' "$output" | grep -nE '^(C[0-9]+|tests/[^ ]+) ' | cut -d: -f1 | sort -n | tail -1)
  counts=$(printf '%s\n' "$output" | grep -nE '^checks: ' | cut -d: -f1)
  [ -n "$last_unit" ] && [ "$last_unit" -lt "$counts" ] || { echo "$output"; false; }
  [ "$counts" -lt "$(printf '%s\n' "$output" | grep -nE '^test files: ' | cut -d: -f1)" ] || { echo "$output"; false; }
}

@test "R176: a test file that still fails adds the last line of its output; the fix stays open and the exit code is non-zero" {
  vbw_run fix done "$FIX"
  [ "$status" -eq 1 ]
  line '^tests/t_a\.sh fail \(exit 1\) [0-9.]+s ran: last result failed: t_a broken$'
  line '^test files: 1 ran, 2 reused$'
  [[ "$output" == *"$FIX: these test files still do not pass: tests/t_a.sh fail"* ]] || { echo "$output"; false; }
  jq -e --arg f "$FIX" '(.fixes[] | select(.id == $f)).status == "open"' .vbw/record.json
  [ "$(ran)" = "t_a " ] || { echo "ran: $(ran)"; false; }
}

@test "R176: a changed test file runs again on its own content" {
  rm -f "$TEST_ROOT/fail_a"
  printf '# edited\n' >> tests/t_b.sh && git commit -q -am "test: b"
  vbw_run fix done "$FIX"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  line '^tests/t_b\.sh pass [0-9.]+s ran: tests/t_b\.sh changed$'
  line '^test files: 2 ran, 1 reused$'
  [ "$(ran)" = "t_a t_b " ] || { echo "ran: $(ran)"; false; }
}

@test "R176: a test file fix done ran is saved in the run store and the next vbw prove reuses it" {
  local at
  rm -f "$TEST_ROOT/fail_a"
  vbw_run fix done "$FIX"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  store | jq -e '.runs["file:tests/t_a.sh"] | .status == "pass" and (.tree | type == "string") and (.fp | type == "string") and (.reads | type == "array") and (.at | type == "string")' > /dev/null || { store; false; }
  at=$(store | jq -r '.runs["file:tests/t_a.sh"].at')
  : > "$RANLOG"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  line "^  tests/t_a\\.sh pass [0-9.]+s reused \\(proof of $at\\)\$"
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; echo "$output"; false; }
  jq -e '.evidence.passed == true' .vbw/record.json
}

@test "R176: with a cause (no earlier recorded run) every test file runs with no 'ran:' part, the cause prints once and the count is the true total" {
  rm -f "$TEST_ROOT/fail_a"
  rm -f "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"
  vbw_run fix done "$FIX"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  line '^every candidate check runs: this clone has no earlier recorded run$'
  line '^tests/t_a\.sh pass [0-9.]+s$'
  line '^tests/t_b\.sh pass [0-9.]+s$'
  line '^tests/t_c\.sh pass [0-9.]+s$'
  printf '%s\n' "$output" | grep -F 'tests/t_' | grep -qF 'ran:' && { echo "$output"; false; }
  line '^test files: 3 ran, 0 reused$'
  [ "$(ran)" = "C1 t_a t_b t_c " ] || { echo "ran: $(ran)"; false; }
}
