#!/usr/bin/env bats
# R61 (hook part, L1): the PostToolUse hook on AskUserQuestion approves when the
# user's answer to VBW's approval question is Approve, for the contract the
# question names, and in no other case. Every refusal leaves the record and the
# consent untouched and tells the user in one plain sentence.

load helper
load approve-choice-helper

setup() {
  vbw_setup
  approve_choice_project
  FP=$(fingerprint)
  Q="Approve contract $FP?"
}
teardown() { vbw_teardown; }

# say: the sentence the user sees (systemMessage), one line.
say() { printf '%s' "$output" | jq -r '.systemMessage // empty'; }

@test "R61: hooks.json runs one PostToolUse hook, only for AskUserQuestion" {
  jq -e '.hooks.PostToolUse | length == 1 and .[0].matcher == "AskUserQuestion" and (.[0].hooks | length == 1)' "$PLUGIN_ROOT/hooks/hooks.json"
}

@test "R61: answering Approve to the question approves the contract the question named, with the same decision entry as /vbw:approve" {
  run answer_hook "$Q" "Approve"
  [ "$status" -eq 0 ]
  [ "$(contract_state)" = "approved" ]
  [ "$(approved_count)" = "1" ]
  jq -e --arg fp "$FP" '.decisions[-1].text | test("^Contract approved: 1 requirements, 1 checks, 1 plans \\(" + $fp + "\\)")' .vbw/record.json
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse" and (.hookSpecificOutput.additionalContext | test("approved"))'
  [ -n "$(say)" ]
}

@test "R61: the answer may come as a list of answers as well as a map from question to answer" {
  jq -nc --arg q "$Q" --arg d "$PROJECT" '{hook_event_name: "PostToolUse", session_id: "s1", cwd: $d, tool_name: "AskUserQuestion",
    tool_input: {question: $q}, tool_response: {answers: ["Approve"]}}' > "$TEST_ROOT/in.json"
  run vbw_hook PostToolUse AskUserQuestion < "$TEST_ROOT/in.json"
  [ "$status" -eq 0 ]
  [ "$(contract_state)" = "approved" ]
}

@test "R61: when the contract changed after the question, Approve approves nothing and the user is told, and shown the new contract" {
  printf 'grep -qx paid src/pay.txt && true\n' > tests/pay.sh
  local new before
  new=$(fingerprint)
  before=$(jq -S . .vbw/record.json)
  run answer_hook "$Q" "Approve"
  [ "$status" -eq 0 ]
  [ "$(contract_state)" = "NOT APPROVED" ]
  [ "$(jq -S . .vbw/record.json)" = "$before" ]
  [[ "$(say)" == *changed* ]]
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" == *"$new"* ]]
}

@test "R61: answering Not yet approves nothing and VBW is told to ask what to change" {
  run answer_hook "$Q" "Not yet"
  [ "$status" -eq 0 ]
  [ "$(contract_state)" = "NOT APPROVED" ]
  [ "$(approved_count)" = "0" ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("what to change")'
}

@test "R61: the user's own words approve nothing, even words that contain Approve, and are handed on as what to change" {
  for words in "please also add a refund requirement" "Approve, but first change R1" "approve"; do
    run answer_hook "$Q" "$words"
    [ "$status" -eq 0 ]
    [ "$(contract_state)" = "NOT APPROVED" ]
    [ "$(approved_count)" = "0" ]
    printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("not approved")'
  done
}

@test "R61: the question may explain the contract after the fingerprint: Approve still approves it (real-app run)" {
  # Claude asked this way in the 2.0.19 real-app run: the kernel's question, then a summary.
  run answer_hook "$Q It builds two small shell scripts, each checked by its own test script." "Approve"
  [ "$status" -eq 0 ]
  [ "$(contract_state)" = "approved" ]
  [ "$(approved_count)" = "1" ]
}

@test "R61: the fingerprint counts only at the very start of the question and only as exactly 12 hex digits" {
  run answer_hook "Please $Q" "Approve"
  [ -z "$output" ]
  run answer_hook "Approve contract ${FP}0? It builds a script." "Approve"
  [ -z "$output" ]
  run answer_hook "Approve contract ${FP}?It builds a script." "Approve"
  [ -z "$output" ]
  [ "$(contract_state)" = "NOT APPROVED" ]
}

@test "R61: any other question changes nothing and prints nothing, in a VBW project and outside one" {
  run answer_hook "Which database should it use?" "Approve"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run answer_hook "Approve this other thing?" "Approve"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(contract_state)" = "NOT APPROVED" ]
  mkdir "$TEST_ROOT/plain" && git -C "$TEST_ROOT/plain" init -q
  HOOK_PROJECT_DIR="$TEST_ROOT/plain" run answer_hook "$Q" "Approve"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$TEST_ROOT/plain/.vbw" ]
}

@test "R61: an answer already approved says so in one sentence and writes no second decision" {
  run answer_hook "$Q" "Approve"
  [ "$(approved_count)" = "1" ]
  run answer_hook "$Q" "Approve"
  [ "$status" -eq 0 ]
  [[ "$(say)" == *"already approved"* ]]
  [ "$(approved_count)" = "1" ]
  "$VBW" approve > /dev/null
  [ "$(approved_count)" = "1" ]
}

@test "R61: plain /vbw:approve first, then the choice: still one decision" {
  "$VBW" approve > /dev/null
  run answer_hook "$Q" "Approve"
  [ "$status" -eq 0 ]
  [ "$(approved_count)" = "1" ]
}

@test "R61: with no contract ready to approve, nothing is approved and the user is told to type /vbw:approve" {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] Another\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  local before
  before=$(jq -S . .vbw/record.json)
  run answer_hook "Approve contract $(fingerprint)?" "Approve"
  [ "$status" -eq 0 ]
  [ "$(approved_count)" = "0" ]
  [ "$(jq -S . .vbw/record.json)" = "$before" ]
  [[ "$(say)" == */vbw:approve* ]]
  [ "$(printf '%s' "$(say)" | wc -l)" -eq 0 ]
}

@test "R61: a damaged record leaves the file as it was, approves nothing and says why in one sentence" {
  printf '{ not json' > .vbw/record.json
  cp .vbw/record.json "$TEST_ROOT/damaged"
  run answer_hook "$Q" "Approve"
  [ "$status" -eq 0 ]
  cmp .vbw/record.json "$TEST_ROOT/damaged"
  [ -n "$(say)" ]
  [[ "$(say)" == */vbw:approve* ]]
  [ "$(printf '%s' "$(say)" | wc -l)" -eq 0 ]
  [ ! -e "$(git rev-parse --git-common-dir)/vbw/consent.json" ] || ! grep -q "$FP" "$(git rev-parse --git-common-dir)/vbw/consent.json"
}
