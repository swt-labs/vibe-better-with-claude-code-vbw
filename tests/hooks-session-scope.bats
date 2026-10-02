#!/usr/bin/env bats
# Another session's run guards the files its lease names: a plan run (files
# null: it may write anywhere) guards every project file, and a QA or mapping
# run (files []: its agents only read) guards none.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src
}

teardown() { vbw_teardown; }

# lease KIND FILES_JSON: an open run of KIND owned by session A.
lease() {
  jq --arg k "$1" --argjson f "$2" '.lease = {run: "r-1", kind: $k, session: "sessA", started_at: (now | todate), files: $f}' \
    .vbw/record.json > "$TEST_ROOT/e.json"
  cp "$TEST_ROOT/e.json" .vbw/record.json
}

# decision SESSION PATH: what the guard decides for an Edit of PATH by SESSION
# (no output from the guard means allow).
decision() {
  local out
  out=$(jq -nc --arg s "$1" --arg p "$PROJECT/$2" --arg d "$PROJECT" \
    '{hook_event_name: "PreToolUse", tool_name: "Edit", cwd: $d, session_id: $s, tool_input: {file_path: $p}}' \
    | vbw_hook PreToolUse Edit)
  if [ -z "$out" ]; then echo allow; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}

@test "a plan run in another session guards every project file" {
  lease plan null
  [ "$(decision sessB src/any.js)" = deny ]
  [ "$(decision sessA src/any.js)" = allow ]
}

@test "a QA run in another session guards no file" {
  lease qa '[]'
  [ "$(decision sessB src/any.js)" = allow ]
}
