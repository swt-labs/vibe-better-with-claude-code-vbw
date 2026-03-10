#!/usr/bin/env bats

# Tests for codebase mapping awareness across agents
# Original: issue #75 (debugger), expanded: #78 (dev), #79 (qa), #80 (lead), #81 (architect)

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# =============================================================================
# Agent definition: debugger references codebase mapping
# =============================================================================

@test "debugger agent references codebase mapping in investigation protocol" {
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent checks META.md for mapping existence" {
  grep -q 'META.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent references ARCHITECTURE.md" {
  grep -q 'ARCHITECTURE.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent references CONCERNS.md" {
  grep -q 'CONCERNS.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent references PATTERNS.md" {
  grep -q 'PATTERNS.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent references DEPENDENCIES.md" {
  grep -q 'DEPENDENCIES.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

# =============================================================================
# Agent definition: dev references codebase mapping
# =============================================================================

@test "dev agent references codebase mapping in execution protocol" {
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/agents/vbw-dev.md"
}

@test "dev agent references CONVENTIONS.md" {
  grep -q 'CONVENTIONS.md' "$PROJECT_ROOT/agents/vbw-dev.md"
}

@test "dev agent references PATTERNS.md" {
  grep -q 'PATTERNS.md' "$PROJECT_ROOT/agents/vbw-dev.md"
}

@test "dev agent references STRUCTURE.md" {
  grep -q 'STRUCTURE.md' "$PROJECT_ROOT/agents/vbw-dev.md"
}

@test "dev agent references DEPENDENCIES.md" {
  grep -q 'DEPENDENCIES.md' "$PROJECT_ROOT/agents/vbw-dev.md"
}

# =============================================================================
# Agent definition: qa references codebase mapping
# =============================================================================

@test "qa agent references codebase mapping in verification protocol" {
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/agents/vbw-qa.md"
}

@test "qa agent references TESTING.md" {
  grep -q 'TESTING.md' "$PROJECT_ROOT/agents/vbw-qa.md"
}

@test "qa agent references CONCERNS.md" {
  grep -q 'CONCERNS.md' "$PROJECT_ROOT/agents/vbw-qa.md"
}

@test "qa agent references ARCHITECTURE.md" {
  grep -q 'ARCHITECTURE.md' "$PROJECT_ROOT/agents/vbw-qa.md"
}

# =============================================================================
# Agent definition: lead references codebase mapping
# =============================================================================

@test "lead agent references codebase mapping in research stage" {
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/agents/vbw-lead.md"
}

@test "lead agent references ARCHITECTURE.md" {
  grep -q 'ARCHITECTURE.md' "$PROJECT_ROOT/agents/vbw-lead.md"
}

@test "lead agent references CONCERNS.md" {
  grep -q 'CONCERNS.md' "$PROJECT_ROOT/agents/vbw-lead.md"
}

@test "lead agent references STRUCTURE.md" {
  grep -q 'STRUCTURE.md' "$PROJECT_ROOT/agents/vbw-lead.md"
}

# =============================================================================
# Agent definition: architect references codebase mapping
# =============================================================================

@test "architect agent references codebase mapping in core protocol" {
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/agents/vbw-architect.md"
}

@test "architect agent references ARCHITECTURE.md" {
  grep -q 'ARCHITECTURE.md' "$PROJECT_ROOT/agents/vbw-architect.md"
}

@test "architect agent references STACK.md" {
  grep -q 'STACK.md' "$PROJECT_ROOT/agents/vbw-architect.md"
}

# =============================================================================
# Compiled context: codebase mapping hint in debugger context
# =============================================================================

# Helper: set up minimal .vbw-planning structure for compile-context.sh
setup_debugger_context() {
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  create_test_config

  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'ROADMAP'
## Phases

## Phase 1: Debug Phase
**Goal:** Fix the broken widget
**Reqs:** REQ-01
**Success:** Widget renders correctly

---

## Phase 2: Future Phase
**Goal:** Placeholder
**Reqs:** REQ-02
**Success:** Placeholder
ROADMAP

  cat > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md" <<'REQS'
## Requirements
- [REQ-01] Widget must render correctly
REQS

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'STATE'
## Status
Phase: 1 of 1 (Debug Phase)
Status: executing
Progress: 0%

## Activity
- Bug reported in widget rendering

## Decisions
- None
STATE
}

@test "compile-context.sh debugger context includes codebase mapping hint when mapping exists" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # Create codebase mapping files
  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture overview" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Known concerns" > .vbw-planning/codebase/CONCERNS.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Codebase Map" ".vbw-planning/phases/01-test/.context-debugger.md"
}

