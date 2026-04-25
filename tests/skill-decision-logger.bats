#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export CLAUDE_SESSION_ID="test-session-123"
}

teardown() {
  unset CLAUDE_SESSION_ID
  teardown_temp_dir
}

run_logger() {
  create_test_vbw_workspace "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR" && printf '%s' "$1" | bash "$SCRIPTS_DIR/skill-decision-logger.sh"
}

@test "skill-decision-logger: multi-line skill_activation extracts joined reason" {
  local input
  input=$(jq -n -c '{tool_input: {prompt: "<skill_activation>\nCall Skill(find-docs).\nCall Skill(xcodebuildmcp-cli).\n</skill_activation>\n\nDo the research task.", agent: "vbw-scout"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ -f "$log" ]
  run jq -r '.decision' "$log"
  [ "$output" = "activation" ]
  run jq -r '.reason' "$log"
  [[ "$output" == *"find-docs"* ]]
  [[ "$output" == *"xcodebuildmcp-cli"* ]]
  run jq -r '.agent' "$log"
  [ "$output" = "vbw-scout" ]
}

@test "skill-decision-logger: multi-line skill_no_activation extracts reason" {
  local input
  input=$(jq -n -c '{tool_input: {prompt: "<skill_no_activation>\nEvaluated installed skills for this task.\nNo installed skills apply.\nReason: pure code investigation.\n</skill_no_activation>\n\nResearch the bug.", agent: "vbw-scout"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ -f "$log" ]
  run jq -r '.decision' "$log"
  [ "$output" = "no_activation" ]
  run jq -r '.reason' "$log"
  [[ "$output" == *"No installed skills apply"* ]]
  [[ "$output" == *"pure code investigation"* ]]
}

@test "skill-decision-logger: single-line activation still works" {
  local input
  input=$(jq -n -c '{tool_input: {prompt: "<skill_activation>Call Skill(find-docs).</skill_activation>\n\nDo it.", agent: "vbw-dev"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ -f "$log" ]
  run jq -r '.decision' "$log"
  [ "$output" = "activation" ]
  run jq -r '.reason' "$log"
  [[ "$output" == *"find-docs"* ]]
}

@test "skill-decision-logger: no tag produces no log entry" {
  local input
  input=$(jq -n -c '{tool_input: {prompt: "Just do the task without any skill blocks.", agent: "vbw-dev"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ ! -f "$log" ]
}

@test "skill-decision-logger: reason truncated at 200 chars" {
  local long_reason
  long_reason=$(printf 'x%.0s' {1..250})
  local input
  input=$(jq -n -c --arg r "$long_reason" '{tool_input: {prompt: ("<skill_activation>" + $r + "</skill_activation>"), agent: "vbw-dev"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ -f "$log" ]
  run jq -r '.reason' "$log"
  [ "${#output}" -le 204 ]  # 200 chars + "..."
  [[ "$output" == *"..."* ]]
}

@test "skill-decision-logger: session ID captured from env" {
  local input
  input=$(jq -n -c '{tool_input: {prompt: "<skill_no_activation>No skills needed.</skill_no_activation>", agent: "vbw-qa"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ -f "$log" ]
  run jq -r '.session' "$log"
  [ "$output" = "test-session-123" ]
}

@test "skill-decision-logger: empty input exits 0" {
  cd "$TEST_TEMP_DIR"
  run bash -c "echo '' | bash '$SCRIPTS_DIR/skill-decision-logger.sh'"
  [ "$status" -eq 0 ]
}

@test "skill-decision-logger: malformed JSON exits 0" {
  cd "$TEST_TEMP_DIR"
  run bash -c "echo 'not json at all' | bash '$SCRIPTS_DIR/skill-decision-logger.sh'"
  [ "$status" -eq 0 ]
}

@test "skill-decision-logger: subagent_type-only input captures agent identity" {
  local input
  input=$(jq -n -c '{tool_input: {prompt: "<skill_no_activation>No skills needed for this task.</skill_no_activation>\n\nFix the bug.", subagent_type: "vbw:vbw-dev"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ -f "$log" ]
  run jq -r '.agent' "$log"
  [ "$output" = "vbw:vbw-dev" ]
  run jq -r '.decision' "$log"
  [ "$output" = "no_activation" ]
}

@test "skill-decision-logger: blank agent falls through to subagent_type" {
  local input
  input=$(jq -n -c '{tool_input: {prompt: "<skill_activation>Call Skill(find-docs).</skill_activation>\nDo research.", agent: "", subagent_type: "vbw:vbw-scout"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ -f "$log" ]
  run jq -r '.agent' "$log"
  [ "$output" = "vbw:vbw-scout" ]
}

@test "skill-decision-logger: blank prompt falls through to description" {
  local input
  input=$(jq -n -c '{tool_input: {prompt: "", description: "<skill_no_activation>Not needed.</skill_no_activation>\nDo the task.", agent: "vbw-dev"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ -f "$log" ]
  run jq -r '.decision' "$log"
  [ "$output" = "no_activation" ]
}

@test "skill-decision-logger: all agent fields blank yields unknown" {
  local input
  input=$(jq -n -c '{tool_input: {prompt: "<skill_activation>Call Skill(x).</skill_activation>", agent: "", name: "", subagent_type: ""}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ -f "$log" ]
  run jq -r '.agent' "$log"
  [ "$output" = "unknown" ]
}

@test "skill-decision-logger: runtime Skill tool usage logs separate entry kind" {
  local input
  input=$(jq -n -c '{tool_name: "Skill", tool_input: {skill: "swiftdata", args: "Investigate SplitTransferService reverse split failure"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ -f "$log" ]
  run jq -r '.kind' "$log"
  [ "$output" = "runtime_skill" ]
  run jq -r '.decision' "$log"
  [ "$output" = "activation" ]
  run jq -r '.skill' "$log"
  [ "$output" = "swiftdata" ]
  run jq -r '.reason' "$log"
  [[ "$output" == *"Skill(swiftdata)"* ]]
  [[ "$output" == *"SplitTransferService"* ]]
}

@test "skill-decision-logger: runtime Skill tool usage works without prompt blocks" {
  local input
  input=$(jq -n -c '{tool_name: "Skill", tool_input: {skill: "xcodebuildmcp-cli"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ -f "$log" ]
  run jq -r '.kind' "$log"
  [ "$output" = "runtime_skill" ]
  run jq -r '.skill' "$log"
  [ "$output" = "xcodebuildmcp-cli" ]
}

@test "skill-decision-logger: malformed skill_activation block exits 0 and writes no log" {
  local input
  input=$(jq -n -c '{tool_input: {prompt: "<skill_activation>Call Skill(find-docs).", agent: "vbw-dev"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ ! -f "$log" ]
}

@test "skill-decision-logger: malformed skill_no_activation block exits 0 and writes no log" {
  local input
  input=$(jq -n -c '{tool_input: {prompt: "<skill_no_activation>Reason: sparse task.", agent: "vbw-dev"}}')
  run_logger "$input"
  local log="$TEST_TEMP_DIR/.vbw-planning/.skill-decisions.log"
  [ ! -f "$log" ]
}
