#!/usr/bin/env bats

load test_helper

SCRIPT="${PROJECT_ROOT}/scripts/compile-verify-context-for-uat.sh"

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/03-test"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "compile-verify-context-for-uat: no remediation state uses full scope" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Original feature
must_haves:
  - Feature works
---
EOF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=full"* ]]
  [[ "$output" == *"=== PLAN 01: Original feature ==="* ]]
}

@test "compile-verify-context-for-uat: QA remediation done without prior UAT still uses full scope" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Original feature
must_haves:
  - Feature works
---
EOF
  mkdir -p "$PHASE_DIR/remediation/qa/round-01"
  printf 'stage=done\nround=01\n' > "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md" <<'EOF'
---
round: 01
title: QA remediation round
must_haves:
  - Documentation updated
---
EOF
  cat > "$PHASE_DIR/remediation/qa/round-01/R01-SUMMARY.md" <<'EOF'
---
status: complete
---
## What Was Built
- Updated QA remediation paperwork
EOF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=full"* ]]
  [[ "$output" == *"=== PLAN 01: Original feature ==="* ]]
  [[ "$output" == *"=== PLAN R01: QA remediation round ==="* ]]
}

@test "compile-verify-context-for-uat: active UAT remediation uses remediation-only scope" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Original feature
must_haves:
  - Feature works
---
EOF
  mkdir -p "$PHASE_DIR/remediation/uat/round-02"
  printf 'stage=research\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  cat > "$PHASE_DIR/remediation/uat/round-02/R02-PLAN.md" <<'EOF'
---
round: 02
title: UAT remediation round
must_haves:
  - UAT issue fixed
---
EOF
  cat > "$PHASE_DIR/remediation/uat/round-02/R02-SUMMARY.md" <<'EOF'
---
status: complete
---
## What Was Built
- Fixed the UAT issue
EOF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=remediation round=02"* ]]
  [[ "$output" == *"=== PLAN R02: UAT remediation round ==="* ]]
  [[ "$output" != *"Original feature"* ]]
}

@test "compile-verify-context-for-uat: legacy UAT remediation marker uses remediation-only scope" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Original feature
must_haves:
  - Feature works
---
EOF
  mkdir -p "$PHASE_DIR/remediation/round-01"
  printf 'verify\n' > "$PHASE_DIR/.uat-remediation-stage"
  cat > "$PHASE_DIR/remediation/round-01/R01-PLAN.md" <<'EOF'
---
round: 01
title: Legacy UAT remediation round
must_haves:
  - Legacy issue fixed
---
EOF
  cat > "$PHASE_DIR/remediation/round-01/R01-SUMMARY.md" <<'EOF'
---
status: complete
---
## What Was Built
- Fixed the legacy UAT issue
EOF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=remediation round=01"* ]]
  [[ "$output" == *"Legacy UAT remediation round"* ]]
  [[ "$output" != *"Original feature"* ]]
}

@test "compile-verify-context-for-uat: verified remediation stage uses full scope" {
  cat > "$PHASE_DIR/03-01-PLAN.md" <<'EOF'
---
plan: 01
title: Original feature
must_haves:
  - Feature works
---
EOF
  mkdir -p "$PHASE_DIR/remediation/uat"
  printf 'stage=verified\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md" <<'EOF'
---
round: 01
title: UAT remediation round
must_haves:
  - UAT issue fixed
---
EOF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=full"* ]]
  [[ "$output" == *"Original feature"* ]]
}

@test "contract: vibe.md uses compile-verify-context-for-uat.sh for auto-UAT context" {
  grep -q 'compile-verify-context-for-uat\.sh' "$PROJECT_ROOT/commands/vibe.md"
}

@test "contract: verify.md uses compile-verify-context-for-uat.sh for precomputed context" {
  grep -q 'compile-verify-context-for-uat\.sh' "$PROJECT_ROOT/commands/verify.md"
}