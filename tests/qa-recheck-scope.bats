#!/usr/bin/env bats
# R47 (docs/proof.md): after a round of fixes QA checks again only the phases
# that did not pass and the phases whose own inputs changed since they passed
# (their files, their tests, or their goal and plan); an untouched phase keeps
# its pass. Each QA pass records what it covered; vbw next hands the narrowed
# list to the verify workflow.

load helper
load qa-recheck-helper

setup() { qa_project 2; }
teardown() { vbw_teardown; }

@test "R47: each QA pass records the phase's files, tests and goal-and-plan as digests, and the record needs schema 2" {
  qa_pass P1 P2
  jq -e '[.phases[].qa.inputs | (.files, .tests, .plan)] | length == 6 and all(.[]; type == "string" and test("^[0-9a-f]{64}$"))' .vbw/record.json
  jq -e '.phases[0].qa.inputs.files != .phases[1].qa.inputs.files' .vbw/record.json
  jq -e '.schema == 2' .vbw/record.json
  vbw_run status
  [ "$status" -eq 0 ]
}

@test "R47: a phase that has never passed QA is checked" {
  [ "$(listed)" = '["P1","P2"]' ]
}

@test "R47: after one phase passes and the other does not, only the other is checked" {
  qa_pass P1
  [ "$(listed)" = '["P2"]' ]
}

@test "R47: a phase whose last verdict was fail is checked again, and a passing phase keeps its pass" {
  qa_pass P2
  "$VBW" qa finding R1 "part 1 deviates from its plan" > /dev/null
  "$VBW" qa record P1 fail standard "1 deviation" > /dev/null
  "$VBW" fix done F1 > /dev/null
  "$VBW" prove > /dev/null
  [ "$(listed)" = '["P1"]' ]
}

@test "R47: two phases passed and a fix touches one: only that one is in the next QA list" {
  qa_pass P1 P2
  [ "$(listed)" = '[]' ]
  qa_touch 1
  [ "$(listed)" = '["P1"]' ]
  next_json | jq -e '.action == "qa"'
}

@test "R47: a pass that stands is still a pass on the proven code: it counts for finishing the phase" {
  qa_pass P1 P2
  qa_touch 1
  jq -e '.phases[1].qa.tree == .evidence.tree and .phases[1].qa.result == "pass"' .vbw/record.json
  vbw_run show phase P2
  [[ "$output" != *"[on older code]"* ]]
  qa_pass P1
  next_json | jq -e '.action == "ship"'
}

@test "R47: changing a file of the phase alone is enough to check it again" {
  qa_pass P1 P2
  qa_touch 2
  [ "$(listed)" = '["P2"]' ]
}

@test "R47: changing a test of the phase alone is enough to check it again" {
  qa_pass P1 P2
  printf '# stricter\n' >> tests/p1.sh
  git add tests/p1.sh && git commit -q -m "test(p1): stricter"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null
  [ "$(listed)" = '["P1"]' ]
}

@test "R47: changing the goal of the phase alone is enough to check it again" {
  qa_pass P1 P2
  edit_record '(.phases[] | select(.id == "P2")).goal = "Part 2 works for every customer"'
  [ "$(listed)" = '["P2"]' ]
}

@test "R47: changing the plan of the phase alone is enough to check it again" {
  qa_pass P1 P2
  edit_record '(.plans[] | select(.id == "P1.1")).tasks += ["also write a receipt"]'
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null
  [ "$(listed)" = '["P1"]' ]
}

@test "R47: a change to a file that belongs to no phase checks no phase" {
  qa_pass P1 P2
  printf 'loose\n' > src/loose.txt
  git add src/loose.txt && git commit -q -m "chore: loose file"
  "$VBW" prove > /dev/null
  [ "$(listed)" = '[]' ]
  next_json | jq -e '.action == "ship"'
}

@test "R47: fixes that close without touching any phase file leave every pass standing" {
  qa_pass P1 P2
  printf '# notes\n' > NOTES.md
  git add NOTES.md && git commit -q -m "docs: notes"
  "$VBW" prove > /dev/null
  jq -e 'all(.phases[]; .qa.result == "pass" and .qa.tree == .evidence.tree)' .vbw/record.json
  next_json | jq -e '.action == "ship" and .qa.recheck == {}'
}

@test "R47: a record written before this change, with passes that carry no digests, is read without error and checked again once" {
  qa_pass P1 P2
  edit_record '.phases |= map(del(.qa.inputs)) | .schema = 1'
  vbw_run next --json
  [ "$status" -eq 0 ]
  [ "$(listed)" = '["P1","P2"]' ]
  vbw_run status
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | grep -qi corrupt; then false; fi
  qa_pass P1 P2
  [ "$(listed)" = '[]' ]
}

@test "R47: QA still refuses a verdict on a proof older than the current code (R12)" {
  printf 'extra\n' >> src/p1.txt
  vbw_run qa record P1 pass standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw prove"* ]]
}

@test "R47: the verify workflow checks exactly the phases it is given and holds no selection of its own" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  qa_pass P1 P2
  qa_touch 1
  local phases out
  phases=$(next_json | jq -c '.detail.phases')
  [ "$phases" = '["P1"]' ]
  out=$(node "$REPO_ROOT/tests/helpers/run-workflow.js" "$PLUGIN_ROOT/workflows/verifying.js" \
    "$(jq -nc --argjson p "$phases" '{phases: $p, tier: "standard"}')" '{}')
  [ "$(printf '%s' "$out" | jq -c '[.calls[].opts.label]')" = '["qa P1"]' ]
  if grep -qE 'inputs|standing|recheck' "$PLUGIN_ROOT/workflows/verifying.js"; then false; fi
}
