#!/usr/bin/env bats

# Tests for commit 4209e6cc: shutdown_request/shutdown_response protocol
# Covers: agent handler presence, handoff-schemas consistency,
#         message-schemas.json machine-readable definitions, and
#         validate-message.sh acceptance/rejection of shutdown messages.

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.contracts"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
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

# =============================================================================
# Agent definitions: all 6 team-participating agents have Shutdown Handling
# =============================================================================

@test "vbw-dev has Shutdown Handling section" {
  grep -q '^## Shutdown Handling$' "$PROJECT_ROOT/agents/vbw-dev.md"
}

@test "vbw-qa has Shutdown Handling section" {
  grep -q '^## Shutdown Handling$' "$PROJECT_ROOT/agents/vbw-qa.md"
}

@test "vbw-scout has Shutdown Handling section" {
  grep -q '^## Shutdown Handling$' "$PROJECT_ROOT/agents/vbw-scout.md"
}

@test "vbw-lead has Shutdown Handling section" {
  grep -q '^## Shutdown Handling$' "$PROJECT_ROOT/agents/vbw-lead.md"
}

@test "vbw-debugger has Shutdown Handling section" {
  grep -q '^## Shutdown Handling$' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "vbw-docs has Shutdown Handling section" {
  grep -q '^## Shutdown Handling$' "$PROJECT_ROOT/agents/vbw-docs.md"
}

# =============================================================================
# Agent handlers reference both message types
# =============================================================================

@test "all agent handlers reference shutdown_request" {
  for agent in dev qa scout lead debugger docs; do
    grep -q 'shutdown_request' "$PROJECT_ROOT/agents/vbw-${agent}.md" || {
      echo "vbw-${agent}.md missing shutdown_request reference"
      return 1
    }
  done
}

@test "all agent handlers reference shutdown_response" {
  for agent in dev qa scout lead debugger docs; do
    grep -q 'shutdown_response' "$PROJECT_ROOT/agents/vbw-${agent}.md" || {
      echo "vbw-${agent}.md missing shutdown_response reference"
      return 1
    }
  done
}

# =============================================================================
# Agent handlers instruct STOP behavior
# =============================================================================

@test "all agent shutdown handlers instruct to STOP" {
  for agent in dev qa scout lead debugger docs; do
    # Each handler must contain a STOP instruction
    sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/vbw-${agent}.md" | grep -qi 'STOP' || {
      echo "vbw-${agent}.md Shutdown Handling section missing STOP instruction"
      return 1
    }
  done
}

@test "debugger handler includes checkpoint instruction" {
  sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep -qi 'checkpoint'
}

# =============================================================================
# Shutdown Handling is positioned between Effort and Circuit Breaker
# =============================================================================

@test "shutdown handling section order: after Effort, before Circuit Breaker" {
  for agent in dev qa scout lead debugger docs; do
    local file="$PROJECT_ROOT/agents/vbw-${agent}.md"
    local effort_line shutdown_line breaker_line
    effort_line=$(grep -n '^## Effort' "$file" | head -1 | cut -d: -f1)
    shutdown_line=$(grep -n '^## Shutdown Handling' "$file" | head -1 | cut -d: -f1)
    breaker_line=$(grep -n '^## Circuit Breaker' "$file" | head -1 | cut -d: -f1)
    [ -n "$effort_line" ] && [ -n "$shutdown_line" ] && [ -n "$breaker_line" ] || {
      echo "vbw-${agent}.md missing one of Effort/Shutdown/Circuit sections"
      return 1
    }
    [ "$effort_line" -lt "$shutdown_line" ] || {
      echo "vbw-${agent}.md: Shutdown Handling ($shutdown_line) not after Effort ($effort_line)"
      return 1
    }
    [ "$shutdown_line" -lt "$breaker_line" ] || {
      echo "vbw-${agent}.md: Shutdown Handling ($shutdown_line) not before Circuit Breaker ($breaker_line)"
      return 1
    }
  done
}

