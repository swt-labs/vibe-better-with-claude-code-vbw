#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "log-event: emits valid JSON for hyphenated plan ID (03-08)" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/log-event.sh" plan_end 3 03-08 status=complete
  LINE=$(tail -1 .vbw-planning/.events/event-log.jsonl)
  # Must be valid JSON (jq -e exits non-zero on parse failure)
  echo "$LINE" | jq -e '.' >/dev/null
  # plan field must be present and equal to "03-08"
  PLAN_VAL=$(echo "$LINE" | jq -r '.plan')
  [ "$PLAN_VAL" = "03-08" ]
}

@test "log-event: emits valid JSON for numeric plan ID" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/log-event.sh" plan_end 1 3 status=complete
  LINE=$(tail -1 .vbw-planning/.events/event-log.jsonl)
  echo "$LINE" | jq -e '.' >/dev/null
  PLAN_VAL=$(echo "$LINE" | jq '.plan')
  [ "$PLAN_VAL" = "3" ]
}

@test "log-event: emits valid JSON with no plan argument" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/log-event.sh" phase_start 1
  LINE=$(tail -1 .vbw-planning/.events/event-log.jsonl)
  echo "$LINE" | jq -e '.' >/dev/null
  # plan field should not be present
  HAS_PLAN=$(echo "$LINE" | jq 'has("plan")')
  [ "$HAS_PLAN" = "false" ]
}

@test "log-event: emits valid JSON with data key=value pairs" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/log-event.sh" plan_end 2 5 status=failed reason=timeout
  LINE=$(tail -1 .vbw-planning/.events/event-log.jsonl)
  echo "$LINE" | jq -e '.' >/dev/null
  STATUS=$(echo "$LINE" | jq -r '.data.status')
  REASON=$(echo "$LINE" | jq -r '.data.reason')
  [ "$STATUS" = "failed" ]
  [ "$REASON" = "timeout" ]
}

@test "log-event: hyphenated plan ID survives roundtrip through recover-state" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  # Set up phase 3 with plan 03-08
  mkdir -p .vbw-planning/phases/03-core
  echo "title: Some Task" > .vbw-planning/phases/03-core/03-08-PLAN.md

  # Log a plan_end event with hyphenated plan ID via log-event.sh
  bash "$SCRIPTS_DIR/log-event.sh" plan_end 3 8 status=complete

  # Verify the event log line is valid JSON
  LINE=$(tail -1 .vbw-planning/.events/event-log.jsonl)
  echo "$LINE" | jq -e '.' >/dev/null

  # Recover state should pick up the completion from the event log
  run bash "$SCRIPTS_DIR/recover-state.sh" 3 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  plan_status=$(echo "$output" | jq -r '.plans[] | select(.id == "03-08") | .status')
  [ "$plan_status" = "complete" ]
}
