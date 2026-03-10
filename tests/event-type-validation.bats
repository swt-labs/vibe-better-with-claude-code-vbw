#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "event-types: accepts V1 event type (graduated protocol)" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/log-event.sh" phase_start 1
  [ "$status" -eq 0 ]
  [ -f .vbw-planning/.events/event-log.jsonl ]
  run grep -c "phase_start" .vbw-planning/.events/event-log.jsonl
  [ "$output" = "1" ]
}

@test "event-types: accepts V2 event type (graduated protocol)" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/log-event.sh" task_claimed 1
  [ "$status" -eq 0 ]
  [ -f .vbw-planning/.events/event-log.jsonl ]
  run grep -c "task_claimed" .vbw-planning/.events/event-log.jsonl
  [ "$output" = "1" ]
}

@test "event-types: rejects unknown event type" {
  cd "$TEST_TEMP_DIR"
  run bash -c "bash '$SCRIPTS_DIR/log-event.sh' bogus_event 1 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown event type 'bogus_event' rejected"* ]]
  # Event file should not exist or not contain the bogus event
  if [ -f .vbw-planning/.events/event-log.jsonl ]; then
    run grep -c "bogus_event" .vbw-planning/.events/event-log.jsonl
    [ "$output" = "0" ]
  fi
}

@test "event-types: all 13 V2 types accepted" {
  cd "$TEST_TEMP_DIR"
  local v2_types="phase_planned task_created task_claimed task_started artifact_written gate_passed gate_failed task_completed_candidate task_completed_confirmed task_blocked task_reassigned shutdown_sent shutdown_received"
  for etype in $v2_types; do
    run bash "$SCRIPTS_DIR/log-event.sh" "$etype" 1
    [ "$status" -eq 0 ]
  done
  [ -f .vbw-planning/.events/event-log.jsonl ]
  run wc -l < .vbw-planning/.events/event-log.jsonl
  # Trim whitespace from wc output
  local count
  count=$(echo "$output" | tr -d ' ')
  [ "$count" = "13" ]
}
