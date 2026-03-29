#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "resolve-verification-path phase prefers brownfield plain VERIFICATION over stale wave files" {
  cat > "$PHASE_DIR/VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  cat > "$PHASE_DIR/01-VERIFICATION-wave2.md" <<'EOF'
---
result: FAIL
---
EOF

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" phase "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/VERIFICATION.md" ]
}

@test "resolve-verification-path current ignores round verification before verify stage" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  printf 'stage=plan\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" current "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-VERIFICATION.md" ]
}

@test "resolve-verification-path current uses round verification during verify stage" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  printf 'stage=verify\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" current "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" ]
}

@test "resolve-verification-path authoritative ignores corrupt stage values" {
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'EOF'
---
result: FAIL
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-VERIFICATION.md" <<'EOF'
---
result: PASS
---
EOF
  printf 'stage=garbage\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"

  run bash "$SCRIPTS_DIR/resolve-verification-path.sh" authoritative "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$PHASE_DIR/01-VERIFICATION.md" ]
}