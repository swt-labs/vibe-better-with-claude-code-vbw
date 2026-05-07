#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/03-test"
  mkdir -p "$PHASE_DIR/remediation/uat/round-03"
  SCRIPT="$SCRIPTS_DIR/track-uat-deviations.sh"
}

teardown() {
  teardown_temp_dir
}

@test "track-uat-deviations: signature is stable for source identity and text" {
  run bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable"
  [ "$status" -eq 0 ]
  first="$output"

  run bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "track-uat-deviations: record-from-uat stores accepted process-exception D entries" {
  local sig
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  cat > "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" <<EOF
---
status: complete
---

## Tests

### D01: Review summary deviation

- **Source:** Summary deviation review
- **Deviation Signature:** $sig
- **Source Plan:** R03
- **Source Summary:** remediation/uat/round-03/R03-SUMMARY.md
- **Deviation:** Full-project SwiftLint unavailable
- **Result:** pass
- **Disposition:** accepted-process-exception

### D02: Actual issue

- **Deviation Signature:** ignored
- **Source Plan:** R03
- **Source Summary:** remediation/uat/round-03/R03-SUMMARY.md
- **Deviation:** Actual bug
- **Result:** issue
- **Disposition:** blocking
EOF

  run bash "$SCRIPT" record-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md"
  [ "$status" -eq 0 ]

  local registry="$PHASE_DIR/remediation/uat/accepted-deviations.json"
  [ -f "$registry" ]
  [ "$(jq -r '.accepted | length' "$registry")" = "1" ]
  [ "$(jq -r '.accepted[0].signature' "$registry")" = "$sig" ]
  [ "$(jq -r '.accepted[0].disposition' "$registry")" = "accepted-process-exception" ]

  run bash "$SCRIPT" accepted-signatures "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$sig" ]
}