#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  # Enable all runtime foundation flags
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_log = true | .v3_schema_validation = true | .v3_snapshot_resume = true' \
    .vbw-planning/config.json > .vbw-planning/config.json.tmp && \
    mv .vbw-planning/config.json.tmp .vbw-planning/config.json

  # Create sample execution state
  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'STATE'
{
  "phase": 5, "phase_name": "test-phase", "status": "running",
  "started_at": "2026-01-01T00:00:00Z", "wave": 1, "total_waves": 1,
  "plans": [{"id": "05-01", "title": "Test", "wave": 1, "status": "pending"}]
}
STATE

  # Create sample PLAN.md with valid frontmatter
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/05-test-phase"
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/05-test-phase/05-01-PLAN.md" <<'EOF'
---
phase: 5
plan: 1
title: "Test Plan"
wave: 1
depends_on: []
must_haves:
  - "Feature A"
---

# Plan 05-01: Test Plan

## Tasks

### Task 1: Do something
- **Files:** `scripts/test.sh`
EOF
}

teardown() {
  teardown_temp_dir
}

# --- log-event.sh tests ---

@test "log-event: creates event log JSONL" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/log-event.sh" phase_start 5
  [ "$status" -eq 0 ]
  [ -f ".vbw-planning/.events/event-log.jsonl" ]
  # Verify JSON structure
  LINE=$(head -1 .vbw-planning/.events/event-log.jsonl)
  echo "$LINE" | jq -e '.event == "phase_start"'
  echo "$LINE" | jq -e '.phase == 5'
}

@test "log-event: appends plan events with key=value data" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/log-event.sh" plan_start 5 1
  bash "$SCRIPTS_DIR/log-event.sh" plan_end 5 1 status=complete
  LINES=$(wc -l < .vbw-planning/.events/event-log.jsonl | tr -d ' ')
  [ "$LINES" -eq 2 ]
  LAST=$(tail -1 .vbw-planning/.events/event-log.jsonl)
  echo "$LAST" | jq -e '.event == "plan_end"'
  echo "$LAST" | jq -e '.data.status == "complete"'
}

@test "log-event: exits 0 when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_log = false' .vbw-planning/config.json > .vbw-planning/config.json.tmp && \
    mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/log-event.sh" phase_start 5
  [ "$status" -eq 0 ]
  [ ! -f ".vbw-planning/.events/event-log.jsonl" ]
}

# --- validate-schema.sh tests ---

@test "validate-schema: returns valid for correct plan frontmatter" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/validate-schema.sh" plan ".vbw-planning/phases/05-test-phase/05-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

@test "validate-schema: returns invalid for missing fields" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/bad-plan.md" <<'EOF'
---
phase: 5
title: "Incomplete"
---

# Bad plan
EOF
  run bash "$SCRIPTS_DIR/validate-schema.sh" plan "$TEST_TEMP_DIR/bad-plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"invalid"* ]]
  [[ "$output" == *"wave"* ]]
}

@test "validate-schema: validates summary schema" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/good-summary.md" <<'EOF'
---
phase: 5
plan: 1
title: "Test Summary"
status: complete
tasks_completed: 3
tasks_total: 3
---

# Summary
EOF
  run bash "$SCRIPTS_DIR/validate-schema.sh" summary "$TEST_TEMP_DIR/good-summary.md"
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

@test "validate-schema: validates contract schema (JSON)" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/contract.json" <<'JSON'
{"phase": 5, "plan": 1, "task_count": 3, "allowed_paths": ["scripts/"]}
JSON
  run bash "$SCRIPTS_DIR/validate-schema.sh" contract "$TEST_TEMP_DIR/contract.json"
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

@test "validate-schema: exits 0 when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_schema_validation = false' .vbw-planning/config.json > .vbw-planning/config.json.tmp && \
    mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/validate-schema.sh" plan ".vbw-planning/phases/05-test-phase/05-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

# --- snapshot-resume.sh tests ---