@test "compile-context.sh debugger context lists available mapping files" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md
  echo "# Patterns" > .vbw-planning/codebase/PATTERNS.md
  echo "# Dependencies" > .vbw-planning/codebase/DEPENDENCIES.md
  echo "# Structure" > .vbw-planning/codebase/STRUCTURE.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "ARCHITECTURE.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "CONCERNS.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "PATTERNS.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "DEPENDENCIES.md" ".vbw-planning/phases/01-test/.context-debugger.md"
}

@test "compile-context.sh debugger context omits codebase mapping when no mapping exists" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # No codebase directory created
  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Should NOT contain codebase mapping section
  run grep "Codebase Map" ".vbw-planning/phases/01-test/.context-debugger.md"
  [ "$status" -eq 1 ]
}

@test "compile-context.sh debugger context omits codebase mapping when META.md missing" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # Create directory but no META.md (incomplete mapping)
  mkdir -p .vbw-planning/codebase
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Should NOT contain codebase mapping section without META.md
  run grep "Codebase Map" ".vbw-planning/phases/01-test/.context-debugger.md"
  [ "$status" -eq 1 ]
}

# =============================================================================
# QA finding: guidance text adapts to available files
# =============================================================================

@test "compile-context.sh debugger guidance mentions only files that exist" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # Only META.md + ARCHITECTURE.md (no CONCERNS, PATTERNS, DEPENDENCIES)
  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Should mention ARCHITECTURE.md in guidance
  grep -q "Read ARCHITECTURE.md first" ".vbw-planning/phases/01-test/.context-debugger.md"
  # Should NOT mention CONCERNS.md in guidance
  run grep "CONCERNS.md first" ".vbw-planning/phases/01-test/.context-debugger.md"
  [ "$status" -eq 1 ]
}

@test "compile-context.sh debugger guidance mentions all four when all exist" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md
  echo "# Patterns" > .vbw-planning/codebase/PATTERNS.md
  echo "# Dependencies" > .vbw-planning/codebase/DEPENDENCIES.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "ARCHITECTURE.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "CONCERNS.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "PATTERNS.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "DEPENDENCIES.md" ".vbw-planning/phases/01-test/.context-debugger.md"
}

# =============================================================================
# Compiled context: codebase mapping hint in dev context
# =============================================================================

@test "compile-context.sh dev context includes codebase mapping hint when mapping exists" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Conventions" > .vbw-planning/codebase/CONVENTIONS.md
  echo "# Patterns" > .vbw-planning/codebase/PATTERNS.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "dev" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Codebase Map" ".vbw-planning/phases/01-test/.context-dev.md"
}

@test "compile-context.sh dev guidance references conventions and patterns" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Conventions" > .vbw-planning/codebase/CONVENTIONS.md
  echo "# Patterns" > .vbw-planning/codebase/PATTERNS.md
  echo "# Structure" > .vbw-planning/codebase/STRUCTURE.md
  echo "# Dependencies" > .vbw-planning/codebase/DEPENDENCIES.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "dev" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "CONVENTIONS.md" ".vbw-planning/phases/01-test/.context-dev.md"
  grep -q "PATTERNS.md" ".vbw-planning/phases/01-test/.context-dev.md"
  grep -q "STRUCTURE.md" ".vbw-planning/phases/01-test/.context-dev.md"
  grep -q "DEPENDENCIES.md" ".vbw-planning/phases/01-test/.context-dev.md"
}

# =============================================================================
# Compiled context: codebase mapping hint in qa context
# =============================================================================

@test "compile-context.sh qa context includes codebase mapping hint when mapping exists" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Testing" > .vbw-planning/codebase/TESTING.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "qa" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Codebase Map" ".vbw-planning/phases/01-test/.context-qa.md"
}

