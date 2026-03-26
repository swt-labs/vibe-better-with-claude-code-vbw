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
  [ "$(grep -cF '/vbw:verify' <<< "$output")" -eq 0 ]
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
  [ "$(grep -cF '/vbw:verify' <<< "$output")" -eq 0 ]
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
  [ "$(grep -cF '/vbw:verify' <<< "$output")" -eq 0 ]
}

@test "suggest-next qa pass honors legacy PLAN.md and SUMMARY.md artifacts" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  rm -f "$dir/01-01-PLAN.md" "$dir/01-01-SUMMARY.md" "$dir/01-VERIFICATION.md"
  printf -- '---\nphase: 01\nplan: 01-legacy\ntitle: Setup\n---\n' > "$dir/PLAN.md"
  printf -- '---\nstatus: complete\ndeviations: 0\n---\nDone.\n' > "$dir/SUMMARY.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:verify"* ]]
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
  # auto_uat=true (from setup) + unverified → needs_verification overrides all_done
  [[ "$output" == *"next_phase_state=needs_verification"* ]]
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

# --- Mid-milestone auto_uat tests (issue #148) ---

@test "phase-detect has_unverified_phases=true mid-milestone when completed phase lacks UAT" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 is fully built (from setup) with no UAT
  # Phase 02 still needs work (unplanned)
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # auto_uat=true + unverified → needs_verification overrides needs_plan_and_execute
  [[ "$output" == *"next_phase_state=needs_verification"* ]]
  # Unverified phases still detected
  [[ "$output" == *"has_unverified_phases=true"* ]]
  # NEXT_PHASE points to the unverified phase, not the next unbuilt one
  [[ "$output" == *"next_phase=01"* ]]
  [[ "$output" == *"next_phase_slug=01-setup"* ]]
}

@test "phase-detect has_unverified_phases=false mid-milestone when completed phase has UAT" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 is fully built with UAT
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: passed\n---\nAll good.\n' > "$dir/01-UAT.md"
  # Phase 02 still needs work
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=needs_plan_and_execute"* ]]
  [[ "$output" == *"has_unverified_phases=false"* ]]
}

@test "phase-detect skips partially-built phase in unverified scan" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 has 2 plans but only 1 summary (partially built)
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nplan: 01-02\ntitle: More Setup\n---\n' > "$dir/01-02-PLAN.md"
  # 01-01 has a SUMMARY from setup(), 01-02 does not

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Phase 01 is partially built, should NOT be flagged as unverified
  [[ "$output" == *"has_unverified_phases=false"* ]]
}

# --- needs_verification state override tests (issue #270) ---

@test "phase-detect needs_verification override fires when auto_uat=true and has_unverified" {
  cd "$TEST_TEMP_DIR"
  # setup(): auto_uat=true, phase 01 fully built, no UAT
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=needs_verification"* ]]
  [[ "$output" == *"next_phase=01"* ]]
  [[ "$output" == *"next_phase_slug=01-setup"* ]]
}

@test "phase-detect needs_verification override does NOT fire when auto_uat=false" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.auto_uat = false' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Without auto_uat, should fall through to all_done (only phase is fully built)
  [[ "$output" == *"next_phase_state=all_done"* ]]
  [[ "$output" == *"has_unverified_phases=true"* ]]
}

@test "phase-detect needs_verification override does NOT preempt needs_reverification" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"
  printf 'done' > "$dir/.uat-remediation-stage"
  # Phase 02 fully built but no UAT → unverified
  local dir2="$TEST_TEMP_DIR/.vbw-planning/phases/02-feature"
  mkdir -p "$dir2"
  printf -- '---\nphase: 02\nplan: 02-01\ntitle: Feature\n---\n' > "$dir2/02-01-PLAN.md"
  printf -- '---\nstatus: complete\ndeviations: 0\n---\nDone.\n' > "$dir2/02-01-SUMMARY.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # needs_reverification should NOT be overridden by needs_verification
  [[ "$output" == *"next_phase_state=needs_reverification"* ]]
  [[ "$output" == *"has_unverified_phases=true"* ]]
}

@test "phase-detect needs_verification override does NOT preempt needs_uat_remediation" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"
  # No remediation stage → needs_uat_remediation
  # Phase 02 fully built but no UAT → unverified
  local dir2="$TEST_TEMP_DIR/.vbw-planning/phases/02-feature"
  mkdir -p "$dir2"
  printf -- '---\nphase: 02\nplan: 02-01\ntitle: Feature\n---\n' > "$dir2/02-01-PLAN.md"
  printf -- '---\nstatus: complete\ndeviations: 0\n---\nDone.\n' > "$dir2/02-01-SUMMARY.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # needs_uat_remediation should NOT be overridden
  [[ "$output" == *"next_phase_state=needs_uat_remediation"* ]]
  [[ "$output" == *"has_unverified_phases=true"* ]]
}

