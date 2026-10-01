#!/usr/bin/env bats
# vbw legacy and vbw decide: converting a VBW 1 project (docs/convert.md) and
# recording the user's decisions.

load helper

setup() {
  vbw_setup
  vbw_git_project
  # A VBW 1 project: one shipped milestone (2 plans, both done) and a loose
  # phase with one of two plans done.
  local m=.vbw-planning/milestones/01-foundation
  mkdir -p "$m/phases/01-scraping" .vbw-planning/phases/02-alerts .vbw-planning/.cache
  printf '# Project\n' > .vbw-planning/PROJECT.md
  printf '# Requirements\n### REQ-01: Alerts\n' > .vbw-planning/REQUIREMENTS.md
  printf '# State\n' > .vbw-planning/STATE.md
  printf 'roadmap\n' > "$m/ROADMAP.md"
  printf 'shipped\n' > "$m/SHIPPED.md"
  touch "$m/phases/01-scraping/01-01-PLAN.md" "$m/phases/01-scraping/01-01-SUMMARY.md" \
        "$m/phases/01-scraping/01-02-PLAN.md" "$m/phases/01-scraping/01-02-SUMMARY.md" \
        .vbw-planning/phases/02-alerts/02-01-PLAN.md .vbw-planning/phases/02-alerts/02-01-SUMMARY.md \
        .vbw-planning/phases/02-alerts/02-02-PLAN.md
  git add .vbw-planning && git commit -q -m "chore(test): VBW 1 plan"
  printf 'cache\n' > .vbw-planning/.cache/ctx.md
}

teardown() { vbw_teardown; }

@test "legacy facts describe a VBW 1 project, before VBW 2 is set up, and change nothing" {
  local before
  before=$(find .vbw-planning -type f | LC_ALL=C sort | xargs cat | git hash-object --stdin)
  vbw_run legacy
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.legacy and (.converted | not) and .git == {tracked: 12, untracked: 1}'
  echo "$output" | jq -e '.files == [".vbw-planning/PROJECT.md", ".vbw-planning/REQUIREMENTS.md", ".vbw-planning/STATE.md",
    ".vbw-planning/milestones/01-foundation/ROADMAP.md", ".vbw-planning/milestones/01-foundation/SHIPPED.md"]'
  echo "$output" | jq -e '.milestones == [{dir: ".vbw-planning/milestones/01-foundation", shipped: true}]'
  echo "$output" | jq -e '[.phases[] | [.dir, .status]] == [[".vbw-planning/phases/02-alerts", "partly done"],
    [".vbw-planning/milestones/01-foundation/phases/01-scraping", "done"]]'
  [ ! -e .vbw ]
  [ "$(find .vbw-planning -type f | LC_ALL=C sort | xargs cat | git hash-object --stdin)" = "$before" ]
}

@test "a project without a VBW 1 plan says so" {
  rm -rf .vbw-planning
  vbw_run legacy
  [ "$status" -eq 0 ]
  [ "$output" = '{"legacy": false}' ]
}

@test "done marks the conversion once; the old folder stays" {
  "$VBW" init > /dev/null
  vbw_run legacy done
  [ "$status" -eq 0 ]
  jq -e '.converted.from == ".vbw-planning" and (.converted.at | test("Z$"))' .vbw/record.json
  [[ "$(git log -1 --format=%s)" == "chore(vbw): convert the VBW 1 plan" ]]
  [ -f .vbw-planning/PROJECT.md ]
  vbw_run legacy
  echo "$output" | jq -e '.converted'
}

@test "remove is refused before the conversion, and deletes nothing" {
  "$VBW" init > /dev/null
  vbw_run legacy remove
  [ "$status" -eq 1 ]
  [[ "$output" == *"not converted yet"* ]]
  [ -f .vbw-planning/PROJECT.md ]
}

@test "remove deletes the folder with a commit of that deletion only; the user's staged work stays" {
  "$VBW" init > /dev/null
  "$VBW" legacy done > /dev/null
  printf 'mine\n' > staged.txt && git add staged.txt
  vbw_run legacy remove
  [ "$status" -eq 0 ]
  [[ "$output" == *"stay in git history"* ]]
  [ ! -e .vbw-planning ]
  [[ "$(git log -1 --format=%s)" == "chore(vbw): remove the VBW 1 plan (converted to .vbw/)" ]]
  ! git show --name-only --format= HEAD | grep -qv '^\.vbw-planning/'
  git diff --cached --name-only | grep -qx staged.txt
  git show HEAD~1:.vbw-planning/PROJECT.md > /dev/null
}

@test "remove of an untracked folder says it was not in git" {
  git rm -r -q --cached .vbw-planning && git commit -q -m "chore(test): untrack"
  "$VBW" init > /dev/null
  "$VBW" legacy done > /dev/null
  vbw_run legacy remove
  [ "$status" -eq 0 ]
  [[ "$output" == *"it was not in git"* ]]
  [ ! -e .vbw-planning ]
}

@test "decide records a decision, with or without its reason" {
  "$VBW" init > /dev/null
  vbw_run decide "Store jobs in SQLite" "works offline; no server to run"
  [ "$status" -eq 0 ]
  [[ "$output" == "recorded D1: Store jobs in SQLite" ]]
  "$VBW" decide "Telegram for alerts" > /dev/null
  jq -e '.decisions[0].why == "works offline; no server to run" and (.decisions[1] | has("why") | not)' .vbw/record.json
  vbw_run decide ""
  [ "$status" -eq 2 ]
  vbw_run decide "x" ""
  [ "$status" -eq 2 ]
}