@test "compile-context.sh qa guidance references testing and concerns" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Testing" > .vbw-planning/codebase/TESTING.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "qa" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "TESTING.md" ".vbw-planning/phases/01-test/.context-qa.md"
  grep -q "CONCERNS.md" ".vbw-planning/phases/01-test/.context-qa.md"
  grep -q "ARCHITECTURE.md" ".vbw-planning/phases/01-test/.context-qa.md"
}

# =============================================================================
# Compiled context: codebase mapping hint in lead context
# =============================================================================

@test "compile-context.sh lead context includes codebase mapping hint when mapping exists" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "lead" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Codebase Map" ".vbw-planning/phases/01-test/.context-lead.md"
}

@test "compile-context.sh lead guidance references architecture and concerns" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md
  echo "# Structure" > .vbw-planning/codebase/STRUCTURE.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "lead" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "ARCHITECTURE.md" ".vbw-planning/phases/01-test/.context-lead.md"
  grep -q "CONCERNS.md" ".vbw-planning/phases/01-test/.context-lead.md"
  grep -q "STRUCTURE.md" ".vbw-planning/phases/01-test/.context-lead.md"
}

# =============================================================================
# Compiled context: codebase mapping hint in architect context
# =============================================================================

@test "compile-context.sh architect context includes codebase mapping hint when mapping exists" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Stack" > .vbw-planning/codebase/STACK.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "architect" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Codebase Map" ".vbw-planning/phases/01-test/.context-architect.md"
}

@test "compile-context.sh architect guidance references architecture and stack" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Stack" > .vbw-planning/codebase/STACK.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "architect" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "ARCHITECTURE.md" ".vbw-planning/phases/01-test/.context-architect.md"
  grep -q "STACK.md" ".vbw-planning/phases/01-test/.context-architect.md"
}

@test "compile-context.sh debugger omits map section when META.md exists but no key files" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # Only META.md, none of the 5 key files
  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Should NOT show Codebase Map section when no key files exist
  run grep "Codebase Map" ".vbw-planning/phases/01-test/.context-debugger.md"
  [ "$status" -eq 1 ]
}

# =============================================================================
# QA finding: cache invalidation when codebase mapping changes
# =============================================================================

@test "cache-context.sh debugger hash changes when codebase mapping files change" {
  cd "$TEST_TEMP_DIR"

  # Set up mapping files
  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture v1" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns v1" > .vbw-planning/codebase/CONCERNS.md

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 debugger "$TEST_TEMP_DIR/.vbw-planning/config.json"
  HASH1=$(echo "$output" | cut -d' ' -f2)

  # Remove a mapping file
  rm .vbw-planning/codebase/CONCERNS.md

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 debugger "$TEST_TEMP_DIR/.vbw-planning/config.json"
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh non-mapping role hash unaffected by codebase mapping" {
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 scout "$TEST_TEMP_DIR/.vbw-planning/config.json"
  HASH1=$(echo "$output" | cut -d' ' -f2)

  # Remove mapping file
  rm .vbw-planning/codebase/ARCHITECTURE.md

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 scout "$TEST_TEMP_DIR/.vbw-planning/config.json"
  HASH2=$(echo "$output" | cut -d' ' -f2)

  # Scout hash should be unchanged — codebase mapping only affects dev/qa/lead/architect/debugger
  [ "$HASH1" = "$HASH2" ]
}

@test "cache-context.sh dev hash changes when codebase mapping files change" {
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Conventions" > .vbw-planning/codebase/CONVENTIONS.md

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 dev "$TEST_TEMP_DIR/.vbw-planning/config.json"
  HASH1=$(echo "$output" | cut -d' ' -f2)

  rm .vbw-planning/codebase/CONVENTIONS.md

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 dev "$TEST_TEMP_DIR/.vbw-planning/config.json"
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

# =============================================================================
# debug.md command: prompt includes codebase bootstrap instruction
# =============================================================================

@test "debug.md Path B prompt includes codebase bootstrap instruction" {
  # The Path B prompt template block must include codebase bootstrap
  grep -A20 'Path B.*Standard' "$PROJECT_ROOT/commands/debug.md" | grep -q '.vbw-planning/codebase/'
}

@test "debug.md Path B prompt mentions .vbw-planning/codebase/" {
  # The prompt template must tell the debugger to check for codebase mapping
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug.md Path A task prompt includes codebase bootstrap instruction" {
  # Path A creates 3 tasks — each task prompt should mention codebase bootstrap
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/commands/debug.md"
  # Both Path A and Path B sections should reference it
  grep -A20 'Create.*tasks via TaskCreate' "$PROJECT_ROOT/commands/debug.md" | grep -q '.vbw-planning/codebase/'
}

# =============================================================================
# Role isolation: scout omits codebase mapping
# =============================================================================

@test "compile-context.sh scout omits codebase mapping even when present" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "scout" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  run grep "Codebase Map" ".vbw-planning/phases/01-test/.context-scout.md"
  [ "$status" -eq 1 ]
}

