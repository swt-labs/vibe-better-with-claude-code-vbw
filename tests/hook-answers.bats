#!/usr/bin/env bats
# R128 (L1): every answer a VBW hook (plugin/hooks/hooks.json) gives Claude
# Code has a test here that names its documented Claude Code meaning and checks
# the exact JSON, and no hook answers a question or allows an action in the
# user's place. The hooks run through hooks.json the way Claude Code runs them
# (vbw_hook). Claude Code's meanings (hooks reference):
#   PreToolUse permissionDecision "deny"  blocks the tool call; the reason goes to Claude
#   PreToolUse permissionDecision "ask"   shows the call to the user, who decides
#   PreToolUse permissionDecision "allow" skips the user (never returned by VBW:
#                                         on AskUserQuestion it means the hook answered)
#   PreToolUse updatedInput               the tool runs with this input instead
#   additionalContext                     text added for Claude to read
#   systemMessage                         a message shown to the user
#   no output, exit 0                     no opinion: Claude Code goes on as normal
# The inventory (tools/check-hook-answers.sh HOOKS_DIR TEST_FILE, run by
# tests/standards.bats) lists every answer shape in the hook files (a
# permissionDecision value, or one of the keys updatedInput, additionalContext,
# systemMessage, decision, continue, stopReason, suppressOutput in an output
# object) and fails when one has no test in TEST_FILE whose name gives the
# file and then the shape, or when any hook can answer "allow".

load helper
load approve-choice-helper

CHECK="$REPO_ROOT/tools/check-hook-answers.sh"

setup() {
  vbw_setup
  approve_choice_project
  FP=$(fingerprint)
}

teardown() { vbw_teardown; }

# shape JSON: the path of every value in JSON (inside updatedInput only the key itself), sorted: the exact shape.
shape() { printf '%s' "$1" | jq -c '[paths(scalars) | map(tostring) | join(".")] | map(select(test("^hookSpecificOutput.updatedInput.") | not)) | sort'; }

bash_call() {
  jq -nc --arg c "$1" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' \
    | vbw_hook PreToolUse Bash
}
file_call() {
  jq -nc --arg t "$1" --arg p "$2" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: $t, cwd: $d, tool_input: {file_path: $p}}' \
    | vbw_hook PreToolUse "$1"
}
ask_call() {
  local extra="${2:-}"
  [ -n "$extra" ] || extra='{}'
  jq -nc --arg q "$1" --arg d "$PROJECT" --argjson x "$extra" \
    '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "AskUserQuestion",
      tool_input: {questions: [{question: $q, header: "Approval", multiSelect: false,
        options: [{label: "Approve", description: "x"}, {label: "Not yet", description: "y"}]}]}} + $x' | vbw_hook PreToolUse AskUserQuestion
}
session_call() { jq -nc --arg d "$PROJECT" '{hook_event_name: "SessionStart", session_id: "s1", cwd: $d, source: "startup"}' | vbw_hook SessionStart; }

DENY='["hookSpecificOutput.hookEventName","hookSpecificOutput.permissionDecision","hookSpecificOutput.permissionDecisionReason"]'
POST='["hookSpecificOutput.additionalContext","hookSpecificOutput.hookEventName","systemMessage"]'

@test "R128: session-start.sh additionalContext: in a VBW project SessionStart adds context for Claude to read, and nothing else" {
  run session_call
  [ "$status" -eq 0 ]
  [ "$(shape "$output")" = '["hookSpecificOutput.additionalContext","hookSpecificOutput.hookEventName"]' ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | startswith("VBW project ("))'
}

@test "R128: session-start.sh systemMessage: a project made by a newer VBW also shows the user a message, next to the context" {
  jq '.schema = 99' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  run session_call
  [ "$status" -eq 0 ]
  [ "$(shape "$output")" = '["hookSpecificOutput.additionalContext","hookSpecificOutput.hookEventName","systemMessage"]' ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.systemMessage | contains("/vbw:update"))'
}

