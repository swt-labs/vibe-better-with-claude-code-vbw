#!/usr/bin/env bats
# R65 (docs/convert.md): the user's choice after the review, convert or start
# fresh, is stored in the project record (project.legacy) by `vbw legacy
# choose`, so it is asked once per project, whatever the session or worktree.
# Starting fresh converts nothing and leaves the old folder untouched.
# Hermetic projects (L1).

load helper

setup() {
  vbw_setup
  vbw_git_project
  mkdir -p .vbw-planning/phases/01-a
  printf '# Project\n' > .vbw-planning/PROJECT.md
  printf 'plan\n' > .vbw-planning/phases/01-a/01-01-PLAN.md
  git add -A && git commit -q -m "chore: VBW 1 plan"
  "$VBW" init > /dev/null
  git add -A && git commit -q -m "chore: init"
}

teardown() { vbw_teardown; }

tree_hash() { find .vbw-planning -type f -print0 | LC_ALL=C sort -z | xargs -0 cat | git hash-object --stdin; }

@test "R65: choosing fresh is stored with the time; the review then shows the choice and that it was asked" {
  run "$VBW" legacy choose fresh
  [ "$status" -eq 0 ]
  jq -e '.project.legacy.choice == "fresh" and (.project.legacy.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))' .vbw/record.json
  run "$VBW" legacy review
  printf '%s' "$output" | jq -e '.choice == "fresh" and .asked == true'
}

@test "R65: choosing convert is stored too, and conversion itself is not marked done" {
  run "$VBW" legacy choose convert
  [ "$status" -eq 0 ]
  jq -e '.project.legacy.choice == "convert" and (has("converted") | not)' .vbw/record.json
}

@test "R65: a new project has not been asked: the review says asked false, choice null" {
  run "$VBW" legacy review
  printf '%s' "$output" | jq -e '.asked == false and .choice == null'
}

@test "R65: the choice is remembered in the project, so another session or worktree path sees it and does not ask again" {
  "$VBW" legacy choose fresh > /dev/null
  VBW_SESSION_ID=another-session run "$VBW" legacy review
  printf '%s' "$output" | jq -e '.asked == true and .choice == "fresh"'
}

@test "R65: starting fresh converts nothing and leaves the old folder exactly as it was" {
  local before
  before=$(tree_hash)
  "$VBW" legacy choose fresh > /dev/null
  [ "$(tree_hash)" = "$before" ]
  [ -z "$(git status --porcelain -- .vbw-planning)" ]
  jq -e 'has("converted") | not' .vbw/record.json
  jq -e '(.requirements | length) == 0 and (.plans | length) == 0' .vbw/record.json
}

@test "R65: after fresh, vbw next no longer says convert; without a choice, or after convert, it still does" {
  run "$VBW" next --json
  printf '%s' "$output" | jq -e '.action == "convert"'
  "$VBW" legacy choose convert > /dev/null
  run "$VBW" next --json
  printf '%s' "$output" | jq -e '.action == "convert"'
  "$VBW" legacy choose fresh > /dev/null
  run "$VBW" next --json
  printf '%s' "$output" | jq -e '.action != "convert"'
}

@test "R65: the choice can be changed later: the latest wins and the record stays valid" {
  "$VBW" legacy choose fresh > /dev/null
  "$VBW" legacy choose convert > /dev/null
  jq -e '.project.legacy.choice == "convert"' .vbw/record.json
  run "$VBW" status
  [ "$status" -eq 0 ]
}

@test "R65: only convert or fresh is accepted; anything else is refused naming the choices and nothing is recorded" {
  run "$VBW" legacy choose maybe
  [ "$status" -ne 0 ]
  [[ "$output" == *"convert"* && "$output" == *"fresh"* ]]
  run "$VBW" legacy choose
  [ "$status" -ne 0 ]
  jq -e '(.project.legacy // null) == null' .vbw/record.json
}

@test "R65: with no VBW 1 folder there is nothing to choose: refused, nothing recorded" {
  rm -rf .vbw-planning
  run "$VBW" legacy choose fresh
  [ "$status" -ne 0 ]
  [[ "$output" == *".vbw-planning"* ]]
  jq -e '(.project.legacy // null) == null' .vbw/record.json
}

@test "R65: in a folder that is not a VBW project the choice is refused and writes nothing" {
  rm -rf .vbw
  run "$VBW" legacy choose fresh
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a VBW project"* ]]
  [ ! -e .vbw ]
}

@test "R65: a record with another project.legacy value is refused as corrupt" {
  jq '.project.legacy = {choice: "perhaps", at: "2026-01-01T00:00:00Z"}' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  run "$VBW" status
  [ "$status" -ne 0 ]
  [[ "$output" == *"project.legacy"* ]]
}

@test "R65: converting afterwards still works: legacy done marks it and keeps the old folder" {
  "$VBW" legacy choose convert > /dev/null
  local before
  before=$(tree_hash)
  run "$VBW" legacy "done"
  [ "$status" -eq 0 ]
  jq -e '.converted.from == ".vbw-planning" and .project.legacy.choice == "convert"' .vbw/record.json
  [ "$(tree_hash)" = "$before" ]
}

@test "R65: the help lists choose" {
  run "$VBW" --help
  [[ "$output" == *"legacy"*"choose"* ]]
}
