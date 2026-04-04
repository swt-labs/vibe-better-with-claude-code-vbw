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

# =============================================================================
# META.md schema and Scout agent validation tests (Tests 6-10)
# =============================================================================

@test "map.md Step 5 includes mcp_capabilities in META.md" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  grep -q 'mcp_capabilities' "$map_file"
}

@test "vbw-scout.md has Code-Analysis MCP for Mapping section" {
  local scout_file="$BATS_TEST_DIRNAME/../agents/vbw-scout.md"
  grep -q 'Code-Analysis MCP for Mapping' "$scout_file"
}

@test "vbw-scout.md mapping MCP section covers index freshness" {
  local scout_file="$BATS_TEST_DIRNAME/../agents/vbw-scout.md"
  grep -q 'index_repository' "$scout_file"
  grep -q 'Index Freshness' "$scout_file"
}

@test "vbw-scout.md mapping MCP section covers hybrid fallback" {
  local scout_file="$BATS_TEST_DIRNAME/../agents/vbw-scout.md"
  grep -q 'Hybrid Fallback' "$scout_file"
  grep -q 'Fall back to Glob/Read/Grep' "$scout_file"
}

@test "vbw-scout.md mapping MCP section covers graph coverage gaps" {
  local scout_file="$BATS_TEST_DIRNAME/../agents/vbw-scout.md"
  grep -q 'Graph Coverage Gaps' "$scout_file"
}

# =============================================================================
# No-regression fallback tests (Tests 11-15)
# =============================================================================

@test "map.md preserves existing Step 1 argument parsing" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  grep -q '\-\-incremental' "$map_file"
  grep -q '\-\-package' "$map_file"
  grep -q '\-\-tier' "$map_file"
}

@test "map.md preserves existing tier table" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  # All three tier names must be present in Step 1.5
  local tier_section
  tier_section=$(sed -n '/Step 1\.5/,/Step [2-9]/p' "$map_file")
  echo "$tier_section" | grep -q 'solo'
  echo "$tier_section" | grep -q 'duo'
  echo "$tier_section" | grep -q 'quad'
}

@test "map.md preserves Step 3.5 document verification" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  grep -q 'Step 3\.5' "$map_file"
}

@test "map.md preserves Step 4 synthesis" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  grep -q 'INDEX\.md' "$map_file"
  grep -q 'PATTERNS\.md' "$map_file"
}

@test "map.md preserves Step 5 shutdown protocol" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  grep -q 'shutdown_request' "$map_file"
}

# =============================================================================
# Extended capability detection tests (Tests 16-25) — Plan 08-04
# =============================================================================

@test "map.md defines new capability categories (OUTLINE, IMPACT_ANALYSIS, CLASS_HIERARCHY)" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  grep -q 'CAPABILITY_OUTLINE' "$map_file"
  grep -q 'CAPABILITY_IMPACT_ANALYSIS' "$map_file"
  grep -q 'CAPABILITY_CLASS_HIERARCHY' "$map_file"
}

@test "map.md has extended suffixes for jcodemunch tools" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  # Extract Pass 1 capability definitions
  local cap_lines
  cap_lines=$(grep 'CAPABILITY_.*:=' "$map_file")
  echo "$cap_lines" | grep -q 'get_symbol_source'
  echo "$cap_lines" | grep -q 'find_importers'
  echo "$cap_lines" | grep -q 'get_blast_radius'
  echo "$cap_lines" | grep -q 'get_changed_symbols'
  echo "$cap_lines" | grep -q 'get_file_outline'
  echo "$cap_lines" | grep -q 'get_class_hierarchy'
  echo "$cap_lines" | grep -q 'find_dead_code'
  echo "$cap_lines" | grep -q 'get_symbol_importance'
}

@test "map.md has extended suffixes for jdocmunch tools" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  local cap_lines
  cap_lines=$(grep 'CAPABILITY_.*:=' "$map_file")
  echo "$cap_lines" | grep -q 'index_local'
  echo "$cap_lines" | grep -q 'index_repo'
  echo "$cap_lines" | grep -q 'search_sections'
  echo "$cap_lines" | grep -q 'get_section'
  echo "$cap_lines" | grep -q 'get_document_outline'
  echo "$cap_lines" | grep -q 'get_toc'
  echo "$cap_lines" | grep -q 'get_broken_links'
  echo "$cap_lines" | grep -q 'get_doc_coverage'
}

