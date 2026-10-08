#!/usr/bin/env bats
# R118 (docs/proof.md): when a check or a project command fails or times out in
# vbw prove, its complete output is kept in .vbw/runtime/output/ (<check id>.log,
# command-<name>.log): one file each, holding the latest failure; a later pass
# removes it, a reused result leaves it. vbw show fix names the kept file of
# every failing check of the fix's requirement and of every failing project
# command (--json: "kept"), and says when it is not kept. Kept output is never
# committed and never written outside .vbw/runtime. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n- R3 [auto] A customer can refund\n' > .vbw/spec.md
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
  # C2 exits 0 but never prints the line its output rule wants.
  printf 'sh tests/lines.sh C2 30\n' > tests/c2.sh
  printf 'echo fine\n' > tests/ok.sh
  # slow.sh prints 30 lines, then outlives its timeout.
  printf 'sh tests/lines.sh SLOW 30; sleep 20\n' > tests/slow.sh
  # many.sh ID: 400 lines of its own, then fail.
  printf 'sh tests/lines.sh "$1" 400; exit 1\n' > tests/many.sh
  printf 'sh tests/lines.sh TEST 40; exit 1\n' > tests/cmd.sh
  git add -A && git commit -q -m "chore(test): shop"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# plan CHECKS_JSON [COMMANDS_JSON]: one phase, a plan per requirement, these
# checks (and project commands); approved and built.
plan() {
  local cmds="${2:-}"
  [ -n "$cmds" ] || cmds='{}'
  edit_record ".checks = $1 | .commands = $cmds
    | .phases = [{id: \"P1\", title: \"Shop\", reqs: [\"R1\", \"R2\", \"R3\"], milestone: \"M1\"}]
    | .plans = [{id: \"P1.1\", phase: \"P1\", title: \"Pay\", reqs: [\"R1\"], files: [\"src/pay.txt\", \"src/msg.txt\"], after: [], status: \"planned\"},
                {id: \"P1.2\", phase: \"P1\", title: \"Receipt\", reqs: [\"R2\"], files: [\"src/two.txt\"], after: [], status: \"planned\"},
                {id: \"P1.3\", phase: \"P1\", title: \"Refund\", reqs: [\"R3\"], files: [\"src/three.txt\"], after: [], status: \"planned\"}]"
  git add .vbw && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  edit_record '.plans[].status = "done"'
  git add .vbw && git commit -q -m "chore(vbw): built"
}

# expected ID N: what lines.sh ID N prints with the current message.
expected() { sh tests/lines.sh "$1" "$2"; }

# user_commit FILE TEXT: the user changes FILE and commits it.
user_commit() {
  printf '%s\n' "$2" > "$1"
  git add -- "$1" && git commit -q -m "fix: $1"
}

fix_of() { jq -r --arg q "$1" '.fixes[] | select(.req == $q or .command == $q) | .id' .vbw/record.json; }

OUT=.vbw/runtime/output

@test "R118: a check that fails on its exit code, and one that misses its expected output, each keep their complete output" {
  plan '[{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
         {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"], output: "^all good$"},
         {id: "C3", req: "R3", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]}]'
  vbw_run prove
  [ "$status" -ne 0 ]
  jq -e '.evidence.checks.C1.status == "fail" and .evidence.checks.C2.status == "fail" and .evidence.checks.C3.status == "pass"' .vbw/record.json
  cmp "$OUT/C1.log" <(expected C1 50)
  cmp "$OUT/C2.log" <(expected C2 30)
  [ ! -e "$OUT/C3.log" ]
  # The proof's clean copy and its scratch folders are gone; the kept files stay.
  [ -z "$(find .vbw/runtime -maxdepth 1 \( -name 'proof.*' -o -name 'run.*' \) -print)" ]
}

@test "R118: a check that times out keeps its complete output" {
  plan '[{id: "C1", req: "R1", run: ["sh", "tests/slow.sh"], files: ["tests/slow.sh"], timeout: 2},
         {id: "C2", req: "R2", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]},
         {id: "C3", req: "R3", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]}]'
  vbw_run prove
  [ "$status" -ne 0 ]
  jq -e '.evidence.checks.C1.status == "timeout"' .vbw/record.json
  cmp "$OUT/C1.log" <(expected SLOW 30)
}

@test "R118: a project command that fails keeps its complete output" {
  plan '[{id: "C1", req: "R1", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]},
         {id: "C2", req: "R2", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]},
         {id: "C3", req: "R3", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]}]' '{test: ["sh", "tests/cmd.sh"]}'
  vbw_run prove
  [ "$status" -ne 0 ]
  jq -e '.evidence.commands.test.status == "fail"' .vbw/record.json
  cmp "$OUT/command-test.log" <(expected TEST 40)
}