@test "suggest-next execute with auto_uat=true mid-milestone suppresses continue" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 completed with no UAT, Phase 02 needs work
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  # Should suggest verify
  [[ "$output" == *"/vbw:verify"* ]]
  # Should NOT suggest continuing to next phase when auto_uat wants verify first
  [ "$(grep -cF 'Continue to' <<< "$output")" -eq 0 ]
  [ "$(grep -cF 'next phase' <<< "$output")" -eq 0 ]
}

@test "suggest-next execute with auto_uat=false mid-milestone suggests continue not verify" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.auto_uat = false' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  # Phase 01 completed with no UAT, Phase 02 needs work (unplanned → active, plans=0)
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  # auto_uat=false: cross-phase unverified detection doesn't fire
  # Active phase (02) has 0 plans → active-phase verify path also doesn't fire
  # Should suggest continue only
  [ "$(grep -cF '/vbw:verify' <<< "$output")" -eq 0 ]
  [[ "$output" == *"/vbw:vibe"* ]]
}

# --- QA round 1 regression tests (issue #148) ---

@test "phase-detect treats UAT with draft status as unverified" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 is fully built (from setup), add UAT with draft status
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: draft\n---\nIn progress.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # UAT exists but is draft — should still be unverified
  [[ "$output" == *"has_unverified_phases=true"* ]]
}

@test "phase-detect treats UAT with complete status as verified" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: complete\n---\nAll passed.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has_unverified_phases=false"* ]]
}

@test "phase-detect treats UAT with issues_found status as verified" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\nIssues.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has_unverified_phases=false"* ]]
}

@test "suggest-next execute avoids dead-end when active phase has stale UAT" {
  cd "$TEST_TEMP_DIR"
  # Phase 01: fully built (from setup), no UAT → unverified
  # Phase 02: unbuilt but has stale UAT with status: complete
  local dir2="$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"
  mkdir -p "$dir2"
  printf -- '---\nphase: 02\nstatus: complete\n---\nStale UAT.\n' > "$dir2/02-UAT.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  # Must suggest verify (for unverified Phase 01) even though active Phase 02 has UAT
  [[ "$output" == *"/vbw:verify"* ]]
}

@test "suggest-next qa pass with auto_uat=true mid-milestone suppresses continue" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 completed with no UAT, Phase 02 needs work
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  # Should suggest verify
  [[ "$output" == *"/vbw:verify"* ]]
  # Should NOT suggest continuing to next phase
  [ "$(grep -cF 'Continue to' <<< "$output")" -eq 0 ]
  [ "$(grep -cF 'next phase' <<< "$output")" -eq 0 ]
}

@test "suggest-next qa pass with auto_uat=false mid-milestone suggests continue" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.auto_uat = false' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  # Should suggest continue (auto_uat off, no suppression)
  [[ "$output" == *"/vbw:vibe"* ]]
}

# --- QA round 2: has_uat with 'passed' status (finding #6) ---

@test "suggest-next qa pass with auto_uat=true skips verify when UAT has passed status" {
  cd "$TEST_TEMP_DIR"
  # Add UAT file with status: passed (not just complete)
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: passed\n---\nAll passed.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  # Should NOT suggest verify since UAT already exists and passed
  [ "$(grep -cF '/vbw:verify' <<< "$output")" -eq 0 ]
}

@test "suggest-next execute with auto_uat=true skips verify when UAT has passed status" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: passed\n---\nAll passed.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  # Should NOT suggest verify since UAT already exists and passed
  [ "$(grep -cF '/vbw:verify' <<< "$output")" -eq 0 ]
}

# --- QA round 3: frontmatter-scoped status parsing (finding #1) ---

@test "phase-detect detects body-only status: passed without frontmatter" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # UAT file with NO frontmatter — status: passed appears in body only
  printf 'UAT notes\nstatus: passed\nNo frontmatter above.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Body fallback detects status: passed → phase is verified
  [[ "$output" == *"has_unverified_phases=false"* ]]
}

@test "phase-detect reads status from frontmatter correctly" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # UAT file WITH proper frontmatter
  printf -- '---\nphase: 01\nstatus: passed\n---\nAll good.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has_unverified_phases=false"* ]]
}

@test "suggest-next detects body-only status: passed in UAT without frontmatter" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # UAT file with NO frontmatter — status line in body
  printf 'UAT notes\nstatus: passed\nNo frontmatter above.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  # Body fallback detects status: passed → no verify needed
  [ "$(grep -cF '/vbw:verify' <<< "$output")" -eq 0 ]
}

# --- QA round 3: cross-phase verify contradiction (finding #2) ---

@test "suggest-next qa pass no verify when prior phase verified and next unplanned" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 complete + passed UAT, Phase 02 unplanned
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: passed\n---\nAll good.\n' > "$dir/01-UAT.md"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  # has_unverified_phases=false, active phase is unplanned (plans=0)
  # Should NOT suggest verify — nothing to verify
  [ "$(grep -cF '/vbw:verify' <<< "$output")" -eq 0 ]
  # Should suggest continue to next phase
  [[ "$output" == *"/vbw:vibe"* ]]
}

