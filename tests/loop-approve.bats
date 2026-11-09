#!/usr/bin/env bats
# R178 (P127; docs/loop.md, Approval by delegation): when a loop is on and not
# stopping, vbw next would ask for approval, and the current milestone's
# requirements are exactly loop items (every requirement's text equals the
# recorded text of one loop item, each item matched at most once, nothing else
# in the milestone except a [human] requirement an earlier ship carried over),
# the kernel's loop step (vbw loop next) approves the contract with no question:
# consent for the contract's fingerprint, the shape and the approved-contract
# snapshot exactly as vbw approve writes them, the project commands and the
# test-file form approved too (D315), a decision saying the contract was
# approved by the loop on the user's behalf (naming the loop's start time, the
# items and the fingerprint), and the approval commit. vbw next then moves past
# approve. L1.

load helper
load loop-helper
load fixture-helper

# planned_loop: a loop over T1 and T2 whose milestone holds T1's requirement, planned with a check and committed.
planned_loop() {
  loop_project
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --no-ceiling > /dev/null
  "$VBW" spec add auto "Visitors can read a greeting" > /dev/null
  Q=$(item_req "Visitors can read a greeting")
  loop_plan "$Q" P2
  git add -A && git commit -q -m "chore(test): planned"
}

setup_file() {
  fixture_build planned planned_loop
  fixture_build human loop_project human
}
setup() { fixture_copy planned; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

contract_state() { "$VBW" show contract < /dev/null | sed -n '1s/^contract [0-9a-f]* (\(.*\))$/\1/p'; }
fingerprint() { local h; h=$(vbw_contract_hash); printf '%s' "${h:0:12}"; }
consent() { cat "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/consent.json"; }

@test "R178: the loop step approves a contract made of exactly its items: consent, shape, snapshot, commands, decision and commit, as vbw approve writes them" {
  local fp started head
  fp=$(fingerprint)
  started=$(jq -r .loop.started_at .vbw/record.json)
  head=$(git rev-parse HEAD)
  [ "$(next_action)" = approve ]
  [ "$(contract_state)" = "NOT APPROVED" ]
  run loop_next s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.action == "build"' || { echo "$output"; false; }
  [ "$(contract_state)" = approved ]
  consent | jq -e --arg h "$(vbw_contract_hash)" 'any(.granted[]; .kind == "contract" and .hash == $h)'
  consent | jq -e 'any(.granted[]; .kind == "shape")'
  consent | jq -e 'any(.granted[]; .kind == "command" and .detail.name == "test")'
  [ -f .vbw/runtime/approved-contract.json ]
  jq -e --arg q "$Q" '(.checks | has("C2")) and (.requirements | has($q))' .vbw/runtime/approved-contract.json
  jq -e --arg fp "$fp" --arg at "$started" '.decisions[-1].text
    | test("approved by the loop on the user.s behalf") and contains($at) and contains("T1") and contains("T2") and contains($fp)' .vbw/record.json \
    || { jq '.decisions[-1]' .vbw/record.json; false; }
  # The loop's approval is its own decision: no user-style "Contract approved:" decision since the loop started (the helper's own M1 approval is older).
  jq -e --arg at "$started" '[.decisions[] | select(.at >= $at and (.text | startswith("Contract approved:")))] | length == 0' .vbw/record.json
  [ "$(git rev-parse HEAD)" != "$head" ]
  git log -1 --format=%s | grep -q "approve contract $fp"
  [ -z "$(git status --porcelain -- .vbw)" ]
  [ "$(next_action)" = build ]
}

@test "R178: the test-file form is approved too (D315)" {
  printf '\n## Test files\n\n- run: sh {file}\n- files: tests/notes.sh tests/greet.sh\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore(test): test files"
  [ "$(next_action)" = approve ]
  loop_next s1 > /dev/null
  consent | jq -e 'any(.granted[]; .kind == "test_files")'
  [ "$(next_action)" = build ]
}

@test "R178: a [human] requirement an earlier ship carried over does not stop the delegation" {
  fixture_copy human
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  "$VBW" spec add auto "Visitors can read a greeting" > /dev/null
  Q=$(item_req "Visitors can read a greeting")
  jq -e '.requirements[] | select(.id == "R2") | .proof == "human" and .milestone == "M2"' .vbw/record.json
  loop_plan "$Q" P2
  git add -A && git commit -q -m "chore(test): planned"
  [ "$(next_action)" = approve ]
  run loop_next s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(contract_state)" = approved ]
  jq -e '.decisions[-1].text | test("approved by the loop")' .vbw/record.json
  [ "$(next_action)" = build ]
}

@test "R178: the approval is idempotent: a second loop step approves nothing again and records no second decision" {
  loop_next s1 > /dev/null
  local n
  n=$(jq '.decisions | length' .vbw/record.json)
  run loop_next s1
  [ "$status" -eq 0 ]
  [ "$(jq '.decisions | length' .vbw/record.json)" -eq "$n" ]
  [ "$(consent | jq '[.granted[] | select(.kind == "contract")] | length')" -eq 2 ]
}

@test "R178 (F174): the approval of edited test files (vbw next row 4a, detail.files) is never delegated: the loop waits for the user" {
  run loop_next s1
  [ "$(contract_state)" = approved ]
  local n
  loop_build P2
  n=$(jq '.decisions | length' .vbw/record.json)
  printf 'grep -q -x hello src/greet.txt\n' > tests/greet.sh
  git commit -q -am "test: the check file edited after the approval"
  VBW_SESSION_ID=s1 "$VBW" next --json < /dev/null | jq -e '.action == "approve" and (.detail.files | length) > 0' || { VBW_SESSION_ID=s1 "$VBW" next --json < /dev/null; false; }
  run loop_next s1
  [ "$(jq '.decisions | length' .vbw/record.json)" = "$n" ] || { jq '.decisions[-1]' .vbw/record.json; false; }
  VBW_SESSION_ID=s1 "$VBW" next --json < /dev/null | jq -e '.action == "approve" and (.detail.files | length) > 0'
}

@test "R178 (F199): the loop grants the consents for a project command and a shape that had none before" {
  local shapes h
  printf 'true\n' > tests/lint.sh
  printf -- '- lint: sh tests/lint.sh\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore(test): a lint command"
  consent | jq -e 'any(.granted[]; .kind == "command" and .detail.name == "lint") | not'
  shapes=$(consent | jq '[.granted[] | select(.kind == "shape")] | length')
  consent | jq -e --arg s "$(vbw_kernel 'contract_shape "$(cat "$VBW_RECORD")"')" 'any(.granted[]; .kind == "shape" and .hash == $s) | not'
  [ "$(next_action)" = approve ]
  loop_next s1 > /dev/null
  h=$(vbw_kernel 'vbw_sha256_argv sh tests/lint.sh')
  consent | jq -e --arg h "$h" 'any(.granted[]; .kind == "command" and .detail.name == "lint" and .hash == $h)' || { consent; false; }
  consent | jq -e --arg s "$(vbw_kernel 'contract_shape "$(cat "$VBW_RECORD")"')" 'any(.granted[]; .kind == "shape" and .hash == $s)' || { consent; false; }
  [ "$(consent | jq '[.granted[] | select(.kind == "shape")] | length')" -eq $((shapes + 1)) ]
  [ "$(next_action)" = build ]
}

@test "R178 (F200): a project command changed after the contract's approval is approved by the loop with its own decision and commit, never by a consent alone" {
  loop_next s1 > /dev/null
  [ "$(next_action)" = build ]
  local d n h
  sed -i.bak 's|^- test: sh tests/run.sh$|- test: sh tests/run.sh all|' .vbw/spec.md && rm -f .vbw/spec.md.bak
  grep -q 'tests/run.sh all' .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore(test): the test command changed"
  [ "$(next_action)" = approve ]
  d=$(jq '.decisions | length' .vbw/record.json)
  n=$(consent | jq '.granted | length')
  loop_next s1 > /dev/null
  h=$(vbw_kernel 'vbw_sha256_argv sh tests/run.sh all')
  consent | jq -e --arg h "$h" 'any(.granted[]; .kind == "command" and .hash == $h)' || { consent; false; }
  [ "$(consent | jq '.granted | length')" -eq $((n + 1)) ]
  jq -e --argjson d "$d" --arg at "$(jq -r .loop.started_at .vbw/record.json)" '(.decisions | length) == $d + 1 and (.decisions[-1].text
    | startswith("Project commands approved by the loop on the user") and contains($at) and contains("T1") and contains("test (sh tests/run.sh all)"))' .vbw/record.json \
    || { jq '.decisions[-2:]' .vbw/record.json; false; }
  git log -1 --format=%s | grep -q '^chore(vbw): approve commands$' || { git log -3 --format=%s; false; }
  [ -z "$(git status --porcelain -- .vbw)" ]
  [ "$(next_action)" = build ]
}