@test "R118: a project command that times out keeps its complete output" {
  # A copy of the plugin whose project-command timeout is 2 seconds instead of 900.
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  local f
  f=$(grep -rl 'VBW_COMMAND_TIMEOUT=900' "$TEST_ROOT/plugin/lib")
  [ -n "$f" ]
  sed 's/VBW_COMMAND_TIMEOUT=900/VBW_COMMAND_TIMEOUT=2/' "$f" > "$TEST_ROOT/t" && cp "$TEST_ROOT/t" "$f"
  VBW="$TEST_ROOT/plugin/bin/vbw"
  plan '[{id: "C1", req: "R1", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]},
         {id: "C2", req: "R2", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]},
         {id: "C3", req: "R3", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]}]' '{test: ["sh", "tests/slow.sh"]}'
  vbw_run prove
  [ "$status" -ne 0 ]
  jq -e '.evidence.commands.test.status == "timeout"' .vbw/record.json
  cmp "$OUT/command-test.log" <(expected SLOW 30)
}

@test "R118: each check has one kept file holding its latest failure; a later pass removes it, a reused result leaves it" {
  plan '[{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
         {id: "C2", req: "R2", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]},
         {id: "C3", req: "R3", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]}]'
  "$VBW" prove > /dev/null || true
  cmp "$OUT/C1.log" <(expected C1 50)
  # A new failure replaces the old one.
  user_commit src/msg.txt second
  "$VBW" prove > /dev/null || true
  cmp "$OUT/C1.log" <(expected C1 50)
  grep -q 'second' "$OUT/C1.log"
  [ "$(find "$OUT" -name 'C1*' | wc -l | tr -d ' ')" = 1 ]
  # C2's file (left by an earlier failure) stays while C2's pass is reused.
  printf 'an earlier failure\n' > "$OUT/C2.log"
  user_commit src/pay.txt paid
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C1.status == "pass" and (.evidence.checks.C1.reused | not) and .evidence.checks.C2.reused == true' .vbw/record.json
  [ ! -e "$OUT/C1.log" ]
  [ "$(cat "$OUT/C2.log")" = 'an earlier failure' ]
}

@test "R118: checks that fail in parallel each keep their own complete, uninterrupted output" {
  "$VBW" config set check_jobs 3 > /dev/null
  plan '[{id: "C1", req: "R1", run: ["sh", "tests/many.sh", "C1"], files: ["tests/many.sh"]},
         {id: "C2", req: "R2", run: ["sh", "tests/many.sh", "C2"], files: ["tests/many.sh"]},
         {id: "C3", req: "R3", run: ["sh", "tests/many.sh", "C3"], files: ["tests/many.sh"]}]'
  vbw_run prove
  [ "$status" -ne 0 ]
  local id
  for id in C1 C2 C3; do
    cmp "$OUT/$id.log" <(expected "$id" 400) || { echo "$id"; false; }
  done
}

