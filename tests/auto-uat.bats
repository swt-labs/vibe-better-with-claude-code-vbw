#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  # Enable auto_uat in config
  local tmp
  tmp=$(mktemp)
  jq '. + {auto_uat: true}' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  # Create a fully-built phase with QA pass
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  mkdir -p "$dir"
  printf -- '---\nphase: 01\nplan: 01-01\ntitle: Setup\n---\n' > "$dir/01-01-PLAN.md"
  printf -- '---\nstatus: complete\ndeviations: 0\n---\nDone.\n' > "$dir/01-01-SUMMARY.md"
  printf -- '---\nphase: 01\nresult: pass\n---\nAll checks passed.\n' > "$dir/01-VERIFICATION.md"

  # PROJECT.md so has_project=true
  printf '# Project\nReal project content\n' > "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"
}

teardown() {
  teardown_temp_dir
}

@test "suggest-next qa pass with auto_uat=true always suggests verify" {
  cd "$TEST_TEMP_DIR"
  # Set autonomy to confident (normally suppresses UAT suggestion)
  local tmp
  tmp=$(mktemp)
  jq '.autonomy = "confident"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:verify"* ]]
}

@test "suggest-next qa pass with auto_uat=true suggests verify even at pure-vibe" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.autonomy = "pure-vibe"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:verify"* ]]
}

@test "suggest-next qa pass with auto_uat=false at confident does not suggest verify" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.auto_uat = false | .autonomy = "confident"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  [[ "$output" != *"/vbw:verify"* ]]
}

@test "suggest-next execute with auto_uat=true suggests verify even at confident" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.autonomy = "confident"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:verify"* ]]
}

@test "suggest-next execute with auto_uat=false at confident does not suggest verify" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.auto_uat = false | .autonomy = "confident"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  [[ "$output" != *"/vbw:verify"* ]]
}

@test "auto_uat defaults.json has auto_uat key set to false" {
  run jq -r '.auto_uat' "$CONFIG_DIR/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "migration adds auto_uat for brownfield config" {
  # Create config without auto_uat
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "autonomy": "standard"
}
EOF

  bash "$SCRIPTS_DIR/migrate-config.sh" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run jq -r '.auto_uat' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "migration preserves existing auto_uat=true" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "auto_uat": true
}
EOF

  bash "$SCRIPTS_DIR/migrate-config.sh" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run jq -r '.auto_uat' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "suggest-next qa pass with auto_uat=true skips verify when UAT already exists" {
  cd "$TEST_TEMP_DIR"
  # Add UAT file to the phase
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: complete\n---\nAll passed.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  # Should NOT suggest verify since UAT already exists and completed
  [[ "$output" != *"/vbw:verify"* ]]
}

# --- phase-detect auto_uat + has_unverified_phases tests ---

@test "phase-detect outputs config_auto_uat=true when set" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"config_auto_uat=true"* ]]
}

@test "phase-detect outputs config_auto_uat=false when not set" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.auto_uat = false' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"config_auto_uat=false"* ]]
}

@test "phase-detect has_unverified_phases=true when phase has SUMMARY but no UAT" {
  cd "$TEST_TEMP_DIR"
  # setup() already creates 01-setup with SUMMARY but no UAT
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=all_done"* ]]
  [[ "$output" == *"has_unverified_phases=true"* ]]
}

@test "phase-detect has_unverified_phases=false when all phases have UAT" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: passed\n---\nAll good.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=all_done"* ]]
  [[ "$output" == *"has_unverified_phases=false"* ]]
}

@test "phase-detect has_unverified_phases ignores SOURCE-UAT files" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # Only a SOURCE-UAT file exists (not a real UAT)
  printf -- '---\nstatus: issues_found\n---\nIssues.\n' > "$dir/01-SOURCE-UAT.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has_unverified_phases=true"* ]]
}
