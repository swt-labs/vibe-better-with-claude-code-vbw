#!/usr/bin/env bats
# R34: the proof half of the leftover scenario of tools/l3-suite.sh
# (leftover_proof), run on a hermetic project (L1: no Claude Code). The scenario
# reaches it with the project's last proof passed, so the lint command's pass is
# in the run store with its read list (lint.sh only), and a plain vbw prove
# reuses it (R166: an untracked file is not committed code). lint then never
# runs in a proof copy and the copy facts cannot be read: the 2026-10-21 run
# failed "the file was not in the proof copy" and "the proof copy is gone" that
# way. leftover_proof proves with nothing reused (vbw prove --full), so lint runs
# in a copy and writes where it ran and whether the leftover file was there.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Greet\n\n## Requirements\n\n- R1 [auto] greet.sh greets by name\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > greet.sh
  printf '[ "$(sh greet.sh Ana)" = "Hello, Ana!" ]\n' > test_greet.sh
  # The scenario's lint.sh: fails while todos.txt exists; under a probe it
  # writes the folder it ran in and whether todos.txt was there.
  printf '#!/bin/sh\n[ -z "${LEFTOVER_PROBE:-}" ] || { pwd -P; [ -e todos.txt ] && echo yes || echo no; } > "$LEFTOVER_PROBE"\n[ ! -e todos.txt ]\n' > lint.sh
  jq '.checks = [{id:"C1", req:"R1", run:["sh","test_greet.sh"], files:["test_greet.sh"]}]
    | .commands = {lint: ["sh","lint.sh"]}
    | .phases = [{id:"P1", title:"Greet", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Greet", reqs:["R1"], files:["greet.sh"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove < /dev/null > /dev/null
  sed -n '/^leftover_proof()/,/^}/p' "$SUITE" > "$TEST_ROOT/fn.sh"
  [ -s "$TEST_ROOT/fn.sh" ] || { echo "tools/l3-suite.sh has no leftover_proof"; return 1; }
  . "$TEST_ROOT/fn.sh"
}

teardown() { vbw_teardown; }

store() { printf '%s/vbw/runs.json\n' "$(git rev-parse --path-format=absolute --git-common-dir)"; }

@test "R34: after a passing proof, leftover_proof runs lint in a proof copy without the leftover file, and the copy is kept with no owner (#738)" {
  # The scenario's situation: lint's pass is stored with a read list, which a plain vbw prove reuses.
  jq -e '.runs["command:lint"] | .status == "pass" and (.reads | type == "array")' "$(store)"
  run leftover_proof "$PROJECT" todos.txt "$TEST_ROOT/probe"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.leftover_file == "todos.txt" and .check_flips_in_working_folder == true
    and .proof_unchanged == true and .proof_passed == true
    and .ran_in_proof_copy == true and .file_in_proof_copy == false and .copy_released == true' || { echo "$output"; false; }
  [ ! -e todos.txt ]
}

@test "R34: a leftover that reaches the proof copy (git-ignored, copied in by design) is reported in the copy, and the proof changes" {
  printf 'todos.txt\n' >> .gitignore
  git add .gitignore && git commit -q -m "chore: ignore todos.txt"
  run leftover_proof "$PROJECT" todos.txt "$TEST_ROOT/probe"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.ran_in_proof_copy == true and .file_in_proof_copy == true
    and .proof_unchanged == false and .proof_passed == false and .copy_released == true' || { echo "$output"; false; }
}
