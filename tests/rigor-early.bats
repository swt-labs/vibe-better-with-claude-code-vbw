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

# P20.5: one definition of the signals, used at both steps.

track_code() { # commit an existing source file
  printf 'x\n' > src/app.js
  git add src/app.js
  git commit -q -m "chore(test): code"
}

@test "express at the plan step holds at apply: one plan of four small files is express" {
  rigor_project 1
  [ "$(early_tier)" = express ]
  rigor_apply "$(rigor_doc 1 "" src/a.js src/b.js src/c.js src/d.js)" > /dev/null
  phase_json '.phases[0].tier == "express"'
}

@test "an existing codebase with no project test command is standard at both steps" {
  rigor_project 1
  track_code
  [ "$(early_tier)" = standard ]
  run rigor_apply "$(rigor_doc 1 express src/app.js)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"floor at standard"* ]]
}

@test "an existing codebase with a project test command stays express at both steps" {
  rigor_project 1
  track_code
  edit_record '.commands.test = ["true"]'
  [ "$(early_tier)" = express ]
  rigor_apply "$(rigor_doc 1 "" src/app.js)" > /dev/null
  phase_json '.phases[0].tier == "express"'
}

@test "the router's express example is a document vbw apply accepts as express" {
  rigor_project 1
  local doc
  doc=$(sed -n 's/^Example: `\(.*\)`\.\{0,1\}$/\1/p' "$BATS_TEST_DIRNAME/../plugin/skills/vibe/SKILL.md")
  [ -n "$doc" ]
  printf 'exit 1\n' > test.sh
  rigor_apply "$doc" > /dev/null
  phase_json '.phases[0].tier == "express" and (.plans | length) == 1 and (.checks | length) >= 1'
}
