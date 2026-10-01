#!/usr/bin/env bats
# SessionStart: one line of state in VBW projects, silence elsewhere, no writes,
# no resume directives (ledger D289).

load helper

setup() {
  vbw_setup
  vbw_git_project
}

teardown() { vbw_teardown; }

session_start() {
  jq -nc --arg d "$1" '{hook_event_name: "SessionStart", source: "startup", cwd: $d}' | HOOK_PROJECT_DIR="$1" vbw_hook SessionStart
}

@test "outside a VBW project the hook says nothing" {
  run session_start "$PROJECT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "in a VBW project it gives the state and the next step, and writes nothing" {
  "$VBW" init > /dev/null
  local before
  before=$(find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs shasum)
  run session_start "$PROJECT"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"project with space · M1 First milestone"* ]]
  [[ "$ctx" == *"Next: spec (needs you): Write the goals and requirements"* ]]
  [[ "$ctx" != *"resume"* ]]
  [ "$(find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs shasum)" = "$before" ]
}

@test "a corrupt record is reported, not hidden" {
  "$VBW" init > /dev/null
  printf '{"schema": 9}' > .vbw/record.json
  run session_start "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" == *"record is corrupt"* ]]
}

@test "a session started in a subdirectory of a VBW project is told the guards are off" {
  "$VBW" init > /dev/null
  mkdir -p src/deep
  run session_start "$PROJECT/src/deep"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" == *"not at its root, so the VBW guards are off"* ]]
}
