#!/usr/bin/env bats
# F76 regression (L1): every place that tells Claude or the user how to prove
# before a QA verdict names vbw prove --full, since a plain proof can be partial.

load helper

@test "vbw help shows prove with its --full option" {
  run "$VBW" help < /dev/null
  [[ "$output" == *"prove [--full]"* ]] || { echo "$output"; false; }
}

@test "the qa record refusal for changed code and the proof docs name vbw prove --full" {
  grep -q 'the code changed since the last proof: run vbw prove --full' "$PLUGIN_ROOT/lib/cmd-qa.sh"
  grep -q 'it runs\s*$\|vbw prove --full` and retries the record once' "$REPO_ROOT/docs/proof.md"
  ! grep -q 'it runs `vbw prove`$' "$REPO_ROOT/docs/proof.md"
}

@test "the docs name the approval-menu hook that adds the fingerprint (R114)" {
  grep -q 'approve-ask' "$REPO_ROOT/docs/proof.md"
  grep -q 'approve-ask' "$REPO_ROOT/docs/guards.md"
}
