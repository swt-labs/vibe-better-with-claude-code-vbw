#!/usr/bin/env bats
# R34: two real-user scenarios in tools/l3-suite.sh, run in the real Claude Code
# app (L3). edgecase: a request that states an edge case gets a check for that
# edge before approval. leftover: an untracked file left in the working folder
# does not change the proof, and is not in the proof copy. As in
# tests/l3-results.bats, these tests do not run Claude Code (L1): they hold the
# suite's structure and each committed result to the facts it states, taken
# from the record, git and the project, never from screen text.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

# scenario_ok NAME: the scenario exists, is in the default list, is named in the
# suite's header, writes its own result, and its committed result is labelled
# honestly (level, fixture, cost, what was not tested).
scenario_ok() {
  grep -q "^scenario_$1()" "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw "$1"
  sed -n '1,20p' "$SUITE" | grep -qw "$1"
  sed -n "/^scenario_$1()/,/^}/p" "$SUITE" | grep -q "result_write $1 "
  local f="$RESULTS/$1.json"
  [ -f "$f" ]
  jq -e --arg n "$1" '.scenario == $n and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0)
    and (.cost_usd | type == "number" and . > 0)
    and (.at | type == "string") and (.facts | type == "object")
    and (.not_tested | type == "array" and length > 0)' "$f" > /dev/null
}

facts() { jq -e "$2" "$RESULTS/$1.json" > /dev/null; }

@test "R34: the edge-case scenario exists, runs the real app and states its fixture and level" {
  scenario_ok edgecase
}

@test "R34: the edge case got a rule and a check before approval, and the check tests that edge" {
  scenario_ok edgecase
  facts edgecase '.facts.edge_case | type == "string" and length > 0'
  facts edgecase '.facts.rule_text | type == "string" and length > 0'
  facts edgecase '.facts.rule_check | type == "string" and test("^C[0-9]+$")'
  facts edgecase '.facts.rule_listed_before_approval == true and .facts.check_approved == true'
  facts edgecase '.facts.check_passes_on_solution == true and .facts.check_fails_without_edge == true'
}

@test "R34: the leftover-file scenario exists, runs the real app and states its fixture and level" {
  scenario_ok leftover
}

@test "R34: a leftover untracked file left the proof unchanged and was not in the proof copy" {
  scenario_ok leftover
  facts leftover '.facts.leftover_file | type == "string" and length > 0'
  facts leftover '.facts.check_flips_in_working_folder == true'
  facts leftover '.facts.proof_unchanged == true and .facts.proof_passed == true'
  facts leftover '.facts.file_in_proof_copy == false and .facts.copy_removed == true'
}

@test "R34: each scenario's result reflects only its own checks" {
  grep -q 'suite_failed=\$failed failed=0' "$SUITE"
  [ "$(jq -r .scenario "$RESULTS/edgecase.json")" = edgecase ]
  [ "$(jq -r .scenario "$RESULTS/leftover.json")" = leftover ]
}
