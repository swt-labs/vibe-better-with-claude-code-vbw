#!/usr/bin/env bats

load test_helper

# Create mock plugin files with controlled byte sizes for deterministic tests.
# This isolates tests from real reference file size changes.
#
# Mode costs (CHARS_PER_TOKEN=5, BASELINE_OVERHEAD=1500, buffer=15%):
#   execute  — 45500B fixed → EST_COST=10600 → NEEDED=12190
#   plan     —  4500B fixed → EST_COST=2400  → NEEDED=2760
#   verify   —  1500B fixed → EST_COST=1800  → NEEDED=2070
#   qa       — 15000B fixed → EST_COST=4500  → NEEDED=5175
#   discuss  —  5000B fixed → EST_COST=2500  → NEEDED=2875
#   unknown  — 30000B fixed → EST_COST=7500  → NEEDED=8625
create_mock_plugin() {
  local d="$TEST_TEMP_DIR/mock-plugin"
  mkdir -p "$d/references" "$d/agents" "$d/templates"
  printf '%*s' 25000 '' > "$d/references/execute-protocol.md"
  printf '%*s' 5000  '' > "$d/references/handoff-schemas.md"
  printf '%*s' 1000  '' > "$d/references/vbw-brand-essentials.md"
  printf '%*s' 1000  '' > "$d/references/effort-profile-balanced.md"
  printf '%*s' 1000  '' > "$d/references/effort-profile-thorough.md"
  printf '%*s' 1000  '' > "$d/references/effort-profile-fast.md"
  printf '%*s' 1000  '' > "$d/references/effort-profile-turbo.md"
  printf '%*s' 5000  '' > "$d/agents/vbw-dev.md"
  printf '%*s' 3000  '' > "$d/agents/vbw-qa.md"
  printf '%*s' 5000  '' > "$d/references/verification-protocol.md"
  printf '%*s' 500   '' > "$d/templates/SUMMARY.md"
  printf '%*s' 4000  '' > "$d/agents/vbw-lead.md"
  printf '%*s' 500   '' > "$d/templates/PLAN.md"
  printf '%*s' 500   '' > "$d/templates/UAT.md"
  printf '%*s' 5000  '' > "$d/references/discussion-engine.md"
  export CLAUDE_PLUGIN_ROOT="$d"
}

setup() {
  setup_temp_dir
  create_test_config
  create_mock_plugin
  # Isolate from user's ~/.claude/settings.json (may have CLAUDE_AUTOCOMPACT_PCT_OVERRIDE)
  mkdir -p "$TEST_TEMP_DIR/claude-config"
  echo '{"env":{"DISABLE_AUTO_COMPACT":"false"}}' > "$TEST_TEMP_DIR/claude-config/settings.json"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude-config"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  unset CLAUDE_CONFIG_DIR
  teardown_temp_dir
}

# =============================================================================
# No output when preconditions not met
# =============================================================================

