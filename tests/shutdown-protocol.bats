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
  # Enable V2 typed protocol
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
# Finding 6: v2_typed_protocol=false fallback for shutdown messages
# =============================================================================

@test "validate-message: shutdown_request passes when v2_typed_protocol=false" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_typed_protocol = false' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  MSG='{"id":"shut-fallback","type":"shutdown_request","phase":1,"task":"","author_role":"lead","timestamp":"2026-02-12T10:30:00Z","schema_version":"2.0","confidence":"high","payload":{"reason":"phase_complete","team_name":"vbw-phase-01"}}'
  run bash "$SCRIPTS_DIR/validate-message.sh" "$MSG"
  [ "$status" -eq 0 ]
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

@test "all agent shutdown handlers specify approve: true" {
  for agent in dev qa scout lead debugger docs; do
    local section
    section=$(sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/vbw-${agent}.md")
    echo "$section" | grep -q 'approve.*true' || {
      echo "vbw-${agent}.md Shutdown Handling missing approve: true instruction"
      return 1
    }
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
