#!/usr/bin/env bats
# R58: the estimates come from how long earlier steps took in this project. The
# kernel keeps that history in the clone's own cache, $(git common dir)/vbw/steps.json
# (like qa.json, D91): a finished run is one step. No new field in the record
# (D91, R46), nothing in a tracked file, and a cache that cannot be written
# never stops a run from ending. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  STEPS="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/steps.json"
}
teardown() { vbw_teardown; }

@test "R58: ending a run adds one finished step: its kind, run, start, end and seconds" {
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  [ -f "$STEPS" ]
  jq -e '.steps | length == 1' "$STEPS"
  jq -e '.steps[0] | (.kind == "plan") and (.run | test("^plan-[0-9TZ]+$")) and (.started_at | test("^[0-9-]+T[0-9:]+Z$")) and (.ended_at | test("^[0-9-]+T[0-9:]+Z$")) and (.seconds | type == "number" and . >= 0)' "$STEPS"
}

@test "R58: each kind of run is recorded under its own kind, oldest first" {
  "$VBW" run start plan > /dev/null; "$VBW" run end > /dev/null
  "$VBW" run start qa > /dev/null; "$VBW" run end > /dev/null
  "$VBW" run start map > /dev/null; "$VBW" run end > /dev/null
  jq -e '[.steps[].kind] == ["plan", "qa", "map"]' "$STEPS"
}

@test "R58: the seconds are the time between the run starting and ending" {
  "$VBW" run start plan > /dev/null
  jq '.lease.started_at = "2026-01-01T00:00:00Z" | .lease.run = "plan-20260101T000000Z"' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" run end > /dev/null
  jq -e '.steps[0].started_at == "2026-01-01T00:00:00Z" and .steps[0].run == "plan-20260101T000000Z" and (.steps[0].seconds > 86400 * 100)' "$STEPS"
}

@test "R58: only the latest 50 steps are kept" {
  mkdir -p "$(dirname "$STEPS")"
  jq -n '{steps: [range(0; 60) | {kind: "build", run: "build-\(.)", started_at: "2026-01-01T00:00:00Z", ended_at: "2026-01-01T00:01:00Z", seconds: 60}]}' > "$STEPS"
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  jq -e '(.steps | length) == 50 and .steps[-1].kind == "plan" and .steps[0].run == "build-11"' "$STEPS"
}

@test "R58: the history is in the clone's git directory: no tracked file and no record field is added" {
  local keys schema
  keys=$(jq -c 'keys' .vbw/record.json)
  schema=$(jq -c '.schema' .vbw/record.json)
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  [ "$(jq -c 'keys' .vbw/record.json)" = "$keys" ]
  [ "$(jq -c '.schema' .vbw/record.json)" = "$schema" ]
  [ -z "$(git status --porcelain)" ] || { git status --porcelain; false; }
  [ -z "$(git ls-files | grep steps.json || true)" ]
  jq -e 'tostring | test("\"seconds\"|\"steps\"") | not' .vbw/record.json
  [ -f "$STEPS" ]
}

@test "R58: a worktree shares its clone's history" {
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  git worktree add -q "$TEST_ROOT/wt" -b wt
  cd "$TEST_ROOT/wt"
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  [ "$(jq '.steps | length' "$STEPS")" -eq 2 ]
}

@test "R58: a history that cannot be written does not stop the run from ending, and a damaged one is replaced" {
  mkdir -p "$(dirname "$STEPS")"
  printf 'not json' > "$STEPS"
  "$VBW" run start plan > /dev/null
  run "$VBW" run end
  [ "$status" -eq 0 ]
  [[ "$output" == *"run ended"* ]]
  jq -e '.steps | length >= 1' "$STEPS"
  rm -f "$STEPS"
  mkdir -p "$STEPS"
  "$VBW" run start plan > /dev/null
  run "$VBW" run end
  [ "$status" -eq 0 ]
  [[ "$output" == *"run ended"* ]]
  [ -z "$(jq -r '.lease // empty' .vbw/record.json)" ]
}

@test "R58: a run ended with no run open adds no step" {
  run "$VBW" run end
  [ ! -f "$STEPS" ] || jq -e '.steps | length == 0' "$STEPS"
}

@test "R58: the record stays one an older VBW reads: same schema number before and after a step is recorded" {
  local schema
  schema=$(jq -c '.schema' .vbw/record.json)
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  [ "$(jq -c '.schema' .vbw/record.json)" = "$schema" ]
  run "$VBW" status
  [ "$status" -eq 0 ]
  [ -f "$STEPS" ]
}
