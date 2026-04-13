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