# =============================================================================
# All roles omit mapping when META.md missing
# =============================================================================

@test "compile-context.sh all roles omit codebase mapping when META.md missing" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md

  for role in dev qa lead architect debugger scout; do
    run bash "$SCRIPTS_DIR/compile-context.sh" "01" "$role" ".vbw-planning/phases"
    [ "$status" -eq 0 ]
    run grep "Codebase Map" ".vbw-planning/phases/01-test/.context-${role}.md"
    [ "$status" -eq 1 ]
  done
}

# =============================================================================
# fix.md command: prompt includes codebase bootstrap instruction (#96)
# =============================================================================

@test "fix.md spawn prompt includes codebase bootstrap instruction" {
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix.md spawn prompt mentions CONVENTIONS.md or PATTERNS.md" {
  grep -qE 'CONVENTIONS|PATTERNS|STRUCTURE|DEPENDENCIES' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix.md spawn prompt gates on META.md not just directory existence" {
  grep -q 'META.md' "$PROJECT_ROOT/commands/fix.md"
}

# =============================================================================
# vbw-dev.md: codebase bootstrap is standalone, not nested in Execution Protocol (#96)
# =============================================================================

@test "dev agent has standalone Codebase Bootstrap section" {
  # Codebase Bootstrap should be a top-level ## section, not ### inside Execution Protocol
  grep -q '^## Codebase Bootstrap' "$PROJECT_ROOT/agents/vbw-dev.md"
}

@test "dev agent codebase bootstrap qualifies files with existence check" {
  grep -q 'whichever.*exist\|Skip any' "$PROJECT_ROOT/agents/vbw-dev.md"
}

@test "dev agent codebase bootstrap mentions compaction re-read" {
  grep -q 'compaction.*re-read\|re-read.*compaction' "$PROJECT_ROOT/agents/vbw-dev.md"
}

# =============================================================================
# compaction-instructions.sh: dev role mentions codebase mapping (#96)
# =============================================================================

@test "compaction-instructions.sh dev priorities include codebase mapping re-read" {
  # The dev case in compaction-instructions.sh should mention codebase mapping
  sed -n '/*dev*/,/;;/p' "$PROJECT_ROOT/scripts/compaction-instructions.sh" | grep -q 'codebase'
}

# =============================================================================
# execute-protocol.md: dev spawn prompt includes codebase bootstrap (#96)
# =============================================================================

@test "execute-protocol.md dev spawn prompt includes codebase bootstrap" {
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/references/execute-protocol.md"
}

@test "execute-protocol.md dev spawn prompt gates on META.md" {
  grep -q 'META.md' "$PROJECT_ROOT/references/execute-protocol.md"
}

# =============================================================================
# compaction-instructions.sh: all mapping-aware roles mention codebase (#96)
# =============================================================================

@test "compaction-instructions.sh debugger priorities include codebase mapping re-read" {
  sed -n '/*debugger*/,/;;/p' "$PROJECT_ROOT/scripts/compaction-instructions.sh" | grep -q 'codebase'
}

@test "compaction-instructions.sh lead priorities include codebase mapping re-read" {
  sed -n '/*lead*/,/;;/p' "$PROJECT_ROOT/scripts/compaction-instructions.sh" | grep -q 'codebase'
}

@test "compaction-instructions.sh architect priorities include codebase mapping re-read" {
  sed -n '/*architect*/,/;;/p' "$PROJECT_ROOT/scripts/compaction-instructions.sh" | grep -q 'codebase'
}

