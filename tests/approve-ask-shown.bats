#!/usr/bin/env bats
# R120 (L1): the approval hook rewrites a reworded approval question but never
# answers it. Claude Code treats permissionDecision "allow" with updatedInput as
# the hook answering AskUserQuestion itself (the menu is not shown and Claude
# reads "The user did not answer the questions"); "ask" with updatedInput shows
# the rewritten question to the user (hooks reference, PreToolUse decision
# control). Seen in the real app on Claude Code 2.1.295, smallchange scenario.

load helper
load approve-choice-helper

setup() {
  vbw_setup
  approve_choice_project
  FP=$(fingerprint)
}
teardown() { vbw_teardown; }

ask_hook() {
  jq -nc --arg q "$1" --arg d "$PROJECT" \
    '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "AskUserQuestion",
      tool_input: {questions: [{question: $q, header: "Approval", multiSelect: false,
        options: [{label: "Approve", description: "x"}, {label: "Not yet", description: "x"}]}]}}' \
    | vbw_hook PreToolUse AskUserQuestion
}

@test "R120: a reworded approval question is rewritten and shown to the user: the hook asks, never allows" {
  run ask_hook "Approve the plan for the --shout change?"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e --arg fp "$FP" '.hookSpecificOutput
    | .permissionDecision == "ask"
      and (.updatedInput.questions[0].question | startswith("Approve contract \($fp)? "))' \
    || { echo "$output"; false; }
}

@test "R120: the hook never supplies answers: the user's own choice is the answer" {
  run ask_hook "Approve the plan for the --shout change?"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.updatedInput | has("answers") | not' \
    || { echo "$output"; false; }
}

@test "R120: docs/guards.md says the rewritten question is shown to the user, never answered by the hook" {
  grep -qiE 'shown to (you|the user)' "$REPO_ROOT/docs/guards.md"
  grep -qiE 'never answers' "$REPO_ROOT/docs/guards.md"
}
