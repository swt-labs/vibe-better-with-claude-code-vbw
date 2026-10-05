#!/usr/bin/env bats
# R62: a real-user scenario in tools/l3-suite.sh (L3, the real Claude Code TUI)
# plays the tools offer: the interview asks once, a yes researches and proposes,
# nothing is installed until the list is approved. As in tests/l3-recheck.bats
# these tests do not run Claude Code (L1): they hold the scenario's structure,
# and a committed result if there is one, to facts taken from the record and
# git, never screen text. Until it has been run no result is committed.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/tools.json"

body() { sed -n '/^scenario_tools()/,/^}/p' "$SUITE"; }

@test "R62: the tools scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_tools()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw tools
  sed -n '1,24p' "$SUITE" | grep -qw tools
}

@test "R62: it answers yes once, reads the stored answer, and checks nothing was installed before approval, from the record and git" {
  [ -n "$(body)" ]
  body | grep -q 'result_write tools '
  body | grep -qE 'vbw tools|project\.tools'
  body | grep -qiE 'install'
  body | grep -qE 'git (status|diff|ls-files|log)|git_'
  if body | grep -q 'screen |.*grep.*tools'; then false; fi
}

@test "R62: it states what it did not test and its fixture" {
  body | grep -qF "'[\""
  body | grep -qi 'fixture='
}

@test "R62: a committed result of it is honest: L3, passed, the answer stored once, nothing installed before approval; none is committed before it ran" {
  if [ ! -f "$RESULT" ]; then skip "tools has not been run: its status is not run"; fi
  jq -e '.scenario == "tools" and .evidence_level == "L3" and .passed == true
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and .facts.answer == "yes" and .facts.asked_again == false
    and .facts.installed_before_approval == false
    and (.not_tested | type == "array" and length > 0)' "$RESULT"
}