# =============================================================================
# Handoff schemas: prose documentation consistency
# =============================================================================

@test "handoff-schemas.md envelope type list includes shutdown_request" {
  grep -q 'shutdown_request' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff-schemas.md envelope type list includes shutdown_response" {
  grep -q 'shutdown_response' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff-schemas.md has shutdown_request section" {
  grep -q '## `shutdown_request`' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff-schemas.md has shutdown_response section" {
  grep -q '## `shutdown_response`' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff-schemas.md role matrix lists shutdown_request sender as lead" {
  grep 'shutdown_request' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q 'lead'
}

@test "handoff-schemas.md role matrix lists all 6 roles as shutdown_request receivers" {
  local row
  row=$(grep 'shutdown_request.*|.*|' "$PROJECT_ROOT/references/handoff-schemas.md" | head -1)
  for role in dev qa scout lead debugger docs; do
    echo "$row" | grep -q "$role" || {
      echo "shutdown_request receiver row missing $role"
      return 1
    }
  done
}

@test "handoff-schemas.md shutdown_request payload has reason field" {
  # The JSON example should contain "reason"
  sed -n '/## `shutdown_request`/,/## `/p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q '"reason"'
}

@test "handoff-schemas.md shutdown_response payload has request_id and approved fields" {
  local section
  section=$(sed -n '/## `shutdown_response`/,/## /p' "$PROJECT_ROOT/references/handoff-schemas.md")
  echo "$section" | grep -q '"request_id"'
  echo "$section" | grep -q '"approved"'
}

@test "handoff-schemas.md shutdown_response payload has final_status field" {
  sed -n '/## `shutdown_response`/,/## /p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q '"final_status"'
}

# =============================================================================
# Machine-readable schema: message-schemas.json includes shutdown types
# =============================================================================

@test "message-schemas.json has shutdown_request schema" {
  jq -e '.schemas.shutdown_request' "$CONFIG_DIR/schemas/message-schemas.json"
}

@test "message-schemas.json has shutdown_response schema" {
  jq -e '.schemas.shutdown_response' "$CONFIG_DIR/schemas/message-schemas.json"
}

@test "message-schemas.json shutdown_request allowed_roles includes lead" {
  jq -e '.schemas.shutdown_request.allowed_roles | index("lead") != null' "$CONFIG_DIR/schemas/message-schemas.json"
}

@test "message-schemas.json shutdown_response allowed_roles includes all 6 teammate roles" {
  for role in dev qa scout lead debugger docs; do
    jq -e --arg r "$role" '.schemas.shutdown_response.allowed_roles | index($r) != null' \
      "$CONFIG_DIR/schemas/message-schemas.json" || {
      echo "shutdown_response missing allowed role: $role"
      return 1
    }
  done
}

@test "message-schemas.json shutdown_request payload requires reason and team_name" {
  jq -e '.schemas.shutdown_request.payload_required | (index("reason") != null and index("team_name") != null)' \
    "$CONFIG_DIR/schemas/message-schemas.json"
}

@test "message-schemas.json shutdown_response payload requires request_id, approved, final_status" {
  jq -e '.schemas.shutdown_response.payload_required | (index("request_id") != null and index("approved") != null and index("final_status") != null)' \
    "$CONFIG_DIR/schemas/message-schemas.json"
}

# =============================================================================
# Role hierarchy: shutdown messages in can_send / can_receive
# =============================================================================

@test "message-schemas.json lead can_send includes shutdown_request" {
  jq -e '.role_hierarchy.lead.can_send | index("shutdown_request") != null' \
    "$CONFIG_DIR/schemas/message-schemas.json"
}

