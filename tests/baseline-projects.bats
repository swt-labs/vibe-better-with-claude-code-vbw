#!/usr/bin/env bats
# R30: tools/baseline/projects holds three multi-requirement projects (a feature on
# an existing codebase with earlier requirements to protect, a data migration, a
# non-UI pipeline). Each has request.txt, case.meta, check.sh and solution.sh there
# and a fixture.sh in tools/baseline/fixtures/NAME. The check fails on the untouched
# fixture and passes after solution.sh.

load helper

BASE="$BATS_TEST_DIRNAME/../tools/baseline"
PROJECTS="protected-feature data-migration non-ui-pipeline"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

seed() { # PROJECT: seed its fixture into the current directory
  local fx
  fx="$(sed -n 's/^fixture=//p' "$BASE/projects/$1/case.meta")"
  [ "$fx" = "$1" ]
  bash "$BASE/fixtures/$fx/fixture.sh" > /dev/null
}

untouched_fails() {
  seed "$1"
  run bash "$BASE/projects/$1/check.sh"
  [ "$status" -ne 0 ]
}

solution_passes() {
  seed "$1"
  bash "$BASE/projects/$1/solution.sh" > /dev/null
  run bash "$BASE/projects/$1/check.sh"
  [ "$status" -eq 0 ]
}

@test "exactly the three projects exist" {
  [ "$(ls -1 "$BASE/projects" | sort | tr '\n' ' ')" = "$(printf '%s\n' $PROJECTS | sort | tr '\n' ' ')" ]
}

@test "every project has a request, meta, check, solution and fixture" {
  for p in $PROJECTS; do
    [ -s "$BASE/projects/$p/request.txt" ]
    [ -s "$BASE/projects/$p/case.meta" ]
    [ -s "$BASE/projects/$p/check.sh" ]
    [ -s "$BASE/projects/$p/solution.sh" ]
    [ -s "$BASE/fixtures/$p/fixture.sh" ]
  done
}

@test "every request states several requirements" {
  for p in $PROJECTS; do [ "$(grep -c '^[0-9]\. ' "$BASE/projects/$p/request.txt")" -ge 3 ]; done
}

@test "protected-feature: untouched fails" { untouched_fails protected-feature; }
@test "protected-feature: solution passes" { solution_passes protected-feature; }
@test "protected-feature: the check fails when an earlier requirement breaks" {
  seed protected-feature
  bash "$BASE/projects/protected-feature/solution.sh" > /dev/null
  sed -i.bak 's/sort "\$f"/cat "$f"/' inv.sh
  run bash "$BASE/projects/protected-feature/check.sh"
  [ "$status" -ne 0 ]
}
@test "data-migration: untouched fails" { untouched_fails data-migration; }
@test "data-migration: solution passes" { solution_passes data-migration; }
@test "data-migration: the check fails when a row is lost" {
  seed data-migration
  bash "$BASE/projects/data-migration/solution.sh" > /dev/null
  sed -i.bak 's/select(length > 0)/select(length > 0 and (startswith("6,") | not))/' migrate.sh
  run bash "$BASE/projects/data-migration/check.sh"
  [ "$status" -ne 0 ]
}
@test "non-ui-pipeline: untouched fails" { untouched_fails non-ui-pipeline; }
@test "non-ui-pipeline: solution passes" { solution_passes non-ui-pipeline; }
@test "non-ui-pipeline: the check fails when malformed lines are counted as requests" {
  seed non-ui-pipeline
  bash "$BASE/projects/non-ui-pipeline/solution.sh" > /dev/null
  sed -i.bak 's/NF == 5 \&\& .*{/NF >= 1 {/' logstat.sh
  run bash "$BASE/projects/non-ui-pipeline/check.sh"
  [ "$status" -ne 0 ]
}
