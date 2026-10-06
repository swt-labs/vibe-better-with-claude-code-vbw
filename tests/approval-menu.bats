#!/usr/bin/env bats
# R83: VBW asks for approval only with the approval menu (AskUserQuestion,
# Approve first so Enter approves). No message the kernel, a guard, a hook, a
# workflow, an agent or the router gives Claude tells it to have the user type
# or run /vbw:approve, so Claude never passes that on; a user who types it is
# still served. Found 2026-10-06: a session asked "type /vbw:approve" in prose,
# copying the guard's and the kernel's wording. L1: the texts and the guard.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

bash_call() {
  jq -nc --arg c "$1" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' \
    | HOOK_PROJECT_DIR="$PROJECT" vbw_hook PreToolUse Bash
}

@test "R83: no text VBW hands Claude says to type or run /vbw:approve" {
  run grep -rnE '(then|run|type|Type|runs|typing) `?/vbw:approve' \
    "$PLUGIN_ROOT/lib" "$PLUGIN_ROOT/bin" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/workflows" "$PLUGIN_ROOT/agents" \
    "$PLUGIN_ROOT/skills/vibe" "$PLUGIN_ROOT/skills/qa" "$PLUGIN_ROOT/skills/interview" "$PLUGIN_ROOT/skills/convert"
  # The router may say that a user who types it is still served.
  [ -z "$(printf '%s\n' "$output" | grep -v 'still works' | grep -v '^$')" ] || { echo "$output"; false; }
}

@test "R83: when Claude tries to approve, the guard refuses and tells it to ask with the approval menu" {
  run bash_call 'vbw approve'
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]
  reason=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')
  [[ "$reason" == *AskUserQuestion* || "$reason" == *"approval menu"* ]] || { echo "$reason"; false; }
  [[ "$reason" != *"run /vbw:approve"* && "$reason" != *"type /vbw:approve"* ]] || { echo "$reason"; false; }
}

@test "R83: the router asks for approval only with the menu and never asks the user to type the command" {
  local step
  step=$(sed -n '/^\*\*approve\*\*/,/^\*\*build\*\*/p' "$PLUGIN_ROOT/skills/vibe/SKILL.md")
  printf '%s' "$step" | grep -q 'AskUserQuestion'
  printf '%s' "$step" | tr '\n' ' ' | grep -qiE 'only (with|through) (the )?(approval )?menu|never ask (the user )?to type'
}