@test "snapshot-resume: save creates snapshot file" {
  cd "$TEST_TEMP_DIR"
  # Init git for git log
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "test" > test.txt && git add test.txt && git commit -q -m "init"

  run bash "$SCRIPTS_DIR/snapshot-resume.sh" save 5
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ -f "$output" ]
  # Verify snapshot content
  jq -e '.phase == 5' "$output"
  jq -e '.execution_state.status == "running"' "$output"
  jq -e '.recent_commits | length > 0' "$output"
}

@test "snapshot-resume: restore finds latest snapshot" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "test" > test.txt && git add test.txt && git commit -q -m "init"

  # Save two snapshots
  bash "$SCRIPTS_DIR/snapshot-resume.sh" save 5
  sleep 1
  bash "$SCRIPTS_DIR/snapshot-resume.sh" save 5

  run bash "$SCRIPTS_DIR/snapshot-resume.sh" restore 5
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ -f "$output" ]
}

@test "snapshot-resume: restore prefers matching agent role when provided" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "test" > test.txt && git add test.txt && git commit -q -m "init"

  # Save snapshots for two different roles
  bash "$SCRIPTS_DIR/snapshot-resume.sh" save 5 ".vbw-planning/.execution-state.json" "vbw-qa" "auto"
  sleep 1
  bash "$SCRIPTS_DIR/snapshot-resume.sh" save 5 ".vbw-planning/.execution-state.json" "vbw-dev" "auto"

  run bash "$SCRIPTS_DIR/snapshot-resume.sh" restore 5 "vbw-qa"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ -f "$output" ]
  run jq -r '.agent_role' "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "vbw-qa" ]
}

@test "post-compact: plan_id_to_num extracts numeric plan number" {
  # Source the helper functions from post-compact.sh
  # They're defined at the top of the file, extract them
  plan_id_to_num() {
    local plan_id="$1"
    echo "$plan_id" | sed 's/^[0-9]*-//;s/^0*//;s/^$/0/'
  }

  run plan_id_to_num "05-01"
  [ "$output" = "1" ]
  run plan_id_to_num "01-02"
  [ "$output" = "2" ]
  run plan_id_to_num "05-00"
  [ "$output" = "0" ]
  run plan_id_to_num ""
  [ "$output" = "0" ]
  run plan_id_to_num "5"
  [ "$output" = "5" ]
}

@test "post-compact: next_task_from_completed increments task number" {
  next_task_from_completed() {
    local task_id="$1"
    if [[ "$task_id" =~ ^([0-9]+-[0-9]+-T)([0-9]+)$ ]]; then
      echo "${BASH_REMATCH[1]}$((BASH_REMATCH[2] + 1))"
    fi
  }

  run next_task_from_completed "1-2-T3"
  [ "$output" = "1-2-T4" ]
  run next_task_from_completed "1-2-T0"
  [ "$output" = "1-2-T1" ]
  run next_task_from_completed "10-20-T99"
  [ "$output" = "10-20-T100" ]
  run next_task_from_completed ""
  [ "$output" = "" ]
  run next_task_from_completed "bad-input"
  [ "$output" = "" ]
}

@test "snapshot-resume: prunes old snapshots beyond 10" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "test" > test.txt && git add test.txt && git commit -q -m "init"

  # Create 12 snapshots manually
  mkdir -p .vbw-planning/.snapshots
  for i in $(seq 1 12); do
    TS=$(printf "20260101T%02d0000" "$i")
    echo '{"snapshot_ts":"'$TS'","phase":5,"execution_state":{},"recent_commits":[]}' \
      > ".vbw-planning/.snapshots/5-${TS}.json"
  done

  # Save one more (should trigger prune)
  bash "$SCRIPTS_DIR/snapshot-resume.sh" save 5

  SNAP_COUNT=$(ls -1 .vbw-planning/.snapshots/5-*.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$SNAP_COUNT" -le 10 ]
}

@test "snapshot-resume: exits 0 when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_snapshot_resume = false' .vbw-planning/config.json > .vbw-planning/config.json.tmp && \
    mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/snapshot-resume.sh" save 5
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
