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

# --- Mid-milestone auto_uat tests (issue #148) ---

@test "phase-detect has_unverified_phases=true mid-milestone when completed phase lacks UAT" {
  cd "$TEST_TEMP_DIR"
  # Phase 01 is fully built (from setup) with no UAT
  # Phase 02 still needs work (unplanned)
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-polish"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  # Phase state is NOT all_done (phase 02 needs work)
  [[ "$output" == *"next_phase_state=needs_plan_and_execute"* ]]
  # But unverified phases should still be detected
  [[ "$output" == *"has_unverified_phases=true"* ]]
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
  # Remediation stage should be removed
  [ ! -f "$dir/.uat-remediation-stage" ]
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

  # .uat-remediation-stage should be staged for deletion
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
