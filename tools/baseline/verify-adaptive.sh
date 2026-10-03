#!/usr/bin/env bash
# Verify the adaptive-rigor benchmark set (R29).
#
#   verify-adaptive.sh [--table] [ADAPTIVE_DIR [PLAIN_DIR [DOC]]]
#
# ADAPTIVE_DIR (default results/adaptive) holds one JSON file per VBW 2 run with
# automatic rigor; PLAIN_DIR (default results/plain-ui) the interactive plain
# runs (bench.sh plain-ui: same app and base context as VBW; level L3, and L2
# headless records are accepted too); DOC
# (default docs/benchmark.md) states the misses. Exits 0 only when
#   - every cell (7 cases x sonnet-5.5, opus-5.5) is present and valid
#     (arm vbw2, rigor auto, level L3, tiers a non-empty list of express,
#     standard or deep, every field typed); the highest round of a cell is final;
#   - at most 2 tuning rounds exist, each described in ADAPTIVE_DIR/tuning.md on
#     a line "Round N: ...";
#   - every miss (a failed case, or a cost above twice plain's) has a line
#     "Miss: CASE MODEL..." in DOC. Plain cost is the mean over the case's plain
#     runs of the latest rerun of each (a record with rerun_of supersedes it).
# --table prints one markdown row per cell (and the header) on stdout.
# Every problem is named on stderr.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
table=0
if [ "${1:-}" = "--table" ]; then table=1; shift; fi
adaptive="${1:-$HERE/results/adaptive}"
plain="${2:-$HERE/results/plain-ui}"
doc="${3:-$ROOT/docs/benchmark.md}"
[ -d "$adaptive" ] || { echo "verify-adaptive: no such directory: $adaptive" >&2; exit 2; }
[ -d "$plain" ] || { echo "verify-adaptive: no such directory: $plain" >&2; exit 2; }
[ -f "$doc" ] || doc=/dev/null
tuning="$adaptive/tuning.md"
[ -f "$tuning" ] || tuning=/dev/null

