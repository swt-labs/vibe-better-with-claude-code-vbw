#!/usr/bin/env bash
# Print the multi-requirement project results as markdown (R30).
#
#   report-projects.sh [RUNS_DIR]
#
# RUNS_DIR defaults to tools/baseline/results/projects. Only records of a
# project in tools/baseline/projects are read; a record named in another
# record's rerun_of is superseded. One table per project and model: plain Claude
# Code against VBW 2 with pass, mean tokens and mean cost; an arm with no runs
# gets a line saying so.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
dir="${1:-$HERE/results/projects}"
[ -d "$dir" ] || { echo "report-projects: no such directory: $dir" >&2; exit 2; }

projects=()
for p in "$HERE"/projects/*/; do projects[${#projects[@]}]=$(basename "$p"); done
list=$(printf '%s\n' "${projects[@]}" | jq -R . | jq -sc .)

files=()
while IFS= read -r -d '' f; do files[${#files[@]}]="$f"; done \
  < <(find "$dir" -maxdepth 1 -name '*.json' -print0 | sort -z)
[ "${#files[@]}" -gt 0 ] || { echo "report-projects: no records in $dir" >&2; exit 2; }

jq -rn --argjson projects "$list" '
  def money: (. * 100 | round) as $c
    | "$\($c / 100 | floor).\(($c % 100) | tostring | if length < 2 then "0" + . else . end)";
  def mean: add / length;
  [inputs | {f: (input_filename | split("/") | last), r: .}] as $all
  | ([$all[].r.rerun_of // empty]) as $sup
  | [$all[] | select(.f as $f | $sup | index($f) | not) | .r
       | select(.case as $c | $projects | index($c))] as $live
  | "# Project benchmark results\n",
    ( $projects[] as $p
      | [$live[] | select(.case == $p)] as $rows
      | select($rows | length > 0)
      | "## Project: \($p)\n",
        ( $rows | map(.model) | unique[] as $m
          | "### \($m)\n\n| Arm | Pass | Mean cost | Mean tokens |\n|---|---|---|---|",
            ( ({plain: "plain Claude Code", vbw2: "VBW 2"} | to_entries[]) as $a
              | [$rows[] | select(.model == $m and .arm == $a.key)] as $g
              | if ($g | length) == 0 then "| \($a.value) | No \($a.value) runs yet | | |"
                else "| \($a.value) | \($g | map(select(.pass)) | length)/\($g | length) | \($g | map(.cost_usd) | mean | money) | \($g | map(.tokens) | mean | round) |" end ),
            "" ) )
' "${files[@]}"
