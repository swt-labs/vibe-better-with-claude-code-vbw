#!/usr/bin/env bash
# Benchmark runner (R18): one run of one case, or the 42 runs of one model.
#
#   bench.sh ARM MODEL CASE RUN       one run (ARM plain|plain-ui|vbw2, MODEL sonnet-5.5|opus-5.5, RUN 1..3)
#   bench.sh rerun ARM MODEL CASE RUN a new record with rerun_of; the earlier record stays
#   bench.sh regrade ARM MODEL CASE RUN  the saved workspace graded again by the current check
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
# plain-ui: plain Claude Code in the same interactive app as vbw2 (same base
# context, settings and sandbox, the plugin not loaded): the case request typed,
# every question answered with the recommended option, finished when the session
# is idle with no question on screen. Its record is arm plain, level L3,
# results/runs/plain-MODEL-CASE-RUN.json (or BENCH_RUNS_DIR).
#
# A session that cannot be driven (a harness fault) exits 70 with no record.
#
# BENCH_ROUND=N (vbw2) writes the record of tuning round N as ...-rN.json, with
# rigor, round and tiers; BENCH_RUNS_DIR=.../results/adaptive keeps the adaptive
# set apart (verify-adaptive.sh checks it).
#
# Test seams: BENCH_CLAUDE, BENCH_L3, BENCH_NEXT, BENCH_RUNS_DIR, BENCH_SCRATCH, BENCH_CONFIG_DIR.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CLAUDE="${BENCH_CLAUDE:-claude}"
L3="${BENCH_L3:-$ROOT/tools/l3.sh}"
RUNS="${BENCH_RUNS_DIR:-$HERE/results/runs}"
SCRATCH="${BENCH_SCRATCH:-$ROOT/.vbw/runtime/bench}"
CONFIG_DIR="${BENCH_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
CASES="fix-oneshot failing-check-fix brownfield-feature safety-destructive safety-secret hostile-repo markdown-deliverable"
LIMIT_RE='usage limit|hit your .*limit|reached your .*limit|limit reached'
EXIT_LIMIT=75
EXIT_FAULT=70
MAX_ROUNDS=90

usage() { sed -n '3,8p' "$0" >&2; exit 2; }

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
  # The run's start: only transcripts written after it are this run's.
  touch "$ws.started"
  # Seed from a copy of the fixture script, so the workspace never holds extras.
  (cd "$ws" && VBW_BASELINE_NO_CACHE_LINK=1 bash "$HERE/fixtures/$(meta fixture "$case_name")/fixture.sh" > /dev/null)
  printf '%s\n' "$ws"
}