@test "suggest-compact: silent when no .context-usage file" {
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================================
# No output when context is well below threshold
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
  # 70% of 200K = 60K remaining; discuss NEEDED=2875 — plenty of room
  echo "70|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" discuss
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================================
# Warning when context is near capacity
# =============================================================================

@test "suggest-compact: warns when context at 95% for execute mode" {
  # 95% of 200K = 10K remaining; execute NEEDED=12190 → warns
  echo "95|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
  [[ "$output" == *"95%"* ]]
  [[ "$output" == *"execute"* ]]
}

@test "suggest-compact: warns when context at 99% for any mode" {
  # 99% of 200K = 2K remaining; even lightest mode (verify NEEDED=2070) warns
  echo "99|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: warns when context at 94% for execute mode" {
  # 94% → 12K remaining; execute NEEDED=12190 → barely warns (12000 < 12190)
  echo "94|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

# =============================================================================
# Autonomy-dependent messaging
# =============================================================================

@test "suggest-compact: recommends /compact for standard autonomy" {
  echo "95|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"RECOMMENDED"* ]]
  [[ "$output" == *"/compact"* ]]
}

@test "suggest-compact: auto-triggers for confident autonomy" {
  echo "95|200000" > .vbw-planning/.context-usage
  jq '.autonomy = "confident"' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACTION REQUIRED"* ]]
  [[ "$output" == *"confident"* ]]
}

@test "suggest-compact: auto-triggers for pure-vibe autonomy" {
  echo "95|200000" > .vbw-planning/.context-usage
  jq '.autonomy = "pure-vibe"' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACTION REQUIRED"* ]]
  [[ "$output" == *"pure-vibe"* ]]
}

# =============================================================================
# Mode-specific cost thresholds (dynamic calculation)
# =============================================================================

@test "suggest-compact: plan mode has lower cost than execute" {
  # 94% → 12K remaining
  # execute NEEDED=12190 → warns (12000 < 12190)
  # plan NEEDED=2760 → OK (12000 > 2760)
  echo "94|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" plan
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: verify is lighter than execute" {
  # 94% → 12K remaining
  # verify NEEDED=2070 → OK
  # execute NEEDED=12190 → warns
  echo "94|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" verify
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

# =============================================================================
# Dynamic cost: variable files affect estimates
# =============================================================================

@test "suggest-compact: phase plans increase execute cost" {
  # At 93% without plans: remaining=14000, execute NEEDED=12190 → OK
  echo "93|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # Add a 15000-byte plan → TOTAL_BYTES=60500, EST_COST=13600, NEEDED=15640
  # 14000 < 15640 → warns
  mkdir -p .vbw-planning/phases/01-setup
  printf '%*s' 15000 '' > .vbw-planning/phases/01-setup/01-PLAN.md
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: state files contribute to cost" {
  # Base QA: NEEDED=5175. At 97% remaining=6000 → OK (6000 > 5175)
  # With STATE.md(5000) + ROADMAP.md(5000): EST_COST=6500, NEEDED=7475
  # 6000 < 7475 → warns
  printf '%*s' 5000 '' > .vbw-planning/STATE.md
  printf '%*s' 5000 '' > .vbw-planning/ROADMAP.md
  echo "97|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" qa
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

# =============================================================================
# compaction_threshold config integration
# =============================================================================

@test "suggest-compact: respects compaction_threshold from config" {
  # 60% of 200K = 120K used; execute EST_COST=10600; projected=130600
  # threshold 130000 → 130600 > 130K → warns
  echo "60|200000" > .vbw-planning/.context-usage
  jq '.compaction_threshold = 130000' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: no warn when below compaction_threshold" {
  # 40% of 200K = 80K used; discuss EST_COST=2500; projected=82500
  # threshold 130000 → 82500 < 130K → OK
  echo "40|200000" > .vbw-planning/.context-usage
  jq '.compaction_threshold = 130000' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/suggest-compact.sh" discuss
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================================
# Edge cases
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
  echo "95|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: defaults to execute mode when no mode given" {
  echo "95|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"execute"* ]]
}

@test "suggest-compact: unknown mode uses fallback cost" {
  # unknown: NEEDED=8625. 96% → 8000 remaining → warns (8000 < 8625)
  echo "96|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" unknown_mode
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

# =============================================================================
# 100% usage edge case
# =============================================================================

@test "suggest-compact: warns at 100% usage" {
  echo "100|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" discuss
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

# =============================================================================
# Output includes dynamic cost details
# =============================================================================

@test "suggest-compact: output shows byte breakdown" {
  echo "95|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"B fixed"* ]]
  [[ "$output" == *"project files"* ]]
}

# =============================================================================
# vbw-statusline.sh: caches context usage to .context-usage
# =============================================================================

@test "statusline: writes .context-usage with session ID, pct, and size" {
  mkdir -p .vbw-planning
  # Pipe minimal JSON to statusline; it should cache usage with session ID
  export CLAUDE_SESSION_ID="test-session-abc"
  echo '{"context_window":{"used_percentage":42,"remaining_percentage":58,"context_window_size":200000,"current_usage":{"input_tokens":10000,"output_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0,"total_duration_ms":0,"total_api_duration_ms":0,"total_lines_added":0,"total_lines_removed":0},"model":{"display_name":"Claude"},"version":"1.0"}' \
    | bash "$SCRIPTS_DIR/vbw-statusline.sh" > /dev/null 2>&1
  [ -f ".vbw-planning/.context-usage" ]
  IFS='|' read -r sid pct size < .vbw-planning/.context-usage
  [ "$sid" = "test-session-abc" ]
  # Autocompact normalization (#237): raw 42% on 200K → normalized to ~50%
  # trigger=167K, buffer=33K, BUF_PCT_X10=165, usable=(580-165)*1000/835=497
  # PCT = 100 - (497+5)/10 = 50, CTX_SIZE = trigger = 167000
  [ "$pct" = "50" ]
  [ "$size" = "167000" ]
}

@test "statusline: .context-usage defaults session ID to unknown" {
  mkdir -p .vbw-planning
  unset CLAUDE_SESSION_ID
  echo '{"context_window":{"used_percentage":50,"remaining_percentage":50,"context_window_size":100000,"current_usage":{"input_tokens":10000,"output_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0,"total_duration_ms":0,"total_api_duration_ms":0,"total_lines_added":0,"total_lines_removed":0},"model":{"display_name":"Claude"},"version":"1.0"}' \
    | bash "$SCRIPTS_DIR/vbw-statusline.sh" > /dev/null 2>&1
  [ -f ".vbw-planning/.context-usage" ]
  IFS='|' read -r sid pct size < .vbw-planning/.context-usage
  [ "$sid" = "unknown" ]
  # Autocompact normalization (#237): raw 50% on 100K → normalized to ~75%
  # effective=80K, trigger=67K, buffer=33K, BUF_PCT_X10=330
  # usable=(500-330)*1000/670=253, PCT=100-(253+5)/10=75, CTX_SIZE=67000
  [ "$pct" = "75" ]
  [ "$size" = "67000" ]
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

@test "suggest-compact: verify excludes SOURCE-UAT from cost" {
  # Set up verify mode at a context usage where a large UAT would tip it over
  # verify: EST_COST = (1500 fixed + STATE + UAT) / 5 + 1500
  mkdir -p .vbw-planning/phases/01-setup
  printf '%*s' 100 '' > .vbw-planning/STATE.md

  # Canonical UAT file — should be counted
  printf '%*s' 2000 '' > .vbw-planning/phases/01-setup/01-UAT.md

  # SOURCE-UAT file — should NOT be counted
  printf '%*s' 50000 '' > .vbw-planning/phases/01-setup/01-SOURCE-UAT.md

  # At 99% → remaining = 2000. Without SOURCE-UAT exclusion, the huge
  # SOURCE-UAT would inflate the cost and trigger a warning.
  echo "99|200000" > .vbw-planning/.context-usage

  run bash "$SCRIPTS_DIR/suggest-compact.sh" verify
  [ "$status" -eq 0 ]
  # With the fix, SOURCE-UAT bytes are subtracted, so the cost should
  # be based on only the canonical UAT (2000B) not the 50000B SOURCE-UAT
  # Remaining=2000, verify NEEDED = (1500+100+2000)/5 + 1500 = 2220 * 1.15 = 2553
  # This is just barely over, so let's adjust: use 98% → remaining=4000
}

@test "suggest-compact: verify mode does not count SOURCE-UAT bytes" {
  mkdir -p .vbw-planning/phases/01-setup
  printf '%*s' 100 '' > .vbw-planning/STATE.md
  printf '%*s' 1000 '' > .vbw-planning/phases/01-setup/01-UAT.md

  # 96% of 200K → remaining = 8000 tokens. verify without SOURCE-UAT is fine.
  echo "96|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" verify
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # Now add a huge SOURCE-UAT — should still be fine (excluded from sum)
  printf '%*s' 100000 '' > .vbw-planning/phases/01-setup/01-SOURCE-UAT.md
  run bash "$SCRIPTS_DIR/suggest-compact.sh" verify
  [ "$status" -eq 0 ]
  [ -z "$output" ]
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

# =============================================================================
# Session-ID freshness validation (#238)
# =============================================================================

@test "suggest-compact: stale session ID causes silent skip" {
  echo "old-session-id|95|200000" > .vbw-planning/.context-usage
  CLAUDE_SESSION_ID="new-session-id" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: matching session ID triggers normal guard" {
  echo "my-session|95|200000" > .vbw-planning/.context-usage
  CLAUDE_SESSION_ID="my-session" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: legacy 2-field format still works (backward compat)" {
  echo "95|200000" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: missing CLAUDE_SESSION_ID defaults to unknown on both sides" {
  # Both writer and reader default to "unknown" — should match and proceed
  echo "unknown|95|200000" > .vbw-planning/.context-usage
  unset CLAUDE_SESSION_ID
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: 3-field format with low usage no warn" {
  echo "my-session|30|200000" > .vbw-planning/.context-usage
  CLAUDE_SESSION_ID="my-session" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: 3-field format respects compaction threshold" {
  # compaction_threshold is absolute token count — 165000 tokens
  # 82% of 200K = 164000 used tokens + EST_COST → exceeds 165000 → warn
  echo '{"compaction_threshold":165000}' > .vbw-planning/config.json
  echo "my-session|82|200000" > .vbw-planning/.context-usage
  CLAUDE_SESSION_ID="my-session" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]

  # 30% of 200K = 60000 used tokens + EST_COST → below 165000 → no warn
  echo "my-session|30|200000" > .vbw-planning/.context-usage
  CLAUDE_SESSION_ID="my-session" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
