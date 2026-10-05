#!/usr/bin/env bats
# R59 (docs/interview.md): the interview opens with a fixed greeting that asks the
# level question, followed by the same four options in the same order as before.
# The procedure is the skill's text (L1: no model runs here); the level values and
# the resume point are the kernel's, and run for real.

load helper

SKILL="$PLUGIN_ROOT/skills/interview/SKILL.md"
ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"
DOC="$BATS_TEST_DIRNAME/../docs/interview.md"
GREETING="Hello, Human! Welcome to VBW. Let me interview you real quick to better adapt to you. What is your level of proficiency?"

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

@test "R59: the first question of the interview skill is exactly the new greeting" {
  grep -qF -- "1. \"$GREETING\"" "$SKILL"
  local first
  first=$(grep -nF -m1 -- "Hello, Human!" "$SKILL" | cut -d: -f1)
  [ "$first" = "$(grep -nE '^1\. ' "$SKILL" | head -1 | cut -d: -f1)" ]
}

@test "R59: the four options follow the greeting, in the same order and wording" {
  local g
  g=$(grep -nF -m1 -- "$GREETING" "$SKILL" | cut -d: -f1)
  [ -n "$g" ]
  [ "$(sed -n "$((g + 1))p" "$SKILL" | sed 's/^ *//')" = "Options: never; small scripts or no-code; professionally; senior engineer." ]
  [ "$(jq -r '.level | join("|")' "$PLUGIN_ROOT/lib/interview.json")" = "never|small scripts or no-code|professionally|senior engineer" ]
}

@test "R59: choosing a level still records it and the interview continues at the next question" {
  grep -qF 'vbw interview set level "<option>"' "$SKILL"
  "$VBW" interview set level "senior engineer" > /dev/null
  run "$VBW" interview --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.level == "senior engineer" and .pending == "depth"'
}

@test "R59: the later questions, the follow-up rules and the keep order are unchanged" {
  grep -qF '2. "How should I explain things?"' "$SKILL"
  grep -qF '3. "How involved do you want to be in technical decisions?"' "$SKILL"
  grep -qF 'then `keep`' "$SKILL"
  grep -qF 'Zero is allowed only when the answers already say what it does and for whom' "$SKILL"
  grep -qF 'a follow-up may be your proposal for them to confirm or' "$SKILL"
  grep -qF 'before the keep question, never left to the spec step' "$SKILL"
}

@test "R59: the old opening wording is gone from the skill and the interview doc, which shows the greeting" {
  ! grep -qF 'How much software have you built' "$SKILL"
  ! grep -qF 'How much have you built before' "$DOC"
  grep -qF -- "$GREETING" "$DOC"
}

@test "R59: the router and the interview prompt stay within their budgets" {
  [ "$(wc -w < "$ROUTER")" -le 1400 ]
  [ "$(wc -w < "$SKILL")" -le 900 ]
  grep -qF -- "$GREETING" "$SKILL"
}

@test "R59: a returning user whose level is recorded is not asked the level question again" {
  grep -qF 'Skip the answers `profile` already holds' "$SKILL"
  "$VBW" interview set level "never" > /dev/null
  run "$VBW" interview --json
  printf '%s' "$output" | jq -e '.pending != "level"'
}