@test "suggest-next execute no verify when prior phase verified and next unplanned" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: passed\n---\nAll good.\n' > "$dir/01-UAT.md"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  [ "$(grep -cF '/vbw:verify' <<< "$output")" -eq 0 ]
  [[ "$output" == *"/vbw:vibe"* ]]
}

# --- QA round 3: dual suggestion suppression in remediation (finding #3) ---

@test "suggest-next qa pass no verify when issues_found remediation active" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  # Should NOT suggest verify when remediation is active
  [ "$(grep -cF '/vbw:verify' <<< "$output")" -eq 0 ]
  # Should suggest remediation
  [[ "$output" == *"/vbw:vibe"* ]] || [[ "$output" == *"/vbw:fix"* ]]
}

@test "suggest-next execute no verify when issues_found remediation active" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  [ "$(grep -cF '/vbw:verify' <<< "$output")" -eq 0 ]
  [[ "$output" == *"/vbw:vibe"* ]] || [[ "$output" == *"/vbw:fix"* ]]
}

# --- QA round 3: status/resume auto-UAT alignment (finding #4) ---

@test "suggest-next status with auto_uat=true suggests verify when unverified phases exist" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 completed with no UAT → unverified, Phase 02 needs work
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" status

  [ "$status" -eq 0 ]
  # Should suggest verify instead of continue
  [[ "$output" == *"/vbw:verify"* ]]
  [ "$(grep -cF 'Continue' <<< "$output")" -eq 0 ]
}

@test "suggest-next resume with auto_uat=true suggests verify when unverified phases exist" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" resume

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:verify"* ]]
}

@test "suggest-next status with auto_uat=false suggests continue normally" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.auto_uat = false' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:vibe"* ]]
}

@test "suggest-next resume with auto_uat=false suggests continue normally" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.auto_uat = false' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" resume

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:vibe"* ]]
}

# --- QA round 4: discussion gate vs auto_uat priority (finding #1) ---

@test "suggest-next execute with auto_uat+discussion gate suggests verify not discuss" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '. + {auto_uat: true, require_phase_discussion: true}' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp" && mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  # Phase 01 completed (from setup), no UAT → unverified
  # Phase 02 unplanned → needs_discussion
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  # auto_uat verify should take priority over discussion
  [[ "$output" == *"/vbw:verify"* ]]
  # Should NOT suggest discuss (verify suppresses continue which would hit discuss)
  [ "$(grep -cF '/vbw:discuss' <<< "$output")" -eq 0 ]
}

# --- QA round 4: deviations frontmatter extraction (finding #2) ---

@test "suggest-next reads deviations from frontmatter only" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # SUMMARY with deviations in frontmatter AND body text with deviations
  printf -- '---\nstatus: complete\ndeviations: 0\n---\ndeviations: 5 from original plan\n' > "$dir/01-01-SUMMARY.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  # Should report zero deviations (frontmatter value), not body value
  [[ "$output" == *"zero deviations"* ]] || [ "$(grep -cF 'deviation(s)' <<< "$output")" -eq 0 ]
}

@test "suggest-next handles CRLF deviations in frontmatter" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # SUMMARY with CRLF line endings (deviations: 2\r\n)
  printf -- "---\r\nstatus: complete\r\ndeviations: 2\r\n---\r\nDone.\r\n" > "$dir/01-01-SUMMARY.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  # Should parse deviations correctly despite CRLF (AWK gsub strips trailing whitespace)
  [[ "$output" == *"2 deviation(s)"* ]]
}

# --- Remediation re-verification lifecycle tests ---

@test "phase-detect outputs needs_reverification when remediation stage=done" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # UAT with issues_found triggers remediation path
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"
  # Remediation is complete
  printf 'done' > "$dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=needs_reverification"* ]]
}

@test "phase-detect outputs needs_uat_remediation when stage != done" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"
  # Remediation in progress (plan stage — creating plans, not yet executing)
  printf 'plan' > "$dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=needs_uat_remediation"* ]]
}

@test "phase-detect outputs needs_uat_remediation when no stage file" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"
  # No .uat-remediation-stage file

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=needs_uat_remediation"* ]]
}

@test "phase-detect outputs first_unverified_phase and slug" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 from setup() has SUMMARY but no UAT → unverified
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first_unverified_phase=01"* ]]
  [[ "$output" == *"first_unverified_slug=01-setup"* ]]
}

@test "phase-detect first_unverified_phase skips verified phases" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 verified
  local dir1="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: passed\n---\nAll good.\n' > "$dir1/01-UAT.md"
  # Phase 02 fully built but unverified
  local dir2="$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"
  mkdir -p "$dir2"
  printf -- '---\nphase: 02\nplan: 02-01\ntitle: Polish\n---\n' > "$dir2/02-01-PLAN.md"
  printf -- '---\nstatus: complete\ndeviations: 0\n---\nDone.\n' > "$dir2/02-01-SUMMARY.md"
  printf -- '---\nphase: 02\nresult: pass\n---\nOK.\n' > "$dir2/02-VERIFICATION.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first_unverified_phase=02"* ]]
  [[ "$output" == *"first_unverified_slug=02-polish"* ]]
}

