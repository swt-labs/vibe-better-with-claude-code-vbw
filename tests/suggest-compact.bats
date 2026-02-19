#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

# =============================================================================
# suggest-compact.sh: no output when no cached usage file
# =============================================================================

@test "suggest-compact: silent when no .context-usage file" {
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================================
# suggest-compact.sh: no output when context is well below threshold
# =============================================================================

@test "suggest-compact: silent when context at 30% (200K window)" {
  echo "30|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: silent when context at 50%" {
  echo "50|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: silent when context at 70% for light command" {
  echo "70|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" discuss
  [ "$status" -eq 0 ]
  # 70% of 200K = 60K remaining, discuss needs ~6K + 15% = ~6.9K — fine
  [ -z "$output" ]
}

# =============================================================================
# suggest-compact.sh: warning when context is near capacity
# =============================================================================

@test "suggest-compact: warns when context at 90% for execute mode" {
  echo "90|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  # 90% of 200K = 20K remaining, execute needs ~25K + 15% = ~28.75K — should warn
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
  [[ "$output" == *"90%"* ]]
  [[ "$output" == *"execute"* ]]
}

@test "suggest-compact: warns when context at 96% for any mode" {
  echo "96|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" qa
  [ "$status" -eq 0 ]
  # 96% = 8K remaining, qa needs ~8K + 15% = ~9.2K — should warn
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: warns when context at 86% for heavy execute mode" {
  echo "86|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  # 86% = 28K remaining, execute needs ~25K + 15% = 28.75K — should warn
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

# =============================================================================
# suggest-compact.sh: autonomy-dependent messaging
# =============================================================================

@test "suggest-compact: recommends /compact for standard autonomy" {
  echo "92|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"RECOMMENDED"* ]]
  [[ "$output" == *"/compact"* ]]
}

@test "suggest-compact: auto-triggers for confident autonomy" {
  echo "92|200000" > .vbw-planning/.context-usage
  # Set autonomy to confident
  jq '.autonomy = "confident"' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACTION REQUIRED"* ]]
  [[ "$output" == *"confident"* ]]
}

@test "suggest-compact: auto-triggers for pure-vibe autonomy" {
  echo "92|200000" > .vbw-planning/.context-usage
  jq '.autonomy = "pure-vibe"' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACTION REQUIRED"* ]]
  [[ "$output" == *"pure-vibe"* ]]
}

# =============================================================================
# suggest-compact.sh: mode-specific cost thresholds
# =============================================================================

@test "suggest-compact: plan mode warns at lower threshold than execute" {
  # At 88% with 200K: 24K remaining
  # execute needs 25K+15%=28.75K -> warn
  # plan needs 12K+15%=13.8K -> NO warn (24K > 13.8K)
  echo "88|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" plan
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: verify is lighter than execute" {
  # At 90%: 20K remaining
  # verify needs 10K+15%=11.5K -> NO warn
  # execute needs 25K+15%=28.75K -> warn
  echo "90|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" verify
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

# =============================================================================
# suggest-compact.sh: compaction_threshold config integration
# =============================================================================

@test "suggest-compact: respects compaction_threshold from config" {
  # 60% of 200K = 120K used, + 25K execute = 145K projected
  # threshold 130000 -> warn because 145K > 130K
  echo "60|200000" > .vbw-planning/.context-usage
  jq '.compaction_threshold = 130000' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: no warn when below compaction_threshold" {
  # 40% of 200K = 80K used, + 6K discuss = 86K projected
  # threshold 130000 -> fine (86K < 130K)
  echo "40|200000" > .vbw-planning/.context-usage
  jq '.compaction_threshold = 130000' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/suggest-compact.sh" discuss
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================================
# suggest-compact.sh: robust handling of edge cases
# =============================================================================

@test "suggest-compact: handles corrupt .context-usage gracefully" {
  echo "garbage" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: handles empty .context-usage gracefully" {
  echo "" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: handles 0|0 context size gracefully" {
  echo "0|0" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: handles missing config.json gracefully" {
  rm -f .vbw-planning/config.json
  echo "92|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: defaults to execute mode when no mode given" {
  echo "92|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"execute"* ]]
}

@test "suggest-compact: unknown mode uses fallback cost" {
  echo "95|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" unknown_mode
  [ "$status" -eq 0 ]
  # 95%: 10K remaining, unknown needs 10K+15%=11.5K -> warn
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

# =============================================================================
# suggest-compact.sh: 100% usage edge case
# =============================================================================

@test "suggest-compact: warns at 100% usage" {
  echo "100|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" discuss
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

# =============================================================================
# vbw-statusline.sh: caches context usage to .context-usage
# =============================================================================

@test "statusline: writes .context-usage with pct and size" {
  mkdir -p .vbw-planning
  # Pipe minimal JSON to statusline; it should cache usage
  echo '{"context_window":{"used_percentage":42,"remaining_percentage":58,"context_window_size":200000,"current_usage":{"input_tokens":10000,"output_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0,"total_duration_ms":0,"total_api_duration_ms":0,"total_lines_added":0,"total_lines_removed":0},"model":{"display_name":"Claude"},"version":"1.0"}' \
    | bash "$SCRIPTS_DIR/vbw-statusline.sh" > /dev/null 2>&1
  [ -f ".vbw-planning/.context-usage" ]
  IFS='|' read -r pct size < .vbw-planning/.context-usage
  [ "$pct" = "42" ]
  [ "$size" = "200000" ]
}

# =============================================================================
# Command templates: pre-flight guard is wired
# =============================================================================

@test "vibe.md includes suggest-compact.sh expansion" {
  grep -q 'suggest-compact.sh' "$PROJECT_ROOT/commands/vibe.md"
}

@test "qa.md includes suggest-compact.sh expansion" {
  grep -q 'suggest-compact.sh' "$PROJECT_ROOT/commands/qa.md"
}

@test "verify.md includes suggest-compact.sh expansion" {
  grep -q 'suggest-compact.sh' "$PROJECT_ROOT/commands/verify.md"
}

@test "discuss.md includes suggest-compact.sh expansion" {
  grep -q 'suggest-compact.sh' "$PROJECT_ROOT/commands/discuss.md"
}

@test "vibe.md passes execute mode to suggest-compact.sh" {
  grep 'suggest-compact.sh' "$PROJECT_ROOT/commands/vibe.md" | grep -q 'execute'
}

@test "qa.md passes qa mode to suggest-compact.sh" {
  grep 'suggest-compact.sh' "$PROJECT_ROOT/commands/qa.md" | grep -q 'qa'
}

@test "verify.md passes verify mode to suggest-compact.sh" {
  grep 'suggest-compact.sh' "$PROJECT_ROOT/commands/verify.md" | grep -q 'verify'
}

@test "discuss.md passes discuss mode to suggest-compact.sh" {
  grep 'suggest-compact.sh' "$PROJECT_ROOT/commands/discuss.md" | grep -q 'discuss'
}