@test "map.md contains Pass 2 description-based matching" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  grep -q 'Pass 2' "$map_file"
  grep -qi 'description-based\|Description-based' "$map_file"
}

@test "map.md Pass 2 has description keyword sets for all 11 categories" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  # Extract the Pass 2 section
  local pass2
  pass2=$(sed -n '/Pass 2.*[Dd]escription/,/### Step/p' "$map_file")
  echo "$pass2" | grep -q 'CAPABILITY_ARCHITECTURE.*description contains'
  echo "$pass2" | grep -q 'CAPABILITY_SYMBOL_SEARCH.*description contains'
  echo "$pass2" | grep -q 'CAPABILITY_DEPENDENCY_GRAPH.*description contains'
  echo "$pass2" | grep -q 'CAPABILITY_CALL_TRACING.*description contains'
  echo "$pass2" | grep -q 'CAPABILITY_CODE_SEARCH.*description contains'
  echo "$pass2" | grep -q 'CAPABILITY_CODE_SNIPPET.*description contains'
  echo "$pass2" | grep -q 'CAPABILITY_HOTSPOT_ANALYSIS.*description contains'
  echo "$pass2" | grep -q 'CAPABILITY_INDEX.*description contains'
  echo "$pass2" | grep -q 'CAPABILITY_OUTLINE.*description contains'
  echo "$pass2" | grep -q 'CAPABILITY_IMPACT_ANALYSIS.*description contains'
  echo "$pass2" | grep -q 'CAPABILITY_CLASS_HIERARCHY.*description contains'
}

@test "map.md Pass 1 name-suffix takes priority over Pass 2 description" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  grep -q 'Pass 1.*always takes priority\|name suffix.*always takes priority' "$map_file"
}

@test "map.md display line shows name vs description breakdown" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  grep -q 'by name.*by description' "$map_file"
}

@test "map.md new categories appear in duo/quad capability-to-document routing" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  # Outline should route to STRUCTURE.md
  grep -q 'Outline.*STRUCTURE\|outline.*STRUCTURE' "$map_file"
  # Class hierarchy should route to ARCHITECTURE.md
  grep -q 'Class hierarchy.*ARCHITECTURE\|class hierarchy.*ARCHITECTURE' "$map_file"
  # Impact analysis should route to CONCERNS.md
  grep -q 'Impact analysis.*CONCERNS\|impact analysis.*CONCERNS' "$map_file"
}

@test "map.md original 8 capability categories still have original suffixes" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  local cap_lines
  cap_lines=$(grep 'CAPABILITY_.*:=' "$map_file")
  # Verify original suffixes from Plan 08-01 are still present
  echo "$cap_lines" | grep -q 'get_architecture'
  echo "$cap_lines" | grep -q 'search_graph'
  echo "$cap_lines" | grep -q 'query_graph'
  echo "$cap_lines" | grep -q 'trace_call_path'
  echo "$cap_lines" | grep -q 'search_code'
  echo "$cap_lines" | grep -q 'get_code_snippet'
  echo "$cap_lines" | grep -q 'detect_changes'
  echo "$cap_lines" | grep -q 'index_repository'
}

@test "map.md extended detection has no hardcoded server names" {
  local map_file="$BATS_TEST_DIRNAME/../commands/map.md"
  # Check both Pass 1 and Pass 2 capability definition lines
  local cap_lines
  cap_lines=$(grep 'CAPABILITY_.*:=\|CAPABILITY_.*description contains' "$map_file")
  if echo "$cap_lines" | grep -q 'codebase-memory-mcp\|jcodemunch\|jdocmunch\|tree-sitter-mcp\|sourcegraph-mcp'; then
    echo "ERROR: Hardcoded MCP server names found in capability detection patterns"
    return 1
  fi
}