@test "phase-detect first_unverified_phase empty when all verified" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: passed\n---\nAll good.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first_unverified_phase="* ]]
  # Should NOT have a value
  local fup
  fup=$(echo "$output" | grep '^first_unverified_phase=' | head -1 | cut -d= -f2)
  [ -z "$fup" ]
}

# --- prepare-reverification.sh tests ---

@test "prepare-reverification archives UAT to round file" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\nIssues.\n' > "$dir/01-UAT.md"
  printf 'done' > "$dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$dir"
  [ "$status" -eq 0 ]
  # Original UAT should be gone
  [ ! -f "$dir/01-UAT.md" ]
  # Round file should exist
  [ -f "$dir/01-UAT-round-01.md" ]
  # Legacy state file should be removed
  [ ! -f "$dir/.uat-remediation-stage" ]
  # New-location state file should persist with advanced round
  [ -f "$dir/remediation/.uat-remediation-stage" ]
  grep -q 'round=02' "$dir/remediation/.uat-remediation-stage"
  # Output should confirm
  [[ "$output" == *"archived=01-UAT.md"* ]]
  [[ "$output" == *"round_file=01-UAT-round-01.md"* ]]
  [[ "$output" == *"phase=01"* ]]
}

@test "prepare-reverification increments round number" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\nIssues.\n' > "$dir/01-UAT.md"
  printf 'done' > "$dir/.uat-remediation-stage"
  # Pre-existing round files
  printf 'round 1\n' > "$dir/01-UAT-round-01.md"
  printf 'round 2\n' > "$dir/01-UAT-round-02.md"

  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$dir"
  [ "$status" -eq 0 ]
  [ -f "$dir/01-UAT-round-03.md" ]
  [[ "$output" == *"round_file=01-UAT-round-03.md"* ]]
  # State file should show advanced round (from legacy round=01 to round=02)
  [ -f "$dir/remediation/.uat-remediation-stage" ]
  grep -q 'stage=research' "$dir/remediation/.uat-remediation-stage"
}

@test "prepare-reverification is idempotent when no UAT exists (already archived)" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # Remove any UAT files (setup doesn't create one, but be explicit)
  rm -f "$dir"/[0-9]*-UAT.md

  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped=already_archived"* ]]
}

@test "prepare-reverification fails when UAT status is not issues_found" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: passed\n---\nAll good.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not 'issues_found'"* ]]
}

@test "prepare-reverification fails when phase dir does not exist" {
  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "/nonexistent/path"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "prepare-reverification pre-stages git changes when in a git repo" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-test@example.com"
  echo "seed" > README.md
  git add -A
  git commit -q -m "chore(init): seed"

  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\nIssues.\n' > "$dir/01-UAT.md"
  printf 'done' > "$dir/.uat-remediation-stage"
  git add "$dir/01-UAT.md" "$dir/.uat-remediation-stage"
  git commit -q -m "chore(phase): add UAT + stage file"

  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$dir"
  [ "$status" -eq 0 ]

  # Round file should be staged for addition
  run git diff --cached --name-only --diff-filter=A
  [[ "$output" == *"01-UAT-round-01.md"* ]]
  # New-location state file should be staged for addition (persists with updated round)
  [[ "$output" == *"remediation/.uat-remediation-stage"* ]]

  # Legacy .uat-remediation-stage should be staged for deletion
  run git diff --cached --name-only --diff-filter=D
  [[ "$output" == *".uat-remediation-stage"* ]]
}

# --- suggest-next needs_reverification routing tests ---

@test "suggest-next execute suggests re-verify when needs_reverification" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"
  printf 'done' > "$dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  # Should suggest re-verification
  [[ "$output" == *"Re-verify"* ]] || [[ "$output" == *"re-verify"* ]] || [[ "$output" == *"/vbw:verify"* ]]
}

@test "suggest-next qa pass suggests re-verify when needs_reverification" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"
  printf 'done' > "$dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  [[ "$output" == *"Re-verify"* ]] || [[ "$output" == *"re-verify"* ]] || [[ "$output" == *"/vbw:verify"* ]]
}

@test "suggest-next verify suggestions include phase number when first_unverified_phase set" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 unverified (from setup), phase 02 needs work
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/suggest-next.sh" execute pass

  [ "$status" -eq 0 ]
  # Should include phase number in verify suggestion
  [[ "$output" == *"/vbw:verify"* ]]
  # The phase number 01 should appear near the verify suggestion
  [[ "$output" == *"01"* ]]
}

# --- verify.md auto-detect fallback regression ---

