#!/usr/bin/env bats
# Tests for organize-wave-structure.sh and migrate-legacy-layout.sh
# Covers: wave assignment, P-prefix renaming, summary co-location,
#         remediation round migration, idempotency, plan-number arithmetic,
#         edge cases (wave=0, non-numeric wave, gaps in plan numbering).

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

# ===========================================================================
# organize-wave-structure.sh
# ===========================================================================

@test "organize-wave: moves flat plan into wave subdir with P-prefix" {
  local phase_dir=".vbw-planning/phases/03-build"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 1
---
# Plan 1
EOF

  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  # Original file should be gone
  [ ! -f "$phase_dir/01-PLAN.md" ]
  # New file should exist in wave dir
  [ -f "$phase_dir/P03-01-wave/P03-W01-01-PLAN.md" ]
}

@test "organize-wave: co-locates matching summary with plan in wave dir" {
  local phase_dir=".vbw-planning/phases/02-design"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 1
---
# Plan
EOF
  cat > "$phase_dir/01-SUMMARY.md" <<'EOF'
---
status: complete
---
# Summary
EOF

  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [ -f "$phase_dir/P02-01-wave/P02-W01-01-PLAN.md" ]
  [ -f "$phase_dir/P02-01-wave/P02-W01-01-SUMMARY.md" ]
  [ ! -f "$phase_dir/01-SUMMARY.md" ]
}

@test "organize-wave: co-locates NN-MM-SUMMARY.md format" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 2
---
EOF
  cat > "$phase_dir/01-01-SUMMARY.md" <<'EOF'
---
status: partial
---
EOF

  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [ -f "$phase_dir/P01-02-wave/P01-W02-01-PLAN.md" ]
  [ -f "$phase_dir/P01-02-wave/P01-W02-01-SUMMARY.md" ]
}

@test "organize-wave: groups multiple plans into same wave dir" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  for mm in 01 02 03; do
    cat > "$phase_dir/${mm}-PLAN.md" <<EOF
---
wave: 1
---
# Plan $mm
EOF
  done

  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [ -d "$phase_dir/P01-01-wave" ]
  [ -f "$phase_dir/P01-01-wave/P01-W01-01-PLAN.md" ]
  [ -f "$phase_dir/P01-01-wave/P01-W01-02-PLAN.md" ]
  [ -f "$phase_dir/P01-01-wave/P01-W01-03-PLAN.md" ]
}

@test "organize-wave: separates plans into different wave dirs" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 1
---
EOF
  cat > "$phase_dir/02-PLAN.md" <<'EOF'
---
wave: 2
---
EOF

  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [ -f "$phase_dir/P01-01-wave/P01-W01-01-PLAN.md" ]
  [ -f "$phase_dir/P01-02-wave/P01-W02-02-PLAN.md" ]
}

@test "organize-wave: defaults missing wave frontmatter to wave 1" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
title: No wave field
---
EOF

  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [ -f "$phase_dir/P01-01-wave/P01-W01-01-PLAN.md" ]
}

@test "organize-wave: non-numeric wave value defaults to 1 with warning" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: TBD
---
EOF

  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: non-numeric wave"* ]]
  [ -f "$phase_dir/P01-01-wave/P01-W01-01-PLAN.md" ]
}

@test "organize-wave: wave=0 defaults to 1 with warning" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 0
---
EOF

  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: wave value"* ]]
  [ -f "$phase_dir/P01-01-wave/P01-W01-01-PLAN.md" ]
  # Should NOT create W00 dir
  [ ! -d "$phase_dir/P01-00-wave" ]
}

