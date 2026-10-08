#!/usr/bin/env bats
# R116: the real-user scenario `smallchange` in tools/l3-suite.sh (L3, the real
# Claude Code TUI) asks for a one-file change in plain words inside a
# milestone that already has planned or proven requirements, and VBW takes it
# to done through /vbw:vibe without the planning workflow, with one approval,
# leaving the earlier work as it was. As in tests/l3-smallchange.bats these
# tests do not run Claude Code (L1): they hold the scenario's structure and its
# committed result to facts from the record, git and the session transcript.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/smallchange.json"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "R116: the smallchange scenario seeds a milestone with earlier requirements and records what it kept" {
  [ -n "$(body smallchange)" ]
  body smallchange | grep -q 'prior_requirements'
  body smallchange | grep -q 'same_milestone'
  body smallchange | grep -q 'prior_kept'
}

@test "R116: the committed result: L3, passed, the request added to a milestone with earlier work, no planning workflow, one approval, one new plan" {
  jq -e '.scenario == "smallchange" and .evidence_level == "L3" and .passed == true
    and (.not_tested | type == "array" and length > 0)
    and (.facts.prior_requirements | type == "number" and . >= 1)
    and .facts.same_milestone == true
    and .facts.prior_kept == true
    and .facts.planning_workflow == false
    and .facts.approvals == 1
    and .facts.approved_by_choice == true
    and .facts.plans == 1
    and .facts.check_passed == true
    and .facts.change_committed == true' "$RESULT"
}