@test "phase-detect auto-detect still works without reverification state" {
  cd "$TEST_TEMP_DIR"
  # Plain setup: phase 01 built, no UAT, no remediation
  # first_unverified_phase should be populated from scan
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first_unverified_phase=01"* ]]
  [[ "$output" == *"has_unverified_phases=true"* ]]
  # No reverification state
  [[ "$output" != *"needs_reverification"* ]]
}

@test "verify.md precomputed verify context prefers next_phase_slug during reverification" {
  local session="qa4-verify-context-$$"
  local link="/tmp/.vbw-plugin-root-link-$session"
  local cache="/tmp/.vbw-phase-detect-$session.txt"
  local plugin_root="$TEST_TEMP_DIR/plugin-root"
  local cmd

  mkdir -p "$plugin_root/scripts" "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup" "$TEST_TEMP_DIR/.vbw-planning/phases/02-feature"
  printf '%s\n' '#!/bin/bash' 'echo "verify_context=stub"' > "$plugin_root/scripts/compile-verify-context.sh"
  chmod +x "$plugin_root/scripts/compile-verify-context.sh"
  ln -s "$plugin_root" "$link"

  printf '%s\n' \
    'next_phase_state=needs_reverification' \
    'next_phase_slug=01-setup' \
    'first_unverified_slug=02-feature' > "$cache"

  cmd=$(awk '
    /^Pre-computed verify context \(PLAN\/SUMMARY aggregation\):$/ { in_block=1; next }
    in_block && /^!`/ {
      sub(/^!`/, "")
      sub(/`$/, "")
      print
      exit
    }
  ' "$PROJECT_ROOT/commands/verify.md")

  cd "$TEST_TEMP_DIR"
  run env CLAUDE_SESSION_ID="$session" bash -c "$cmd"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_target_slug=01-setup"* ]]

  rm -f "$link" "$cache"
}

@test "verify.md precomputed UAT resume prefers next_phase_slug during reverification" {
  local session="qa4-uat-resume-$$"
  local link="/tmp/.vbw-plugin-root-link-$session"
  local cache="/tmp/.vbw-phase-detect-$session.txt"
  local plugin_root="$TEST_TEMP_DIR/plugin-root-resume"
  local cmd

  mkdir -p "$plugin_root/scripts" "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup" "$TEST_TEMP_DIR/.vbw-planning/phases/02-feature"
  printf '%s\n' '#!/bin/bash' 'echo "uat_resume=stub"' > "$plugin_root/scripts/extract-uat-resume.sh"
  chmod +x "$plugin_root/scripts/extract-uat-resume.sh"
  ln -s "$plugin_root" "$link"

  printf '%s\n' \
    'next_phase_state=needs_reverification' \
    'next_phase_slug=01-setup' \
    'first_unverified_slug=02-feature' > "$cache"

  cmd=$(awk '
    /^Pre-computed UAT resume metadata:$/ { in_block=1; next }
    in_block && /^!`/ {
      sub(/^!`/, "")
      sub(/`$/, "")
      print
      exit
    }
  ' "$PROJECT_ROOT/commands/verify.md")

  cd "$TEST_TEMP_DIR"
  run env CLAUDE_SESSION_ID="$session" bash -c "$cmd"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_resume_target_slug=01-setup"* ]]

  rm -f "$link" "$cache"
}

# --- QA round 5 finding 1: status/resume prioritise reverification over remediation ---

@test "suggest-next status suggests re-verify not remediation when needs_reverification" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # UAT with issues_found (current_uat_issues_phase would be set)
  printf -- '---\nphase: 01\nstatus: issues_found\n---\nFailed tests.\n' > "$dir/01-UAT.md"
  # Remediation done → needs_reverification
  printf 'done' > "$dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/suggest-next.sh" status

  [ "$status" -eq 0 ]
  # Should suggest re-verify, NOT the remediation action
  [[ "$output" == *"Re-verify"* ]] || [[ "$output" == *"re-verify"* ]]
  [ "$(grep -cF 'Remediate UAT' <<< "$output")" -eq 0 ]
}

@test "suggest-next resume suggests re-verify not remediation when needs_reverification" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\nFailed tests.\n' > "$dir/01-UAT.md"
  printf 'done' > "$dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/suggest-next.sh" resume

  [ "$status" -eq 0 ]
  [[ "$output" == *"Re-verify"* ]] || [[ "$output" == *"re-verify"* ]]
  [ "$(grep -cF 'Remediate UAT' <<< "$output")" -eq 0 ]
}

# --- QA round 5 finding 2: prepare-reverification.sh stage guard ---

@test "prepare-reverification refuses when remediation stage not done" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\nFailed.\n' > "$dir/01-UAT.md"
  # Stage is execute (not done)
  printf 'execute' > "$dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$dir"

  [ "$status" -ne 0 ]
  [[ "$output" == *"remediation still in progress"* ]]
}

@test "prepare-reverification refuses when no stage file exists" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\nFailed.\n' > "$dir/01-UAT.md"
  # No .uat-remediation-stage file

  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$dir"

  [ "$status" -ne 0 ]
  [[ "$output" == *"remediation still in progress"* ]]
}

