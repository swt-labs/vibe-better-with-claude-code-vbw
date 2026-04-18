#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.metrics"
  # Copy token-budgets.json to test dir so SCRIPT_DIR/../config resolves
  mkdir -p "$TEST_TEMP_DIR/config"
  cp "$CONFIG_DIR/token-budgets.json" "$TEST_TEMP_DIR/config/token-budgets.json"
  # Create a wrapper script in test dir that sources the real script
  mkdir -p "$TEST_TEMP_DIR/scripts"
  cp "$SCRIPTS_DIR/token-baseline.sh" "$TEST_TEMP_DIR/scripts/token-baseline.sh"
  chmod +x "$TEST_TEMP_DIR/scripts/token-baseline.sh"
}

teardown() {
  teardown_temp_dir
}

@test "token-baseline: exits 0 with no event data" {
  cd "$TEST_TEMP_DIR"
  # Remove event/metrics dirs so files don't exist
  rm -rf ".vbw-planning/.events" ".vbw-planning/.metrics"
  run bash scripts/token-baseline.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"No event data"* ]]
}

@test "token-baseline: measure counts overages per phase" {
  cd "$TEST_TEMP_DIR"
  # 2 overages in phase 1, 1 in phase 2
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .vbw-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:01:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"600","lines_max":"800","lines_truncated":"50"}}' >> .vbw-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:02:00Z","event":"token_overage","phase":2,"data":{"role":"qa","lines_total":"400","lines_max":"600","lines_truncated":"30"}}' >> .vbw-planning/.metrics/run-metrics.jsonl

  run bash scripts/token-baseline.sh measure
  [ "$status" -eq 0 ]

  # Parse JSON output
  phase1_overages=$(echo "$output" | jq '.phases["1"].overages')
  phase2_overages=$(echo "$output" | jq '.phases["2"].overages')
  [ "$phase1_overages" -eq 2 ]
  [ "$phase2_overages" -eq 1 ]
}

@test "token-baseline: measure computes truncated lines sum" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .vbw-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:01:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"600","lines_max":"800","lines_truncated":"50"}}' >> .vbw-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:02:00Z","event":"token_overage","phase":2,"data":{"role":"qa","lines_total":"400","lines_max":"600","lines_truncated":"30"}}' >> .vbw-planning/.metrics/run-metrics.jsonl

  run bash scripts/token-baseline.sh measure
  [ "$status" -eq 0 ]

  total_truncated=$(echo "$output" | jq '.totals.truncated_chars')
  [ "$total_truncated" -eq 180 ]
}

@test "token-baseline: measure --save stores baseline" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .vbw-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:00:00Z","event_id":"e1","event":"task_started","phase":1}' >> .vbw-planning/.events/event-log.jsonl

  run bash scripts/token-baseline.sh measure --save
  [ "$status" -eq 0 ]

  # Baseline file should exist and be valid JSON
  [ -f ".vbw-planning/.baselines/token-baseline.json" ]
  run jq -e '.timestamp' .vbw-planning/.baselines/token-baseline.json
  [ "$status" -eq 0 ]
  run jq -e '.phases' .vbw-planning/.baselines/token-baseline.json
  [ "$status" -eq 0 ]
  run jq -e '.totals' .vbw-planning/.baselines/token-baseline.json
  [ "$status" -eq 0 ]
}

@test "token-baseline: compare shows deltas against baseline" {
  cd "$TEST_TEMP_DIR"
  # Create baseline with known values
  mkdir -p .vbw-planning/.baselines
  cat > .vbw-planning/.baselines/token-baseline.json <<'JSON'
{"timestamp":"2026-02-10T00:00:00Z","phases":{"1":{"overages":3,"truncated_chars":200,"tasks":10,"escalations":1,"overages_per_task":0.3}},"totals":{"overages":3,"truncated_chars":200,"tasks":10,"escalations":1,"overages_per_task":0.3},"budget_utilization":{}}
JSON

  # Create current data with fewer overages (better)
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"300","lines_max":"800","lines_truncated":"50"}}' >> .vbw-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:00:00Z","event_id":"e1","event":"task_started","phase":1}' >> .vbw-planning/.events/event-log.jsonl

  run bash scripts/token-baseline.sh compare
  [ "$status" -eq 0 ]

  # Current has 1 overage vs baseline 3 = delta -2 = better
  direction=$(echo "$output" | jq -r '.deltas.overages.direction')
  [ "$direction" = "better" ]
  delta=$(echo "$output" | jq '.deltas.overages.delta')
  [ "$delta" -eq -2 ]
}

