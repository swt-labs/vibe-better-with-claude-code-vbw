#!/usr/bin/env bats
# Tests for MuninnDB native integration — verifies MuninnDB is
# unconditionally integrated as the memory system across all components.

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  # Create minimal phase directory structure for compile-context tests
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase"
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 1: Test Phase
**Goal:** Test goal
**Success:** Tests pass
**Reqs:** REQ-01
EOF
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test-phase/01-01-PLAN.md" <<'EOF'
---
phase: 1
plan: 1
title: "Test Plan"
wave: 1
depends_on: []
must_haves: ["test"]
---
# Test Plan
## Tasks
### Task 1: Test
- **Files:** test.sh
- **Action:** Test
EOF
}

teardown() {
  teardown_temp_dir
}

# ============================================================
# MuninnDB config
# ============================================================

@test "defaults.json has muninndb_vault field" {
  run jq -e 'has("muninndb_vault")' "$CONFIG_DIR/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "test config includes muninndb_vault" {
  run jq -r '.muninndb_vault' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "test-vault" ]
}

# ============================================================
# compile-context.sh — emit_muninn_memory_hint
# ============================================================

@test "compile-context.sh defines emit_muninn_memory_hint function" {
  grep -q "emit_muninn_memory_hint()" "$SCRIPTS_DIR/compile-context.sh"
}

@test "compile-context.sh emits MuninnDB hint for lead role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-lead.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-lead.md"
}

@test "compile-context.sh emits MuninnDB hint for dev role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-dev.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-dev.md"
}

@test "compile-context.sh emits MuninnDB hint for qa role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 qa ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-qa.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-qa.md"
}

@test "compile-context.sh emits MuninnDB hint for scout role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 scout ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-scout.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-scout.md"
}

@test "compile-context.sh emits MuninnDB hint for debugger role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 debugger ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-debugger.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-debugger.md"
}

@test "compile-context.sh emits MuninnDB hint for architect role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 architect ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-architect.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-architect.md"
}

# ============================================================
# bootstrap-state.sh — Memory section
# ============================================================

@test "bootstrap-state.sh generates Memory section with vault" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    "$TEST_TEMP_DIR/STATE.md" "Test Project" "v1.0" 3 "my-vault"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/STATE.md" ]
  grep -q "## Memory" "$TEST_TEMP_DIR/STATE.md"
  grep -q "Vault.*my-vault" "$TEST_TEMP_DIR/STATE.md"
}

@test "bootstrap-state.sh generates Memory section without vault" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    "$TEST_TEMP_DIR/STATE.md" "Test Project" "v1.0" 3
  [ "$status" -eq 0 ]
  grep -q "## Memory" "$TEST_TEMP_DIR/STATE.md"
  grep -q "pending setup" "$TEST_TEMP_DIR/STATE.md"
}

@test "bootstrap-state.sh preserves existing Memory section on re-bootstrap" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/STATE.md" <<'EOF'
# State

## Memory
**Vault:** existing-vault
**Custom note:** preserved
EOF

  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-state.sh" \
    "$TEST_TEMP_DIR/STATE.md" "Test Project" "v2.0" 5 "new-vault"
  [ "$status" -eq 0 ]
  grep -q "existing-vault" "$TEST_TEMP_DIR/STATE.md"
  grep -q "Custom note.*preserved" "$TEST_TEMP_DIR/STATE.md"
}

# ============================================================
# persist-state-after-ship.sh — Memory persistence
# ============================================================

@test "persist-state-after-ship.sh preserves Memory section" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/default
  cat > .vbw-planning/milestones/default/STATE.md <<'EOF'
# State

**Project:** Test Project

## Current Phase
Phase: 2 of 2

## Decisions
- Use MuninnDB for memory

## Todos
None.

## Blockers
None

## Memory
**Vault:** test-vault
EOF

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Test Project"
  [ "$status" -eq 0 ]
  grep -q "## Memory" .vbw-planning/STATE.md
  grep -q "Vault.*test-vault" .vbw-planning/STATE.md
}

# ============================================================
# Agent files — unconditional MuninnDB instructions
# ============================================================

