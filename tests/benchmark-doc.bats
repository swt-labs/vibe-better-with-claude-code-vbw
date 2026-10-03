#!/usr/bin/env bats
# R19: docs/benchmark.md compares VBW 2 with plain Claude Code case by case, shows
# VBW 1 from its recorded runs, and says what was not measured. Its numbers are the
# output of tools/baseline/report.sh, so a changed result fails here until the doc is
# regenerated.

load helper

DOC="$BATS_TEST_DIRNAME/../docs/benchmark.md"
REPORT="$BATS_TEST_DIRNAME/../tools/baseline/report.sh"
ROOT="$BATS_TEST_DIRNAME/.."
CASES="fix-oneshot failing-check-fix brownfield-feature safety-destructive safety-secret hostile-repo markdown-deliverable"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "the doc has a section per case" {
  local c
  for c in $CASES; do grep -Eq "^## .*$c" "$DOC"; done
}

@test "the doc has Not measured and How it ran sections" {
  grep -Eq '^## Not measured' "$DOC"
  grep -Eq '^## How it ran' "$DOC"
}

@test "Not measured names the VBW 1 cases without data and the sample size" {
  local sec
  sec=$(awk '/^## Not measured/{on=1;next} /^## /{on=0} on' "$DOC")
  [[ "$sec" == *"VBW 1"* ]]
  [[ "$sec" == *"3 per cell"* ]]
}

@test "How it ran names the evidence levels" {
  local sec
  sec=$(awk '/^## How it ran/{on=1;next} /^## /{on=0} on' "$DOC")
  [[ "$sec" == *"plain"*"L2"* ]]
  [[ "$sec" == *"VBW 2"*"L3"* ]]
}

@test "VBW 1 is labelled inferred" {
  grep -q 'inferred' "$DOC"
}

@test "every cited result path exists" {
  local p n=0
  while IFS= read -r p; do
    [ -f "$ROOT/$p" ] || { echo "missing: $p"; return 1; }
    n=$((n + 1))
  done < <(grep -o 'tools/baseline/results/[A-Za-z0-9._/-]*\.jsonl\?' "$DOC" | sort -u)
  [ "$n" -gt 0 ]
}

@test "every table row of report.sh output is in the doc" {
  local line
  run bash "$REPORT"
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    grep -qxF -- "$line" "$DOC" || { echo "not in doc: $line"; return 1; }
  done < <(printf '%s\n' "$output" | grep '^| ')
}