@test "organize-wave: renames phase-root files to P-prefix" {
  local phase_dir=".vbw-planning/phases/05-deploy"
  mkdir -p "$phase_dir"
  echo "# Context" > "$phase_dir/05-CONTEXT.md"
  echo "# Research" > "$phase_dir/05-RESEARCH.md"
  echo "# Verification" > "$phase_dir/05-VERIFICATION.md"
  echo "# UAT" > "$phase_dir/05-UAT.md"
  # Need at least one plan to trigger organization
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 1
---
EOF

  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [ -f "$phase_dir/P05-CONTEXT.md" ]
  [ -f "$phase_dir/P05-RESEARCH.md" ]
  [ -f "$phase_dir/P05-VERIFICATION.md" ]
  [ -f "$phase_dir/P05-UAT.md" ]
  [ ! -f "$phase_dir/05-CONTEXT.md" ]
}

@test "organize-wave: idempotent — skips already-organized files" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir/P01-01-wave"
  cat > "$phase_dir/P01-01-wave/P01-W01-01-PLAN.md" <<'EOF'
---
wave: 1
---
EOF

  # No flat plan files → nothing to organize, should exit cleanly
  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [ -f "$phase_dir/P01-01-wave/P01-W01-01-PLAN.md" ]
}

@test "organize-wave: skips remediation NN-MM-PLAN.md files" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  # Initial plan
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 1
---
EOF
  # Remediation plan (two-number prefix) — should NOT be organized into waves
  cat > "$phase_dir/01-02-PLAN.md" <<'EOF'
---
phase: 01
plan: 02
---
EOF

  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  # Initial plan moved
  [ -f "$phase_dir/P01-01-wave/P01-W01-01-PLAN.md" ]
  # Remediation plan left in place
  [ -f "$phase_dir/01-02-PLAN.md" ]
}

@test "organize-wave: no-op on empty phase dir" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"

  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "$phase_dir"
  [ "$status" -eq 0 ]
}

@test "organize-wave: no-op on nonexistent dir" {
  run bash "$SCRIPTS_DIR/organize-wave-structure.sh" "/nonexistent/path"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# migrate-legacy-layout.sh
# ===========================================================================

@test "migrate-legacy: organizes initial plans into waves" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 1
---
# Plan
EOF

  run bash "$SCRIPTS_DIR/migrate-legacy-layout.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [ -f "$phase_dir/P01-01-wave/P01-W01-01-PLAN.md" ]
}

@test "migrate-legacy: migrates remediation artifacts into round dirs" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  # Initial plans
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 1
---
EOF
  echo "---\nstatus: complete\n---" > "$phase_dir/01-SUMMARY.md"
  # Remediation plan (plan 02 = initial_count(1) + round(1))
  cat > "$phase_dir/01-02-PLAN.md" <<'EOF'
---
phase: 01
plan: 02
---
# Remediation
EOF
  echo "---\nstatus: partial\n---" > "$phase_dir/01-02-SUMMARY.md"
  # UAT round file and stage file
  echo "# UAT Round 1" > "$phase_dir/01-UAT-round-1.md"
  echo "needs-round" > "$phase_dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/migrate-legacy-layout.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  # Round dir should exist with migrated files
  [ -d "$phase_dir/remediation/P01-01-round" ]
  [ -f "$phase_dir/remediation/P01-01-round/P01-R01-UAT.md" ]
  # Stage file should be moved
  [ ! -f "$phase_dir/.uat-remediation-stage" ]
  [ -f "$phase_dir/remediation/.uat-remediation-stage" ]
  grep -q "stage=needs-round" "$phase_dir/remediation/.uat-remediation-stage"
  grep -q "round=01" "$phase_dir/remediation/.uat-remediation-stage"
}

@test "migrate-legacy: plan-number uses max(existing) not count to avoid gaps" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  # Plans with a gap: 01 and 03, missing 02
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 1
---
EOF
  cat > "$phase_dir/03-PLAN.md" <<'EOF'
---
wave: 1
---
EOF
  # Remediation plan at offset max(1,3)+1=4
  cat > "$phase_dir/01-04-PLAN.md" <<'EOF'