@test "message-schemas.json all teammate roles can_receive shutdown_request" {
  for role in dev qa scout debugger docs; do
    jq -e --arg r "$role" '.role_hierarchy[$r].can_receive | index("shutdown_request") != null' \
      "$CONFIG_DIR/schemas/message-schemas.json" || {
      echo "$role missing shutdown_request in can_receive"
      return 1
    }
  done
}

@test "message-schemas.json all teammate roles can_send shutdown_response" {
  for role in dev qa scout debugger docs lead; do
    jq -e --arg r "$role" '.role_hierarchy[$r].can_send | index("shutdown_response") != null' \
      "$CONFIG_DIR/schemas/message-schemas.json" || {
      echo "$role missing shutdown_response in can_send"
      return 1
    }
  done
}

@test "message-schemas.json lead can_receive includes shutdown_response" {
  jq -e '.role_hierarchy.lead.can_receive | index("shutdown_response") != null' \
    "$CONFIG_DIR/schemas/message-schemas.json"
}

# =============================================================================
# validate-message.sh: shutdown_request accepted from lead
# =============================================================================

@test "validate-message: shutdown_request from lead passes" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-001","type":"shutdown_request","phase":1,"task":"","author_role":"lead","timestamp":"2026-02-12T10:30:00Z","schema_version":"2.0","confidence":"high","payload":{"reason":"phase_complete","team_name":"vbw-phase-01"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: shutdown_request from dev rejected (unauthorized)" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-bad","type":"shutdown_request","phase":1,"task":"","author_role":"dev","timestamp":"2026-02-12T10:30:00Z","schema_version":"2.0","confidence":"high","payload":{"reason":"phase_complete","team_name":"vbw-phase-01"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not authorized"* ]]
}

@test "validate-message: shutdown_request missing reason rejected" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-002","type":"shutdown_request","phase":1,"task":"","author_role":"lead","timestamp":"2026-02-12T10:30:00Z","schema_version":"2.0","confidence":"high","payload":{"team_name":"vbw-phase-01"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing payload field"* ]]
}

@test "validate-message: shutdown_request missing team_name rejected" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-003","type":"shutdown_request","phase":1,"task":"","author_role":"lead","timestamp":"2026-02-12T10:30:00Z","schema_version":"2.0","confidence":"high","payload":{"reason":"phase_complete"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing payload field"* ]]
}

# =============================================================================
# validate-message.sh: shutdown_response accepted from teammates
# =============================================================================

@test "validate-message: shutdown_response from dev passes" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-resp-001","type":"shutdown_response","phase":1,"task":"","author_role":"dev","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","approved":true,"final_status":"complete"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: shutdown_response from qa passes" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-resp-002","type":"shutdown_response","phase":1,"task":"","author_role":"qa","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","approved":true,"final_status":"idle"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: shutdown_response from scout passes" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-resp-003","type":"shutdown_response","phase":1,"task":"","author_role":"scout","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","approved":true,"final_status":"idle"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: shutdown_response from debugger passes" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-resp-004","type":"shutdown_response","phase":1,"task":"","author_role":"debugger","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","approved":true,"final_status":"in_progress"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: shutdown_response from lead passes" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-resp-005","type":"shutdown_response","phase":1,"task":"","author_role":"lead","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","approved":true,"final_status":"complete"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: shutdown_response from docs passes" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-resp-006","type":"shutdown_response","phase":1,"task":"","author_role":"docs","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","approved":true,"final_status":"idle"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: shutdown_response missing request_id rejected" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-resp-bad","type":"shutdown_response","phase":1,"task":"","author_role":"dev","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"approved":true,"final_status":"complete"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing payload field"* ]]
}

@test "validate-message: shutdown_response missing approved rejected" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-resp-bad2","type":"shutdown_response","phase":1,"task":"","author_role":"dev","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","final_status":"complete"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing payload field"* ]]
}

@test "validate-message: shutdown_response missing final_status rejected" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-resp-bad3","type":"shutdown_response","phase":1,"task":"","author_role":"dev","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","approved":true}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing payload field"* ]]
}

