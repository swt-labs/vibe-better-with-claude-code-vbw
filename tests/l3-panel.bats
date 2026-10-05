#!/usr/bin/env bats
# R51 (with R56 and R58): a real-user scenario in tools/l3-suite.sh (L3, the real
# Claude Code app) shows the panel on a realistic project: the milestone and its
# progress, what VBW is doing, a need for the user with what it is for, the cost
# line, and an estimate or the plain 'no basis yet'. As in tests/l3-results.bats,
# these tests do not run Claude Code (L1): they hold the scenario's structure and
# its committed result. The result is written by the run, not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/panel.json"

body() { sed -n '/^scenario_panel()/,/^}/p' "$SUITE"; }

@test "R51: the panel scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_panel()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw panel
  sed -n '1,26p' "$SUITE" | grep -qw panel
}

@test "R51: it runs the real app in a window wide enough for the panel, and writes its own result with its fixture and what it did not test" {
  [ -n "$(body)" ]
  body | grep -q 'result_write panel '
  body | grep -qi 'fixture='
  body | grep -qF "'[\""
  body | grep -qE '14[4-9]|1[5-9][0-9]|[2-9][0-9]{2}'
}

@test "R51: a committed result of it is honest: L3, passed, and the panel facts are all there" {
  [ -f "$RESULT" ] || { echo "the panel scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "panel" and .evidence_level == "L3" and .passed == true
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.at | type == "string")
    and (.facts.milestone_shown == true)
    and (.facts.progress_shown == true)
    and (.facts.doing_shown == true)
    and (.facts.need_shown == true)
    and (.facts.need_text | type == "string" and length > 0)
    and (.facts.cost_shown == true)
    and (.facts.estimate_shown | type == "string" and length > 0)
    and (.facts.sound_toggle_persisted == true)
    and (.facts.closed_stays_closed == true)
    and (.not_tested | type == "array" and length > 0)' "$RESULT"
}

@test "R51: the result says what was seen on the screen was read from the panel, and the sound was not heard" {
  [ -f "$RESULT" ] || { echo "the panel scenario has not been run: no result is committed"; false; }
  jq -e '(.not_tested | map(ascii_downcase) | any(test("sound"))) and (.not_tested | map(ascii_downcase) | any(test("human|read by a person|at a glance")))' "$RESULT"
}
