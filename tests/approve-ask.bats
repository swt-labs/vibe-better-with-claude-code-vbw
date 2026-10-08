#!/usr/bin/env bats
# R114 (L1): when Claude asks the approval menu (options Approve and Not yet)
# without the contract's fingerprint while a contract waits for approval, VBW's
# PreToolUse hook puts "Approve contract <fingerprint>?" in front of the
# question, so the user's Approve approves exactly that contract. Other
# questions, subagents, a question that already names a fingerprint and an
# approved contract are left as they are.

load helper
load approve-choice-helper

setup() {
  vbw_setup
  approve_choice_project
  FP=$(fingerprint)
}
teardown() { vbw_teardown; }

# ask_hook QUESTION [LABELS_JSON [EXTRA_JSON]]: the PreToolUse hook of hooks.json for AskUserQuestion.
ask_hook() {
  local labels="${2:-}" extra="${3:-}"
  [ -n "$labels" ] || labels='["Approve","Not yet"]'
  [ -n "$extra" ] || extra='{}'
  jq -nc --arg q "$1" --arg d "$PROJECT" --argjson l "$labels" --argjson x "$extra" \
    '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "AskUserQuestion",
      tool_input: {questions: [{question: $q, header: "Approval", multiSelect: false,
        options: [$l[] | {label: ., description: "x"}]}]}} + $x' | vbw_hook PreToolUse AskUserQuestion
}
asked() { printf '%s' "$output" | jq -r '.hookSpecificOutput.updatedInput.questions[0].question // empty'; }

@test "R114: an approval menu asked without the fingerprint gets it in front of the question" {
  run ask_hook "Approve the contract for the --shout change? It adds R2."
  [ "$status" -eq 0 ]
  [ "$(asked)" = "Approve contract $FP? Approve the contract for the --shout change? It adds R2." ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and (.hookSpecificOutput.updatedInput.questions[0].options | map(.label)) == ["Approve","Not yet"]'
}

@test "R114: the user's Approve to the completed question approves exactly that contract" {
  run ask_hook "Shall we go ahead with this plan?"
  local q
  q=$(asked)
  [ -n "$q" ]
  run answer_hook "$q" "Approve"
  [ "$(contract_state)" = "approved" ] || { echo "$output"; false; }
  [ "$(approved_count)" = "1" ]
}

@test "R114: a question that already names a fingerprint, or any other question, is left alone" {
  run ask_hook "Approve contract $FP? It builds the checkout."
  [ -z "$output" ]
  run ask_hook "Approve contract 000000000000? An old contract."
  [ -z "$output" ]
  run ask_hook "Which colour do you prefer?" '["Blue","Green"]'
  [ -z "$output" ]
}

@test "R114: a subagent's question and a question once the contract is approved are left alone" {
  run ask_hook "Approve this?" '' '{"agent_type":"vbw:lead"}'
  [ -z "$output" ]
  "$VBW" approve > /dev/null
  run ask_hook "Approve this?"
  [ -z "$output" ]
}