@test "R128: session-start.sh no output: outside a VBW project SessionStart says nothing" {
  mkdir -p "$TEST_ROOT/plain"
  HOOK_PROJECT_DIR="$TEST_ROOT/plain" run vbw_hook SessionStart < /dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R128: guard-bash.jq and common.jq deny: a guarded Bash call is denied with a 'VBW guard:' reason, which blocks it and tells Claude why" {
  run bash_call "vbw approve"
  [ "$status" -eq 0 ]
  [ "$(shape "$output")" = "$DENY" ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.hookSpecificOutput | .hookEventName == "PreToolUse" and .permissionDecision == "deny" and (.permissionDecisionReason | startswith("VBW guard: "))'
}

@test "R128: guard-bash.jq no output: an ordinary Bash call gets no answer, so Claude Code's own permission flow decides" {
  run bash_call "ls -la"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R128: guard-file.jq deny: writing the record with a file tool is denied with a 'VBW guard:' reason" {
  run file_call Write "$PROJECT/.vbw/record.json"
  [ "$status" -eq 0 ]
  [ "$(shape "$output")" = "$DENY" ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.hookSpecificOutput | .hookEventName == "PreToolUse" and .permissionDecision == "deny" and (.permissionDecisionReason | startswith("VBW guard: "))'
}

@test "R128: guard-file.jq no output: an ordinary read gets no answer" {
  run file_call Read "$PROJECT/README.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R128: each guard's failure gives no output and exit 0, never an allow (Claude Code goes on as normal)" {
  local tool input
  for tool in Bash Read Write; do
    for input in 'not json' '{}' '[]' '{"tool_name": 7}'; do
      run vbw_hook PreToolUse "$tool" < <(printf '%s' "$input")
      [ "$status" -eq 0 ] || { echo "$tool $input: exit $status"; false; }
      [ -z "$output" ] || { echo "$tool $input: $output"; false; }
    done
  done
  # A record that cannot be read still counts as a VBW project: the guards stay on.
  printf 'not json' > .vbw/record.json
  run bash_call "ls"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
  run bash_call "vbw approve"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | startswith("VBW guard:")'
}

@test "R128: approve-ask.sh ask with updatedInput: the approval menu is rewritten and handed back as ask, so the user still sees and answers it" {
  run ask_call "Shall we build this?"
  [ "$status" -eq 0 ]
  [ "$(shape "$output")" = '["hookSpecificOutput.hookEventName","hookSpecificOutput.permissionDecision"]' ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.hookSpecificOutput | keys == ["hookEventName", "permissionDecision", "updatedInput"]' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e --arg q "Approve contract $FP? Shall we build this?" '.hookSpecificOutput
    | .hookEventName == "PreToolUse" and .permissionDecision == "ask"
      and .updatedInput.questions[0].question == $q
      and (.updatedInput.questions[0].options | map(.label)) == ["Approve", "Not yet"]
      and (.updatedInput | has("answers") | not)' || { echo "$output"; false; }
}

@test "R128: approve-ask.sh no output: other questions, subagents' questions and an approved contract get no answer" {
  run ask_call "Approve contract $FP? Already named."
  [ -z "$output" ] || { echo "$output"; false; }
  run ask_call "Shall we build this?" '{"agent_type": "vbw:lead"}'
  [ -z "$output" ] || { echo "$output"; false; }
  "$VBW" approve > /dev/null
  run ask_call "Shall we build this?"
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R128: approve-answer.sh systemMessage and additionalContext: after the user answered, the hook only adds a message and context; only the exact answer Approve approves" {
  local q="Approve contract $FP? Shall we build this?" a
  for a in "Not yet" "approve" "Approve!" " Approve" "Approved" "Yes, approve it"; do
    run answer_hook "$q" "$a"
    [ "$status" -eq 0 ]
    [ "$(shape "$output")" = "$POST" ] || { echo "$a: $output"; false; }
    printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' > /dev/null
    [ "$(contract_state)" = "NOT APPROVED" ] || { echo "the answer '$a' approved"; false; }
  done
  run answer_hook "$q" "Approve"
  [ "$status" -eq 0 ]
  [ "$(shape "$output")" = "$POST" ] || { echo "$output"; false; }
  [ "$(contract_state)" = "approved" ] || { echo "$output"; false; }
}

@test "R128: approve-answer.sh no output: other questions and subagents' answers get no answer and approve nothing" {
  run answer_hook "Which colour?" "Approve"
  [ -z "$output" ] || { echo "$output"; false; }
  run answer_hook "Approve contract $FP? Build?" "Approve" AskUserQuestion '{"agent_type": "vbw:lead"}'
  [ -z "$output" ] || { echo "$output"; false; }
  [ "$(contract_state)" = "NOT APPROVED" ]
}

@test "R128: no hook ever answers allow, for any input below, and a failing hook gives no output" {
  local outs="" o tool
  outs+=$(session_call)$'\n'
  for o in "vbw approve" "ls" "git push --force" "cat .env" "echo x > .vbw/record.json"; do outs+=$(bash_call "$o")$'\n'; done
  for tool in Read Write Edit Grep; do outs+=$(file_call "$tool" "$PROJECT/.vbw/record.json")$'\n'$(file_call "$tool" "$PROJECT/README.md")$'\n'; done
  outs+=$(ask_call "Shall we build this?")$'\n'$(ask_call "Which colour?")$'\n'
  outs+=$(answer_hook "Approve contract $FP? Build?" "Not yet")$'\n'
  if printf '%s' "$outs" | grep -E '"permissionDecision" *: *"allow"|"decision" *: *"approve"'; then false; fi
  for o in PreToolUse:Bash PreToolUse:AskUserQuestion PreToolUse:Read PostToolUse:AskUserQuestion; do
    run vbw_hook "${o%%:*}" "${o#*:}" < <(printf 'not json')
    [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$o: $status $output"; false; }
  done
}

@test "R128: the hook answer inventory passes on the hooks as they are" {
  [ -f "$CHECK" ] || { echo "no $CHECK"; false; }
  run bash "$CHECK" "$PLUGIN_ROOT/hooks" "$BATS_TEST_FILENAME"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R128: the hook answer inventory fails on a new answer shape with no pinning test, names it, and passes once a test pins it" {
  [ -f "$CHECK" ] || { echo "no $CHECK"; false; }
  cp -R "$PLUGIN_ROOT/hooks" "$TEST_ROOT/hooks"
  printf '| {systemMessage: "a new answer"}\n' >> "$TEST_ROOT/hooks/guard-file.jq"
  run bash "$CHECK" "$TEST_ROOT/hooks" "$BATS_TEST_FILENAME"
  [ "$status" -ne 0 ] || { echo "accepted: $output"; false; }
  [[ "$output" == *guard-file.jq* && "$output" == *systemMessage* ]] || { echo "$output"; false; }
  cp "$BATS_TEST_FILENAME" "$TEST_ROOT/pinned.bats"
  printf '@%s "R128: %s %s: a new answer" {\n  true\n}\n' test guard-file.jq systemMessage >> "$TEST_ROOT/pinned.bats"
  run bash "$CHECK" "$TEST_ROOT/hooks" "$TEST_ROOT/pinned.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R128: the hook answer inventory fails when any hook could answer allow, even with a test named for it" {
  [ -f "$CHECK" ] || { echo "no $CHECK"; false; }
  cp -R "$PLUGIN_ROOT/hooks" "$TEST_ROOT/hooks"
  printf '%s\n' "jq -nc '{hookSpecificOutput: {hookEventName: \"PreToolUse\", permissionDecision: \"allow\"}}'" >> "$TEST_ROOT/hooks/approve-ask.sh"
  cp "$BATS_TEST_FILENAME" "$TEST_ROOT/pinned.bats"
  printf '@%s "R128: %s %s: allowed" {\n  true\n}\n' test approve-ask.sh allow >> "$TEST_ROOT/pinned.bats"
  run bash "$CHECK" "$TEST_ROOT/hooks" "$TEST_ROOT/pinned.bats"
  [ "$status" -ne 0 ] || { echo "accepted: $output"; false; }
  [[ "$output" == *approve-ask.sh* && "$output" == *allow* ]] || { echo "$output"; false; }
}

@test "R128: the engineering standards run the hook answer inventory, and their selftest shows it failing" {
  grep -qF 'tools/check-hook-answers.sh' "$REPO_ROOT/tests/standards.bats"
  grep -qF 'tools/check-hook-answers.sh' "$REPO_ROOT/tests/standards-selftest.bats"
}

@test "R128: hook timing stays within the hot-path budget (tools/bench-hooks.sh)" {
  run bash "$REPO_ROOT/tools/bench-hooks.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
