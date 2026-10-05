#!/usr/bin/env bats
# R61: a real-user scenario in tools/l3-suite.sh (L3, the real Claude Code app)
# shows the approval question appearing as a choice and Enter approving the
# contract it named. As in tests/l3-recheck.bats these tests do not run Claude
# Code (L1): they hold the scenario's structure, and a committed result if there
# is one, to facts taken from the record and git, never screen text. Until the
# scenario has been run no result is committed: its status is "not run".

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/approval.json"

body() { sed -n '/^scenario_approval()/,/^}/p' "$SUITE"; }

@test "R61: the approval scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_approval()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw approval
  sed -n '1,30p' "$SUITE" | grep -qw approval
}

@test "R61: it answers the approval question with Enter, never by typing /vbw:approve, and checks the record and git" {
  [ -n "$(body)" ]
  body | grep -q 'result_write approval '
  body | grep -qi 'enter'
  body | grep -q 'Approve contract'
  body | grep -qE 'Contract approved|contract_hash|show contract'
  body | grep -qi 'fixture='
  body | grep -qF "'[\""
}

@test "R61: a committed result of it is honest: L3, passed, the choice was shown and Enter approved the shown contract; none is committed before it ran" {
  if [ ! -f "$RESULT" ]; then skip "approval has not been run: its status is not run"; fi
  jq -e '.scenario == "approval" and .evidence_level == "L3" and .passed == true
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and .facts.choice_shown == true and .facts.approved_by_enter == true
    and (.facts.fingerprint | type == "string" and length == 12)
    and (.not_tested | type == "array" and length > 0)' "$RESULT"
}
