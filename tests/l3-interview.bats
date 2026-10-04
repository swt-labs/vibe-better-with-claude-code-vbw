#!/usr/bin/env bats
# R42: two real-user scenarios in tools/l3-suite.sh answer the interview as a
# newcomer and as a senior engineer, in the real Claude Code app (L3). Each
# records its answers, is not asked again, reaches the ship step, and saves its
# transcript so a person can compare the wording (R41, human). As in
# tests/l3-scenarios.bats, these tests do not run Claude Code (L1): they hold the
# suite's structure and each committed result to the facts it states, taken from
# the record, the private answers file and git, never from screen text.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

# scenario_ok NAME: the scenario exists, is in the default list and the header,
# writes its own result, and its committed result is labelled honestly.
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

@test "R42: the newcomer scenario exists, runs the real app and states its fixture and level" {
  scenario_ok newcomer
}

@test "R42: the senior-engineer scenario exists, runs the real app and states its fixture and level" {
  scenario_ok senior
}

@test "R42: the newcomer answered the three fixed questions, what and for whom, the follow-ups and where to keep them" {
  scenario_ok newcomer
  facts newcomer '.facts.answered.level == "never" and .facts.answered.depth == "plain words"
    and .facts.answered.involvement == "decide and tell me"'
  facts newcomer '.facts.answered.purpose | type == "string" and length > 0'
  facts newcomer '.facts.answered.follow_ups | type == "number" and . >= 0 and . <= 3'
  facts newcomer '.facts.answered.keep | . == "private" or . == "project"'
}

@test "R42: the senior engineer answered the three fixed questions, what and for whom, the follow-ups and where to keep them" {
  scenario_ok senior
  facts senior '.facts.answered.level == "senior engineer" and .facts.answered.depth == "technical and brief"
    and .facts.answered.involvement == "I make the calls"'
  facts senior '.facts.answered.purpose | type == "string" and length > 0'
  facts senior '.facts.answered.follow_ups | type == "number" and . >= 0 and . <= 3'
  facts senior '.facts.answered.keep | . == "private" or . == "project"'
}

@test "R42: each scenario's recorded answers (vbw interview, taken from the project) match what was answered" {
  local s
  for s in newcomer senior; do
    scenario_ok "$s"
    facts "$s" '.facts.recorded.level == .facts.answered.level and .facts.recorded.depth == .facts.answered.depth
      and .facts.recorded.involvement == .facts.answered.involvement and .facts.recorded.kept == .facts.answered.keep'
    facts "$s" '.facts.recorded_matches_answered == true'
    facts "$s" '.facts.purpose_in_spec_goals == true'
  done
}

@test "R42: in each scenario a second request in a new session did not trigger the interview again" {
  local s
  for s in newcomer senior; do
    scenario_ok "$s"
    facts "$s" '.facts.second_session_asked_interview == false and .facts.next_profile_ask_after == false'
  done
}

@test "R42: each scenario reaches the ship step" {
  local s
  for s in newcomer senior; do
    scenario_ok "$s"
    facts "$s" '.facts.milestone_shipped == true and .facts.reached_ship == true'
  done
}

@test "R42: the two scenarios record different explanation depth and involvement, and their transcripts are saved for comparison" {
  local s
  scenario_ok newcomer
  scenario_ok senior
  [ "$(jq -r '.facts.recorded.depth' "$RESULTS/newcomer.json")" != "$(jq -r '.facts.recorded.depth' "$RESULTS/senior.json")" ]
  [ "$(jq -r '.facts.recorded.involvement' "$RESULTS/newcomer.json")" != "$(jq -r '.facts.recorded.involvement' "$RESULTS/senior.json")" ]
  for s in newcomer senior; do
    local t
    t=$(jq -r '.facts.transcript' "$RESULTS/$s.json")
    [ -n "$t" ] && [ "$t" != null ]
    [ -s "$REPO_ROOT/$t" ] || { echo "transcript missing or empty: $t"; false; }
    case "$t" in tools/l3-results/*) ;; *) echo "transcript outside tools/l3-results: $t"; false ;; esac
  done
}

@test "R42: the release gate runs every scenario for a milestone release: both new scenarios are in the default list" {
  grep -E '^ALL=' "$SUITE" | grep -qw newcomer
  grep -E '^ALL=' "$SUITE" | grep -qw senior
}