@test "all agents reference MuninnDB tools" {
  for agent in vbw-lead vbw-dev vbw-qa vbw-scout vbw-debugger vbw-architect vbw-docs; do
    local agent_file="$PROJECT_ROOT/agents/${agent}.md"
    [ -f "$agent_file" ] || { echo "MISSING: $agent_file"; return 1; }
    grep -q "muninn" "$agent_file" || { echo "NO muninn ref: $agent"; return 1; }
  done
}

@test "all agents reference muninn_guide" {
  for agent in vbw-lead vbw-dev vbw-qa vbw-scout vbw-debugger vbw-architect vbw-docs; do
    local agent_file="$PROJECT_ROOT/agents/${agent}.md"
    [ -f "$agent_file" ] || { echo "MISSING: $agent_file"; return 1; }
    grep -q "muninn_guide" "$agent_file" || { echo "NO muninn_guide: $agent"; return 1; }
  done
}

@test "compile-context.sh hint includes muninn_guide" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "muninn_guide" ".vbw-planning/phases/01-test-phase/.context-lead.md"
}

@test "init.md references muninn_guide after vault creation" {
  grep -q "muninn_guide" "$PROJECT_ROOT/commands/init.md"
}

# ============================================================
# Cache context — ROLLING-CONTEXT.md is not part of fingerprint
# ============================================================

@test "cache-context.sh hash ignores ROLLING-CONTEXT.md file" {
  cd "$TEST_TEMP_DIR"
  echo "# Old rolling context" > "$TEST_TEMP_DIR/.vbw-planning/ROLLING-CONTEXT.md"

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 dev \
    ".vbw-planning/config.json" \
    ".vbw-planning/phases/01-test-phase/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH1=$(echo "$output" | cut -d' ' -f2)

  rm "$TEST_TEMP_DIR/.vbw-planning/ROLLING-CONTEXT.md"

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 dev \
    ".vbw-planning/config.json" \
    ".vbw-planning/phases/01-test-phase/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" = "$HASH2" ]
}

# ============================================================
# Phase-aware memory hint
# ============================================================

@test "compile-context.sh emits phase-aware warning for phase > 1" {
  cd "$TEST_TEMP_DIR"
  # Create phase 02 directory
  mkdir -p ".vbw-planning/phases/02-second-phase"
  # Update ROADMAP for phase 2
  cat >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
## Phase 2: Second Phase
**Goal:** Second goal
**Success:** Tests pass
**Reqs:** REQ-02
EOF

  run bash "$SCRIPTS_DIR/compile-context.sh" 02 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Phase 02: if recall returns 0 results, report a warning" ".vbw-planning/phases/02-second-phase/.context-lead.md"
}

@test "compile-context.sh omits warning for phase 1" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  ! grep -q "if recall returns 0 results, report a warning" ".vbw-planning/phases/01-test-phase/.context-lead.md"
}

@test "SUMMARY.md template has memory_recalled field" {
  grep -q "memory_recalled" "$PROJECT_ROOT/templates/SUMMARY.md"
}

# ============================================================
# P0 guardrails
# ============================================================

@test "debugger agent stores findings after fixing" {
  grep -q "muninn_remember" "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "compaction instructions include muninn_guide for all roles" {
  for role in scout dev qa lead architect debugger docs; do
    grep -q "muninn_guide" "$SCRIPTS_DIR/compaction-instructions.sh" || {
      echo "muninn_guide missing from compaction-instructions.sh"; return 1
    }
  done
}

@test "post-compact.sh includes muninn_guide" {
  grep -q "muninn_guide" "$SCRIPTS_DIR/post-compact.sh"
}

@test "all agents handle empty vault name" {
  for agent in vbw-dev vbw-lead vbw-scout vbw-debugger vbw-architect vbw-docs vbw-qa; do
    local agent_file="$PROJECT_ROOT/agents/${agent}.md"
    grep -q "vault not configured" "$agent_file" || {
      echo "NO empty vault guard: $agent"; return 1
    }
  done
}

@test "compile-context.sh warns when vault is empty" {
  cd "$TEST_TEMP_DIR"
  # Override config with empty vault
  jq '.muninndb_vault = ""' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp" \
    && mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "vault not configured" ".vbw-planning/phases/01-test-phase/.context-lead.md"
}

