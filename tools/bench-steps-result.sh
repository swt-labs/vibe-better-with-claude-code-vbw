#!/usr/bin/env bash
# R243 (T212): record the step tables of one bench-steps.yml run (GitHub's runners) in
# tools/probes/guard-steps.json. Usage: bench-steps-result.sh RUN_ID before|after
# Reads the run with gh run view (read only): each job is named 'Steps (<runner>)', its
# 'Step table' step prints the net rows, each cell 'ms (quotient to the reference run)'.
# Merges {id, sha, when, tables: {<runner>: {<row>: [{ms, q} x4]}}} into the file by run id.
set -euo pipefail

[ $# -eq 2 ] && [[ "$1" =~ ^[0-9]+$ ]] && { [ "$2" = before ] || [ "$2" = after ]; } \
  || { echo "usage: bench-steps-result.sh RUN_ID before|after" >&2; exit 2; }
run=$1 when=$2
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/tools/probes/guard-steps.json"

sha=$(gh run view "$run" --json headSha --jq .headSha)
log=$(gh run view "$run" --log)

# One line per net row: runner, row name, then ms and quotient of the four columns.
cells=$(printf '%s\n' "$log" | awk -F'\t' '
  $2 == "Step table" && $1 ~ /^Steps \(.*\)$/ {
    runner = $1; sub(/^Steps \(/, "", runner); sub(/\)$/, "", runner)
    text = $3; sub(/^[^ ]* /, "", text)
    if (match(text, /^(shell prelude|program compile|program run|reference compile|reference run) +/)) {
      name = substr(text, 1, RLENGTH); sub(/ +$/, "", name)
      rest = substr(text, RLENGTH + 1); gsub(/[()]/, "", rest)
      printf "%s\t%s\t%s\n", runner, name, rest
    }
  }')
[ -n "$cells" ] || { echo "no step table in run $run" >&2; exit 1; }

mkdir -p "$(dirname "$out")"
[ -f "$out" ] || printf '{"probe":"guard-steps","runs":[]}\n' > "$out"

printf '%s\n' "$cells" | jq -R -s --arg id "$run" --arg sha "$sha" --arg when "$when" --slurpfile old "$out" '
  { id: $id, sha: $sha, when: $when,
    tables: (split("\n") | map(select(length > 0) | split("\t"))
      | map({runner: .[0], row: .[1], cells: (.[2] | split(" +"; null) | map(select(length > 0) | tonumber)
          | [range(0; length; 2) as $i | {ms: .[$i], q: .[$i + 1]}])})
      | group_by(.runner) | map({key: .[0].runner, value: (map({key: .row, value: .cells}) | from_entries)}) | from_entries) } as $new
  | if ($new.tables | length > 0) and all($new.tables[]; length == 5 and all(.[]; length == 4))
    then $old[0] | .runs = ([.runs[] | select(.id != $new.id)] + [$new])
    else error("run " + $id + " has no net rows with quotients (a table older than the net rows)") end' > "$out.new" \
  || { rm -f "$out.new"; exit 1; }
mv "$out.new" "$out"
