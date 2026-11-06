#!/usr/bin/env bats
# R195 (T165; docs/proof.md): the complete output of every failing check or
# test file is kept after vbw fix done and vbw check too, as it is after
# vbw prove (R118), in .vbw/runtime/output/ under the same names (C1.log,
# file-<id>.log). vbw fix done replaces an older file, a pass removes that
# unit's file, a reused unit leaves it, and the files outlive the command and the
# removal of the proof copies. vbw check keeps each failing or timed-out check's
# output and says where it is under the check's line, whose meaning is unchanged;
# a passing check removes nothing (the proof's or another Dev's failure stays
# readable); --expect-red keeps nothing; two vbw check runs of the same check at
# once each leave a whole file. Kept output is never committed and never written
# outside .vbw/runtime. L1: the kernel on a fixture project.

load helper
load fixture-helper

shop_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n- R3 [auto] A customer can refund\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'unpaid\n' > src/pay.txt
  printf 'first\n' > src/msg.txt
  printf 'receipt\n' > src/two.txt
  printf 'refund\n' > src/three.txt
  # lines.sh ID N: print "ID line i <message>" N times.
  printf 'i=0; while [ "$i" -lt "$2" ]; do i=$((i + 1)); echo "$1 line $i $(cat src/msg.txt)"; done\n' > tests/lines.sh
  # C1 prints 50 lines, then fails until src/pay.txt says paid.
  printf 'sh tests/lines.sh C1 50; grep -qx paid src/pay.txt\n' > tests/c1.sh
  # C2 reads src/two.txt and passes; C3 passes reading nothing.
  printf 'grep -q . src/two.txt\n' > tests/c2.sh
  printf 'echo fine\n' > tests/ok.sh
  # many.sh ID: 400 lines of its own, then fail.
  printf 'sh tests/lines.sh "$1" 400; exit 1\n' > tests/many.sh
  # The test file t_a prints 30 lines, then fails until src/pay.txt says paid.
  printf 'sh tests/lines.sh TA 30; grep -qx paid src/pay.txt\n' > tests/t_a.sh
  printf 'echo all\n' > tests/all.sh
  edit_record '.checks = [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
                          {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]},
                          {id: "C3", req: "R3", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]}]
    | .phases = [{id: "P1", title: "Shop", reqs: ["R1", "R2", "R3"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt", "src/msg.txt"], after: [], status: "done"},
                {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/two.txt"], after: [], status: "done"},
                {id: "P1.3", phase: "P1", title: "Refund", reqs: ["R3"], files: ["src/three.txt"], after: [], status: "done"}]'
  git add -A && git commit -q -m "chore(vbw): built"
  "$VBW" approve > /dev/null
  # The proof fails C1 and tests/t_a.sh: fixes for R1 and the test command, and both kept files.
  "$VBW" prove > /dev/null 2>&1 || true
  F_REQ=$(jq -r '[.fixes[] | select(.req == "R1")][0].id // empty' .vbw/record.json)
  F_TEST=$(jq -r '[.fixes[] | select(.command == "test")][0].id // empty' .vbw/record.json)
  [ -n "$F_REQ" ] && [ -n "$F_TEST" ] || { echo "the proof opened no fixes"; jq .fixes .vbw/record.json; return 1; }
  TA_LOG=$(find "$OUT" -maxdepth 1 -name 'file-*.log' -print | sed "s|^$OUT/||")
  [ "$(printf '%s\n' "$TA_LOG" | grep -c .)" -eq 1 ] || { echo "no single kept file for tests/t_a.sh: $TA_LOG"; return 1; }
  export F_REQ F_TEST TA_LOG
  rm -rf "$OUT"
}

setup_file() { fixture_build shop shop_project; }
setup() {
  fixture_copy shop
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

OUT=.vbw/runtime/output

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
# expected ID N: what lines.sh ID N prints with the current message.
expected() { sh tests/lines.sh "$1" "$2"; }
# user_commit FILE TEXT: the user changes FILE and commits it.
user_commit() {
  printf '%s\n' "$2" > "$1"
  git add -- "$1" && git commit -q -m "fix: $1"
}

@test "R195: vbw fix done keeps the complete output of every failing check and test file under vbw prove's names, replacing an older file; the files outlive the command and the proof copies" {
  mkdir -p "$OUT"
  printf 'an older failure\n' > "$OUT/C1.log"
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  run "$VBW" fix done "$F_REQ" "$F_TEST" < /dev/null
  [ "$status" -ne 0 ]
  cmp "$OUT/C1.log" <(expected C1 50)
  cmp "$OUT/$TA_LOG" <(expected TA 30)
  [ "$(find "$OUT" -name '*.log' | wc -l | tr -d ' ')" = 2 ]
  # The proof copies are kept for the next command (#738), held by none.
  [ -z "$(find .vbw/runtime -maxdepth 1 \( -name 'proof.*' ! -name 'proof.keep.*' -o -name 'run.*' \) -print)" ]
  [ -z "$(find .vbw/runtime -path '*/proof.keep.*/pid' -print)" ]
}

@test "R195: in vbw fix done a pass removes that unit's kept file and a reused unit leaves it" {
  mkdir -p "$OUT"
  printf 'an earlier failure\n' > "$OUT/C2.log"
  printf 'an earlier failure\n' > "$OUT/C3.log"
  # C2 reads src/two.txt: changed, it runs and passes; C3 is unchanged: reused.
  user_commit src/two.txt "receipt again"
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  run "$VBW" fix done "$F_REQ" < /dev/null
  [[ "$output" == *"C2 pass"* ]] || { echo "$output"; false; }
  [[ "$output" == *"C3 unchanged since its pass"* ]] || { echo "$output"; false; }
  [ ! -e "$OUT/C2.log" ]
  [ "$(cat "$OUT/C3.log")" = 'an earlier failure' ]
}

@test "R195: vbw check keeps a failing check's complete output and says where it is under the check's own line; a pass removes nothing; --expect-red keeps nothing" {
  run "$VBW" check C1 < /dev/null
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q '^C1 fail [0-9.]*s: ' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q "full output: $OUT/C1.log" || { echo "$output"; false; }
  cmp "$OUT/C1.log" <(expected C1 50)
  printf 'the proof'"'"'s failure\n' > "$OUT/C2.log"
  run "$VBW" check C2 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$OUT/C2.log")" = "the proof's failure" ]
  rm -f "$OUT/C1.log"
  run "$VBW" check --expect-red C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$OUT/C1.log" ]
}

@test "R195: two vbw check runs of the same check at once each leave a whole file" {
  edit_record '(.checks[] | select(.id == "C1")).run = ["sh", "tests/many.sh", "C1"] | (.checks[] | select(.id == "C1")).files = ["tests/many.sh"]'
  git add -A && git commit -q -m "chore(vbw): many"
  "$VBW" approve > /dev/null
  "$VBW" check C1 > "$TEST_ROOT/one.out" 2>&1 < /dev/null &
  "$VBW" check C1 > "$TEST_ROOT/two.out" 2>&1 < /dev/null &
  wait
  cmp "$OUT/C1.log" <(expected C1 400)
  [ "$(find "$OUT" -type f | wc -l | tr -d ' ')" = 1 ]
}

@test "R195: kept output is never committed and never written outside .vbw/runtime" {
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  "$VBW" fix done "$F_REQ" "$F_TEST" > /dev/null 2>&1 || true
  "$VBW" check C1 > /dev/null 2>&1 || true
  [ -f "$OUT/C1.log" ]
  [ -f "$OUT/$TA_LOG" ]
  [ -z "$(git ls-files -- .vbw/runtime)" ]
  [ -z "$(git log --all --format= --name-only | grep -F 'runtime/output')" ]
  [ -z "$(git status --porcelain -- .vbw/runtime)" ]
  # The only copies of the whole output are the kept files (the record and the run store keep tails).
  [ "$(grep -rlF 'C1 line 1 ' "$TEST_ROOT" | grep -v '/\.git/' | sed "s|^$PROJECT/||")" = "$OUT/C1.log" ]
  [ "$(grep -rlF 'TA line 1 ' "$TEST_ROOT" | grep -v '/\.git/' | sed "s|^$PROJECT/||")" = "$OUT/$TA_LOG" ]
}
