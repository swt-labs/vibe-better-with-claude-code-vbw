#!/usr/bin/env bash
# Benchmark runner (R18): one run of one case, or the 42 runs of one model.
#
#   bench.sh ARM MODEL CASE RUN       one run (ARM plain|vbw2, MODEL sonnet-5.5|opus-5.5, RUN 1..3)
#   bench.sh rerun ARM MODEL CASE RUN a new record with rerun_of; the earlier record stays
#   bench.sh all MODEL                the 42 runs of MODEL, resuming; vbw2 runs 4 at a time
#
# plain: headless `claude -p`, VBW not loaded, the case request as the prompt
# (level L2, user_inputs 0). vbw2: the real Claude Code TUI driven as a user
# through tools/l3.sh with the plugin from ./plugin: /vbw:vibe with the case
# request, every question answered with the recommended option, /vbw:approve typed
# when VBW asks, no [human] requirement ever accepted for the user; it stops when
# VBW reaches ship or a gate (level L3). Both arms are graded with the case's
# check.sh and write results/runs/ARM-MODEL-CASE-RUN.json. An existing record is
# skipped (an interrupted batch resumes) and never overwritten or deleted. A usage
# limit stops with exit 75 and writes no record.
#
# Test seams: BENCH_CLAUDE, BENCH_L3, BENCH_RUNS_DIR, BENCH_SCRATCH, BENCH_CONFIG_DIR.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CLAUDE="${BENCH_CLAUDE:-claude}"
L3="${BENCH_L3:-$ROOT/tools/l3.sh}"
RUNS="${BENCH_RUNS_DIR:-$HERE/results/runs}"
SCRATCH="${BENCH_SCRATCH:-$ROOT/.vbw/bench}"
CONFIG_DIR="${BENCH_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
CASES="fix-oneshot failing-check-fix brownfield-feature safety-destructive safety-secret hostile-repo markdown-deliverable"
LIMIT_RE='usage limit|hit your .*limit|reached your .*limit|limit reached'
EXIT_LIMIT=75
MAX_ROUNDS=40

usage() { sed -n '3,6p' "$0" >&2; exit 2; }

model_id() {
  case "$1" in
    sonnet-5.5) echo "${BENCH_MODEL_SONNET:-claude-sonnet-5-5}" ;;
    opus-5.5) echo "${BENCH_MODEL_OPUS:-claude-opus-5-5}" ;;
    *) echo "bench: unknown model: $1" >&2; exit 2 ;;
  esac
}

meta() { sed -n "s/^$1=//p" "$HERE/cases/$2/case.meta"; }

# Seed a fresh workspace from the case's fixture; print its path.
seed() {
  local arm=$1 model=$2 case_name=$3 n=$4 ws
  ws="$SCRATCH/$arm-$model-$case_name-$n"
  rm -rf "$ws"
  mkdir -p "$ws"
  ws="$(cd "$ws" && pwd -P)"
  # Seed from a copy of the fixture script, so the workspace never holds extras.
  (cd "$ws" && VBW_BASELINE_NO_CACHE_LINK=1 bash "$HERE/fixtures/$(meta fixture "$case_name")/fixture.sh" > /dev/null)
  printf '%s\n' "$ws"
}

