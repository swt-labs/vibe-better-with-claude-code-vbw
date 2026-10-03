#!/usr/bin/env bats
# R24: express is decided before planning. At the plan step, vbw next --json
# carries detail.tier, computed from the record and the tracked-file count.

load helper
load rigor-helper

teardown() { vbw_teardown; }

early_tier() {
  run "$VBW" next --json < /dev/null
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "plan"' > /dev/null
  printf '%s' "$output" | jq -r '.detail.tier'
}

track_files() { # N: commit N more tracked files
  local i
  mkdir -p many
  for ((i = 1; i <= $1; i++)); do printf '%s\n' "$i" > "many/f$i.txt"; done
  git add many
  git commit -q -m "chore(test): files"
}

@test "one [auto] requirement with no risk word in a small repository is express" {
  rigor_project 1
  [ "$(early_tier)" = express ]
}

@test "more than one requirement is standard" {
  rigor_project 2
  [ "$(early_tier)" = standard ]
}

@test "a [human] requirement is standard" {
  rigor_project 1 human
  [ "$(early_tier)" = standard ]
}

@test "a requirement text naming a risk category is standard" {
  rigor_project 1
  printf '%s\n' '# Notes' '' '## Requirements' '' '- R1 [auto] Visitors can log in with a password' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  [ "$(early_tier)" = standard ]
}

@test "a repository tracking more than 30 files is standard" {
  rigor_project 1
  track_files 40
  [ "$(early_tier)" = standard ]
}

@test "a repository tracking at most 30 files stays express" {
  rigor_project 1
  track_files 20
  [ "$(early_tier)" = express ]
}

@test "rigor deep forces deep" {
  rigor_project 1
  edit_record '.settings.rigor = "deep"'
  [ "$(early_tier)" = deep ]
}

@test "rigor standard forces standard" {
  rigor_project 1
  edit_record '.settings.rigor = "standard"'
  [ "$(early_tier)" = standard ]
}

@test "a forced express on a bigger request still says express" {
  rigor_project 3
  track_files 40
  edit_record '.settings.rigor = "express"'
  [ "$(early_tier)" = express ]
}

@test "detail.tier appears only at the plan step" {
  rigor_flow_setup
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "approve" and (.detail | has("tier") | not)' > /dev/null
}