# =============================================================================
# validate-message.sh: target_role routing for shutdown messages
# =============================================================================

@test "validate-message: shutdown_request targeted to dev passes receive check" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-t1","type":"shutdown_request","phase":1,"task":"","author_role":"lead","target_role":"dev","timestamp":"2026-02-12T10:30:00Z","schema_version":"2.0","confidence":"high","payload":{"reason":"phase_complete","team_name":"vbw-phase-01"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: shutdown_response targeted to lead passes receive check" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-t2","type":"shutdown_response","phase":1,"task":"","author_role":"dev","target_role":"lead","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","approved":true,"final_status":"complete"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

# =============================================================================
# validate-message.sh: shutdown_request targeted to specific roles
# =============================================================================

@test "validate-message: shutdown_request targeted to docs passes" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-t3","type":"shutdown_request","phase":1,"task":"","author_role":"lead","target_role":"docs","timestamp":"2026-02-12T10:30:00Z","schema_version":"2.0","confidence":"high","payload":{"reason":"phase_complete","team_name":"vbw-phase-01"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

@test "validate-message: shutdown_request targeted to lead passes" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-t4","type":"shutdown_request","phase":1,"task":"","author_role":"lead","target_role":"lead","timestamp":"2026-02-12T10:30:00Z","schema_version":"2.0","confidence":"high","payload":{"reason":"phase_complete","team_name":"vbw-phase-01"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

# =============================================================================
# Finding 6: v2_typed_protocol is graduated — validator always validates
# =============================================================================

@test "validate-message: shutdown_request validates even when v2_typed_protocol absent (graduated flag)" {
  cd "$TEST_TEMP_DIR"
  # Remove the flag entirely (simulates graduated config after migration)
  jq 'del(.v2_typed_protocol)' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  # Valid message should still pass
  MSG='{"id":"shut-fallback","type":"shutdown_request","phase":1,"task":"","author_role":"lead","timestamp":"2026-02-12T10:30:00Z","schema_version":"2.0","confidence":"high","payload":{"reason":"phase_complete","team_name":"vbw-phase-01"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
}

@test "validate-message: invalid shutdown_request rejected even when v2_typed_protocol absent" {
  cd "$TEST_TEMP_DIR"
  jq 'del(.v2_typed_protocol)' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  # Missing required payload fields → should be rejected
  MSG='{"id":"shut-invalid","type":"shutdown_request","phase":1,"task":"","author_role":"lead","timestamp":"2026-02-12T10:30:00Z","schema_version":"2.0","confidence":"high","payload":{}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
}

# =============================================================================
# Architect exclusion: shutdown messages rejected for planning-only role
# =============================================================================

@test "validate-message: shutdown_request targeted to architect rejected" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-arch-1","type":"shutdown_request","phase":1,"task":"","author_role":"lead","target_role":"architect","timestamp":"2026-02-12T10:30:00Z","schema_version":"2.0","confidence":"high","payload":{"reason":"phase_complete","team_name":"vbw-phase-01"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
}

@test "validate-message: shutdown_response from architect rejected" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-arch-2","type":"shutdown_response","phase":1,"task":"","author_role":"architect","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","approved":true,"final_status":"idle"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not authorized"* ]]
}

@test "validate-message: shutdown_request from architect as sender rejected" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-arch-3","type":"shutdown_request","phase":1,"task":"","author_role":"architect","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"reason":"phase_complete","team_name":"vbw-phase-01"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not authorized"* ]]
}

@test "architect agent documents shutdown exemption" {
  grep -q '## Shutdown Handling' "$PROJECT_ROOT/agents/vbw-architect.md"
  sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/vbw-architect.md" | grep -qi 'planning-only'
}

# =============================================================================
# Architect ordering: Shutdown Handling between Effort and Circuit Breaker
# =============================================================================

