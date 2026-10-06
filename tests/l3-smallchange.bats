#!/usr/bin/env bats
# R72: the real-user scenario `smallchange` in tools/l3-suite.sh (L3, the real
# Claude Code TUI, run during the milestone, D95): on a project whose first
# milestone is shipped, the user asks for one small change in plain words, and
# VBW takes it to done through /vbw:vibe without the planning workflow, with
# one approval, a check that passes and a quick QA at most. As in
# tests/l3-legacy.bats these tests do not run Claude Code (L1): they hold the
# scenario's structure and its committed result to facts from the record, git
# and the session transcript, never screen text.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "R72: the smallchange scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_smallchange()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw smallchange
  sed -n '1,24p' "$SUITE" | grep -qw smallchange
}

@test "R72: it asks for one small change in plain words and reads the record, git and the transcript" {
  [ -n "$(body smallchange)" ]
  body smallchange | grep -q 'result_write smallchange '
  body smallchange | grep -qi 'fixture='
  body smallchange | grep -qE 'transcripts|Workflow'
  body smallchange | grep -qE 'git (log|status|diff|show)|git_'
  body smallchange | grep -qE 'decisions|approve'
  body smallchange | grep -qF "'[\""
  if body smallchange | grep -q 'screen |.*grep.*small'; then false; fi
}

@test "R72: the committed result: L3, passed, no planning workflow, one approval, one plan, its check passed, QA quick at most, the change committed" {
  jq -e '.scenario == "smallchange" and .evidence_level == "L3" and .passed == true
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.not_tested | type == "array" and length > 0)
    and .facts.planning_workflow == false
    and .facts.approvals == 1
    and .facts.plans == 1
    and .facts.check_passed == true
    and (.facts.qa_tier | IN("quick", "express", "none"))
    and .facts.change_committed == true' "$RESULTS/smallchange.json"
}
