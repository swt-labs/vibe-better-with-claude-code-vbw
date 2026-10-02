#!/usr/bin/env bats
# vbw rtk recognises RTK's Claude Code hook by RTK's own rule
# (rtk-ai/rtk src/hooks/mod.rs, is_claude_hook_command): exactly the rtk
# binary, by name or path, then `hook claude`; or its older rtk-rewrite.sh.

load helper

setup() {
  vbw_setup
  vbw_git_project
}

teardown() { vbw_teardown; }

# hook_state COMMAND: what vbw rtk says about a PreToolUse hook running COMMAND.
hook_state() {
  jq -n --arg c "$1" '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $c}]}]}}' \
    > "$CLAUDE_CONFIG_DIR/settings.json"
  vbw_run rtk
  printf '%s\n' "$output" | sed -n 's/^claude hook: \([a-z]*\).*/\1/p'
}

@test "rtk: RTK's hook is on however RTK names its binary" {
  local c
  for c in 'rtk hook claude' '/opt/homebrew/bin/rtk hook claude' '"/opt/homebrew/bin/rtk" hook claude' \
      '/Users/jane/My\ Apps/rtk hook claude' "$HOME/.claude/hooks/rtk-rewrite.sh"; do
    [ "$(hook_state "$c")" = on ] || { echo "not recognised: $c"; false; }
  done
}

@test "rtk: commands RTK does not count as its hook are off" {
  local c
  for c in 'echo rtk hook claude' 'echo /opt/rtk hook claude' 'not-rtk hook claude' '/opt/homebrew/bin/rtk hook cursor'; do
    [ "$(hook_state "$c")" = off ] || { echo "wrongly recognised: $c"; false; }
  done
}