@test "architect shutdown handling section order: after Effort, before Circuit Breaker" {
  local file="$PROJECT_ROOT/agents/vbw-architect.md"
  local effort_line shutdown_line breaker_line
  effort_line=$(grep -n '^## Effort' "$file" | head -1 | cut -d: -f1)
  shutdown_line=$(grep -n '^## Shutdown Handling' "$file" | head -1 | cut -d: -f1)
  breaker_line=$(grep -n '^## Circuit Breaker' "$file" | head -1 | cut -d: -f1)
  [ -n "$effort_line" ] && [ -n "$shutdown_line" ] && [ -n "$breaker_line" ]
  [ "$effort_line" -lt "$shutdown_line" ]
  [ "$shutdown_line" -lt "$breaker_line" ]
}

# =============================================================================
# Rejection path: approved=false is a valid response
# =============================================================================

@test "validate-message: shutdown_response with approved=false passes" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-resp-reject","type":"shutdown_response","phase":1,"task":"","author_role":"dev","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","approved":false,"final_status":"in_progress"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

# =============================================================================
# Optional field: pending_work passes through correctly
# =============================================================================

@test "validate-message: shutdown_response with pending_work passes" {
  cd "$TEST_TEMP_DIR"
  MSG='{"id":"shut-resp-pw","type":"shutdown_response","phase":1,"task":"","author_role":"debugger","timestamp":"2026-02-12T10:30:05Z","schema_version":"2.0","confidence":"high","payload":{"request_id":"shut-001","approved":true,"final_status":"in_progress","pending_work":"Investigating hypothesis 2: race condition in auth module"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.valid == true'
}

# =============================================================================
# Issue #198: Mechanical tool-call instructions in agent Shutdown Handling
# Agents must be told to CALL the SendMessage tool, not just "respond"
# =============================================================================