# Sum token usage over the session transcripts (main and subagents) this run
# wrote: a reused workspace path keeps earlier runs' transcripts beside them.
transcript_tokens() {
  local enc dir
  enc=$(printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g')
  dir="$CONFIG_DIR/projects/$enc"
  local files=()
  while IFS= read -r -d '' f; do files[${#files[@]}]="$f"; done \
    < <(find "$dir" -name '*.jsonl' -newer "$1.started" -print0 2> /dev/null)
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
  # A tuning round of a VBW 2 run is its own record (the earlier rounds stay).
  [ "${BENCH_ROUND:-0}" -eq 0 ] || [ "$1" != vbw2 ] || base="$base-r$BENCH_ROUND"
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

# The settings of a plain session: VBW off, and this repository's own
# maintainer instructions (CLAUDE.md, AGENTS.md) never read.
excludes_settings() {
  jq -cn --arg a "$ROOT/CLAUDE.md" --arg b "$ROOT/AGENTS.md" \
    '{enabledPlugins:{"vbw@vbw-marketplace":false},claudeMdExcludes:[$a,$b]}'
}

run_plain() {
  local model=$1 case_name=$2 n=$3 out=$4 ws result
  ws=$(seed plain "$model" "$case_name" "$n")
  result="$ws.result.json"
  (cd "$ws" && "$CLAUDE" -p --model "$(model_id "$model")" \
    --settings "$(excludes_settings)" \
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

# answer_question NAME SCREEN: answer the question on screen as a user who
# takes the proposal: a single choice gets its first (recommended) option; a
# multi-select gets every proposed option ticked (not the free-text line),
# then Submit. Returns 1 when no question is on screen.
answer_question() {
  local name=$1 screen=$2 n i
  printf '%s' "$screen" | grep -q 'Enter to select\|Ready to submit' || return 1
  if printf '%s' "$screen" | grep -q '^ *Submit *$'; then
    n=$(printf '%s\n' "$screen" | grep -E '^[^0-9]*[0-9]+\. \[ \] ' | grep -vc 'Type something' || true)
    for ((i = 0; i < n; i++)); do
      bash "$L3" keys "$name" Enter > /dev/null 2>&1 || true
      bash "$L3" keys "$name" Down > /dev/null 2>&1 || true
    done
    # Past the free-text line, onto Submit.
    bash "$L3" keys "$name" Down > /dev/null 2>&1 || true
  fi
  bash "$L3" keys "$name" Enter > /dev/null 2>&1 || true
}

# session_cost NAME: the session's cost from /cost, empty when unreadable.
session_cost() {
  local screen
  bash "$L3" keys "$1" Escape > /dev/null 2>&1 || true
  bash "$L3" type "$1" "/cost" > /dev/null 2>&1 || true
  screen=$(bash "$L3" wait "$1" 120 2> /dev/null) || true
  printf '%s' "$screen" | grep -oE '\$[0-9]+(\.[0-9]+)?' | head -1 | tr -d '$' || true
}

# plain-ui: the interactive app without the plugin, driven as a user: the
# request typed, a question answered with the recommended option (Enter), a
# Claude Code dialog that is not a question dismissed; the run is finished when
# the session settles idle with no question on screen.
run_plain_ui() {
  local model=$1 case_name=$2 n=$3 out=$4 ws name screen inputs=0 round=0 settled done=0
  ws=$(seed plain-ui "$model" "$case_name" "$n")
  name="bench-plain-${model//./-}-$case_name-$n"
  if ! bash "$L3" start "$name" "$ws" "$(model_id "$model")" plain > /dev/null 2>&1 \
      || ! bash "$L3" type "$name" "$(cat "$HERE/cases/$case_name/request.txt")" > /dev/null 2>&1; then
    bash "$L3" stop "$name" > /dev/null 2>&1 || true
    echo "bench: could not drive a session for $name; no record written" >&2
    return "$EXIT_FAULT"
  fi
  while [ "$round" -lt "$MAX_ROUNDS" ]; do
    round=$((round + 1))
    settled=1
    screen=$(bash "$L3" wait "$name" 60 2> /dev/null) || settled=0
    if printf '%s' "$screen" | grep -Eqi "$LIMIT_RE"; then
      bash "$L3" stop "$name" > /dev/null 2>&1 || true
      echo "bench: usage limit reached; no record written" >&2
      return "$EXIT_LIMIT"
    fi
    printf '%s' "$screen" | grep -q 'esc to interrupt' && continue
    if answer_question "$name" "$screen"; then
      inputs=$((inputs + 1))
      continue
    fi
    if printf '%s' "$screen" | grep -q 'Esc to cancel'; then
      bash "$L3" keys "$name" Escape > /dev/null 2>&1 || true
      continue
    fi
    [ "$settled" -eq 1 ] || continue
    done=1
    break
  done
  [ "$done" -eq 1 ] || echo "bench: $name did not go idle in $MAX_ROUNDS rounds" >&2
  local cost tokens pass
  cost=$(session_cost "$name")
  bash "$L3" stop "$name" > /dev/null 2>&1 || true
  tokens=$(transcript_tokens "$ws")
  if [ "${tokens:-0}" -eq 0 ]; then
    echo "bench: no session transcript for $name; no record written" >&2
    return "$EXIT_FAULT"
  fi
  pass=$(grade "$ws" "$case_name")
  write_record "$out" plain "$model" "$case_name" "$n" "$pass" "$tokens" "${cost:-0}" "$inputs" L3
}

# next_action WS: VBW's next step in the workspace, from the plugin under test.
next_action() {
  if [ -n "${BENCH_NEXT:-}" ]; then "$BENCH_NEXT" "$1"; return 0; fi
  (cd "$1" && bash "$ROOT/plugin/bin/vbw" next --json 2> /dev/null | jq -r '.action // "none"') || echo none
}

# vbw2: drive the session as a user, the way tools/l3-suite.sh does: answer a
# question with the recommended option, type /vbw:approve when VBW asks for
# approval, wait while a run works, type /vbw:vibe when the session goes quiet,
# and stop when the work is proven (ship, accept or milestone). Every typed or
# chosen input after the request counts in user_inputs. A session that cannot be
# driven is a harness fault: exit 70 and no record.
run_vbw2() {
  local model=$1 case_name=$2 n=$3 out=$4 ws name screen inputs=0 round=0 action cost done=0
  ws=$(seed vbw2 "$model" "$case_name" "$n")
  # No dots: tmux reads one in a session name as a window.pane separator.
  name="bench-${model//./-}-$case_name-$n"
  if ! bash "$L3" start "$name" "$ws" "$(model_id "$model")" > /dev/null 2>&1 \
      || ! bash "$L3" type "$name" "/vbw:vibe $(cat "$HERE/cases/$case_name/request.txt")" > /dev/null 2>&1; then
    bash "$L3" stop "$name" > /dev/null 2>&1 || true
    echo "bench: could not drive a session for $name; no record written" >&2
    return "$EXIT_FAULT"
  fi
  # Each round waits at most a minute, then acts on VBW's state: the screen
  # need not settle (the status line keeps changing), and a finished run stops
  # whatever the screen shows.
  local settled nudges=0 last_state="" state
  while [ "$round" -lt "$MAX_ROUNDS" ]; do
    round=$((round + 1))
    settled=1
    screen=$(bash "$L3" wait "$name" 60 2> /dev/null) || settled=0
    if printf '%s' "$screen" | grep -Eqi "$LIMIT_RE"; then
      bash "$L3" stop "$name" > /dev/null 2>&1 || true
      echo "bench: usage limit reached; no record written" >&2
      return "$EXIT_LIMIT"
    fi
    action=$(next_action "$ws")
    case "$action" in ship | accept | milestone) done=1; break ;; esac
    printf '%s' "$screen" | grep -q 'esc to interrupt' && continue
    if answer_question "$name" "$screen"; then
      inputs=$((inputs + 1))
      continue
    fi
    # A Claude Code dialog that is not a VBW question (onboarding, tips):
    # dismissed, never answered, and not a user input.
    if printf '%s' "$screen" | grep -q 'Esc to cancel'; then
      bash "$L3" keys "$name" Escape > /dev/null 2>&1 || true
      continue
    fi
    case "$action" in
      approve) bash "$L3" type "$name" "/vbw:approve" > /dev/null 2>&1 || true; inputs=$((inputs + 1)) ;;
      run) ;;
      *)
        # Only a settled, idle session is asked to continue, and a session
        # whose state three nudges did not change has stopped: the run ends.
        [ "$settled" -eq 1 ] || continue
        state="$action $(git -C "$ws" rev-parse HEAD 2> /dev/null)"
        if [ "$state" = "$last_state" ]; then nudges=$((nudges + 1)); else nudges=1; last_state=$state; fi
        [ "$nudges" -le 3 ] || break
        bash "$L3" type "$name" "/vbw:vibe" > /dev/null 2>&1 || true; inputs=$((inputs + 1)) ;;
    esac
  done
  [ "$done" -eq 1 ] || echo "bench: $name did not reach a finished step in $MAX_ROUNDS rounds" >&2
  cost=$(session_cost "$name")
  bash "$L3" stop "$name" > /dev/null 2>&1 || true
  local tokens pass
  tokens=$(transcript_tokens "$ws")
  if [ "${tokens:-0}" -eq 0 ]; then
    echo "bench: no session transcript for $name; no record written" >&2
    return "$EXIT_FAULT"
  fi
  pass=$(grade "$ws" "$case_name")
  write_record "$out" vbw2 "$model" "$case_name" "$n" "$pass" "$tokens" "${cost:-0}" "$inputs" L3
  # Whether VBW was set up at all: a session may do the task without it.
  local engaged=false
  [ -d "$ws/.vbw" ] && engaged=true
  # The adaptive-rigor fields: the setting in force (auto when unset), the
  # tuning round (BENCH_ROUND, 0 is the first run) and the phases' tiers.
  local rigor tiers=[]
  if [ -f "$ws/.vbw/record.json" ]; then
    rigor=$(jq -r '.settings.rigor // "auto"' "$ws/.vbw/record.json" 2> /dev/null || echo auto)
    tiers=$(jq -c '[.phases[]? | .tier // empty]' "$ws/.vbw/record.json" 2> /dev/null || echo '[]')
  else
    rigor=auto
  fi
  jq --argjson e "$engaged" --arg rigor "$rigor" --argjson round "${BENCH_ROUND:-0}" --argjson tiers "$tiers" \
    '. + {vbw_engaged: $e, rigor: $rigor, round: $round, tiers: $tiers}' "$out" > "$out.tmp" && mv "$out.tmp" "$out"
}

run_one() {
  local arm=$1 model=$2 case_name=$3 n=$4 out rc=0
  case "$arm" in plain | plain-ui | vbw2) ;; *) usage ;; esac
  model_id "$model" > /dev/null
  [ -d "$HERE/cases/$case_name" ] || { echo "bench: unknown case: $case_name" >&2; exit 2; }
  case "$n" in 1 | 2 | 3) ;; *) usage ;; esac
  # plain-ui writes the plain arm's record (arm plain, level L3).
  record_path "${arm%-ui}" "$model" "$case_name" "$n"
  out=$REC
  if [ -e "$out" ] && [ "${rerun:-0}" -eq 0 ]; then
    echo "bench: skip $(basename "$out") (exists)" >&2
    return 0
  fi
  "run_${arm//-/_}" "$model" "$case_name" "$n" "$out" || rc=$?
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

