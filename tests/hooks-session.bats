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

@test "VBW 1's command copies are removed (they would shadow VBW 2's commands); nothing else is touched" {
  local dir="$CLAUDE_CONFIG_DIR/commands/vbw"
  mkdir -p "$dir" "$CLAUDE_CONFIG_DIR/commands/mine"
  printf -- '---\nname: vbw:init\ndescription: x\n---\nbody\n' > "$dir/init.md"
  printf -- '---\nname: vbw:vibe\n---\nbody\n' > "$dir/vibe.md"
  printf -- '---\nname: my-own\n---\nname: vbw:not-frontmatter\n' > "$dir/mine.md"
  printf 'name: vbw:no-frontmatter\n' > "$dir/plain.md"
  printf -- '---\nname: vbw:elsewhere\n---\n' > "$CLAUDE_CONFIG_DIR/commands/mine/keep.md"
  run session_start "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" == *"removed 2 outdated VBW 1 command copies"* ]]
  [ ! -e "$dir/init.md" ] && [ ! -e "$dir/vibe.md" ]
  [ -f "$dir/mine.md" ] && [ -f "$dir/plain.md" ]
  [ -f "$CLAUDE_CONFIG_DIR/commands/mine/keep.md" ]
}

@test "the copies' directory is removed once empty, and a clean setup says nothing" {
  local dir="$CLAUDE_CONFIG_DIR/commands/vbw"
  mkdir -p "$dir"
  printf -- '---\nname: vbw:init\n---\n' > "$dir/init.md"
  run session_start "$PROJECT"
  [ ! -d "$dir" ]
  run session_start "$PROJECT"
  [ -z "$output" ]
}

@test "only the config directory this session uses is cleaned" {
  mkdir -p "$HOME/.claude/commands/vbw" "$TEST_ROOT/other/commands/vbw"
  printf -- '---\nname: vbw:init\n---\n' > "$HOME/.claude/commands/vbw/init.md"
  printf -- '---\nname: vbw:init\n---\n' > "$TEST_ROOT/other/commands/vbw/init.md"
  CLAUDE_CONFIG_DIR="$TEST_ROOT/other" run session_start "$PROJECT"
  [ ! -e "$TEST_ROOT/other/commands/vbw/init.md" ]
  [ -f "$HOME/.claude/commands/vbw/init.md" ]
}