# ============================================================
# Hook: muninn-vault-gate.sh (SubagentStart)
# ============================================================

@test "muninn-vault-gate.sh passes when vault is configured" {
  cd "$TEST_TEMP_DIR"
  run bash -c 'echo "{\"agent_type\":\"vbw-lead\"}" | bash "'"$SCRIPTS_DIR"'/muninn-vault-gate.sh"'
  [ "$status" -eq 0 ]
}

@test "muninn-vault-gate.sh blocks lead when vault is empty" {
  cd "$TEST_TEMP_DIR"
  jq '.muninndb_vault = ""' .vbw-planning/config.json > .vbw-planning/config.tmp \
    && mv .vbw-planning/config.tmp .vbw-planning/config.json
  run bash -c 'echo "{\"agent_type\":\"vbw-lead\"}" | bash "'"$SCRIPTS_DIR"'/muninn-vault-gate.sh"'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "vault not configured"
}

@test "muninn-vault-gate.sh blocks architect when vault is empty" {
  cd "$TEST_TEMP_DIR"
  jq '.muninndb_vault = ""' .vbw-planning/config.json > .vbw-planning/config.tmp \
    && mv .vbw-planning/config.tmp .vbw-planning/config.json
  run bash -c 'echo "{\"agent_type\":\"vbw-architect\"}" | bash "'"$SCRIPTS_DIR"'/muninn-vault-gate.sh"'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "vault not configured"
}

@test "muninn-vault-gate.sh advisory for dev when vault is empty" {
  cd "$TEST_TEMP_DIR"
  jq '.muninndb_vault = ""' .vbw-planning/config.json > .vbw-planning/config.tmp \
    && mv .vbw-planning/config.tmp .vbw-planning/config.json
  run bash -c 'echo "{\"agent_type\":\"vbw-dev\"}" | bash "'"$SCRIPTS_DIR"'/muninn-vault-gate.sh"'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "vault not configured"
}

@test "muninn-vault-gate.sh registered in hooks.json" {
  grep -q "muninn-vault-gate.sh" "$PROJECT_ROOT/hooks/hooks.json"
}

# ============================================================
# Hook: validate-summary.sh — memory_recalled check
# ============================================================

@test "validate-summary.sh warns when memory_recalled is missing" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/phases/01-test-phase
  cat > .vbw-planning/phases/01-test-phase/SUMMARY.md <<'EOF'
---
phase: 1
plan: 1
title: "Test Plan"
status: complete
---
## What Was Built
Test

## Files Modified
- test.sh
EOF
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"'"$TEST_TEMP_DIR"'/.vbw-planning/phases/01-test-phase/SUMMARY.md\"}}" | bash "'"$SCRIPTS_DIR"'/validate-summary.sh"'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "memory_recalled"
}

@test "validate-summary.sh passes when memory_recalled is present" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/phases/01-test-phase
  cat > .vbw-planning/phases/01-test-phase/SUMMARY.md <<'EOF'
---
phase: 1
plan: 1
title: "Test Plan"
status: complete
memory_recalled:
  - "none"
---
## What Was Built
Test

## Files Modified
- test.sh
EOF
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"'"$TEST_TEMP_DIR"'/.vbw-planning/phases/01-test-phase/SUMMARY.md\"}}" | bash "'"$SCRIPTS_DIR"'/validate-summary.sh"'
  [ "$status" -eq 0 ]
  # Should not contain memory_recalled warning
  ! echo "$output" | grep -q "memory_recalled"
}

# ============================================================
# P1-3: QA stores verification findings
# ============================================================

@test "QA agent references muninn_remember for storing findings" {
  grep -q "muninn_remember" "$PROJECT_ROOT/agents/vbw-qa.md"
}

# ============================================================
# P1-4: docs role in compile-context.sh
# ============================================================

@test "compile-context.sh emits MuninnDB hint for docs role" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 docs ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Cross-Phase Memory" ".vbw-planning/phases/01-test-phase/.context-docs.md"
  grep -q "muninn_activate" ".vbw-planning/phases/01-test-phase/.context-docs.md"
}

# ============================================================
# P1-7: Engram type documentation
# ============================================================

