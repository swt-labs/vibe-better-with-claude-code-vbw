#!/usr/bin/env bash
# Print the benchmark results as markdown tables (R19).
#
#   report.sh [RUNS_DIR [VBW1_JSONL]]
#
# RUNS_DIR defaults to tools/baseline/results/runs, VBW1_JSONL to
# tools/baseline/results/2026-09-30-fix-oneshot-sonnet.jsonl. A record named in
# another record's rerun_of is superseded and left out; only *.json files are
# records (README.md is not). Every row cites the result files it summarises.
# VBW 1 rows come from its recorded runs (pass as recorded by check_passed, and cost) and are
# labelled inferred.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
dir="${1:-$HERE/results/runs}"
v1="${2:-$HERE/results/2026-09-30-fix-oneshot-sonnet.jsonl}"
[ -d "$dir" ] || { echo "report: no such directory: $dir" >&2; exit 2; }

files=()
while IFS= read -r -d '' f; do files[${#files[@]}]="$f"; done \
  < <(find "$dir" -maxdepth 1 -name '*.json' -print0 | sort -z)
[ "${#files[@]}" -gt 0 ] || { echo "report: no records in $dir" >&2; exit 2; }

# Paths are cited relative to the project when the directory lives under it.
prefix="${REPORT_CITE_PREFIX-tools/baseline/results/runs/}"

jq -rn --arg prefix "$prefix" '
  def money: (. * 100 | round) as $c
    | "$\($c / 100 | floor).\(($c % 100) | tostring | if length < 2 then "0" + . else . end)";
  def mean: add / length;
  def median: sort | if length % 2 == 1 then .[length / 2 | floor]
              else (.[length / 2 - 1] + .[length / 2]) / 2 end;
  def num: if . == (. | floor) then tostring else (. * 10 | round / 10 | tostring) end;
  def cite: map("`\($prefix)\(.f)`") | join(", ");
  def row($label; $g):
    ($g | map(.r)) as $r
    | "| \($label) | \($r | map(select(.pass)) | length)/\($r | length) | \($r | map(.user_inputs) | median | num) (\($r | map(.user_inputs) | min)-\($r | map(.user_inputs) | max)) | \($r | map(.cost_usd) | mean | money) | \($r | map(.tokens) | mean | round) | \($g | cite) |";
  def head($first): "| \($first) | Pass | User inputs median (range) | Mean cost | Mean tokens | Result files |\n|---|---|---|---|---|---|";
  def evidence: if . == "plain" then "plain Claude Code, L2" else "VBW 2, L3" end;
  [inputs | {f: (input_filename | split("/") | last), r: .}] as $all
  | ([$all[].r.rerun_of // empty]) as $sup
  | [$all[] | select(.f as $f | $sup | index($f) | not)] as $live
  | ($live | map(.r.case) | unique) as $cases
  | ($live | map(.r.model) | unique) as $models
  | "# Benchmark results\n",
    ( $cases[] as $c
      | "## Case: \($c)\n\n\(head("Model, arm (evidence level)"))",
        ( $models[] as $m | ("plain","vbw2") as $a
          | [$live[] | select(.r.case == $c and .r.model == $m and .r.arm == $a)]
          | select(length > 0)
          | row("\($m), \($a | evidence)"; .) ),
        "" ),
    ( "## Totals\n",
      ( $models[] as $m
        | "### \($m)\n\n\(head("Arm (evidence level)"))",
          ( ("plain","vbw2") as $a
            | [$live[] | select(.r.model == $m and .r.arm == $a)]
            | select(length > 0)
            | row($a | evidence; .) ),
          "" ) )
' "${files[@]}"

if [ -f "$v1" ]; then
  v1cite="${REPORT_CITE_V1-tools/baseline/results/}$(basename "$v1")"
  jq -rn --arg cite "$v1cite" '
    def money: (. * 100 | round) as $c
      | "$\($c / 100 | floor).\(($c % 100) | tostring | if length < 2 then "0" + . else . end)";
    [inputs] as $all
    | "## VBW 1 (inferred)\n",
      "Recorded runs of the fix-oneshot case on Sonnet, VBW 1.37.1 against plain Claude Code. Pass is the recorded check_passed, cost is the recorded cost. Labelled inferred.\n",
      "| Arm (evidence level) | Runs | Pass | Mean cost | Result file |\n|---|---|---|---|---|",
      ( ("plain","vbw") as $a
        | [$all[] | select(.arm == $a)] | select(length > 0)
        | "| \(if $a == "vbw" then "VBW 1, inferred" else "plain Claude Code, inferred" end) | \(length) | \(map(select(.check_passed == true)) | length)/\(length) | \(map(.cost_usd) | add / length | money) | `\($cite)` |" )
  ' "$v1"
fi
