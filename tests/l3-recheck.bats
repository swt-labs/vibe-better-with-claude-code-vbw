#!/usr/bin/env bats
# R48: a real-user scenario in tools/l3-suite.sh (L3, run before a milestone
# release) shows a fix round followed by QA that checks again only the changed
# phase and names why. As in tests/l3-scenarios.bats these tests do not run
# Claude Code (L1): they hold the scenario's structure, and a committed result
# if there is one, to facts taken from the record and git, never screen text.
# Until the scenario has been run no result is committed: its status is "not run".

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/recheck.json"

body() { sed -n '/^scenario_recheck()/,/^}/p' "$SUITE"; }

@test "R48: the recheck scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_recheck()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw recheck
  sed -n '1,22p' "$SUITE" | grep -qw recheck
}

@test "R48: it plays a fix round on a project of two phases, and takes its facts from the record and git" {
  [ -n "$(body)" ]
  body | grep -q 'result_write recheck '
  body | grep -qE 'vbw next --json|next_json|record_history'
  body | grep -qiE 'two phases|phase'
  body | grep -qE 'qa\.recheck|\.qa\.'
  body | grep -q 'standing'
  # No fact is read from the screen.
  if body | grep -q 'screen |.*grep.*recheck'; then false; fi
}

@test "R48: it states what it did not test and its fixture" {
  body | grep -qF "'[\""
  body | grep -qi 'fixture='
}

@test "R48: a committed result of it is honest: L3, passed, with the phases checked again and the reason named; none is committed before it ran" {
  if [ ! -f "$RESULT" ]; then skip "recheck has not been run: its status is not run"; fi
  jq -e '.scenario == "recheck" and .evidence_level == "L3" and .passed == true
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts.rechecked | type == "array" and length == 1)
    and (.facts.kept | type == "array" and length >= 1)
    and (.facts.reason | type == "string" and length > 0)
    and (.not_tested | type == "array" and length > 0)' "$RESULT"
}