# regrade ARM MODEL CASE RUN: grade the run's saved workspace again with the
# current check (after a case check is corrected), as a new record with
# rerun_of and regraded; tokens, cost and inputs are the run's, unchanged.
regrade() {
  local arm=$1 model=$2 case_name=$3 n=$4 ws src pass
  ws="$SCRATCH/$arm-$model-$case_name-$n"
  rerun=1 record_path "$arm" "$model" "$case_name" "$n"
  src="$RUNS/$RERUN_OF"
  [ -d "$ws" ] && [ -f "$src" ] || { echo "bench: no saved workspace or record for $arm-$model-$case_name-$n" >&2; exit 2; }
  pass=$(grade "$ws" "$case_name")
  # A VBW 2 run also records whether VBW was set up, read from its workspace.
  local engaged=null
  [ "$arm" != vbw2 ] || { engaged=false; [ ! -d "$ws/.vbw" ] || engaged=true; }
  jq --argjson pass "$pass" --arg of "$RERUN_OF" --arg date "$(date -u +%F)" --argjson e "$engaged" \
    '.pass = $pass | .rerun_of = $of | .regraded = true | .date = $date
     | if $e == null then . else .vbw_engaged = $e end' "$src" > "$REC.tmp"
  mv "$REC.tmp" "$REC"
  echo "bench: wrote $(basename "$REC") (regraded: pass $pass)" >&2
}

rerun=0
case "${1:-}" in
  all) [ $# -eq 2 ] || usage; run_all "$2" ;;
  rerun) [ $# -eq 5 ] || usage; rerun=1; run_one "$2" "$3" "$4" "$5" ;;
  regrade) [ $# -eq 5 ] || usage; regrade "$2" "$3" "$4" "$5" ;;
  plain | plain-ui | vbw2) [ $# -eq 4 ] || usage; run_one "$1" "$2" "$3" "$4" ;;
  *) usage ;;
esac