@test "compaction-instructions.sh qa priorities include codebase mapping re-read" {
  sed -n '/*qa*/,/;;/p' "$PROJECT_ROOT/scripts/compaction-instructions.sh" | grep -q 'codebase'
}

# =============================================================================
# debug.md command: gates on META.md, includes "whichever exist" qualifier (#96)
# =============================================================================

@test "debug.md Path A gates on META.md not just directory existence" {
  grep -A5 'Create.*tasks via TaskCreate' "$PROJECT_ROOT/commands/debug.md" | grep -q 'META.md'
}

@test "debug.md Path B gates on META.md not just directory existence" {
  grep -A20 'Path B.*Standard' "$PROJECT_ROOT/commands/debug.md" | grep -q 'META.md'
}

@test "debug.md includes whichever exist qualifier in spawn prompts" {
  grep -q 'whichever exist' "$PROJECT_ROOT/commands/debug.md"
}

# =============================================================================
# qa.md command: spawn prompt includes full codebase bootstrap (#96)
# =============================================================================

@test "qa.md spawn prompt includes codebase bootstrap instruction" {
  grep -q 'META.md' "$PROJECT_ROOT/commands/qa.md"
}

@test "qa.md spawn prompt references TESTING.md and CONCERNS.md" {
  grep -q 'TESTING.md' "$PROJECT_ROOT/commands/qa.md" &&
  grep -q 'CONCERNS.md' "$PROJECT_ROOT/commands/qa.md"
}

# =============================================================================
# execute-protocol.md: QA spawn prompts include codebase bootstrap (#96)
# =============================================================================

@test "execute-protocol.md per-wave QA prompt includes codebase bootstrap" {
  grep -A5 'Per-wave QA' "$PROJECT_ROOT/references/execute-protocol.md" | grep -q 'META.md'
}

@test "execute-protocol.md post-build QA prompt includes codebase bootstrap" {
  grep -A5 'Post-build QA' "$PROJECT_ROOT/references/execute-protocol.md" | grep -q 'META.md'
}

# =============================================================================
# Agent definitions: "whichever exist" qualifier in bootstrap (#96 round 4)
# =============================================================================