# Sum token usage over session transcripts (main and subagents) of a workspace.
transcript_tokens() {
  local enc dir
  enc=$(printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g')
  dir="$CONFIG_DIR/projects/$enc"
  local files=()
  while IFS= read -r -d '' f; do files[${#files[@]}]="$f"; done \
    < <(find "$dir" -name '*.jsonl' -print0 2> /dev/null)
  [ "${#files[@]}" -gt 0 ] || { echo 0; return 0; }
  jq -s '[ .[] | select(.type == "assistant" and (.message.usage != null)) ]
         | unique_by(.message.id // .uuid)
         | map(.message.usage | (.input_tokens // 0) + (.output_tokens // 0)
               + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
         | add // 0' "${files[@]}"
}

# Set REC to this run's record path; for a rerun a fresh name, and RERUN_OF to
# the record it re-runs (the latest earlier one).
REC="" RERUN_OF=""
record_path() {
  local base="$RUNS/$1-$2-$3-$4" k=1
  if [ "${rerun:-0}" -eq 0 ]; then REC="$base.json"; return 0; fi
  RERUN_OF=$(basename "$base.json")
  while [ -e "$base-rerun$k.json" ]; do RERUN_OF=$(basename "$base-rerun$k.json"); k=$((k + 1)); done
  REC="$base-rerun$k.json"
}

write_record() {
  local out=$1 arm=$2 model=$3 case_name=$4 n=$5 pass=$6 tokens=$7 cost=$8 inputs=$9 level=${10}
  mkdir -p "$RUNS"
  jq -n --arg arm "$arm" --arg model "$model" --arg case "$case_name" --argjson run "$n" \
    --argjson pass "$pass" --argjson tokens "$tokens" --argjson cost "$cost" \
    --argjson inputs "$inputs" --arg level "$level" --arg fixture "$(meta fixture "$case_name")" \
    --arg date "$(date -u +%F)" --arg rerun "$RERUN_OF" \
    '{arm:$arm, model:$model, case:$case, run:$run, pass:$pass, tokens:$tokens, cost_usd:$cost,
      user_inputs:$inputs, level:$level, fixture:$fixture, date:$date}
     + (if $rerun == "" then {} else {rerun_of:$rerun} end)' > "$out.tmp"
  mv "$out.tmp" "$out"
}

grade() { (cd "$1" && bash "$HERE/cases/$2/check.sh" > /dev/null 2>&1) && echo true || echo false; }

run_plain() {
  local model=$1 case_name=$2 n=$3 out=$4 ws result
  ws=$(seed plain "$model" "$case_name" "$n")
  result="$ws.result.json"
  (cd "$ws" && "$CLAUDE" -p --model "$(model_id "$model")" \
    --settings '{"enabledPlugins":{"vbw@vbw-marketplace":false}}' \
    --allowedTools Bash Write Edit --max-turns "$(meta max_turns "$case_name")" \
    --output-format json "$(cat "$HERE/cases/$case_name/request.txt")" \
    < /dev/null > "$result" 2> "$ws.stderr") || true
  if grep -Eqi "$LIMIT_RE" "$result" "$ws.stderr" 2> /dev/null; then
    echo "bench: usage limit reached; no record written" >&2
    return "$EXIT_LIMIT"
  fi
  local tokens cost pass
  tokens=$(jq '[.usage.input_tokens, .usage.output_tokens, .usage.cache_creation_input_tokens,
                .usage.cache_read_input_tokens] | map(. // 0) | add' "$result" 2> /dev/null || echo 0)
  cost=$(jq '.total_cost_usd // 0' "$result" 2> /dev/null || echo 0)
  pass=$(grade "$ws" "$case_name")
  write_record "$out" plain "$model" "$case_name" "$n" "$pass" "${tokens:-0}" "${cost:-0}" 0 L2
}

run_vbw2() {
  local model=$1 case_name=$2 n=$3 out=$4 ws name screen prev="" inputs=0 round=0 cost
  ws=$(seed vbw2 "$model" "$case_name" "$n")
  name="bench-$model-$case_name-$n"
  "$L3" start "$name" "$ws" "$(model_id "$model")" > /dev/null
  "$L3" type "$name" "/vbw:vibe $(cat "$HERE/cases/$case_name/request.txt")"
  while [ "$round" -lt "$MAX_ROUNDS" ]; do
    round=$((round + 1))
    screen=$("$L3" wait "$name" 1800 2> /dev/null) || true
    if printf '%s' "$screen" | grep -Eqi "$LIMIT_RE"; then
      "$L3" stop "$name" || true
      echo "bench: usage limit reached; no record written" >&2
      return "$EXIT_LIMIT"
    fi
    # The same screen after an answer means nothing is left to answer: a gate.
    [ "$screen" != "$prev" ] || break
    prev=$screen
    if printf '%s' "$screen" | grep -Eq 'Enter to select|\(Recommended\)'; then
      "$L3" keys "$name" Enter
      inputs=$((inputs + 1))
    elif printf '%s' "$screen" | grep -q '/vbw:approve'; then
      "$L3" type "$name" "/vbw:approve"
      inputs=$((inputs + 1))
    else
      break
    fi
  done
  "$L3" type "$name" "/cost"
  screen=$("$L3" wait "$name" 120 2> /dev/null) || true
  cost=$(printf '%s' "$screen" | grep -oE '\$[0-9]+(\.[0-9]+)?' | head -1 | tr -d '$' || true)
  "$L3" stop "$name" || true
  local tokens pass
  tokens=$(transcript_tokens "$ws")
  pass=$(grade "$ws" "$case_name")
  write_record "$out" vbw2 "$model" "$case_name" "$n" "$pass" "$tokens" "${cost:-0}" "$inputs" L3
}

run_one() {
  local arm=$1 model=$2 case_name=$3 n=$4 out rc=0
  case "$arm" in plain | vbw2) ;; *) usage ;; esac
  model_id "$model" > /dev/null
  [ -d "$HERE/cases/$case_name" ] || { echo "bench: unknown case: $case_name" >&2; exit 2; }
  case "$n" in 1 | 2 | 3) ;; *) usage ;; esac
  record_path "$arm" "$model" "$case_name" "$n"
  out=$REC
  if [ -e "$out" ] && [ "${rerun:-0}" -eq 0 ]; then
    echo "bench: skip $(basename "$out") (exists)" >&2
    return 0
  fi
  "run_$arm" "$model" "$case_name" "$n" "$out" || rc=$?
  [ "$rc" -eq 0 ] && echo "bench: wrote $(basename "$out")" >&2
  return "$rc"
}

run_all() {
  local model=$1 c n limit=0 pids=() p
  model_id "$model" > /dev/null
  for c in $CASES; do for n in 1 2 3; do
    [ -e "$RUNS/plain-$model-$c-$n.json" ] || bash "$0" plain "$model" "$c" "$n" || [ "$?" -ne "$EXIT_LIMIT" ] || return "$EXIT_LIMIT"
  done; done
  for c in $CASES; do for n in 1 2 3; do
    [ -e "$RUNS/vbw2-$model-$c-$n.json" ] || {
      bash "$0" vbw2 "$model" "$c" "$n" &
      pids[${#pids[@]}]=$!
    }
    if [ "${#pids[@]}" -ge 4 ]; then
      for p in "${pids[@]}"; do wait "$p" || [ "$?" -ne "$EXIT_LIMIT" ] || limit=1; done
      pids=()
      [ "$limit" -eq 0 ] || return "$EXIT_LIMIT"
    fi
  done; done
  for p in ${pids[@]+"${pids[@]}"}; do wait "$p" || [ "$?" -ne "$EXIT_LIMIT" ] || limit=1; done
  [ "$limit" -eq 0 ] || return "$EXIT_LIMIT"
  return 0
}

rerun=0
case "${1:-}" in
  all) [ $# -eq 2 ] || usage; run_all "$2" ;;
  rerun) [ $# -eq 5 ] || usage; rerun=1; run_one "$2" "$3" "$4" "$5" ;;
  plain | vbw2) [ $# -eq 4 ] || usage; run_one "$1" "$2" "$3" "$4" ;;
  *) usage ;;
esac
