#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.contracts"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
  # Copy schemas
  mkdir -p "$TEST_TEMP_DIR/config/schemas"
  cp "$CONFIG_DIR/schemas/message-schemas.json" "$TEST_TEMP_DIR/config/schemas/"
  # V2 typed protocol graduated — flag set for backward compat with older test configs
  jq '.v2_typed_protocol = true | .v3_event_log = true' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
}

teardown() {
  teardown_temp_dir
}

valid_message() {
  cat << 'MSG'
{
  "id": "test-001",
  "type": "execution_update",
  "phase": 1,
  "task": "1-1-T1",
  "author_role": "dev",
  "timestamp": "2026-02-12T10:00:00Z",
  "schema_version": "2.0",
  "confidence": "high",
  "payload": {
    "plan_id": "1-1",
    "task_id": "1-1-T1",
    "status": "complete",
    "commit": "abc1234"
  }
}
MSG
}

@test "validate-message: valid message passes all checks" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/validate-message.sh" "$(valid_message)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: missing envelope field rejected" {
  cd "$TEST_TEMP_DIR"
  MSG='{"type":"execution_update","payload":{"plan_id":"1-1","task_id":"1-1-T1","status":"complete","commit":"abc"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.valid == false'
  [[ "$output" == *"missing envelope field"* ]]
}

@test "validate-message: unknown type rejected" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"x","type":"unknown_type","phase":1,"task":"1-1-T1","author_role":"dev","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.valid == false'
  [[ "$output" == *"unknown message type"* ]]
}

@test "validate-message: unauthorized role rejected" {
  cd "$TEST_TEMP_DIR"
  # QA agent sending execution_update (only dev is allowed)
  MSG='{"id":"x","type":"execution_update","phase":1,"task":"1-1-T1","author_role":"qa","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{"plan_id":"1-1","task_id":"1-1-T1","status":"complete","commit":"abc"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.valid == false'
  [[ "$output" == *"not authorized"* ]]
}

@test "validate-message: missing payload field rejected" {
  cd "$TEST_TEMP_DIR"
  # execution_update requires plan_id, task_id, status, commit
  MSG='{"id":"x","type":"execution_update","phase":1,"task":"1-1-T1","author_role":"dev","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{"plan_id":"1-1"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.valid == false'
  [[ "$output" == *"missing payload field"* ]]
}

@test "validate-message: scout_findings validates correctly" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"s1","type":"scout_findings","phase":1,"task":"1-1-T1","author_role":"scout","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{"domain":"tech-stack","documents":[{"name":"STACK.md","content":"test"}]}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: plan_contract validates correctly" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"c1","type":"plan_contract","phase":1,"task":"1-1-T1","author_role":"lead","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{"plan_id":"1-1","phase_id":"phase-1","objective":"Test","tasks":["1-1-T1"],"allowed_paths":["src/a.js"],"must_haves":["Works"]}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: qa_verdict validates correctly" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"q1","type":"qa_verdict","phase":1,"task":"1-1-T1","author_role":"qa","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{"tier":"standard","result":"PASS","checks":{"passed":10,"failed":0,"total":10}}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: qa_verdict with checks_detail validates correctly" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"q2","type":"qa_verdict","phase":1,"task":"1-1-T1","author_role":"qa","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{"tier":"standard","result":"PASS","checks":{"passed":2,"failed":0,"total":2},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Feature A","status":"PASS","evidence":"ok"},{"id":"ART-01","category":"artifact","description":"README","status":"PASS","evidence":"found"}]}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: qa_verdict rejects checks/detail counter mismatch" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"q2b","type":"qa_verdict","phase":1,"task":"1-1-T1","author_role":"qa","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{"tier":"standard","result":"PASS","checks":{"passed":2,"failed":1,"total":2},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Feature A","status":"PASS","evidence":"ok"},{"id":"ART-01","category":"artifact","description":"README","status":"PASS","evidence":"found"}]}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"checks.failed"* ]]
}

@test "validate-message: qa_verdict rejects checks_detail with non-string status" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"q3","type":"qa_verdict","phase":1,"task":"1-1-T1","author_role":"qa","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Feature A","status":false,"evidence":"ok"}]}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"PASS|FAIL|WARN"* ]]
}

@test "validate-message: qa_verdict rejects checks_detail with whitespace-only id/status" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"q4","type":"qa_verdict","phase":1,"task":"1-1-T1","author_role":"qa","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"   ","category":"must_have","description":"Feature A","status":"   ","evidence":"ok"}]}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"require non-empty string id and status"* ]]
}

@test "validate-message: blocker_report validates correctly" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"b1","type":"blocker_report","phase":1,"task":"1-1-T1","author_role":"dev","timestamp":"2026-01-01","schema_version":"2.0","confidence":"medium","payload":{"plan_id":"1-1","task_id":"1-1-T1","blocker":"Dependency missing","needs":"Plan 1-1 to complete"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: approval_request validates correctly" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"a1","type":"approval_request","phase":1,"task":"1-1-T1","author_role":"dev","timestamp":"2026-01-01","schema_version":"2.0","confidence":"medium","payload":{"subject":"Scope change","request_type":"scope_change","evidence":"Need auth module"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: approval_response validates correctly" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"r1","type":"approval_response","phase":1,"task":"1-1-T1","author_role":"lead","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{"request_id":"a1","approved":true,"reason":"Justified"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: file reference outside contract rejected" {
  cd "$TEST_TEMP_DIR"
  # Create a contract with limited allowed_paths
  cat > ".vbw-planning/.contracts/1-1.json" << 'CONTRACT'
{"phase":1,"plan":1,"task_count":2,"allowed_paths":["src/a.js"],"forbidden_paths":[]}
CONTRACT
  MSG='{"id":"x","type":"execution_update","phase":1,"task":"1-1-T1","author_role":"dev","timestamp":"2026-01-01","schema_version":"2.0","confidence":"high","payload":{"plan_id":"1-1","task_id":"1-1-T1","status":"complete","commit":"abc","files_modified":["src/unauthorized.js"]}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside contract scope"* ]]
}

@test "validate-message: validation always active (v2_typed_protocol graduated)" {
  cd "$TEST_TEMP_DIR"
  # v2_typed_protocol flag graduated - validation is now always active
  # Invalid JSON should always be rejected, regardless of config
  run bash "$SCRIPTS_DIR/validate-message.sh" "not even json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "validate-message: not valid JSON rejected" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/validate-message.sh" "this is not json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "validate-message: target role cannot receive is rejected" {
  cd "$TEST_TEMP_DIR"
  # scout_findings can_receive is NOT in dev's can_receive list
  MSG='{"id":"t-010","type":"scout_findings","phase":1,"task":"1-1-T1","author_role":"scout","target_role":"dev","timestamp":"2026-02-12T10:00:00Z","schema_version":"2.0","confidence":"high","payload":{"domain":"test","documents":["doc.md"]}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot receive"* ]]
}

@test "validate-message: target role can receive passes" {
  cd "$TEST_TEMP_DIR"
  # plan_contract IS in dev's can_receive list
  MSG='{"id":"t-011","type":"plan_contract","phase":1,"task":"1-1-T1","author_role":"lead","target_role":"dev","timestamp":"2026-02-12T10:00:00Z","schema_version":"2.0","confidence":"high","payload":{"plan_id":"1-1","phase_id":"phase-1","objective":"test","tasks":["t1"],"allowed_paths":["src/"],"must_haves":["works"]}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: absent target_role passes" {
  cd "$TEST_TEMP_DIR"
  # No target_role field — should not error
  run bash "$SCRIPTS_DIR/validate-message.sh" "$(valid_message)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}
