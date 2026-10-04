#!/usr/bin/env bats
# R38 (docs/interview.md): the interview is asked only once per project. A new
# project is asked at its spec step; once answers exist it is never asked again
# (new session, new milestone, another worktree); a project started before this
# version (milestones, no answers) is asked once, at its next milestone's spec
# step, never in the middle of a run or phase. Run through `vbw next --json`
# on hermetic projects (L1).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  git add -A && git commit -q -m "chore: init"
}

teardown() { vbw_teardown; }

next_json() { "$VBW" next --json < /dev/null; }
ask() { next_json | jq -r '.profile.ask'; }

# ship_m1: the project's first milestone is shipped (as a project from before the
# interview existed would have it): one proven requirement, M1 in the shipped list.
ship_m1() {
  jq '.requirements = [{id: "R1", text: "Visitors can read the page", proof: "auto", status: "proven", milestone: "M1"}]
    | .milestone.status = "shipped"
    | .shipped = [{id: "M1", title: "First milestone", at: "2026-01-01T00:00:00Z"}]' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
}

answer_all() {
  "$VBW" interview set level "professionally" > /dev/null
  "$VBW" interview set depth "plain with technical terms explained" > /dev/null
  "$VBW" interview set involvement "options with a recommendation" > /dev/null
  "$VBW" interview keep "$1" > /dev/null
}

@test "R38: a new project, at its spec step with no answers, is asked the interview" {
  run next_json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "spec" and .profile.ask == true and .profile.interviewed == false and .profile.pending == "level"'
}

@test "R38: once the answers exist the interview is never asked again, whatever the location or session" {
  answer_all private
  [ "$(ask)" = "false" ]
  [ "$(VBW_SESSION_ID=another-session ask)" = "false" ]
  run next_json
  printf '%s' "$output" | jq -e '.action == "spec" and .profile.interviewed == true and .profile.pending == null and .profile.ask == false'
  "$VBW" interview keep project > /dev/null
  [ "$(ask)" = "false" ]
}

@test "R38: a new milestone does not ask again once the answers exist, shared or private" {
  answer_all project
  ship_m1
  vbw_run milestone start "Second"
  [ "$status" -eq 0 ]
  run next_json
  printf '%s' "$output" | jq -e '.action == "spec" and .profile.ask == false and .profile.interviewed == true'
  "$VBW" interview keep private > /dev/null
  [ "$(ask)" = "false" ]
}

@test "R38: a project started before this version is not asked mid-run or mid-phase, only at its next milestone" {
  ship_m1
  # Shipped, milestone not yet started: not the spec step, so not asked.
  run next_json
  printf '%s' "$output" | jq -e '.action == "milestone" and .profile.ask == false and .profile.interviewed == false'
  vbw_run milestone start "Second"
  [ "$status" -eq 0 ]
  run next_json
  printf '%s' "$output" | jq -e '.action == "spec" and .profile.ask == true'
  # Mid-run steps never ask: a project with requirements and no plan is at plan.
  "$VBW" spec add auto "Visitors can read a second page" > /dev/null
  run next_json
  printf '%s' "$output" | jq -e '.action == "plan" and .profile.ask == false and .profile.interviewed == false'
}

@test "R38: a project record from an older VBW is read, is not mid-run asked, and counts as not yet interviewed" {
  cp "$BATS_TEST_DIRNAME/fixtures/records/v1.json" .vbw/record.json
  run next_json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.profile.ask == false and .profile.interviewed == false'
}

@test "R38: answers shared by choice are not asked again in a second worktree" {
  answer_all project
  git add .vbw/record.json && git commit -q -m "chore(vbw): share the interview answers"
  git worktree add -q "$TEST_ROOT/wt" -b other
  run bash -c 'cd "$1" && "$2" next --json' _ "$TEST_ROOT/wt" "$VBW"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.profile.ask == false and .profile.interviewed == true and .profile.kept == "project"'
}

@test "R38: the router asks the interview only when next says profile.ask, never mid-run" {
  local r="$PLUGIN_ROOT/skills/vibe/SKILL.md"
  grep -qF 'profile.ask' "$r"
  grep -qiE 'once|never ask(ed)? again' "$PLUGIN_ROOT/skills/interview/SKILL.md"
}
