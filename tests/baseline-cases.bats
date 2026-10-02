#!/usr/bin/env bats
# R17: tools/baseline holds exactly seven cases. Each has fixtures/<fixture>/fixture.sh
# (seeds a git repo in the current directory), cases/<case>/check.sh (exit 0 only
# when solved) and cases/<case>/solution.sh (a known-correct solution applied in the
# workspace). The check fails on the untouched fixture and passes after solution.sh.

load helper

BASE="$BATS_TEST_DIRNAME/../tools/baseline"
CASES="fix-oneshot failing-check-fix brownfield-feature safety-destructive safety-secret hostile-repo markdown-deliverable"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

seed() { # CASE: seed its fixture into the current directory
  local fx
  fx="$(sed -n 's/^fixture=//p' "$BASE/cases/$1/case.meta")"
  [ -n "$fx" ]
  bash "$BASE/fixtures/$fx/fixture.sh" > /dev/null
}

untouched_fails() {
  [ -f "$BASE/cases/$1/check.sh" ]
  seed "$1"
  run bash "$BASE/cases/$1/check.sh"
  [ "$status" -ne 0 ]
}

solution_passes() {
  [ -f "$BASE/cases/$1/solution.sh" ]
  seed "$1"
  bash "$BASE/cases/$1/solution.sh" > /dev/null
  run bash "$BASE/cases/$1/check.sh"
  [ "$status" -eq 0 ]
}

@test "exactly the seven cases exist" {
  [ "$(ls -1 "$BASE/cases" | sort | tr '\n' ' ')" = "$(printf '%s\n' $CASES | sort | tr '\n' ' ')" ]
}

@test "every case has a request" {
  for c in $CASES; do [ -s "$BASE/cases/$c/request.txt" ]; done
}

@test "fix-oneshot: untouched fails" { untouched_fails fix-oneshot; }
@test "fix-oneshot: solution passes" { solution_passes fix-oneshot; }
@test "failing-check-fix: untouched fails" { untouched_fails failing-check-fix; }
@test "failing-check-fix: solution passes" { solution_passes failing-check-fix; }
@test "brownfield-feature: untouched fails" { untouched_fails brownfield-feature; }
@test "brownfield-feature: solution passes" { solution_passes brownfield-feature; }
@test "safety-destructive: untouched fails" { untouched_fails safety-destructive; }
@test "safety-destructive: solution passes" { solution_passes safety-destructive; }
@test "safety-secret: untouched fails" { untouched_fails safety-secret; }
@test "safety-secret: solution passes" { solution_passes safety-secret; }
@test "hostile-repo: untouched fails" { untouched_fails hostile-repo; }
@test "hostile-repo: solution passes" { solution_passes hostile-repo; }
@test "markdown-deliverable: untouched fails" { untouched_fails markdown-deliverable; }
@test "markdown-deliverable: solution passes" { solution_passes markdown-deliverable; }

@test "the README names each case, its fixture and its check" {
  for c in $CASES; do
    fx="$(sed -n 's/^fixture=//p' "$BASE/cases/$c/case.meta")"
    grep -q "$c" "$BASE/README.md"
    grep -q "$fx" "$BASE/README.md"
    grep -q "cases/$c/check.sh" "$BASE/README.md"
  done
}
