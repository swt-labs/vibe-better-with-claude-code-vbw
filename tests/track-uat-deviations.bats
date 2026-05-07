#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

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

make_no_jq_path() {
  local shim_dir="$TEST_TEMP_DIR/no-jq-bin"
  local cmd
  mkdir -p "$shim_dir"
  for cmd in awk shasum sha256sum openssl; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ln -sf "$(command -v "$cmd")" "$shim_dir/$cmd"
    fi
  done
  printf '%s' "$shim_dir"
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

@test "track-uat-deviations: signature does not require jq" {
  local no_jq_path expected
  no_jq_path=$(make_no_jq_path)
  expected=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")

  run env PATH="$no_jq_path" /bin/bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "track-uat-deviations: accepted-signatures fails open when jq is unavailable" {
  local no_jq_path registry sig
  no_jq_path=$(make_no_jq_path)
  registry="$PHASE_DIR/remediation/uat/accepted-deviations.json"
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  cat > "$registry" <<EOF
{"schema_version":1,"phase":"03-test","accepted":[{"signature":"$sig"}]}
EOF

  run --separate-stderr env PATH="$no_jq_path" /bin/bash "$SCRIPT" accepted-signatures "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [[ "$stderr" == *"jq not available"* ]]
  [[ "$stderr" == *"continuing without accepted signatures"* ]]
}

@test "track-uat-deviations: record-from-uat fails open without registry side effects when jq is unavailable" {
  local no_jq_path sig registry
  no_jq_path=$(make_no_jq_path)
  registry="$PHASE_DIR/remediation/uat/accepted-deviations.json"
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
EOF

  run --separate-stderr env PATH="$no_jq_path" /bin/bash "$SCRIPT" record-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [[ "$stderr" == *"jq not available"* ]]
  [[ "$stderr" == *"skipping accepted deviation registry sync"* ]]
  [ ! -e "$registry" ]
}