@test "prepare-reverification succeeds when stage is done" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\nFailed.\n' > "$dir/01-UAT.md"
  printf 'done' > "$dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$dir"

  [ "$status" -eq 0 ]
  # Old UAT should be archived
  [ ! -f "$dir/01-UAT.md" ]
  # Round file should exist
  ls "$dir"/01-UAT-round-*.md 2>/dev/null | grep -q .
  # New-location state file should persist with advanced round
  [ -f "$dir/remediation/.uat-remediation-stage" ]
  grep -q 'stage=research' "$dir/remediation/.uat-remediation-stage"
}

# --- QA round 6: body-fallback tightening (finding #1) ---

@test "phase-detect body-fallback ignores indented status lines" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # UAT file with NO frontmatter — only indented status: line (should NOT match)
  printf '## Issue Details\n  status: needs_review\nThe component works.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Indented status: should NOT be detected → phase is unverified
  [[ "$output" == *"has_unverified_phases=true"* ]]
}

@test "phase-detect body-fallback matches unindented status line" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # UAT file with NO frontmatter — unindented status: line (body fallback)
  printf 'status: passed\nAll tests pass.\n' > "$dir/01-UAT.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has_unverified_phases=false"* ]]
}

# --- QA round 6: has_uat excludes SOURCE-UAT (finding #10) ---

@test "suggest-next has_uat ignores SOURCE-UAT.md files" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # Only a SOURCE-UAT with passed status (not a real UAT)
  printf -- '---\nstatus: passed\n---\nAll good.\n' > "$dir/01-SOURCE-UAT.md"

  run bash "$SCRIPTS_DIR/suggest-next.sh" qa pass

  [ "$status" -eq 0 ]
  # SOURCE-UAT should NOT satisfy has_uat → verify should still be suggested
  [[ "$output" == *"/vbw:verify"* ]]
}

# --- QA round 6: prepare-reverification double-run idempotency (finding #9) ---

@test "prepare-reverification double-run is idempotent" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\nIssues.\n' > "$dir/01-UAT.md"
  printf 'done' > "$dir/.uat-remediation-stage"

  # First run: archives the UAT
  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"archived=01-UAT.md"* ]]
  [ -f "$dir/01-UAT-round-01.md" ]
  [ ! -f "$dir/01-UAT.md" ]

  # Second run: should exit 0 with skip marker (no UAT to archive)
  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped=already_archived"* ]]
}

# --- QA round 2: reverification preempts mid-milestone auto_uat (finding #7) ---

@test "phase-detect: needs_reverification preempts has_unverified_phases" {
  cd "$TEST_TEMP_DIR"
  # Phase 1: issues_found + remediation done → needs_reverification
  local dir1="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nstatus: issues_found\n---\nIssues.\n' > "$dir1/01-UAT.md"
  printf 'done' > "$dir1/.uat-remediation-stage"

  # Phase 2: fully built, no UAT → unverified
  local dir2="$TEST_TEMP_DIR/.vbw-planning/phases/02-feature"
  mkdir -p "$dir2"
  printf -- '---\nplan: 02-01\ntitle: Feature\n---\n' > "$dir2/02-01-PLAN.md"
  printf -- '---\nstatus: complete\ndeviations: 0\n---\nDone.\n' > "$dir2/02-01-SUMMARY.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # P4 (needs_reverification) must fire, not P7 (auto_uat + has_unverified)
  [[ "$output" == *"next_phase_state=needs_reverification"* ]]
  [[ "$output" == *"has_unverified_phases=true"* ]]
  # The target phase should be 01-setup (reverification target), not 02-feature
  [[ "$output" == *"next_phase_slug=01-setup"* ]]
}

# --- Round archival consistency (phase-detect + prepare-reverification agree) ---

@test "prepare-reverification and phase-detect agree on round count" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"

  # Create 3 archived round files
  printf 'round 1\n' > "$dir/01-UAT-round-01.md"
  printf 'round 2\n' > "$dir/01-UAT-round-02.md"
  printf 'round 3\n' > "$dir/01-UAT-round-03.md"

  # Active UAT with issues + remediation done
  printf -- '---\nphase: 01\nstatus: issues_found\n---\nIssues.\n' > "$dir/01-UAT.md"
  printf 'done' > "$dir/.uat-remediation-stage"

  # phase-detect should report count=3
  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_round_count=3"* ]]

  # prepare-reverification should create round-04 (3 + 1)
  run bash "$SCRIPTS_DIR/prepare-reverification.sh" "$dir"
  [ "$status" -eq 0 ]
  [ -f "$dir/01-UAT-round-04.md" ]
  [[ "$output" == *"round_file=01-UAT-round-04.md"* ]]
}

# --- QA round 1 #255: in-progress remediation summary must not auto-advance ---

