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

# report.sh on a synthetic result set (L1).
rec() { # DIR NAME ARM MODEL CASE RUN PASS TOKENS COST INPUTS [EXTRA-JSON]
  jq -n --arg a "$3" --arg m "$4" --arg c "$5" --argjson n "$6" --argjson p "$7" \
    --argjson t "$8" --argjson k "$9" --argjson i "${10}" --argjson x "${11:-{\}}" \
    '{arm:$a,model:$m,case:$c,run:$n,pass:$p,tokens:$t,cost_usd:$k,user_inputs:$i,
      level:(if $a == "plain" then "L2" else "L3" end),fixture:$c} + $x' > "$1/$2.json"
}

synthetic() {
  S="$BATS_TEST_TMPDIR/runs"; mkdir -p "$S"
  rec "$S" plain-m-c-1 plain m c 1 true 100 0.10 0
  rec "$S" plain-m-c-2 plain m c 2 false 200 0.20 0
  rec "$S" plain-m-c-3 plain m c 3 true 300 0.30 0
  rec "$S" vbw2-m-c-1 vbw2 m c 1 true 1000 1.00 1
  rec "$S" vbw2-m-c-2 vbw2 m c 2 true 2000 2.00 5
  rec "$S" vbw2-m-c-3-old vbw2 m c 3 false 9999 9.00 9
  rec "$S" vbw2-m-c-3 vbw2 m c 3 true 3000 3.00 3 '{"rerun_of":"vbw2-m-c-3-old.json"}'
  echo "not a record" > "$S/README.md"
  : > "$BATS_TEST_TMPDIR/v1.jsonl"
  printf '%s\n' '{"arm":"vbw","case":"fix-oneshot","model":"sonnet","cost_usd":0.2,"check_passed":true}' \
    '{"arm":"vbw","case":"fix-oneshot","model":"sonnet","cost_usd":0.4,"check_passed":true}' \
    > "$BATS_TEST_TMPDIR/v1.jsonl"
}

report() { REPORT_CITE_PREFIX="" REPORT_CITE_V1="" bash "$REPORT" "$S" "$BATS_TEST_TMPDIR/v1.jsonl"; }

@test "report.sh: pass rate, median and range, means, evidence levels" {
  synthetic
  run report
  [ "$status" -eq 0 ]
  [[ "$output" == *"| m, plain Claude Code, L2 | 2/3 | 0 (0-0) | \$0.20 | 200 |"* ]]
  [[ "$output" == *"| m, VBW 2, L3 | 3/3 | 3 (1-5) | \$2.00 | 2000 |"* ]]
}

@test "report.sh: a superseded record is excluded and the replacement counted" {
  synthetic
  run report
  [[ "$output" != *"vbw2-m-c-3-old"* ]]
  [[ "$output" == *"\`vbw2-m-c-3.json\`"* ]]
  [[ "$output" != *"9999"* ]]
}

@test "report.sh: a regraded record counts once, in place of the original" {
  synthetic
  rec "$S" plain-m-c-2-rerun1 plain m c 2 true 200 0.20 0 '{"rerun_of":"plain-m-c-2.json","regraded":true}'
  run report
  [[ "$output" == *"| m, plain Claude Code, L2 | 3/3 | 0 (0-0) | \$0.20 | 200 |"* ]]
  [[ "$output" != *"\`plain-m-c-2.json\`"* ]]
}

@test "report.sh: README.md is not a record, totals per model, VBW 1 inferred" {
  synthetic
  run report
  [[ "$output" != *"README"* ]]
  [[ "$output" == *"## Totals"* ]]
  [[ "$output" == *"### m"* ]]
  [[ "$output" == *"## VBW 1 (inferred)"* ]]
  [[ "$output" == *"| VBW 1, inferred | 2 | \$0.30 |"* ]]
}

@test "report.sh: an empty or missing directory is an error" {
  run bash "$REPORT" "$BATS_TEST_TMPDIR/none"
  [ "$status" -eq 2 ]
  mkdir "$BATS_TEST_TMPDIR/empty"
  run bash "$REPORT" "$BATS_TEST_TMPDIR/empty"
  [ "$status" -eq 2 ]
}