@test "muninn-types.md documents all agent engram types" {
  [ -f "$PROJECT_ROOT/references/muninn-types.md" ]
  grep -q "Issue" "$PROJECT_ROOT/references/muninn-types.md"
  grep -q "Observation" "$PROJECT_ROOT/references/muninn-types.md"
  grep -q "Decision" "$PROJECT_ROOT/references/muninn-types.md"
  grep -q "Task" "$PROJECT_ROOT/references/muninn-types.md"
}

# ============================================================
# P1-2: Phase-end consolidation scoping
# ============================================================

@test "execute-protocol phase-end consolidation collects engram IDs" {
  grep -q "muninn_activate" "$PROJECT_ROOT/references/execute-protocol.md"
  grep -q "engram_ids" "$PROJECT_ROOT/references/execute-protocol.md"
  grep -q "score > 0.3" "$PROJECT_ROOT/references/execute-protocol.md"
}

# ============================================================
# P1-5: MuninnDB in discuss mode
# ============================================================

@test "discussion-engine recalls prior decisions via MuninnDB" {
  grep -q "muninn_activate" "$PROJECT_ROOT/references/discussion-engine.md"
  grep -q "muninn_guide" "$PROJECT_ROOT/references/discussion-engine.md"
}

@test "discussion-engine stores decisions via muninn_decide" {
  grep -q "muninn_decide" "$PROJECT_ROOT/references/discussion-engine.md"
}

# ============================================================
# P1-6: MuninnDB failure mode tests
# ============================================================

@test "muninn-vault-gate.sh passes when no .vbw-planning dir" {
  cd /tmp
  run bash -c 'echo "{\"agent_type\":\"vbw-lead\"}" | bash "'"$SCRIPTS_DIR"'/muninn-vault-gate.sh"'
  [ "$status" -eq 0 ]
}

@test "muninn-vault-gate.sh passes when config.json missing" {
  cd "$TEST_TEMP_DIR"
  rm -f .vbw-planning/config.json
  run bash -c 'echo "{\"agent_type\":\"vbw-lead\"}" | bash "'"$SCRIPTS_DIR"'/muninn-vault-gate.sh"'
  # No config = no vault check, pass through
  [ "$status" -eq 0 ]
}

@test "muninn-vault-gate.sh handles missing muninndb_vault key" {
  cd "$TEST_TEMP_DIR"
  echo '{"effort":"balanced"}' > .vbw-planning/config.json
  run bash -c 'echo "{\"agent_type\":\"vbw-lead\"}" | bash "'"$SCRIPTS_DIR"'/muninn-vault-gate.sh"'
  # Missing key = empty vault = block lead
  [ "$status" -eq 2 ]
}

@test "compile-context.sh succeeds with empty vault in config" {
  cd "$TEST_TEMP_DIR"
  jq '.muninndb_vault = ""' .vbw-planning/config.json > .vbw-planning/config.tmp \
    && mv .vbw-planning/config.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Should still produce a context file with vault warning
  [ -f ".vbw-planning/phases/01-test-phase/.context-dev.md" ]
  grep -q "vault not configured" ".vbw-planning/phases/01-test-phase/.context-dev.md"
}

@test "compile-context.sh succeeds with missing config.json" {
  cd "$TEST_TEMP_DIR"
  rm -f .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 dev ".vbw-planning/phases"
  # compile-context.sh should still work without config (vault=empty)
  [ "$status" -eq 0 ]
  [ -f ".vbw-planning/phases/01-test-phase/.context-dev.md" ]
}

@test "validate-summary.sh ignores non-SUMMARY files" {
  cd "$TEST_TEMP_DIR"
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"some/random/file.md\"}}" | bash "'"$SCRIPTS_DIR"'/validate-summary.sh"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate-summary.sh handles nonexistent SUMMARY.md gracefully" {
  cd "$TEST_TEMP_DIR"
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"'"$TEST_TEMP_DIR"'/.vbw-planning/phases/01-test-phase/SUMMARY.md\"}}" | bash "'"$SCRIPTS_DIR"'/validate-summary.sh"'
  [ "$status" -eq 0 ]
}