---
phase: 01
plan: 04
---
EOF
  echo "# UAT Round 1" > "$phase_dir/01-UAT-round-1.md"
  echo "needs-round" > "$phase_dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/migrate-legacy-layout.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  # Round dir should exist
  [ -d "$phase_dir/remediation/P01-01-round" ]
  # It should look for plan_mm=04 (max(3)+1), not 03 (count(2)+1)
  [ -f "$phase_dir/remediation/P01-01-round/P01-R01-PLAN.md" ]
}

@test "migrate-legacy: idempotent — skips already-migrated phase" {
  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  echo "01-setup migrated 2026-01-01T00:00:00Z" > "$TEST_TEMP_DIR/.vbw-planning/.layout-v2-migrated"

  run bash "$SCRIPTS_DIR/migrate-legacy-layout.sh" "$phase_dir"
  [ "$status" -eq 0 ]
}

@test "migrate-legacy: resumes interrupted migration (in-progress marker)" {
  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  # Simulate interrupted migration: in-progress marker but no round dirs
  echo "01-setup in-progress 2026-01-01T00:00:00Z" > "$TEST_TEMP_DIR/.vbw-planning/.layout-v2-migrated"
  echo "# UAT Round 1" > "$phase_dir/01-UAT-round-1.md"
  echo "needs-round" > "$phase_dir/.uat-remediation-stage"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 1
---
EOF

  run bash "$SCRIPTS_DIR/migrate-legacy-layout.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  # Should complete the migration
  [ -d "$phase_dir/remediation/P01-01-round" ]
  # Marker should be updated to 'migrated'
  grep -q "01-setup migrated" "$TEST_TEMP_DIR/.vbw-planning/.layout-v2-migrated"
  # In-progress line should be removed
  ! grep -q "01-setup in-progress" "$TEST_TEMP_DIR/.vbw-planning/.layout-v2-migrated"
}

@test "migrate-legacy: multi-round migration creates correct round dirs" {
  local phase_dir=".vbw-planning/phases/02-build"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 1
---
EOF
  # Two rounds of remediation
  echo "# UAT R1" > "$phase_dir/02-UAT-round-1.md"
  echo "# UAT R2" > "$phase_dir/02-UAT-round-2.md"
  echo "done" > "$phase_dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/migrate-legacy-layout.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [ -d "$phase_dir/remediation/P02-01-round" ]
  [ -d "$phase_dir/remediation/P02-02-round" ]
  [ -f "$phase_dir/remediation/P02-01-round/P02-R01-UAT.md" ]
  [ -f "$phase_dir/remediation/P02-02-round/P02-R02-UAT.md" ]
}

@test "migrate-legacy: removes SOURCE-UAT files" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 1
---
EOF
  echo "# Source UAT" > "$phase_dir/01-SOURCE-UAT.md"
  echo "# UAT R1" > "$phase_dir/01-UAT-round-1.md"
  echo "done" > "$phase_dir/.uat-remediation-stage"

  run bash "$SCRIPTS_DIR/migrate-legacy-layout.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [ ! -f "$phase_dir/01-SOURCE-UAT.md" ]
}

@test "migrate-legacy: exits 1 for nonexistent dir" {
  run bash "$SCRIPTS_DIR/migrate-legacy-layout.sh" "/nonexistent/path"
  [ "$status" -eq 1 ]
}

@test "migrate-legacy: no remediation — only organizes waves" {
  local phase_dir=".vbw-planning/phases/01-setup"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'EOF'
---
wave: 2
---
EOF

  run bash "$SCRIPTS_DIR/migrate-legacy-layout.sh" "$phase_dir"
  [ "$status" -eq 0 ]
  [ -f "$phase_dir/P01-02-wave/P01-W02-01-PLAN.md" ]
  [ ! -d "$phase_dir/remediation" ]
}

# ===========================================================================
# frontmatter_scalar_value — indented key guard (F5)
# ===========================================================================