@test "phase-detect does not auto-advance when remediation summary is in-progress" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  # UAT with issues triggers remediation path
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"
  # Remediation round-01 in execute stage with round-dir layout
  mkdir -p "$dir/remediation"
  printf 'stage=execute\nround=01\nlayout=round-dir\n' > "$dir/remediation/.uat-remediation-stage"
  # Round-01 has PLAN and an in-progress SUMMARY (not terminal)
  mkdir -p "$dir/remediation/round-01"
  printf -- '---\nphase: 1\nround: 01\ntitle: Fix bugs\ntype: remediation\n---\n' > "$dir/remediation/round-01/R01-PLAN.md"
  printf -- '---\nstatus: in-progress\ntasks_completed: 1\ntasks_total: 5\n---\n\n## Task 1: Done\n' > "$dir/remediation/round-01/R01-SUMMARY.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Must NOT advance to needs_reverification — summary is not terminal
  [[ "$output" == *"next_phase_state=needs_uat_remediation"* ]]
}

@test "phase-detect auto-advances when remediation summary has terminal status" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"
  mkdir -p "$dir/remediation"
  printf 'stage=execute\nround=01\nlayout=round-dir\n' > "$dir/remediation/.uat-remediation-stage"
  mkdir -p "$dir/remediation/round-01"
  printf -- '---\nphase: 1\nround: 01\ntitle: Fix bugs\ntype: remediation\n---\n' > "$dir/remediation/round-01/R01-PLAN.md"
  printf -- '---\nstatus: complete\ntasks_completed: 5\ntasks_total: 5\n---\n\nAll done.\n' > "$dir/remediation/round-01/R01-SUMMARY.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Terminal status — should advance
  [[ "$output" == *"next_phase_state=needs_reverification"* ]]
}

@test "phase-detect auto-advances when remediation summary has partial status" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"
  mkdir -p "$dir/remediation"
  printf 'stage=execute\nround=01\nlayout=round-dir\n' > "$dir/remediation/.uat-remediation-stage"
  mkdir -p "$dir/remediation/round-01"
  printf -- '---\nphase: 1\nround: 01\ntitle: Fix bugs\ntype: remediation\n---\n' > "$dir/remediation/round-01/R01-PLAN.md"
  printf -- '---\nstatus: partial\ntasks_completed: 3\ntasks_total: 5\n---\n\nPartial.\n' > "$dir/remediation/round-01/R01-SUMMARY.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=needs_reverification"* ]]
}

@test "phase-detect auto-advances when remediation summary has failed status" {
  cd "$TEST_TEMP_DIR"
  local dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  printf -- '---\nphase: 01\nstatus: issues_found\n---\n- Severity: major\n' > "$dir/01-UAT.md"
  mkdir -p "$dir/remediation"
  printf 'stage=execute\nround=01\nlayout=round-dir\n' > "$dir/remediation/.uat-remediation-stage"
  mkdir -p "$dir/remediation/round-01"
  printf -- '---\nphase: 1\nround: 01\ntitle: Fix bugs\ntype: remediation\n---\n' > "$dir/remediation/round-01/R01-PLAN.md"
  printf -- '---\nstatus: failed\ntasks_completed: 0\ntasks_total: 5\n---\n\nFailed.\n' > "$dir/remediation/round-01/R01-SUMMARY.md"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=needs_reverification"* ]]
}

# --- Contract: UAT inline execution prohibition (issue #273) ---

@test "vibe.md Verify mode contains inline execution prohibition" {
  local vibe="$BATS_TEST_DIRNAME/../commands/vibe.md"
  # Verify mode must explicitly prohibit subagent delegation
  grep -q "Do NOT spawn a QA agent" "$vibe"
  grep -q "Do NOT use TaskCreate to delegate UAT" "$vibe"
  grep -q "AskUserQuestion tool is only available to the orchestrator" "$vibe"
}

@test "vibe.md needs_verification routing note mentions inline execution" {
  local vibe="$BATS_TEST_DIRNAME/../commands/vibe.md"
  # The routing note after the priority table must reinforce inline execution
  grep -q "do NOT spawn a QA agent or any subagent for UAT" "$vibe"
}

@test "execute-protocol.md Step 4.5 contains subagent prohibition" {
  local proto="$BATS_TEST_DIRNAME/../references/execute-protocol.md"
  # Step 4.5 must prohibit subagent delegation for UAT
  grep -q "Do NOT spawn a QA agent" "$proto"
  grep -q "this is NOT a subagent operation" "$proto"
  grep -q "AskUserQuestion tool is only available to the orchestrator" "$proto"
}

@test "verify.md has AskUserQuestion in allowed-tools" {
  local verify="$BATS_TEST_DIRNAME/../commands/verify.md"
  # verify.md MUST have AskUserQuestion — this is what enables interactive UAT
  grep -q "AskUserQuestion" "$verify"
}