@test "R118: vbw show fix names the kept file of every failing check of its requirement and of every failing project command, as text and as JSON" {
  plan '[{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
         {id: "C4", req: "R1", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"], output: "^all good$"},
         {id: "C2", req: "R2", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]},
         {id: "C3", req: "R3", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]}]' '{test: ["sh", "tests/cmd.sh"]}'
  "$VBW" prove > /dev/null || true
  local f1 ft
  f1=$(fix_of R1)
  ft=$(fix_of test)
  [ -n "$f1" ]
  [ -n "$ft" ]
  vbw_run show fix "$f1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$OUT/C1.log"* ]] || { echo "$output"; false; }
  [[ "$output" == *"$OUT/C4.log"* ]] || { echo "$output"; false; }
  [[ "$output" == *"$OUT/command-test.log"* ]] || { echo "$output"; false; }
  vbw_run show fix "$f1" --json
  printf '%s' "$output" | jq -e --arg o "$OUT" '([.checks[] | select(.id == "C1") | .kept] == ["\($o)/C1.log"])
    and ([.checks[] | select(.id == "C4") | .kept] == ["\($o)/C4.log"])
    and ([.commands[] | select(.name == "test") | .kept] == ["\($o)/command-test.log"])' || { echo "$output"; false; }
  vbw_run show fix "$ft"
  [[ "$output" == *"$OUT/command-test.log"* ]] || { echo "$output"; false; }
  vbw_run show fix "$ft" --json
  printf '%s' "$output" | jq -e --arg o "$OUT" '[.commands[] | select(.name == "test") | .kept] == ["\($o)/command-test.log"]' || { echo "$output"; false; }
}

@test "R118: when a kept file is missing, vbw show fix says the full output is not kept and to run vbw prove again" {
  plan '[{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
         {id: "C2", req: "R2", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]},
         {id: "C3", req: "R3", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]}]'
  "$VBW" prove > /dev/null || true
  rm -f "$OUT/C1.log"
  local f1
  f1=$(fix_of R1)
  vbw_run show fix "$f1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$OUT/C1.log"* ]] || { echo "$output"; false; }
  printf '%s' "$output" | grep -qi 'not kept' || { echo "$output"; false; }
  printf '%s' "$output" | grep -q 'vbw prove' || { echo "$output"; false; }
  vbw_run show fix "$f1" --json
  printf '%s' "$output" | jq -e '[.checks[] | select(.id == "C1") | .kept] == [null]' || { echo "$output"; false; }
}

@test "R118: kept output is never committed and never written outside .vbw/runtime" {
  plan '[{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
         {id: "C2", req: "R2", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]},
         {id: "C3", req: "R3", run: ["sh", "tests/ok.sh"], files: ["tests/ok.sh"]}]' '{test: ["sh", "tests/cmd.sh"]}'
  "$VBW" prove > /dev/null || true
  [ -f "$OUT/C1.log" ]
  [ -f "$OUT/command-test.log" ]
  [ -z "$(git ls-files -- .vbw/runtime)" ]
  [ -z "$(git log --all --format= --name-only | grep -F 'runtime/output')" ]
  [ -z "$(git status --porcelain -- .vbw/runtime)" ]
  # The only copies of the whole output are the kept files (the record keeps the last 20 lines).
  [ "$(grep -rlF 'C1 line 1 ' "$TEST_ROOT" | grep -v '/\.git/' | sed "s|^$PROJECT/||")" = "$OUT/C1.log" ]
  [ "$(grep -rlF 'TEST line 1 ' "$TEST_ROOT" | grep -v '/\.git/' | sed "s|^$PROJECT/||")" = "$OUT/command-test.log" ]
}

@test "R118: docs/proof.md tells where a failure's full output is kept and that vbw show fix names it" {
  grep -q '\.vbw/runtime/output' "$REPO_ROOT/docs/proof.md"
  grep -qiE 'show fix.*(kept|full output)|(kept|full output).*show fix' "$REPO_ROOT/docs/proof.md"
}
