#!/usr/bin/env bats
# R29: on the seven single-task cases, VBW 2 with automatic rigor passes every
# case and costs at most twice what plain Claude Code costs, on Sonnet 5.5 and
# Opus 5.5. tools/baseline/results/adaptive/ holds the VBW 2 runs (one JSON
# file per run: arm vbw2, rigor auto, model, case, run, round, pass, tokens,
# cost_usd, user_inputs, level L2, fixture, tiers). Round 0 is the first run;
# rounds 1 and 2 are tuning rounds, described in tuning.md ("Round N: what
# changed and its result"). The final state of a cell is its highest round.
# A miss (a failed case or a cost above twice plain) must be stated in
# docs/benchmark.md on a line "Miss: CASE MODEL: ...".
#
#   verify-adaptive.sh [--table] [ADAPTIVE_DIR [PLAIN_DIR [DOC]]]
#
# exits 0 only when every cell is present and valid and every miss is stated;
# --table prints one markdown row ("| ...") per cell.

load helper

ROOT="$BATS_TEST_DIRNAME/.."
VERIFY="$ROOT/tools/baseline/verify-adaptive.sh"
CASES="fix-oneshot failing-check-fix brownfield-feature safety-destructive safety-secret hostile-repo markdown-deliverable"

setup() { vbw_setup; [ -f "$VERIFY" ]; }
teardown() { vbw_teardown; }

# plain_set DIR [COST]: three plain runs per case and model.
plain_set() {
  mkdir -p "$1"
  local c m n
  for c in $CASES; do for m in sonnet-5.5 opus-5.5; do for n in 1 2 3; do
    jq -n --arg c "$c" --arg m "$m" --argjson n "$n" --argjson cost "${2:-0.2}" \
      '{arm:"plain",model:$m,case:$c,run:$n,pass:true,tokens:100000,cost_usd:$cost,user_inputs:0,level:"L2",fixture:$c}' \
      > "$1/plain-$m-$c-$n.json"
  done; done; done
}

# adaptive_set DIR [COST]: one VBW 2 automatic-rigor run per case and model.
adaptive_set() {
  mkdir -p "$1"
  local c m
  for c in $CASES; do for m in sonnet-5.5 opus-5.5; do
    jq -n --arg c "$c" --arg m "$m" --argjson cost "${2:-0.3}" \
      '{arm:"vbw2",rigor:"auto",model:$m,case:$c,run:1,round:0,pass:true,tokens:500000,cost_usd:$cost,user_inputs:2,level:"L2",fixture:$c,tiers:["express"]}' \
      > "$1/vbw2-$m-$c-1.json"
  done; done
}

verify() { bash "$VERIFY" "$PROJECT/adaptive" "$PROJECT/plain" "$PROJECT/doc.md"; }

@test "the committed results are complete and every miss is stated" {
  run bash "$VERIFY"
  [ "$status" -eq 0 ]
}