@test "vbw-qa.md does NOT have AskUserQuestion in tools" {
  local qa="$BATS_TEST_DIRNAME/../agents/vbw-qa.md"
  # QA agent must NOT have AskUserQuestion — it cannot interact with the user
  # This is the architectural reason UAT cannot be delegated to QA
  ! grep -q "AskUserQuestion" "$qa"
}

# --- Contract: UAT automated-check prohibition (issue #274) ---

@test "execute-protocol.md Step 4.5 prohibits automated checks in UAT" {
  local proto="$BATS_TEST_DIRNAME/../references/execute-protocol.md"
  # Must prohibit grep/file-check/test-suite type UAT tests
  grep -q "NEVER generate tests that can be performed programmatically" "$proto"
  grep -q "Grep/search files for expected content" "$proto"
  grep -q "Verify file existence" "$proto"
  grep -q "Run a test suite" "$proto"
}

@test "verify.md Step 4 prohibits automated checks in UAT" {
  local verify="$BATS_TEST_DIRNAME/../commands/verify.md"
  # Must prohibit automated checks
  grep -q "NEVER generate tests that ask the user to run automated checks" "$verify"
  grep -q "Grepping files for expected content" "$verify"
  grep -q "Verifying file existence" "$verify"
}

@test "execute-protocol.md Step 4.5 has skill-aware exclusion" {
  local proto="$BATS_TEST_DIRNAME/../references/execute-protocol.md"
  # Must account for skill/tool/MCP-based UI automation
  grep -q "Skill-aware exclusion" "$proto"
  grep -q "UI automation capabilities" "$proto"
  grep -q "MCP server" "$proto"
}

@test "verify.md Step 4 has skill-aware exclusion" {
  local verify="$BATS_TEST_DIRNAME/../commands/verify.md"
  # Must account for skill/tool/MCP-based UI automation
  grep -q "Skill-aware exclusion" "$verify"
  grep -q "UI automation capabilities" "$verify"
  grep -q "MCP server" "$verify"
}

# --- UAT format and lifecycle contract tests ---

@test "verify.md enforces exact Result field values" {
  local verify="$BATS_TEST_DIRNAME/../commands/verify.md"
  # Must enforce exactly pass/skip/issue (lowercase)
  grep -q 'MUST be exactly one of three lowercase values' "$verify" || \
    grep -q 'MUST be exactly.*pass.*skip.*issue' "$verify"
  # Must prohibit FAIL, PARTIAL, PASS values
  grep -q 'Never write.*FAIL.*PARTIAL' "$verify"
}

@test "verify.md Step 9 calls finalize-uat-status.sh" {
  local verify="$BATS_TEST_DIRNAME/../commands/verify.md"
  # Must call the finalize script instead of relying on LLM instruction
  grep -q "finalize-uat-status.sh" "$verify"
  grep -q "script is the source of truth" "$verify"
}

@test "finalize-uat-status.sh exists and is executable" {
  local script="$BATS_TEST_DIRNAME/../scripts/finalize-uat-status.sh"
  [ -f "$script" ]
  [ -x "$script" ]
}

@test "vibe.md UAT Remediation chains into re-verification after execute" {
  local vibe="$BATS_TEST_DIRNAME/../commands/vibe.md"
  # Must call prepare-reverification.sh after execute stage
  grep -q "prepare-reverification.sh" "$vibe"
  # Must continue directly into Verify mode
  grep -q "Continue directly into Verify mode" "$vibe"
  # Must NOT just suggest /vbw:vibe
  grep -q "Chain into re-verification (NON-NEGOTIABLE)" "$vibe"
}

@test "extract-uat-issues.sh accepts FAIL and PARTIAL Result values" {
  local script="$BATS_TEST_DIRNAME/../scripts/extract-uat-issues.sh"
  # The AWK parser must handle issue/fail/failed/partial
  grep -q 'issue|fail|failed|partial' "$script"
}

@test "verify.md writes stage=verified instead of deleting state file" {
  local verify="$BATS_TEST_DIRNAME/../commands/verify.md"
  # Must write stage=verified for successful re-verification
  grep -q 'stage=verified' "$verify"
  # Must NOT delete the state file (rm deletes it, breaking current_uat())
  ! grep -q 'rm "$_state_file"' "$verify"
}

@test "vibe.md re-verification chain has error guard for prepare-reverification" {
  local vibe="$BATS_TEST_DIRNAME/../commands/vibe.md"
  # Both call sites must check for script failure:
  # 1. Execute→verify chain (in UAT Remediation mode)
  # 2. State routing path (needs_reverification priority)
  local guard_count
  guard_count=$(grep -c 'Error guard.*script fails\|non-zero exit.*STOP' "$vibe")
  [ "$guard_count" -ge 2 ]
}

@test "uat-utils.sh extract_round_issue_ids matches lenient Result values" {
  local utils="$BATS_TEST_DIRNAME/../scripts/uat-utils.sh"
  # Must use lenient matching (issue|fail|failed|partial), not just literal "issue"
  grep -q 'issue|fail|failed|partial' "$utils"
}
