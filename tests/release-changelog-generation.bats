#!/usr/bin/env bats

# Tests that internal/release.md auto-creates [Unreleased] section and populates
# it from merged PRs (primary) and commits (fallback) when missing.
#
# Fixes #169

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RELEASE_CMD="$REPO_ROOT/internal/release.md"

# Helper: extract guard section by number (anchored to guard number prefix)
# Stops at the next guard number OR at a markdown ## heading. Uses a "done"
# flag to prevent re-entry on finalize guards that share the same number.
extract_guard() {
  local keyword="$1"
  local num
  num=$(echo "$keyword" | grep -oE '^[0-9]+')
  if [ -n "$num" ]; then
    awk -v n="$num" '
      !done && $0 ~ "^"n"\\. \\*\\*" {found=1; print; next}
      found && /^[0-9]+\./ {found=0; done=1}
      found && /^## / {found=0; done=1}
      found {print}
    ' "$RELEASE_CMD"
  else
    awk -v kw="$keyword" '
      !done && index($0, kw) {found=1; print; next}
      found && /^[0-9]+\./ {found=0; done=1}
      found && /^## / {found=0; done=1}
      found {print}
    ' "$RELEASE_CMD"
  fi
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

# --- extract_guard helper ---

@test "extract_guard keyword-fallback path works with done flag" {
  # Exercise the non-numeric fallback branch of extract_guard
  local result
  result=$(extract_guard "Dirty tree")
  [ -n "$result" ]
  echo "$result" | grep -qi 'uncommitted'
  # Should NOT contain finalize guard content (done flag prevents re-entry)
  ! echo "$result" | grep -qi 'Tag already exists\|Locate merged release'
}

# --- Guard 5: Missing CHANGELOG.md ---

@test "guard 5 creates CHANGELOG.md when missing" {
  local guard5
  guard5=$(extract_guard "5. No CHANGELOG.md")
  [ -n "$guard5" ]
  echo "$guard5" | grep -qi 'create.*CHANGELOG\|CHANGELOG.*create'
  echo "$guard5" | grep -qi '\[Unreleased\]'
}

@test "guard 5 respects --dry-run by not writing" {
  local guard5
  guard5=$(extract_guard "5. No CHANGELOG.md")
  echo "$guard5" | grep -qi 'dry-run.*NOT write\|dry-run.*do NOT'
}

@test "guard 5 dry-run skips to Guard 7 (not Guard 6)" {
  local guard5
  guard5=$(extract_guard "5. No CHANGELOG.md")
  # Dry-run path should skip to Guard 7, not chain to Guard 6
  echo "$guard5" | grep -qi 'Skip to Guard 7\|Guard 7'
  ! echo "$guard5" | grep -qi 'Continue to Guard 6'
}

@test "guard 5 non-dry-run skips to Guard 7" {
  local guard5
  guard5=$(extract_guard "5. No CHANGELOG.md")
  # Non-dry-run path also skips to Guard 7 (Guard 6 is satisfied)
  echo "$guard5" | grep -qi 'Skip to Guard 7'
}

@test "guard 5 warns about empty section when --skip-audit" {
  local guard5
  guard5=$(extract_guard "5. No CHANGELOG.md")
  echo "$guard5" | grep -qi 'skip-audit'
  echo "$guard5" | grep -qi 'empty\|re-running without'
}

# --- Guard 6: Missing [Unreleased] ---

@test "guard 6 auto-creates [Unreleased] section when missing" {
  local guard6
  guard6=$(extract_guard "6. No [Unreleased]")
  [ -n "$guard6" ]
  echo "$guard6" | grep -qi 'insert\|create'
  ! echo "$guard6" | grep -qi 'WARN.*confirm'
  ! echo "$guard6" | grep -qi 'only bump versions'
}

@test "guard 6 inserts [Unreleased] above first version entry" {
  local guard6
  guard6=$(extract_guard "6. No [Unreleased]")
  echo "$guard6" | grep -qi 'above.*first.*\[x\.y\.z\]\|above.*latest\|above.*version'
}

@test "guard 6 signals that audit will populate the section" {
  local guard6
  guard6=$(extract_guard "6. No [Unreleased]")
  echo "$guard6" | grep -qi 'audit.*populate\|audit.*generate\|audit.*insert'
}

@test "guard 6 respects --dry-run by not writing" {
  local guard6
  guard6=$(extract_guard "6. No [Unreleased]")
  echo "$guard6" | grep -qi 'dry-run.*NOT write\|dry-run.*do NOT'
}

@test "guard 6 skips creation when --skip-audit" {
  local guard6
  guard6=$(extract_guard "6. No [Unreleased]")
  echo "$guard6" | grep -qi 'skip-audit.*NOT create\|skip-audit.*do NOT'
}

@test "guard 6 --skip-audit takes precedence over --dry-run" {
  local guard6
  guard6=$(extract_guard "6. No [Unreleased]")
  # skip-audit branch must appear before dry-run-only branch
  local skip_line dry_line
  skip_line=$(echo "$guard6" | grep -n -i '^\s*- If.*--skip-audit' | head -1 | cut -d: -f1)
  dry_line=$(echo "$guard6" | grep -n -i '^\s*- If.*--dry-run.*without' | head -1 | cut -d: -f1)
  [ -n "$skip_line" ]
  [ -n "$dry_line" ]
  [ "$skip_line" -lt "$dry_line" ]
}

@test "guard 6 preserves content between header and first version" {
  local guard6
  guard6=$(extract_guard "6. No [Unreleased]")
  echo "$guard6" | grep -qi 'preserv'
}

@test "guard 6 branches continue to Guard 7" {
  local guard6
  guard6=$(extract_guard "6. No [Unreleased]")
  # All branches should reference Guard 7 (not jump directly to audit)
  echo "$guard6" | grep -qi 'Guard 7'
}

# --- Audit 1: Change collection ---

@test "audit 1 collects merged PRs as primary changelog source" {
  local audit1
  audit1=$(extract_audit1)
  [ -n "$audit1" ]
  echo "$audit1" | grep -q 'gh pr list.*merged'
  echo "$audit1" | grep -q 'git log'
}

@test "audit 1 uses --first-parent to exclude branch commits" {
  local audit1
  audit1=$(extract_audit1)
  echo "$audit1" | grep -q '\-\-first-parent'
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

@test "audit 1 documents rebase merge limitation for commit correlation" {
  local audit1
  audit1=$(extract_audit1)
  echo "$audit1" | grep -qi 'rebase'
}

@test "audit 1 correlates commits to PRs via commit messages" {
  local audit1
  audit1=$(extract_audit1)
  # Must mention both concrete patterns for commit-message correlation
  echo "$audit1" | grep -q '(#N)'
  echo "$audit1" | grep -q 'Merge pull request #N'
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

@test "audit 2 handles non-existent CHANGELOG.md" {
  local audit2
  audit2=$(awk '/\*\*Audit 2/{found=1; print; next} found && /^\*\*Audit [3-9]/{found=0} found{print}' "$RELEASE_CMD")
  echo "$audit2" | grep -qi 'does not exist\|undocumented\|skip extraction'
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
  # Must reference both Guard 5 and Guard 6 as auto-creation sources
  echo "$audit5" | grep -qi 'Guard 5\|Guard 6'
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
