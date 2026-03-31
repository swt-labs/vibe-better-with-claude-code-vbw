#!/usr/bin/env bats

# Tests for MCP delegation in map.md (Phase 8)
# Validates: capability detection, Scout prompt injection, META.md schema,
#            vbw-scout.md MCP guidance, and no-regression for existing behavior.
# All tests are grep/content-based -- no live MCP server needed.

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# =============================================================================
# Capability detection tests (Tests 1-5)
# =============================================================================

@test "map.md contains Step 1.3 MCP capability detection" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  # Step 1.3 must exist
  grep -qi 'Step 1\.3' "$map_file"
  # The step must mention MCP or capability
  local section
  section=$(sed -n '/Step 1\.3/,/Step 2/p' "$map_file")
  echo "$section" | grep -qi 'MCP\|capability'
}

@test "map.md defines all capability categories" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  grep -q 'CAPABILITY_ARCHITECTURE' "$map_file"
  grep -q 'CAPABILITY_SYMBOL_SEARCH' "$map_file"
  grep -q 'CAPABILITY_DEPENDENCY_GRAPH' "$map_file"
  grep -q 'CAPABILITY_CALL_TRACING' "$map_file"
  grep -q 'CAPABILITY_CODE_SEARCH' "$map_file"
  grep -q 'CAPABILITY_CODE_SNIPPET' "$map_file"
  grep -q 'CAPABILITY_HOTSPOT_ANALYSIS' "$map_file"
  grep -q 'CAPABILITY_INDEX' "$map_file"
}

@test "map.md detection logic has no hardcoded server names" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  # Extract the capability definition lines (CAPABILITY_ := ...) from Step 1.3
  # These are the actual detection patterns -- they must not contain server names
  local cap_lines
  cap_lines=$(grep 'CAPABILITY_.*:=' "$map_file")
  # Known MCP server names must NOT appear in the capability patterns
  if echo "$cap_lines" | grep -q 'codebase-memory-mcp\|tree-sitter-mcp\|sourcegraph-mcp'; then
    echo "ERROR: Hardcoded MCP server names found in capability detection patterns"
    return 1
  fi
}

@test "map.md contains mcp_code_analysis block for Scout prompts" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  # mcp_code_analysis must appear in both duo and quad sections (at least 2 occurrences)
  local count
  count=$(grep -c 'mcp_code_analysis' "$map_file")
  [ "$count" -ge 2 ]
}

@test "map.md solo mode has MCP-accelerated analysis block" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  # Solo path should reference MCP_MAP_CAPABILITIES or MCP-accelerated
  local solo_section
  solo_section=$(sed -n '/Step 3-solo/,/Step 3-duo/p' "$map_file")
  echo "$solo_section" | grep -q 'MCP_MAP_CAPABILITIES\|MCP-accelerated\|mcp_code_analysis\|code-analysis MCP'
}
