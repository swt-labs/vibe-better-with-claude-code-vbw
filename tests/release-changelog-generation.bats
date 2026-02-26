#!/usr/bin/env bats

# Tests that internal/release.md auto-creates [Unreleased] section and populates
# it from commits when missing, instead of just warning and skipping.
#
# Fixes #169

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RELEASE_CMD="$REPO_ROOT/internal/release.md"

@test "release command file exists" {
  [ -f "$RELEASE_CMD" ]
}

@test "guard 5 auto-creates [Unreleased] section when missing" {
  # Guard 5 must instruct auto-insertion of [Unreleased], not just warn
  local guard5
  guard5=$(awk '/\*\*No \[Unreleased\]/{found=1; print; next} found && /^[0-9]+\./{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$guard5" ]
  # Must contain insert/create language, not just warn/confirm
  echo "$guard5" | grep -qi 'insert\|create'
  # Must NOT contain "WARN + confirm" or "only bump versions"
  ! echo "$guard5" | grep -qi 'WARN.*confirm'
  ! echo "$guard5" | grep -qi 'only bump versions'
}

@test "guard 5 inserts [Unreleased] above first version entry" {
  local guard5
  guard5=$(awk '/\*\*No \[Unreleased\]/{found=1; print; next} found && /^[0-9]+\./{found=0} found{print}' "$RELEASE_CMD")
  # Must reference inserting above the first version entry
  echo "$guard5" | grep -qi 'above.*first.*\[x\.y\.z\]\|above.*latest\|above.*version'
}

@test "guard 5 signals that audit will populate the section" {
  local guard5
  guard5=$(awk '/\*\*No \[Unreleased\]/{found=1; print; next} found && /^[0-9]+\./{found=0} found{print}' "$RELEASE_CMD")
  # Must mention audit will populate/generate content
  echo "$guard5" | grep -qi 'audit.*populate\|audit.*generate\|audit.*insert'
}

@test "audit 5 remediation generates changelog entries by commit prefix" {
  local audit5
  audit5=$(awk '/\*\*Audit 5: Remediation/{found=1; print; next} found && /^---$/{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$audit5" ]
  # Must reference commit prefix mapping
  echo "$audit5" | grep -q 'feat.*Added'
  echo "$audit5" | grep -q 'fix.*Fixed'
}

@test "audit 5 auto-inserts when [Unreleased] was auto-created" {
  local audit5
  audit5=$(awk '/\*\*Audit 5: Remediation/{found=1; print; next} found && /^---$/{found=0} found{print}' "$RELEASE_CMD")
  # Must reference auto-insert behavior for auto-created sections
  echo "$audit5" | grep -qi 'auto-created.*insert\|auto-created.*automatic\|auto-created.*without.*confirmation'
}

@test "audit 5 groups entries under conventional sub-headers" {
  local audit5
  audit5=$(awk '/\*\*Audit 5: Remediation/{found=1; print; next} found && /^---$/{found=0} found{print}' "$RELEASE_CMD")
  # Must reference Added/Changed/Fixed sub-headers
  echo "$audit5" | grep -q 'Added'
  echo "$audit5" | grep -q 'Changed'
  echo "$audit5" | grep -q 'Fixed'
}

@test "step 4 still renames [Unreleased] to version header" {
  local step4
  step4=$(awk '/^### Step 4: Update CHANGELOG header/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$step4" ]
  echo "$step4" | grep -q '\[Unreleased\]'
  echo "$step4" | grep -q '\[{new-version}\]'
}