@test "token-baseline: ignores archive lifecycle pseudo-phase" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-02-13T10:00:00Z","event_id":"e1","event":"task_started","phase":1}' >> .vbw-planning/.events/event-log.jsonl
  echo '{"ts":"2026-02-13T10:00:01Z","event_id":"e2","event":"milestone_shipped","phase":"archive","data":{"slug":"01-demo","archive_path":"/tmp/demo/.vbw-planning/milestones/01-demo","tag":"milestone/01-demo"}}' >> .vbw-planning/.events/event-log.jsonl
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .vbw-planning/.metrics/run-metrics.jsonl

  run bash scripts/token-baseline.sh measure
  [ "$status" -eq 0 ]
  archive_present=$(echo "$output" | jq '.phases | has("archive")')
  [ "$archive_present" = "false" ]

  mkdir -p .vbw-planning/.baselines
  cat > .vbw-planning/.baselines/token-baseline.json <<'JSON'
{"timestamp":"2026-02-10T00:00:00Z","phases":{"1":{"overages":1,"truncated_chars":100,"tasks":1,"escalations_legacy":0,"overages_per_task":1},"archive":{"overages":0,"truncated_chars":0,"tasks":0,"escalations_legacy":0,"overages_per_task":0}},"totals":{"overages":1,"truncated_chars":100,"tasks":1,"escalations_legacy":0,"overages_per_task":1},"budget_utilization":{}}
JSON

  run bash scripts/token-baseline.sh compare
  [ "$status" -eq 0 ]
  archive_change=$(echo "$output" | jq '.phase_changes | has("archive")')
  [ "$archive_change" = "false" ]

  run bash scripts/token-baseline.sh report
  [ "$status" -eq 0 ]
  [[ "$output" != *"| archive |"* ]]
}

@test "token-baseline: compare exits 0 when no baseline exists" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .vbw-planning/.metrics/run-metrics.jsonl

  run bash scripts/token-baseline.sh compare
  [ "$status" -eq 0 ]
  [[ "$output" == *"No baseline"* ]]
}

@test "token-baseline: report generates markdown" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-02-13T10:00:00Z","event_id":"e1","event":"task_started","phase":1}' >> .vbw-planning/.events/event-log.jsonl
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .vbw-planning/.metrics/run-metrics.jsonl

  run bash scripts/token-baseline.sh report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Token Usage Baseline Report"* ]]
  [[ "$output" == *"Per-Phase Summary"* ]]
  [[ "$output" == *"Budget Utilization"* ]]
  [[ "$output" == *"| Phase |"* ]]
}

@test "token-baseline: report includes comparison when baseline exists" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/.baselines
  cat > .vbw-planning/.baselines/token-baseline.json <<'JSON'
{"timestamp":"2026-02-10T00:00:00Z","phases":{"1":{"overages":5,"truncated_chars":300,"tasks":10,"escalations":2,"overages_per_task":0.5}},"totals":{"overages":5,"truncated_chars":300,"tasks":10,"escalations":2,"overages_per_task":0.5},"budget_utilization":{}}
JSON

  echo '{"ts":"2026-02-13T10:00:00Z","event_id":"e1","event":"task_started","phase":1}' >> .vbw-planning/.events/event-log.jsonl
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"300","lines_max":"800","lines_truncated":"50"}}' >> .vbw-planning/.metrics/run-metrics.jsonl

  run bash scripts/token-baseline.sh report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Comparison with Baseline"* ]]
  [[ "$output" == *"Baseline from:"* ]]
  [[ "$output" == *"| Metric |"* ]]
  [[ "$output" == *"better"* ]]
}

@test "token-baseline: phase filter works" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-02-13T10:00:00Z","event_id":"e1","event":"task_started","phase":1}' >> .vbw-planning/.events/event-log.jsonl
  echo '{"ts":"2026-02-13T10:01:00Z","event_id":"e2","event":"task_started","phase":2}' >> .vbw-planning/.events/event-log.jsonl
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .vbw-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:01:00Z","event":"token_overage","phase":2,"data":{"role":"qa","lines_total":"400","lines_max":"600","lines_truncated":"30"}}' >> .vbw-planning/.metrics/run-metrics.jsonl

  run bash scripts/token-baseline.sh report --phase=1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Phase filter: 1"* ]]
  # Phase 1 should appear
  [[ "$output" == *"| 1 |"* ]]
  # Phase 2 should NOT appear in the per-phase table
  [[ "$output" != *"| 2 |"* ]]
}

@test "token-baseline: handles empty event log gracefully" {
  cd "$TEST_TEMP_DIR"
  # Create empty files (0 bytes)
  touch .vbw-planning/.events/event-log.jsonl
  touch .vbw-planning/.metrics/run-metrics.jsonl

  run bash scripts/token-baseline.sh measure
  [ "$status" -eq 0 ]

  total_overages=$(echo "$output" | jq '.totals.overages')
  total_tasks=$(echo "$output" | jq '.totals.tasks')
  [ "$total_overages" -eq 0 ]
  [ "$total_tasks" -eq 0 ]
}
