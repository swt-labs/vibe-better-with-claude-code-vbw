#!/usr/bin/env bats
# R75 (docs/guards.md): while VBW plans, its agents may write only VBW's own
# files (.vbw/) and test files; a write anywhere else is refused with the
# reason. A planning run never blocks another session: its lease holds back
# only the files planning writes. L1: the real guard hook on a plan lease made
# by vbw run start plan.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  VBW_SESSION_ID=sessA "$VBW" run start plan > /dev/null
}

teardown() { vbw_teardown; }

# write_call SESSION PATH [AGENT_TYPE]: a Write tool call.
write_call() {
  jq -nc --arg s "$1" --arg p "$PROJECT/$2" --arg d "$PROJECT" --arg a "${3:-}" \
    '{hook_event_name: "PreToolUse", tool_name: "Write", cwd: $d, session_id: $s, tool_input: {file_path: $p}}
     + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)' \
    | vbw_hook PreToolUse Write
}

# shell_call SESSION COMMAND [AGENT_TYPE]: a Bash tool call.
shell_call() {
  jq -nc --arg s "$1" --arg c "$2" --arg d "$PROJECT" --arg a "${3:-}" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, session_id: $s, tool_input: {command: $c}}
     + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)' \
    | vbw_hook PreToolUse Bash
}

denied() { [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')" = deny ]; }

@test "R75: a planning agent writing a project file that is not a test file is refused, with the reason" {
  run write_call sessA src/app.js workflow-subagent
  denied
  [[ "$output" == *"src/app.js"* ]]
  [[ "$output" == *"plan"* ]]
  run write_call sessA README.md workflow-subagent
  denied
}

@test "R75: a planning agent may write VBW's own files" {
  run write_call sessA .vbw/map.md workflow-subagent
  [ -z "$output" ]
  run write_call sessA .vbw/spec.md workflow-subagent
  [ -z "$output" ]
}

@test "R75: a planning agent may write test files, in the usual places and by the usual names" {
  local p
  for p in tests/signup.test.js test/signup.bats tests/test_signup.py src/signup.test.ts src/signup_test.go spec/signup_spec.rb src/__tests__/signup.js; do
    run write_call sessA "$p" workflow-subagent
    [ -z "$output" ] || { echo "refused: $p -> $output"; false; }
  done
}

@test "R75: a planning agent's shell writes are held to the same files" {
  run shell_call sessA "echo x > src/app.js" workflow-subagent
  denied
  run shell_call sessA "echo x > tests/signup.test.js" workflow-subagent
  [ -z "$output" ]
  run shell_call sessA "echo x > .vbw/map.md" workflow-subagent
  [ -z "$output" ]
}

@test "R75: a planning run never blocks another session's folders" {
  run write_call sessB src/app.js
  [ -z "$output" ] || { echo "$output"; false; }
  run write_call sessB README.md workflow-subagent
  [ -z "$output" ] || { echo "$output"; false; }
  run shell_call sessB "echo x > src/app.js"
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R75: another session still may not write the files planning itself writes" {
  run write_call sessB .vbw/map.md
  denied
  [[ "$output" == *"sessA"* ]]
}

@test "R75: the main conversation of the planning session is not held to the plan lease" {
  run write_call sessA src/app.js
  [ -z "$output" ]
}

@test "R75: other runs keep their lease exactly: a build agent still writes only its plan's files" {
  VBW_SESSION_ID=sessA "$VBW" run end > /dev/null
  jq '.lease = {run: "build-1", kind: "build", session: "sessA", started_at: (now | todate), files: ["src/pay.js"]}' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  run write_call sessA src/pay.js workflow-subagent
  [ -z "$output" ]
  run write_call sessA src/other.js workflow-subagent
  denied
}
