#!/usr/bin/env bats

# Tests that internal/release.md auto-creates [Unreleased] section and populates
# it from merged PRs (primary) and commits (fallback) when missing.
#
# Fixes #169

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RELEASE_CMD="$REPO_ROOT/internal/release.md"

# Helper: extract guard section by keyword (simple text match)
extract_guard() {
  local keyword="$1"
  awk -v kw="$keyword" 'index($0, kw){found=1; print; next} found && /^[0-9]+\./{found=0} found{print}' "$RELEASE_CMD"
}

# Helper: extract audit 5 section
extract_audit5() {
  awk '/\*\*Audit 5: Remediation/{found=1; print; next} found && /^---$/{found=0} found{print}' "$RELEASE_CMD"
}

# Helper: extract audit 1 section
extract_audit1() {
  awk '/\*\*Audit 1/{found=1; print; next} found && /^\*\*Audit [2-9]/{found=0} found{print}' "$RELEASE_CMD"
}

@test "release command file exists" {
  [ -f "$RELEASE_CMD" ]
}

# --- Guard 5: Missing CHANGELOG.md ---

@test "guard 5 creates CHANGELOG.md when missing" {
  local guard5
  guard5=$(extract_guard "No CHANGELOG.md")
  [ -n "$guard5" ]
  echo "$guard5" | grep -qi 'create.*CHANGELOG\|CHANGELOG.*create'
  echo "$guard5" | grep -qi '\[Unreleased\]'
}

@test "guard 5 respects --dry-run by not writing" {
  local guard5
  guard5=$(extract_guard "No CHANGELOG.md")
  echo "$guard5" | grep -qi 'dry-run.*NOT write\|dry-run.*do NOT'
}

# --- Guard 6: Missing [Unreleased] ---

@test "guard 6 auto-creates [Unreleased] section when missing" {
  local guard6
  guard6=$(extract_guard "No \[Unreleased\]")
  [ -n "$guard6" ]
  echo "$guard6" | grep -qi 'insert\|create'
  ! echo "$guard6" | grep -qi 'WARN.*confirm'
  ! echo "$guard6" | grep -qi 'only bump versions'
}

@test "guard 6 inserts [Unreleased] above first version entry" {
  local guard6
  guard6=$(extract_guard "No \[Unreleased\]")
  echo "$guard6" | grep -qi 'above.*first.*\[x\.y\.z\]\|above.*latest\|above.*version'
}

@test "guard 6 signals that audit will populate the section" {
  local guard6
  guard6=$(extract_guard "No \[Unreleased\]")
  echo "$guard6" | grep -qi 'audit.*populate\|audit.*generate\|audit.*insert'
}

@test "guard 6 respects --dry-run by not writing" {
  local guard6
  guard6=$(extract_guard "No \[Unreleased\]")
  echo "$guard6" | grep -qi 'dry-run.*NOT write\|dry-run.*do NOT'
}

@test "guard 6 skips creation when --skip-audit" {
  local guard6
  guard6=$(extract_guard "No \[Unreleased\]")
  echo "$guard6" | grep -qi 'skip-audit.*NOT create\|skip-audit.*do NOT'
}

@test "guard 6 preserves content between header and first version" {
  local guard6
  guard6=$(extract_guard "No \[Unreleased\]")
  echo "$guard6" | grep -qi 'preserv'
}

# --- Audit 1: Change collection ---

@test "audit 1 collects merged PRs as primary changelog source" {
  local audit1
  audit1=$(extract_audit1)
  [ -n "$audit1" ]
  echo "$audit1" | grep -q 'gh pr list.*merged'
  echo "$audit1" | grep -q 'git log'
}

@test "audit 1 handles gh CLI unavailability gracefully" {
  local audit1
  audit1=$(extract_audit1)
  echo "$audit1" | grep -qi 'gh.*unavailable\|gh.*not available\|command fails'
  echo "$audit1" | grep -qi 'commit.*fallback\|commit-only'
}

@test "audit 1 warns when PR list may be truncated" {
  local audit1
  audit1=$(extract_audit1)
  echo "$audit1" | grep -qi 'truncat'
}

@test "audit 1 has date fallback when date cannot be parsed" {
  local audit1
  audit1=$(extract_audit1)
  echo "$audit1" | grep -qi 'fallback.*empty\|fallback.*omit'
}

@test "audit 1 correlates commits to PRs via commit messages" {
  local audit1
  audit1=$(extract_audit1)
  # Must use commit message pattern matching, not per-PR API calls
  echo "$audit1" | grep -qi 'commit message\|#N\|Merge pull request'
  # Must NOT require per-PR gh pr view calls
  ! echo "$audit1" | grep -qi 'gh pr view.*--json commits'
}

# --- Audit 2: Completeness ---

@test "audit 2 checks PR numbers in changelog for completeness" {
  local audit2
  audit2=$(awk '/\*\*Audit 2/{found=1; print; next} found && /^\*\*Audit [3-9]/{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$audit2" ]
  echo "$audit2" | grep -qi 'PR\|merged'
}

# --- Audit 5: Remediation ---

@test "audit 5 has dry-run gate before any writes" {
  local audit5
  audit5=$(extract_audit5)
  [ -n "$audit5" ]
  # Dry-run gate must appear before insertion logic
  local dryrun_line insertion_line
  dryrun_line=$(echo "$audit5" | grep -n -i 'dry-run gate\|dry-run.*NOT write' | head -1 | cut -d: -f1)
  insertion_line=$(echo "$audit5" | grep -n -i 'Insertion.*non-dry-run\|Insertion.*review' | head -1 | cut -d: -f1)
  [ -n "$dryrun_line" ]
  [ -n "$insertion_line" ]
  [ "$dryrun_line" -lt "$insertion_line" ]
}

@test "audit 5 generates entries from PR titles and bodies" {
  local audit5
  audit5=$(extract_audit5)
  echo "$audit5" | grep -qi 'PR.*title\|PR.*body\|merged PR'
  echo "$audit5" | grep -q 'PR #{number}\|PR #'
}

@test "audit 5 has commit-based fallback for uncovered commits" {
  local audit5
  audit5=$(extract_audit5)
  echo "$audit5" | grep -qi 'commit.*fallback\|uncovered commit\|not covered by.*PR'
}

@test "audit 5 classifies by PR title prefix" {
  local audit5
  audit5=$(extract_audit5)
  echo "$audit5" | grep -q 'feat.*Added'
  echo "$audit5" | grep -q 'fix.*Fixed'
}

@test "audit 5 has default classification for unrecognized prefixes" {
  local audit5
  audit5=$(extract_audit5)
  echo "$audit5" | grep -qi 'default.*Changed\|no.*prefix.*Changed\|no recognized.*Changed'
}

@test "audit 5 auto-inserts when [Unreleased] was auto-created" {
  local audit5
  audit5=$(extract_audit5)
  echo "$audit5" | grep -qi 'auto-created.*insert\|auto-created.*automatic\|auto-created.*without.*confirmation'
}

@test "audit 5 groups entries under conventional sub-headers" {
  local audit5
  audit5=$(extract_audit5)
  echo "$audit5" | grep -q 'Added'
  echo "$audit5" | grep -q 'Changed'
  echo "$audit5" | grep -q 'Fixed'
}

# --- Step 4: Header rename ---

@test "step 4 still renames [Unreleased] to version header" {
  local step4
  step4=$(awk '/^### Step 4: Update CHANGELOG header/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$step4" ]
  echo "$step4" | grep -q '\[Unreleased\]'
  echo "$step4" | grep -q '\[{new-version}\]'
}