files=()
bad=0
while IFS= read -r -d '' f; do
  if jq -e 'type == "object"' "$f" > /dev/null 2>&1; then
    files[${#files[@]}]="$f"
  else
    echo "invalid JSON: $f" >&2
    bad=1
  fi
done < <(find "$adaptive" "$plain" -maxdepth 1 -name '*.json' -print0 | sort -z)

out=$(jq -n --rawfile doc "$doc" --rawfile tuning "$tuning" '
  def cases: ["fix-oneshot","failing-check-fix","brownfield-feature","safety-destructive","safety-secret","hostile-repo","markdown-deliverable"];
  def models: ["sonnet-5.5","opus-5.5"];
  def num: type == "number";
  def r2: ((. * 100) | round) / 100;
  [inputs | {f: (input_filename | split("/") | last), r: .}] as $all
  | ([$all[].r.rerun_of // empty]) as $superseded
  | [$all[] | select(.f as $f | $superseded | index($f) | not)] as $live
  | [$live[] | select(.r.arm == "vbw2")] as $ad
  | [$live[] | select(.r.arm == "plain" and (.r.cost_usd | num))] as $pl
  | ($doc | split("\n")) as $docl
  | ($tuning | split("\n")) as $tunl
  # The final record of a cell is its highest round; a record a later round replaced
  # is history and needs only what orders it (case, model, round).
  | [ $ad[] | select(.r | has("case") and has("model") and has("round") and (.round | num)) ] as $ordered
  | ( [ $ordered | group_by([.r.case, .r.model])[] | max_by(.r.round) ] ) as $final_files
  | [ ($ad[] | select(.r | has("case") and has("model") and has("round") and (.round | num) | not)), $final_files[]
      | .f as $f | .r as $r
      | ( ["arm","rigor","model","case","run","round","pass","tokens","cost_usd","user_inputs","level","fixture","tiers"][]
          | select(. as $k | $r | has($k) | not) | "\($f): missing field \(.)" ),
        ( ["run","round","tokens","cost_usd","user_inputs"][] | . as $k
          | select($r | has($k) and (.[$k] | num | not)) | "\($f): \($k) is not a number" ),
        ( if ($r | has("pass")) and ($r.pass | type) != "boolean" then "\($f): pass is not boolean" else empty end ),
        ( if ($r | has("rigor")) and $r.rigor != "auto" then "\($f): rigor \($r.rigor) is not auto" else empty end ),
        ( if ($r | has("level")) and $r.level != "L3" then "\($f): level \($r.level) is not L3" else empty end ),
        ( if ($r | has("tiers")) and (($r.tiers | type) != "array" or ($r.tiers | length) == 0
              or ($r.tiers | all(. == "express" or . == "standard" or . == "deep") | not))
          then "\($f): tiers must be a non-empty list of express, standard or deep" else empty end )
    ] as $field_problems
  | [ $ordered[].r ] as $valid
  | [ $final_files[].r ] as $final
  | ( [ cases[] as $c | models[] as $m
        | select([$final[] | select(.case == $c and .model == $m)] | length == 0)
        | "missing cell: \($c) \($m)" ] ) as $missing
  | ( [ $valid[].round ] | unique ) as $rounds
  | ( [ [ $rounds[] | select(. > 2) | "round \(.) exceeds the 2 tuning rounds allowed" ],
      [ $rounds[] | select(. > 0) | . as $n
        | select([$tunl[] | select(startswith("Round \($n):"))] | length == 0)
        | "round \($n) is not described in tuning.md (a line \"Round \($n): ...\")" ] ] ) as [$over, $undesc]
  | [ cases[] as $c | models[] as $m
      | ([$final[] | select(.case == $c and .model == $m)] | first) as $f
      | select($f != null)
      | ([$pl[] | .r | select(.case == $c and .model == $m)] | group_by(.run)) as $runs
      | (if ($runs | length) == 0 then null else ([$runs[] | (map(.cost_usd) | add / length)] | add / ($runs | length)) end) as $pc
      | ($docl | map(select(startswith("Miss: \($c) \($m)"))) | length > 0) as $stated
      | {c: $c, m: $m, f: $f, pc: $pc, stated: $stated,
         ratio: (if $pc == null or $pc == 0 then null else $f.cost_usd / $pc end)} ] as $cells
  | { table: ( ["| Case | Model | Pass | Cost (USD) | Plain (USD) | Ratio | Round | Tiers |"]
               + [ $cells[] | "| \(.c) | \(.m) | \(if .f.pass == true then "pass" else "fail" end) | \(.f.cost_usd | r2) | \(if .pc == null then "n/a" else (.pc | r2) end) | \(if .ratio == null then "n/a" else (.ratio | r2) end) | \(.f.round) | \(.f.tiers | if type == "array" then join(",") else "" end) |" ] ),
      problems: ( $field_problems + $missing + $over + $undesc
        + [ $cells[] | select(.pc == null) | "no plain runs for \(.c) \(.m)" ]
        + [ $cells[] | select(.stated | not)
            | (if .f.pass != true then "\(.c) \(.m): the case failed (state it as \"Miss: \(.c) \(.m): ...\" in the doc)" else empty end),
              (if .pc != null and .f.cost_usd > 2 * .pc then "\(.c) \(.m): cost \(.ratio | r2)x plain, above 2x (state it as \"Miss: \(.c) \(.m): ...\" in the doc)" else empty end) ] ) }
' "${files[@]+"${files[@]}"}") || bad=1

if [ "$table" -eq 1 ] && [ -n "$out" ]; then
  printf '%s\n' "$out" | jq -r '.table[]'
fi
if [ -n "$out" ] && [ "$(printf '%s\n' "$out" | jq '.problems | length')" -gt 0 ]; then
  printf '%s\n' "$out" | jq -r '.problems[]' >&2
  bad=1
fi
if [ "$bad" -ne 0 ]; then
  echo "verify-adaptive: FAILED" >&2
  exit 1
fi
echo "verify-adaptive: 14 cells complete" >&2