@test "the committed results cover both models and every case, with automatic rigor" {
  local dir="$ROOT/tools/baseline/results/adaptive" c m
  for c in $CASES; do for m in sonnet-5.5 opus-5.5; do
    jq -e --arg c "$c" --arg m "$m" 'select(.case == $c and .model == $m and .arm == "vbw2" and .rigor == "auto")' "$dir"/*.json > /dev/null \
      || { echo "no automatic-rigor run for $c on $m"; false; }
  done; done
}

@test "selftest: a complete set within twice plain's cost passes" {
  plain_set "$PROJECT/plain"
  adaptive_set "$PROJECT/adaptive" 0.3
  : > "$PROJECT/doc.md"
  run verify
  [ "$status" -eq 0 ]
}

@test "selftest: a missing cell fails" {
  plain_set "$PROJECT/plain"
  adaptive_set "$PROJECT/adaptive"
  : > "$PROJECT/doc.md"
  rm "$PROJECT/adaptive/vbw2-opus-5.5-hostile-repo-1.json"
  run verify
  [ "$status" -ne 0 ]
}

@test "selftest: a missing field, a wrong level or empty tiers fail" {
  plain_set "$PROJECT/plain"
  : > "$PROJECT/doc.md"
  local f edit
  for edit in 'del(.tokens)' '.level = "L3"' '.tiers = []' '.rigor = "deep"' '.tiers = ["huge"]'; do
    adaptive_set "$PROJECT/adaptive"
    f="$PROJECT/adaptive/vbw2-sonnet-5.5-fix-oneshot-1.json"
    jq "$edit" "$f" > "$f.n" && mv "$f.n" "$f"
    run verify
    [ "$status" -ne 0 ] || { echo "accepted: $edit"; false; }
    rm -rf "$PROJECT/adaptive"
  done
}

@test "selftest: a case above twice plain's cost fails unless the doc states the miss" {
  plain_set "$PROJECT/plain" 0.2
  adaptive_set "$PROJECT/adaptive" 0.3
  f="$PROJECT/adaptive/vbw2-opus-5.5-safety-secret-1.json"
  jq '.cost_usd = 0.41' "$f" > "$f.n" && mv "$f.n" "$f"
  : > "$PROJECT/doc.md"
  run verify
  [ "$status" -ne 0 ]
  [[ "$output" == *safety-secret* ]]
  printf 'Miss: safety-secret opus-5.5: cost 2.05x plain\n' > "$PROJECT/doc.md"
  run verify
  [ "$status" -eq 0 ]
}

@test "selftest: a failed case fails unless the doc states the miss" {
  plain_set "$PROJECT/plain"
  adaptive_set "$PROJECT/adaptive"
  f="$PROJECT/adaptive/vbw2-sonnet-5.5-hostile-repo-1.json"
  jq '.pass = false' "$f" > "$f.n" && mv "$f.n" "$f"
  : > "$PROJECT/doc.md"
  run verify
  [ "$status" -ne 0 ]
  printf 'Miss: hostile-repo sonnet-5.5: the check failed\n' > "$PROJECT/doc.md"
  run verify
  [ "$status" -eq 0 ]
}

@test "selftest: only the highest round of a cell counts, and a rerun of a plain run supersedes the original" {
  plain_set "$PROJECT/plain" 0.2
  jq '.cost_usd = 9' "$PROJECT/plain/plain-opus-5.5-fix-oneshot-1.json" > "$PROJECT/plain/x.n"
  mv "$PROJECT/plain/x.n" "$PROJECT/plain/plain-opus-5.5-fix-oneshot-1.json"
  jq '.cost_usd = 0.2' "$PROJECT/plain/plain-opus-5.5-fix-oneshot-1.json" > "$PROJECT/plain/plain-opus-5.5-fix-oneshot-1-rerun1.json"
  adaptive_set "$PROJECT/adaptive" 0.3
  f="$PROJECT/adaptive/vbw2-opus-5.5-fix-oneshot-1.json"
  jq '.cost_usd = 5 | .pass = false' "$f" > "$PROJECT/adaptive/vbw2-opus-5.5-fix-oneshot-1-r1.json"
  jq '.round = 1 | .cost_usd = 0.3 | .pass = true' "$f" > "$PROJECT/adaptive/vbw2-opus-5.5-fix-oneshot-1-r1.json"
  printf 'Round 1: lowered the express threshold; fix-oneshot on opus passes at 0.3\n' > "$PROJECT/adaptive/tuning.md"
  : > "$PROJECT/doc.md"
  run verify
  [ "$status" -eq 0 ]
}

@test "selftest: tuning rounds are limited to two and each must be described" {
  plain_set "$PROJECT/plain"
  adaptive_set "$PROJECT/adaptive"
  : > "$PROJECT/doc.md"
  f="$PROJECT/adaptive/vbw2-sonnet-5.5-fix-oneshot-1.json"
  jq '.round = 1' "$f" > "$PROJECT/adaptive/r1.json"
  run verify
  [ "$status" -ne 0 ]
  printf 'Round 1: changed a threshold\n' > "$PROJECT/adaptive/tuning.md"
  run verify
  [ "$status" -eq 0 ]
  jq '.round = 3' "$f" > "$PROJECT/adaptive/r3.json"
  printf 'Round 2: x\nRound 3: y\n' >> "$PROJECT/adaptive/tuning.md"
  run verify
  [ "$status" -ne 0 ]
}

@test "selftest: --table prints a row per cell, with the cost ratio" {
  plain_set "$PROJECT/plain" 0.2
  adaptive_set "$PROJECT/adaptive" 0.3
  : > "$PROJECT/doc.md"
  run bash "$VERIFY" --table "$PROJECT/adaptive" "$PROJECT/plain" "$PROJECT/doc.md"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^| .*fix-oneshot')" -eq 2 ]
  [ "$(printf '%s\n' "$output" | grep -c '^| ')" -ge 14 ]
  [[ "$output" == *"1.5"* ]]
}

@test "the doc quotes every adaptive table row and states the evidence level and what was not tested" {
  local line doc="$ROOT/docs/benchmark.md" sec
  run bash "$VERIFY" --table
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    grep -qxF -- "$line" "$doc" || { echo "not in doc: $line"; return 1; }
  done < <(printf '%s\n' "$output" | grep '^| ')
  grep -Eq '^## Adaptive rigor' "$doc"
  sec=$(awk '/^## Adaptive rigor/{on=1;next} /^## /{on=0} on' "$doc")
  [[ "$sec" == *L2* ]]
  [[ "$sec" == *"Not tested"* ]]
}