@test "all agents specify failure behavior for MuninnDB" {
  for agent in vbw-dev vbw-lead vbw-scout vbw-debugger vbw-architect vbw-docs vbw-qa; do
    local agent_file="$PROJECT_ROOT/agents/${agent}.md"
    grep -qE "(STOP|blocker_report|warn|Report)" "$agent_file" || {
      echo "NO failure behavior: $agent"; return 1
    }
  done
}

@test "session-start.sh checks MuninnDB health" {
  grep -q "muninn_port" "$SCRIPTS_DIR/session-start.sh"
  grep -q "MuninnDB" "$SCRIPTS_DIR/session-start.sh"
}

# ============================================================
# P1-1: Centralised MuninnDB configuration
# ============================================================

@test "defaults.json has muninndb port config keys" {
  run jq -e 'has("muninndb_port_mcp") and has("muninndb_port_rest")' "$CONFIG_DIR/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "muninn-setup.sh reads port from config" {
  grep -q "_MUNINN_MCP_PORT" "$SCRIPTS_DIR/muninn-setup.sh"
  grep -q "_MUNINN_REST_PORT" "$SCRIPTS_DIR/muninn-setup.sh"
}

@test "session-start.sh reads port from config" {
  grep -q "muninndb_port_mcp" "$SCRIPTS_DIR/session-start.sh"
}

@test "muninn reference doc lists all config parameters" {
  grep -q "MCP port" "$PROJECT_ROOT/references/muninn-types.md"
  grep -q "REST port" "$PROJECT_ROOT/references/muninn-types.md"
  grep -q "Recall limit" "$PROJECT_ROOT/references/muninn-types.md"
  grep -q "Score threshold" "$PROJECT_ROOT/references/muninn-types.md"
}

# ============================================================
# P2-1: Contradiction checking for Lead and Architect
# ============================================================

@test "lead agent calls muninn_contradictions pre-planning" {
  grep -q "muninn_contradictions" "$PROJECT_ROOT/agents/vbw-lead.md"
}

@test "architect agent calls muninn_contradictions pre-scoping" {
  grep -q "muninn_contradictions" "$PROJECT_ROOT/agents/vbw-architect.md"
}

# ============================================================
# P2-7: Role-specific compile-context hints
# ============================================================

@test "compile-context.sh emits role-specific hint for qa" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 qa ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "muninn_contradictions" ".vbw-planning/phases/01-test-phase/.context-qa.md"
}

@test "compile-context.sh emits role-specific hint for debugger" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 debugger ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "bug description" ".vbw-planning/phases/01-test-phase/.context-debugger.md"
}

@test "compile-context.sh emits role-specific hint for lead" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 01 lead ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "muninn_contradictions" ".vbw-planning/phases/01-test-phase/.context-lead.md"
}

# ============================================================
# P2-8: Inline orchestrator compaction fallback
# ============================================================

@test "compaction wildcard includes muninn recovery" {
  grep -q "muninn_guide" "$SCRIPTS_DIR/compaction-instructions.sh"
  # Check the wildcard case specifically includes muninn
  grep -A1 '^\s*\*)' "$SCRIPTS_DIR/compaction-instructions.sh" | grep -q "muninn"
}

# ============================================================
# P2-9: Phase-level outcome engrams
# ============================================================

@test "execute-protocol stores phase outcome engram before consolidation" {
  grep -q "Phase.*outcome" "$PROJECT_ROOT/references/execute-protocol.md"
  grep -q "muninn_remember.*outcome" "$PROJECT_ROOT/references/execute-protocol.md"
}

# ============================================================
# P2-5: Scout post-research consolidation
# ============================================================

@test "lead agent consolidates scout engrams after research" {
  grep -q "Scout engram consolidation" "$PROJECT_ROOT/agents/vbw-lead.md"
  grep -q "muninn_consolidate" "$PROJECT_ROOT/agents/vbw-lead.md"
}

# ============================================================
# P2-10: MuninnDB in /vbw:verify
# ============================================================

