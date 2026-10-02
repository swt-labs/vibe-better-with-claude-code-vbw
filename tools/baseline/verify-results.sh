#!/usr/bin/env bash
# Verify the benchmark's committed results (R18).
#
#   verify-results.sh [DIR]    DIR defaults to tools/baseline/results/runs
#
# Exits 0 only if the 84 runs (7 cases x 2 arms x 2 models x 3) are each present
# exactly once with every field, a level matching the arm (plain L2, vbw2 L3) and
# user_inputs. A record with rerun_of (the file name of an earlier record)
# supersedes that record. Every problem is named on stderr.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
dir="${1:-$HERE/results/runs}"
[ -d "$dir" ] || { echo "verify-results: no such directory: $dir" >&2; exit 2; }

files=()
while IFS= read -r -d '' f; do files[${#files[@]}]="$f"; done \
  < <(find "$dir" -maxdepth 1 -name '*.json' -print0 | sort -z)

bad=0
good=()
for f in ${files[@]+"${files[@]}"}; do
  if jq -e 'type == "object"' "$f" > /dev/null 2>&1; then
    good[${#good[@]}]="$f"
  else
    echo "invalid JSON: $(basename "$f")" >&2
    bad=1
  fi
done

problems=$(jq -rn '
  def cases: ["fix-oneshot","failing-check-fix","brownfield-feature","safety-destructive","safety-secret","hostile-repo","markdown-deliverable"];
  def want: [cases[] as $c | ("plain","vbw2") as $a | ("sonnet-5.5","opus-5.5") as $m | (1,2,3) as $n
             | {arm:$a, model:$m, case:$c, run:$n}];
  def key: "\(.arm)/\(.model)/\(.case)/\(.run)";
  def complete: has("arm") and has("model") and has("case") and has("run");
  [inputs | {f: (input_filename | split("/") | last), r: .}] as $all
  | ([$all[].r.rerun_of // empty]) as $superseded
  | [$all[] | select(.f as $f | $superseded | index($f) | not)] as $live
  | ( $live[]
      | .f as $f | .r as $r
      | ( ["arm","model","case","run","pass","tokens","cost_usd","user_inputs","level","fixture"][]
          | select(. as $k | $r | has($k) | not) | "\($f): missing field \(.)" ),
        ( if ($r | has("pass")) and ($r.pass | type) != "boolean" then "\($f): pass is not boolean" else empty end ),
        ( ["tokens","cost_usd","user_inputs","run"][] | . as $k
          | select($r | has($k) and (.[$k] | type) != "number") | "\($f): \($k) is not a number" ),
        ( if ($r | has("fixture")) and ($r.fixture | type) != "string" then "\($f): fixture is not a string" else empty end ),
        ( if ($r.arm == "plain" and $r.level != "L2") or ($r.arm == "vbw2" and $r.level != "L3")
          then "\($f): level \($r.level) does not match arm \($r.arm)" else empty end )
    ),
    ( [$live[].r | select(complete)] | group_by(key) | .[] | select(length > 1) | "duplicate run: \(.[0] | key)" ),
    ( [$live[].r | select(complete) | key] as $have
      | want[] | select(key as $k | $have | index($k) | not) | "missing run: \(key)" )
' ${good[@]+"${good[@]}"} 2>&1) || bad=1

if [ -n "$problems" ]; then
  printf '%s\n' "$problems" >&2
  bad=1
fi
if [ "$bad" -ne 0 ]; then
  echo "verify-results: FAILED" >&2
  exit 1
fi
echo "verify-results: 84 runs complete"
