#!/usr/bin/env bats
# R37 (docs/interview.md): at the start of a project (after mapping, for existing
# code) VBW asks three fixed questions with fixed options, then what is being
# built and for whom, then up to three follow-ups it writes, then where to keep
# the answers. The procedure is the interview skill's text and the router's
# step (L1: no model runs here); the values and the refusal of any other value
# are the kernel's, and run for real.

load helper

SKILL="$PLUGIN_ROOT/skills/interview/SKILL.md"
ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

# line_of TEXT FILE: the line number of the first line containing TEXT (fixed string).
line_of() { grep -nF -m1 -- "$1" "$2" | cut -d: -f1; }

@test "R37: the interview is a skill of its own, named interview, within a mode prompt's budget" {
  [ -f "$SKILL" ]
  [ "$(sed -n 1p "$SKILL")" = "---" ]
  grep -qx 'name: interview' "$SKILL"
  grep -qE '^description: .{20,}$' "$SKILL"
  [ "$(wc -w < "$SKILL")" -le 900 ]
}

@test "R37: the three fixed questions are asked in order with exactly the listed options" {
  local o first prev=0 n
  for o in "never" "small scripts or no-code" "professionally" "senior engineer" \
    "plain words" "plain with technical terms explained" "technical and brief" \
    "decide and tell me" "options with a recommendation" "I make the calls"; do
    grep -qF -- "$o" "$SKILL" || { echo "option missing: $o"; false; }
  done
  # Level, then depth, then involvement: the first line of each question's own option.
  for o in "small scripts or no-code" "plain with technical terms explained" "I make the calls"; do
    n=$(line_of "$o" "$SKILL")
    [ -n "$n" ] && [ "$n" -gt "$prev" ] || { echo "out of order at: $o"; false; }
    prev=$n
  done
  first=$(line_of "small scripts or no-code" "$SKILL")
  [ "$first" -gt 0 ]
}

@test "R37: after the three, VBW asks briefly what is being built and for whom, and writes it into the spec Goals" {
  local who goal
  who=$(grep -inE 'what (are you|is being) building and for whom|what you are building and for whom' "$SKILL" | head -1 | cut -d: -f1)
  [ -n "$who" ]
  [ "$who" -gt "$(line_of "I make the calls" "$SKILL")" ]
  grep -qE '## Goals' "$SKILL"
  grep -q '\.vbw/spec\.md' "$SKILL"
  goal=$(line_of "## Goals" "$SKILL")
  [ "$goal" -ge "$who" ]
}

@test "R37: at most three follow-up questions, written for that user's level and this project; zero is allowed" {
  grep -qiE 'at most three (written )?follow-up' "$SKILL"
  grep -qiE 'zero' "$SKILL"
  grep -qiE 'never (ask )?(a )?(fourth|four)' "$SKILL"
  grep -qiE 'level' "$SKILL"
  [ "$(grep -inE 'follow-up' "$SKILL" | head -1 | cut -d: -f1)" -gt "$(line_of "I make the calls" "$SKILL")" ]
}

@test "R37: the last question asks where to keep the personal answers and applies the choice through the kernel" {
  local keep follow
  grep -qF 'private on this machine' "$SKILL"
  grep -qiE 'saved in the project' "$SKILL"
  grep -qF 'vbw interview keep private' "$SKILL"
  grep -qF 'vbw interview keep project' "$SKILL"
  keep=$(line_of 'vbw interview keep private' "$SKILL")
  follow=$(grep -inE 'follow-up' "$SKILL" | head -1 | cut -d: -f1)
  [ "$keep" -gt "$follow" ]
  grep -qiE 'last question' "$SKILL"
}

@test "R37: each answer is recorded as it is given, so an interrupted interview resumes at the first unanswered question" {
  grep -qF 'vbw interview set level' "$SKILL"
  grep -qF 'vbw interview set depth' "$SKILL"
  grep -qF 'vbw interview set involvement' "$SKILL"
  grep -qiE 'first unanswered' "$SKILL"
  grep -qF 'pending' "$SKILL"
}

@test "R37: an interrupted interview records nothing as complete and resumes at the first unanswered question" {
  vbw_run next --json
  printf '%s' "$output" | jq -e '.profile.pending == "level" and .profile.interviewed == false'
  "$VBW" interview set level "senior engineer" > /dev/null
  "$VBW" interview --json | jq -e '.interviewed == false and .pending == "depth" and .kept == null'
  vbw_run next --json
  printf '%s' "$output" | jq -e '.profile.interviewed == false and .profile.pending == "depth"'
  "$VBW" interview set depth "technical and brief" > /dev/null
  "$VBW" interview --json | jq -e '.interviewed == false and .pending == "involvement"'
  "$VBW" interview set involvement "I make the calls" > /dev/null
  "$VBW" interview --json | jq -e '.interviewed == false and .pending == "keep"'
  vbw_run status
  [[ "$output" == *"not finished"* || "$output" == *"has not been done"* ]]
  "$VBW" interview keep private > /dev/null
  "$VBW" interview --json | jq -e '.interviewed == true and .pending == null'
}

@test "R37: an unrecognised answer to a fixed question is refused and never recorded" {
  "$VBW" interview set level "never" > /dev/null
  local before
  before=$(git rev-parse --path-format=absolute --git-common-dir)/vbw/profile.json
  vbw_run interview set level "I am a bit of everything"
  [ "$status" -ne 0 ]
  vbw_run interview set depth ""
  [ "$status" -ne 0 ]
  jq -e '.level == "never" and (has("depth") | not)' "$before"
  grep -qiE 're-ask|ask again|asks again' "$SKILL"
  grep -qiE 'never record' "$SKILL"
}

@test "R37: the router runs the interview before spec work, after mapping for existing code," {
  local map ask
  grep -qF 'vbw:interview' "$ROUTER"
  grep -qF 'profile.ask' "$ROUTER"
  map=$(line_of 'map.md' "$ROUTER")
  ask=$(line_of 'profile.ask' "$ROUTER")
  [ -n "$map" ] && [ -n "$ask" ] && [ "$ask" -gt "$map" ]
  grep -qiE 'after (the )?map' "$SKILL"
}

@test "R37: the router stays within its budget and the interview adds no more than a mode prompt" {
  [ "$(wc -w < "$ROUTER")" -le 1400 ]
  [ "$(wc -w < "$SKILL")" -le 900 ]
}
