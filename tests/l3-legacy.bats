#!/usr/bin/env bats
# R65: two real-user scenarios in tools/l3-suite.sh (L3, the real Claude Code
# TUI, run during the milestone, D95). `legacy`: a project with a VBW 1 folder; the
# interview shows the review, recommends, asks, and the user picks the option that
# is not recommended. `nolegacy`: a project without one is not asked. As in
# tests/l3-tools.bats these tests do not run Claude Code (L1): they hold the
# scenarios' structure and their committed results to facts taken from the record,
# git and the session transcript, never screen text.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "R65: both scenarios exist, are in the default list and are named in the suite's header" {
  local s
  for s in legacy nolegacy; do
    grep -q "^scenario_$s()" "$SUITE"
    grep -E '^ALL=' "$SUITE" | grep -qw "$s"
    sed -n '1,24p' "$SUITE" | grep -qw "$s"
  done
}

@test "R65: legacy builds a fixture with a VBW 1 folder, picks the option that is not recommended, and reads the record and git" {
  [ -n "$(body legacy)" ]
  body legacy | grep -q 'result_write legacy '
  body legacy | grep -q '\.vbw-planning'
  body legacy | grep -qE 'project\.legacy|legacy review'
  body legacy | grep -qE 'git (status|diff|ls-files|log)|git_'
  body legacy | grep -qiE 'fresh'
  body legacy | grep -qi 'fixture='
  body legacy | grep -qF "'[\""
  if body legacy | grep -q 'screen |.*grep.*legacy'; then false; fi
}

@test "R65: nolegacy uses a project without a VBW 1 folder and checks from the transcript that no review question was asked" {
  [ -n "$(body nolegacy)" ]
  body nolegacy | grep -q 'result_write nolegacy '
  body nolegacy | grep -qE 'transcripts|legacy review|project\.legacy'
  body nolegacy | grep -qi 'fixture='
  body nolegacy | grep -qF "'[\""
  if body nolegacy | grep -q '\.vbw-planning' ; then
    body nolegacy | grep -qE 'no VBW 1|without'
  fi
}

@test "R65: the committed result of legacy: L3, passed, the review shown before another question, recommended option first, the other picked, nothing converted, folder untouched, not asked again" {
  jq -e '.scenario == "legacy" and .evidence_level == "L3" and .passed == true
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.not_tested | type == "array" and length > 0)
    and .facts.recommendation == "convert" and .facts.choice == "fresh"
    and .facts.review_before_other_questions == true
    and .facts.recommended_option_first == true
    and .facts.converted == false and .facts.old_folder_unchanged == true
    and .facts.asked_again == false and .facts.interview_completed == true' "$RESULTS/legacy.json"
}

@test "R65: the committed result of nolegacy: L3, passed, the review question never asked, the interview completed" {
  jq -e '.scenario == "nolegacy" and .evidence_level == "L3" and .passed == true
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.not_tested | type == "array" and length > 0)
    and .facts.asked_legacy == false and .facts.interview_completed == true' "$RESULTS/nolegacy.json"
}