@test "verify command includes MuninnDB recall step" {
  grep -q "muninn_activate" "$PROJECT_ROOT/commands/verify.md"
  grep -q "muninn_guide" "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command stores UAT issues in MuninnDB" {
  grep -q "muninn_remember.*UAT" "$PROJECT_ROOT/commands/verify.md"
}

# ============================================================
# P2-4: Engram lifecycle at ship-time
# ============================================================

@test "vibe archive tags engrams as archived" {
  grep -q "archived" "$PROJECT_ROOT/commands/vibe.md"
  grep -q "Engram archival" "$PROJECT_ROOT/commands/vibe.md"
}

# ============================================================
# P2-3: memory_recalled enrichment
# ============================================================

@test "SUMMARY.md template includes score in memory_recalled" {
  grep -q "score:" "$PROJECT_ROOT/templates/SUMMARY.md"
}

@test "lead agent includes memory_recalled in PLAN.md" {
  grep -q "memory_recalled" "$PROJECT_ROOT/agents/vbw-lead.md"
}

@test "QA agent includes memory_recalled in VERIFICATION.md" {
  grep -q "memory_recalled" "$PROJECT_ROOT/agents/vbw-qa.md"
}

# ============================================================
# P2-11: Consolidation call tests
# ============================================================

@test "execute-protocol has phase-end consolidation with muninn_consolidate" {
  grep -q "muninn_consolidate" "$PROJECT_ROOT/references/execute-protocol.md"
}

@test "vibe archive has milestone consolidation with muninn_consolidate" {
  grep -q "muninn_consolidate" "$PROJECT_ROOT/commands/vibe.md"
}

@test "lead agent has scout consolidation with muninn_consolidate" {
  grep -q "muninn_consolidate" "$PROJECT_ROOT/agents/vbw-lead.md"
}

# ============================================================
# P2-12: Session-start health check tests
# ============================================================

@test "session-start.sh checks both MCP and REST ports" {
  grep -q "muninndb_port_mcp" "$SCRIPTS_DIR/session-start.sh"
  grep -q "muninndb_port_rest" "$SCRIPTS_DIR/session-start.sh"
}

@test "session-start.sh uses max-time 1 for health checks" {
  grep -q "max-time 1" "$SCRIPTS_DIR/session-start.sh"
}

@test "session-start.sh verifies vault existence on server" {
  grep -q "vault.*not found" "$SCRIPTS_DIR/session-start.sh"
}

# ============================================================
# P2-13: Doctor check 16 tests
# ============================================================

@test "doctor.md check 16 reads ports from config" {
  grep -q "muninndb_port_mcp" "$PROJECT_ROOT/commands/doctor.md"
  grep -q "muninndb_port_rest" "$PROJECT_ROOT/commands/doctor.md"
}

@test "doctor.md check 16 checks both MCP and REST" {
  grep -q "MCP" "$PROJECT_ROOT/commands/doctor.md"
  grep -q "REST" "$PROJECT_ROOT/commands/doctor.md"
}

# ============================================================
# P2-2: Memory observability metrics
# ============================================================

@test "collect-metrics.sh documents MuninnDB events" {
  grep -q "muninn_recall" "$SCRIPTS_DIR/collect-metrics.sh"
  grep -q "muninn_store" "$SCRIPTS_DIR/collect-metrics.sh"
  grep -q "muninn_unavailable" "$SCRIPTS_DIR/collect-metrics.sh"
}

# ============================================================
# P2-17: Vault isolation
# ============================================================

@test "muninn-setup.sh derives vault names with multi-project isolation" {
  grep -q "Multi-project isolation" "$SCRIPTS_DIR/muninn-setup.sh"
}

# ============================================================
# P2-14: Session-start latency
# ============================================================

@test "session-start.sh health check uses max-time 1 not 2" {
  # Ensure no --max-time 2 remains in the MuninnDB health section
  ! grep -A20 "MuninnDB health check" "$SCRIPTS_DIR/session-start.sh" | grep -q "max-time 2"
}

# ============================================================
# P2-15: README MuninnDB section
# ============================================================

@test "README.md has MuninnDB section" {
  grep -q "## MuninnDB" "$PROJECT_ROOT/README.md"
}

# ============================================================
# P2-16: Troubleshooting guide
# ============================================================

@test "MuninnDB troubleshooting guide exists" {
  [ -f "$PROJECT_ROOT/docs/muninndb-troubleshooting.md" ]
}