@test "all agent shutdown handlers require calling SendMessage tool" {
  for agent in dev qa scout lead debugger docs; do
    local section
    section=$(sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/vbw-${agent}.md")
    echo "$section" | grep -qi 'call.*SendMessage tool' || {
      echo "vbw-${agent}.md Shutdown Handling missing 'call the SendMessage tool' instruction"
      return 1
    }
  done
}

@test "all agent shutdown handlers warn plain text is NOT sufficient" {
  for agent in dev qa scout lead debugger docs; do
    local section
    section=$(sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/vbw-${agent}.md")
    echo "$section" | grep -qi 'NOT sufficient' || {
      echo "vbw-${agent}.md Shutdown Handling missing 'NOT sufficient' warning"
      return 1
    }
  done
}

@test "all agent shutdown handlers specify approved (not approve) field" {
  for agent in dev qa scout lead debugger docs; do
    local section
    section=$(sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/vbw-${agent}.md")
    echo "$section" | grep -q '"approved"' || {
      echo "vbw-${agent}.md Shutdown Handling uses wrong field name (should be \"approved\", not \"approve\")"
      return 1
    }
  done
}

@test "all agent shutdown handlers include request_id in template" {
  for agent in dev qa scout lead debugger docs; do
    local section
    section=$(sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/vbw-${agent}.md")
    echo "$section" | grep -q 'request_id' || {
      echo "vbw-${agent}.md Shutdown Handling missing request_id in JSON template"
      return 1
    }
  done
}

@test "all agent shutdown handler templates match schema payload_required fields in JSON block" {
  local schema_file="$CONFIG_DIR/schemas/message-schemas.json"
  local required_fields
  required_fields=$(jq -r '.schemas.shutdown_response.payload_required[]' "$schema_file")
  for agent in dev qa scout lead debugger docs; do
    # Extract only the fenced JSON block from the Shutdown Handling section
    local json_block
    json_block=$(sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/vbw-${agent}.md" | sed -n '/```json$/,/```$/p')
    [ -n "$json_block" ] || {
      echo "vbw-${agent}.md Shutdown Handling missing fenced JSON code block"
      return 1
    }
    for field in $required_fields; do
      echo "$json_block" | grep -q "\"$field\"" || {
        echo "vbw-${agent}.md JSON template missing schema-required field: $field"
        return 1
      }
    done
  done
}

@test "all agent shutdown handlers specify shutdown_response type" {
  for agent in dev qa scout lead debugger docs; do
    local section
    section=$(sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/vbw-${agent}.md")
    echo "$section" | grep -q 'shutdown_response' || {
      echo "vbw-${agent}.md Shutdown Handling missing shutdown_response type"
      return 1
    }
  done
}

@test "handoff-schemas.md includes delivery format note" {
  grep -q 'Delivery format' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff-schemas.md delivery note warns about plain text" {
  local section
  section=$(sed -n '/### Delivery format/,/^## /p' "$PROJECT_ROOT/references/handoff-schemas.md")
  echo "$section" | grep -qi 'NOT satisfy\|NOT sufficient\|not plain text'
}

@test "compaction-instructions.sh injects shutdown protocol reminder for team agents" {
  cd "$TEST_TEMP_DIR"
  for agent in scout dev qa lead debugger docs; do
    echo '{"agent_name":"vbw-'"$agent"'","matcher":"auto"}' | \
      bash "$PROJECT_ROOT/scripts/compaction-instructions.sh" > "$TEST_TEMP_DIR/compaction-output.json"
    local ctx
    ctx=$(jq -r '.hookSpecificOutput.additionalContext' "$TEST_TEMP_DIR/compaction-output.json")
    echo "$ctx" | grep -qi 'SHUTDOWN PROTOCOL' || {
      echo "compaction-instructions.sh missing shutdown reminder for $agent"
      return 1
    }
    echo "$ctx" | grep -qi 'SendMessage tool' || {
      echo "compaction-instructions.sh missing SendMessage tool in shutdown reminder for $agent"
      return 1
    }
    # Verify all schema-required fields appear in the compaction reminder JSON
    for field in approved request_id final_status; do
      echo "$ctx" | grep -q "\"$field\"" || {
        echo "compaction-instructions.sh shutdown reminder missing field: $field for $agent"
        return 1
      }
    done
  done
}

@test "compaction-instructions.sh does NOT inject shutdown reminder for default/unknown agents" {
  cd "$TEST_TEMP_DIR"
  echo '{"agent_name":"unknown-agent","matcher":"auto"}' | \
    bash "$PROJECT_ROOT/scripts/compaction-instructions.sh" > "$TEST_TEMP_DIR/compaction-output.json"
  local ctx
  ctx=$(jq -r '.hookSpecificOutput.additionalContext' "$TEST_TEMP_DIR/compaction-output.json")
  echo "$ctx" | grep -qi 'SHUTDOWN PROTOCOL' && {
    echo "compaction-instructions.sh should NOT inject shutdown reminder for unknown agents"
    return 1
  }
  return 0
}

@test "compaction-instructions.sh does NOT inject shutdown reminder for architect" {
  cd "$TEST_TEMP_DIR"
  echo '{"agent_name":"vbw-architect","matcher":"auto"}' | \
    bash "$PROJECT_ROOT/scripts/compaction-instructions.sh" > "$TEST_TEMP_DIR/compaction-output.json"
  local ctx
  ctx=$(jq -r '.hookSpecificOutput.additionalContext' "$TEST_TEMP_DIR/compaction-output.json")
  echo "$ctx" | grep -qi 'SHUTDOWN PROTOCOL' && {
    echo "compaction-instructions.sh should NOT inject shutdown reminder for architect"
    return 1
  }
  return 0
}

# =============================================================================
# Flat shutdown message normalization (validate-message.sh)
# =============================================================================

@test "validate-message.sh normalizes flat shutdown_request with requestId" {
  cd "$TEST_TEMP_DIR"
  local result
  result=$(echo '{"type":"shutdown_request","requestId":"abc-123","reason":"phase_complete","team_name":"vbw-phase-01","from":"lead"}' \
    | bash "$SCRIPTS_DIR/validate-message.sh")
  echo "$result" | jq -e '.valid == true'
}

@test "validate-message.sh normalizes flat shutdown_request with id" {
  cd "$TEST_TEMP_DIR"
  local result
  result=$(echo '{"type":"shutdown_request","id":"abc-456","reason":"phase_complete","team_name":"vbw-phase-01","from":"lead"}' \
    | bash "$SCRIPTS_DIR/validate-message.sh")
  echo "$result" | jq -e '.valid == true'
}

@test "validate-message.sh normalizes flat shutdown_response with id" {
  cd "$TEST_TEMP_DIR"
  local result
  result=$(echo '{"type":"shutdown_response","id":"rsp-1","request_id":"abc-123","approved":true,"final_status":"complete","from":"dev"}' \
    | bash "$SCRIPTS_DIR/validate-message.sh")
  echo "$result" | jq -e '.valid == true'
}

@test "validate-message.sh still accepts full V2 envelope shutdown_request" {
  cd "$TEST_TEMP_DIR"
  local result
  result=$(echo '{"id":"v2-1","type":"shutdown_request","phase":1,"task":"0-0","author_role":"lead","timestamp":"2026-03-10T00:00:00Z","schema_version":"2.0","payload":{"reason":"phase_complete","team_name":"vbw-phase-01"},"confidence":1.0}' \
    | bash "$SCRIPTS_DIR/validate-message.sh")
  echo "$result" | jq -e '.valid == true'
}

@test "validate-message.sh rejects flat shutdown_request missing required payload fields" {
  cd "$TEST_TEMP_DIR"
  local result
  result=$(echo '{"type":"shutdown_request","requestId":"abc-123","from":"lead"}' \
    | bash "$SCRIPTS_DIR/validate-message.sh") || true
  echo "$result" | jq -e '.valid == false'
  echo "$result" | jq -e '.errors | length > 0'
}

@test "validate-message.sh normalizes requestId into envelope id field" {
  cd "$TEST_TEMP_DIR"
  # Run normalization jq directly to verify field-level mapping
  local input='{"type":"shutdown_request","requestId":"req-id-001","reason":"phase_complete","team_name":"vbw-phase-01","from":"lead"}'
  local fid
  fid=$(echo "$input" | jq -r '.requestId // .id // ""')
  local fauthor
  fauthor=$(echo "$input" | jq -r '.from // .author_role // "unknown"')
  local normalized
  normalized=$(echo "$input" | jq --arg fid "$fid" --arg fauthor "$fauthor" '
    {
      id: ($fid | if . == "" then "normalized-\(now | floor | tostring)" else . end),
      type: .type,
      author_role: $fauthor
    }
  ')
  # Verify requestId mapped to envelope id
  echo "$normalized" | jq -e '.id == "req-id-001"'
  # Verify from mapped to author_role
  echo "$normalized" | jq -e '.author_role == "lead"'
  # Also verify full validation passes
  local result
  result=$(echo "$input" | bash "$SCRIPTS_DIR/validate-message.sh")
  echo "$result" | jq -e '.valid == true'
}

@test "validate-message.sh requestId takes precedence over id when both present" {
  cd "$TEST_TEMP_DIR"
  local input='{"type":"shutdown_request","requestId":"req-wins","id":"id-loses","reason":"phase_complete","team_name":"vbw-phase-01","from":"lead"}'
  local fid
  fid=$(echo "$input" | jq -r '.requestId // .id // ""')
  [ "$fid" = "req-wins" ]
  # Verify full validation also passes
  local result
  result=$(echo "$input" | bash "$SCRIPTS_DIR/validate-message.sh")
  echo "$result" | jq -e '.valid == true'
}

@test "validate-message.sh rejects flat message with empty string type" {
  cd "$TEST_TEMP_DIR"
  local result
  result=$(echo '{"type":"","requestId":"abc-123","reason":"phase_complete","team_name":"vbw-phase-01","from":"lead"}' \
    | bash "$SCRIPTS_DIR/validate-message.sh") || true
  echo "$result" | jq -e '.valid == false'
}

@test "validate-message.sh normalization does not leak confidence into payload" {
  cd "$TEST_TEMP_DIR"
  local input='{"type":"shutdown_request","requestId":"c-test","reason":"phase_complete","team_name":"vbw-phase-01","from":"lead","confidence":0.5}'
  local fid
  fid=$(echo "$input" | jq -r '.requestId // .id // ""')
  local fauthor
  fauthor=$(echo "$input" | jq -r '.from // .author_role // "unknown"')
  local normalized
  normalized=$(echo "$input" | jq --arg fid "$fid" --arg fauthor "$fauthor" '
    {
      id: ($fid | if . == "" then "normalized-\(now | floor | tostring)" else . end),
      type: .type,
      phase: (.phase // 0),
      task: (.task // "0-0"),
      author_role: $fauthor,
      target_role: (.target_role // null),
      timestamp: (.timestamp // (now | tostring)),
      schema_version: (.schema_version // "2.0"),
      payload: (del(.type, .id, .requestId, .from, .phase, .task,
                    .author_role, .target_role, .timestamp, .schema_version, .confidence)),
      confidence: (.confidence // 1.0)
    }
  ')
  # confidence should be at envelope level
  echo "$normalized" | jq -e '.confidence == 0.5'
  # confidence should NOT be inside payload
  echo "$normalized" | jq -e '(.payload | has("confidence")) | not'
}

# =============================================================================
# Prompt-equivalence: compaction reminder must match agent final_status semantics
# =============================================================================

@test "compaction reminder includes all final_status values from agent prompts" {
  cd "$TEST_TEMP_DIR"
  # Verify ALL 6 team agents have the canonical final_status trio
  for agent in dev lead qa scout debugger docs; do
    local agent_statuses
    agent_statuses=$(grep -o '"complete".*"idle".*"in_progress"' "$PROJECT_ROOT/agents/vbw-${agent}.md" || true)
    [ -n "$agent_statuses" ] || {
      echo "FAIL: vbw-${agent}.md missing final_status values"
      return 1
    }
  done

  # Verify compaction reminder includes the same three values
  local compaction_output
  compaction_output=$(echo '{"agent_name":"vbw-dev","matcher":"auto"}' \
    | bash "$SCRIPTS_DIR/compaction-instructions.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || true)
  echo "$compaction_output" | grep -q 'complete|idle|in_progress'
}

@test "shutdown recovery guidance present in all team-producing commands" {
  # All commands that create teams must mention plain text retry, doctor cleanup,
  # and zero-teammate verification
  for cmd in vibe.md debug.md map.md; do
    local content
    content=$(cat "$PROJECT_ROOT/commands/$cmd")
    echo "$content" | grep -q 'plain text' || {
      echo "FAIL: $cmd missing plain text retry guidance"
      return 1
    }
    echo "$content" | grep -q 'doctor' || {
      echo "FAIL: $cmd missing /vbw:doctor cleanup reference"
      return 1
    }
    echo "$content" | grep -qi 'zero active teammates\|ZERO active teammates' || {
      echo "FAIL: $cmd missing zero-teammate verification"
      return 1
    }
  done
}

@test "handoff-schemas.md backward compat describes graduated flag accurately" {
  local schemas_content
  schemas_content=$(cat "$PROJECT_ROOT/references/handoff-schemas.md")
  # Must mention "graduated" (the flag is always-on)
  echo "$schemas_content" | grep -q 'graduated'
  # Must NOT claim short-circuit/fail-open behavior
  ! echo "$schemas_content" | grep -q 'short-circuits to valid'
}
