#!/usr/bin/env bats
# verify-adaptive.sh holds a cell's final record (its highest round) to every
# field rule; a record a later round replaced is history and needs only what
# orders it (case, model, round).

load helper

VERIFY="$BATS_TEST_DIRNAME/../tools/baseline/verify-adaptive.sh"
CASES="fix-oneshot failing-check-fix brownfield-feature safety-destructive safety-secret hostile-repo markdown-deliverable"

setup() {
  vbw_setup
  mkdir -p "$PROJECT/plain" "$PROJECT/adaptive"
  local c m
  for c in $CASES; do for m in sonnet-5.5 opus-5.5; do
    jq -n --arg c "$c" --arg m "$m" '{arm:"plain",model:$m,case:$c,run:1,pass:true,tokens:1,cost_usd:0.2,user_inputs:0,level:"L3",fixture:$c}' \
      > "$PROJECT/plain/plain-$m-$c-1.json"
    jq -n --arg c "$c" --arg m "$m" '{arm:"vbw2",rigor:"auto",model:$m,case:$c,run:1,round:0,pass:true,tokens:1,cost_usd:0.3,user_inputs:1,level:"L3",fixture:$c,tiers:["express"]}' \
      > "$PROJECT/adaptive/vbw2-$m-$c-1.json"
  done; done
  : > "$PROJECT/doc.md"
}
teardown() { vbw_teardown; }

verify() { bash "$VERIFY" "$PROJECT/adaptive" "$PROJECT/plain" "$PROJECT/doc.md"; }

@test "a replaced round-0 record with empty tiers does not fail the set" {
  f="$PROJECT/adaptive/vbw2-sonnet-5.5-markdown-deliverable-1.json"
  jq '.round = 1' "$f" > "$PROJECT/adaptive/vbw2-sonnet-5.5-markdown-deliverable-1-r1.json"
  jq '.tiers = [] | .user_inputs = 90' "$f" > "$f.n" && mv "$f.n" "$f"
  printf 'Round 1: x\n' > "$PROJECT/adaptive/tuning.md"
  run verify
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a final record with empty tiers still fails" {
  f="$PROJECT/adaptive/vbw2-sonnet-5.5-markdown-deliverable-1.json"
  jq '.tiers = []' "$f" > "$f.n" && mv "$f.n" "$f"
  run verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"tiers must be"* ]]
}