@test "debugger agent bootstrap qualifies files with existence check" {
  grep -qE 'whichever.*exist|Skip any' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "qa agent bootstrap qualifies files with existence check" {
  grep -qE 'whichever.*exist|Skip any' "$PROJECT_ROOT/agents/vbw-qa.md"
}

@test "lead agent bootstrap qualifies files with existence check" {
  grep -qE 'whichever.*exist|Skip any' "$PROJECT_ROOT/agents/vbw-lead.md"
}

@test "architect agent bootstrap qualifies files with existence check" {
  grep -qE 'whichever.*exist|Skip any' "$PROJECT_ROOT/agents/vbw-architect.md"
}

# =============================================================================
# compaction-instructions.sh: default case does NOT include codebase (#96 round 4)
# =============================================================================

@test "compaction-instructions.sh default case does NOT include codebase mapping" {
  # The wildcard *) case should not mention codebase — only named roles get it
  # Feed an unknown agent name and verify no codebase reference in output
  cd "$TEST_TEMP_DIR"
  echo '{"agent_name":"unknown-agent","matcher":"auto"}' | \
    bash "$PROJECT_ROOT/scripts/compaction-instructions.sh" > "$TEST_TEMP_DIR/compaction-output.json"
  ! grep -q 'codebase' "$TEST_TEMP_DIR/compaction-output.json"
}

@test "compaction-instructions.sh docs agent does NOT include codebase mapping" {
  cd "$TEST_TEMP_DIR"
  echo '{"agent_name":"vbw-docs","matcher":"auto"}' | \
    bash "$PROJECT_ROOT/scripts/compaction-instructions.sh" > "$TEST_TEMP_DIR/compaction-output.json"
  ! grep -q 'codebase' "$TEST_TEMP_DIR/compaction-output.json"
}

# =============================================================================
# compaction-instructions.sh: output uses full META.md path and "whichever exist" (#96 QA round 4)
# =============================================================================

@test "compaction-instructions.sh dev output uses full .vbw-planning/codebase/META.md path" {
  cd "$TEST_TEMP_DIR"
  echo '{"agent_name":"vbw-dev","matcher":"auto"}' | \
    bash "$PROJECT_ROOT/scripts/compaction-instructions.sh" > "$TEST_TEMP_DIR/compaction-output.json"
  grep -q '.vbw-planning/codebase/META.md' "$TEST_TEMP_DIR/compaction-output.json"
}

@test "compaction-instructions.sh dev output includes whichever exist qualifier" {
  cd "$TEST_TEMP_DIR"
  echo '{"agent_name":"vbw-dev","matcher":"auto"}' | \
    bash "$PROJECT_ROOT/scripts/compaction-instructions.sh" > "$TEST_TEMP_DIR/compaction-output.json"
  grep -q 'whichever exist' "$TEST_TEMP_DIR/compaction-output.json"
}

@test "compaction-instructions.sh qa output uses full META.md path and whichever exist" {
  cd "$TEST_TEMP_DIR"
  echo '{"agent_name":"vbw-qa","matcher":"auto"}' | \
    bash "$PROJECT_ROOT/scripts/compaction-instructions.sh" > "$TEST_TEMP_DIR/compaction-output.json"
  grep -q '.vbw-planning/codebase/META.md' "$TEST_TEMP_DIR/compaction-output.json"
  grep -q 'whichever exist' "$TEST_TEMP_DIR/compaction-output.json"
}

@test "compaction-instructions.sh debugger output uses full META.md path and whichever exist" {
  cd "$TEST_TEMP_DIR"
  echo '{"agent_name":"vbw-debugger","matcher":"auto"}' | \
    bash "$PROJECT_ROOT/scripts/compaction-instructions.sh" > "$TEST_TEMP_DIR/compaction-output.json"
  grep -q '.vbw-planning/codebase/META.md' "$TEST_TEMP_DIR/compaction-output.json"
  grep -q 'whichever exist' "$TEST_TEMP_DIR/compaction-output.json"
}

@test "compaction-instructions.sh lead output uses full META.md path and whichever exist" {
  cd "$TEST_TEMP_DIR"
  echo '{"agent_name":"vbw-lead","matcher":"auto"}' | \
    bash "$PROJECT_ROOT/scripts/compaction-instructions.sh" > "$TEST_TEMP_DIR/compaction-output.json"
  grep -q '.vbw-planning/codebase/META.md' "$TEST_TEMP_DIR/compaction-output.json"
  grep -q 'whichever exist' "$TEST_TEMP_DIR/compaction-output.json"
}

@test "compaction-instructions.sh architect output uses full META.md path and whichever exist" {
  cd "$TEST_TEMP_DIR"
  echo '{"agent_name":"vbw-architect","matcher":"auto"}' | \
    bash "$PROJECT_ROOT/scripts/compaction-instructions.sh" > "$TEST_TEMP_DIR/compaction-output.json"
  grep -q '.vbw-planning/codebase/META.md' "$TEST_TEMP_DIR/compaction-output.json"
  grep -q 'whichever exist' "$TEST_TEMP_DIR/compaction-output.json"
}

# =============================================================================
# vibe.md: gates on META.md not directory existence (#96 QA round 4)
# =============================================================================

@test "vibe.md bootstrap codebase constraint gates on META.md" {
  grep -q 'META.md' "$PROJECT_ROOT/commands/vibe.md"
}

@test "vibe.md does not gate codebase reads on bare directory existence" {
  # Every line referencing .vbw-planning/codebase/ should also mention META.md
  while IFS= read -r line; do
    echo "$line" | grep -q 'META.md' || {
      # Allow "from .vbw-planning/codebase/" (trailing path in read instructions)
      echo "$line" | grep -q 'from.*\.vbw-planning/codebase/' && continue
      echo "FAIL: line missing META.md gate: $line"
      return 1
    }
  done < <(grep '.vbw-planning/codebase/' "$PROJECT_ROOT/commands/vibe.md")
}

# =============================================================================
# compile-context.sh: docs role excluded from codebase mapping (#96 QA round 4)
# =============================================================================

@test "compile-context.sh docs role is not a valid role (no codebase mapping possible)" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md

  # docs is not a valid compile-context.sh role — it should exit non-zero
  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "docs" ".vbw-planning/phases"
  [ "$status" -ne 0 ]
}
