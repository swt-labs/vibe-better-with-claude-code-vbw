#!/usr/bin/env bats
# R18: the benchmark's committed results. tools/baseline/results/runs/ holds one JSON
# file per run: arm (plain|vbw2), model (sonnet-5.5|opus-5.5), case, run (1..3),
# pass (boolean), tokens (number), cost_usd (number), user_inputs (number: answers
# and approvals the run needed), level, fixture (string). Plain Claude Code runs
# headless (claude -p): level "L2". VBW 2 runs driven as a user through its
# commands (tools/l3.sh, answering and approving as a user would): level "L3".
# tools/baseline/verify-results.sh [DIR] exits 0 only if the 84 runs
# (7 cases x 2 arms x 2 models x 3) are all present once, with every field.

load helper

VERIFY="$BATS_TEST_DIRNAME/../tools/baseline/verify-results.sh"
CASES="fix-oneshot failing-check-fix brownfield-feature safety-destructive safety-secret hostile-repo markdown-deliverable"

setup() { vbw_setup; [ -f "$VERIFY" ]; }
teardown() { vbw_teardown; }

# Write the full, valid set of 84 records into DIR.
full_set() {
  mkdir -p "$1"
  local c a m n
  for c in $CASES; do for a in plain vbw2; do for m in sonnet-5.5 opus-5.5; do for n in 1 2 3; do
    jq -n --arg c "$c" --arg a "$a" --arg m "$m" --argjson n "$n" \
      '{arm:$a,model:$m,case:$c,run:$n,pass:true,tokens:1000,cost_usd:0.5,
        user_inputs:(if $a == "vbw2" then 3 else 0 end), level:(if $a == "vbw2" then "L3" else "L2" end),fixture:$c}' \
      > "$1/$a-$m-$c-$n.json"
  done; done; done; done
}

@test "the committed results are complete" {
  run bash "$VERIFY"
  [ "$status" -eq 0 ]
}

@test "selftest: a complete set passes" {
  full_set "$PROJECT/runs"
  run bash "$VERIFY" "$PROJECT/runs"
  [ "$status" -eq 0 ]
}

@test "selftest: a missing run fails" {
  full_set "$PROJECT/runs"
  rm "$PROJECT/runs/plain-opus-5.5-hostile-repo-2.json"
  run bash "$VERIFY" "$PROJECT/runs"
  [ "$status" -ne 0 ]
}

@test "selftest: a missing field fails" {
  full_set "$PROJECT/runs"
  f="$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json"
  jq 'del(.tokens)' "$f" > "$f.n" && mv "$f.n" "$f"
  run bash "$VERIFY" "$PROJECT/runs"
  [ "$status" -ne 0 ]
}

@test "selftest: a duplicate run fails" {
  full_set "$PROJECT/runs"
  cp "$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-1.json" "$PROJECT/runs/dup.json"
  run bash "$VERIFY" "$PROJECT/runs"
  [ "$status" -ne 0 ]
}

@test "selftest: a result whose level does not match its arm fails" {
  full_set "$PROJECT/runs"
  f="$PROJECT/runs/vbw2-opus-5.5-safety-secret-3.json"
  jq '.level="L2"' "$f" > "$f.n" && mv "$f.n" "$f"
  run bash "$VERIFY" "$PROJECT/runs"
  [ "$status" -ne 0 ]
  full_set "$PROJECT/runs2"
  f="$PROJECT/runs2/plain-sonnet-5.5-fix-oneshot-1.json"
  jq '.level="L3"' "$f" > "$f.n" && mv "$f.n" "$f"
  run bash "$VERIFY" "$PROJECT/runs2"
  [ "$status" -ne 0 ]
}

@test "selftest: a result without user_inputs fails" {
  full_set "$PROJECT/runs"
  f="$PROJECT/runs/vbw2-sonnet-5.5-hostile-repo-2.json"
  jq 'del(.user_inputs)' "$f" > "$f.n" && mv "$f.n" "$f"
  run bash "$VERIFY" "$PROJECT/runs"
  [ "$status" -ne 0 ]
}