@test "frontmatter_scalar_value: rejects indented sub-keys" {
  source "$SCRIPTS_DIR/summary-utils.sh"
  local tmpf
  tmpf=$(mktemp)
  cat > "$tmpf" <<'EOF'
---
metadata:
  phase: 99
phase: 3
---
EOF
  result=$(frontmatter_scalar_value "$tmpf" phase)
  rm -f "$tmpf"
  # Should return 3 (top-level), not 99 (indented sub-key)
  [ "$result" = "3" ]
}

@test "frontmatter_scalar_value: normal top-level key works" {
  source "$SCRIPTS_DIR/summary-utils.sh"
  local tmpf
  tmpf=$(mktemp)
  cat > "$tmpf" <<'EOF'
---
phase: 5
plan: 2
title: Test
---
EOF
  phase=$(frontmatter_scalar_value "$tmpf" phase)
  plan=$(frontmatter_scalar_value "$tmpf" plan)
  rm -f "$tmpf"
  [ "$phase" = "5" ]
  [ "$plan" = "2" ]
}

# ===========================================================================
# Inline fallback plan_contract_numbers — frontmatter-first (F1)
# ===========================================================================

@test "hard-gate fallback plan_contract_numbers: uses frontmatter over filename" {
  # Extract just the fallback functions from hard-gate.sh (the else branch)
  local plan_dir
  plan_dir=$(mktemp -d)
  cat > "$plan_dir/P01-R01-PLAN.md" <<'EOF'
---
phase: 01
plan: 03
title: Remediation
---
EOF

  # Define the inline fallback functions directly (mirrors hard-gate.sh else branch)
  result=$(bash -c '
    _hg_frontmatter_scalar() {
      local f="$1" key="$2"
      [ -f "$f" ] || return 0
      awk -v key="$key" '\''
        BEGIN { in_fm=0 }
        NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
        in_fm && /^---[[:space:]]*$/ { exit }
        in_fm && /^[^[:space:]]/ && $0 ~ key ":[[:space:]]*" {
          line = $0; sub(key ":[[:space:]]*", "", line); print line; exit
        }
      '\'' "$f" 2>/dev/null | sed "s/^[\"'"'"']//; s/[\"'"'"']$//" || true
    }
    plan_contract_numbers() {
      local plan_file="$1"
      local basename phase plan
      basename=$(basename "$plan_file" 2>/dev/null) || basename="$plan_file"
      phase=$(_hg_frontmatter_scalar "$plan_file" phase)
      plan=$(_hg_frontmatter_scalar "$plan_file" plan)
      if [ -z "$phase" ]; then
        case "$basename" in
          P[0-9]*-R[0-9]*-*|P[0-9]*-W[0-9]*-*) phase=$(echo "$basename" | sed "s/^P\([0-9]*\)-.*/\1/") ;;
          *) phase=$(echo "$basename" | sed "s/^\([0-9]*\)-.*/\1/") ;;
        esac
      fi
      if [ -z "$plan" ]; then
        case "$basename" in
          P[0-9]*-R[0-9]*-*) plan=$(echo "$basename" | sed "s/^P[0-9]*-R\([0-9]*\)-.*/\1/") ;;
          P[0-9]*-W[0-9]*-*) plan=$(echo "$basename" | sed "s/^P[0-9]*-W[0-9]*-\([0-9]*\)-.*/\1/") ;;
          *) plan=$(echo "$basename" | sed "s/^[0-9]*-\([0-9]*\)-.*/\1/") ;;
        esac
      fi
      printf "%s|%s\n" "$phase" "$plan"
    }
    plan_contract_numbers "'"$plan_dir"'/P01-R01-PLAN.md"
  ')

  rm -rf "$plan_dir"
  # Should get 01|03 (frontmatter plan=03), not 01|01 (filename R01)
  [[ "$result" == *"01|03"* ]] || [[ "$result" == *"1|03"* ]]
}
