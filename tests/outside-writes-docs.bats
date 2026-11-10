#!/usr/bin/env bats
# R185 (F218, D364): the writes VBW makes outside the project are named, all three: the user's
# settings.json, the machine slot store and the --plugin-dir session record. docs/guards.md and
# AGENTS.md (CLAUDE.md links to it) say so, and the SessionStart section no longer says it never writes. L1.

load helper

@test "R185 (F218): docs/guards.md names the session record as an allowed write outside the project, with its folder and lifetime" {
  local g="$REPO_ROOT/docs/guards.md"
  grep -qF '<claude-config-dir>/vbw/sessions/<session id>' "$g"
  grep -q '7' "$g"
  grep -q 'D364' "$g"
  ! grep -q 'It never writes and never injects' "$g" || false
  grep -qF 'CLAUDE_ENV_FILE' "$g"
}

@test "R185 (F218): AGENTS.md's nothing-outside-the-project rule names four exceptions (R285: the session's env file the fourth), the session record among them" {
  local a="$REPO_ROOT/AGENTS.md" line
  line=$(grep 'Nothing outside the project' "$a")
  [[ "$line" == *"Four exceptions"* ]]
  [[ "$line" == *"vbw/sessions/"* ]]
  [[ "$line" == *"R185"* ]]
}

@test "R185 (F218): the session-start hook writes its record only under the documented folder" {
  local h="$REPO_ROOT/plugin/hooks/session-start.sh"
  grep -q 'vbw/sessions' "$h"
  # No other folder outside the project is written by the hook: every redirect target is the env file or the record.
  ! grep -E '>[[:space:]]*"?/tmp' "$h"
}
