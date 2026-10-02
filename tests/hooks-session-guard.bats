#!/usr/bin/env bats
# R15 (D11): while a run is open, another session (main conversation or agents)
# cannot edit the files that run writes. The user lifts it with
# `vbw run end --owner-closed`.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src
  VBW_SESSION_ID=sessA "$VBW" run start qa > /dev/null
  # A build lease owned by A that writes src/pay.js.
  jq '.lease = {run: "build-1", kind: "build", session: "sessA", started_at: (now | todate), files: ["src/pay.js"]}' \
    .vbw/record.json > "$TEST_ROOT/e.json"
  cp "$TEST_ROOT/e.json" .vbw/record.json
}

teardown() { vbw_teardown; }

# edit SESSION PATH [AGENT_TYPE]
edit() {
  jq -nc --arg s "$1" --arg p "$PROJECT/$2" --arg d "$PROJECT" --arg a "${3:-}" \
    '{hook_event_name: "PreToolUse", tool_name: "Edit", cwd: $d, session_id: $s, tool_input: {file_path: $p}}
     + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)' \
    | vbw_hook PreToolUse Edit
}

denied() { [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]; }

@test "another session's main conversation cannot edit a file the run writes" {
  run edit sessB src/pay.js
  denied
  [[ "$output" == *"sessA"* ]]
}

@test "another session's subagent cannot edit it either" {
  run edit sessB src/pay.js workflow-subagent
  denied
}

@test "files the run does not write stay editable from another session" {
  run edit sessB src/other.js
  [ -z "$output" ]
}

@test "the owning session and its agents can edit the file" {
  run edit sessA src/pay.js
  [ -z "$output" ]
  run edit sessA src/pay.js workflow-subagent
  [ -z "$output" ]
}

@test "after the user states the owner is closed, the edit is allowed" {
  VBW_SESSION_ID=sessB "$VBW" run end --owner-closed > /dev/null
  run edit sessB src/pay.js
  [ -z "$output" ]
}

@test "a run older than 24 hours no longer guards its files" {
  jq '.lease.started_at = (now - 25 * 3600 | todate)' .vbw/record.json > "$TEST_ROOT/e.json"
  cp "$TEST_ROOT/e.json" .vbw/record.json
  run edit sessB src/pay.js
  [ -z "$output" ]
}

@test "with no open run, or outside a VBW project, edits are allowed" {
  jq '.lease = null' .vbw/record.json > "$TEST_ROOT/e.json"
  cp "$TEST_ROOT/e.json" .vbw/record.json
  run edit sessB src/pay.js
  [ -z "$output" ]
  rm -rf .vbw
  run edit sessB src/pay.js
  [ -z "$output" ]
}
