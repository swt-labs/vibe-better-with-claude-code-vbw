#!/usr/bin/env bats

# Tests that internal/release.md generates changelog entries directly under a
# versioned section header (no [Unreleased] indirection) and uses a robust grep
# pattern to find the last release commit.
#
# Fixes #169, #172

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

# Helper: extract version pre-computation section
extract_version_precompute() {
  awk '/^### Version Pre-computation/{found=1; print; next} found && /^(### |## )/{found=0} found{print}' "$RELEASE_CMD"
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
}

@test "guard 5 does NOT create [Unreleased] section" {
  local guard5
  guard5=$(extract_guard "5. No CHANGELOG.md")
  # [Unreleased] indirection was removed — entries go directly under versioned header
  ! echo "$guard5" | grep -qi '\[Unreleased\]'
}

@test "guard 5 respects --dry-run by not writing" {
  local guard5
  guard5=$(extract_guard "5. No CHANGELOG.md")
  echo "$guard5" | grep -qi 'dry-run.*NOT write\|dry-run.*do NOT'
}

@test "guard 5 skips to Guard 6 (version sync)" {
  local guard5
  guard5=$(extract_guard "5. No CHANGELOG.md")
  echo "$guard5" | grep -qi 'Guard 6'
}

# --- Guard 6 (was [Unreleased]) removed ---

@test "no guard for [Unreleased] section exists" {
  # Guard 6 was the old [Unreleased] guard — it should not exist in the file
  ! grep -q 'No \[Unreleased\]' "$RELEASE_CMD"
}

@test "guard 6 is now version sync" {
  local guard6
  guard6=$(extract_guard "6. Version sync")
  [ -n "$guard6" ]
  echo "$guard6" | grep -qi 'bump-version\|sync'
}

@test "guard 7 is now existing release branch" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  [ -n "$guard7" ]
  echo "$guard7" | grep -qi 'release.*branch\|branch.*already'
}

# --- Audit 1: Change collection ---

@test "audit 1 collects merged PRs as primary changelog source" {
  local audit1
  audit1=$(extract_audit1)
  [ -n "$audit1" ]
  echo "$audit1" | grep -q 'gh pr list.*merged'
  echo "$audit1" | grep -q 'git log'
}

@test "audit 1 grep pattern matches both commit formats" {
  local audit1
  audit1=$(extract_audit1)
  # Must use a pattern that matches both:
  #   chore: release v1.32.0    (no scope)
  #   chore(release): v1.31.0   (scoped)
  # The old pattern "chore: release" missed the scoped format
  echo "$audit1" | grep -q '\^chore.*release'
}

@test "audit 1 grep pattern excludes fix(release) commits" {
  local audit1
  audit1=$(extract_audit1)
  # Pattern must be anchored to ^chore to exclude fix(release): commits
  echo "$audit1" | grep -q '\^chore'
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

@test "audit 2 checks versioned section instead of [Unreleased]" {
  local audit2
  audit2=$(awk '/\*\*Audit 2/{found=1; print; next} found && /^\*\*Audit [3-9]/{found=0} found{print}' "$RELEASE_CMD")
  # Should reference the versioned section header, not [Unreleased]
  echo "$audit2" | grep -qi '{new-version}'
  ! echo "$audit2" | grep -q '\[Unreleased\]'
}

# --- Version pre-computation ---

@test "version pre-computation happens before audit" {
  local precompute
  precompute=$(extract_version_precompute)
  [ -n "$precompute" ]
  echo "$precompute" | grep -qi 'VERSION\|bump'
  # Must appear before Audit 1 in the file
  local precompute_line audit1_line
  precompute_line=$(grep -n 'Version Pre-computation' "$RELEASE_CMD" | head -1 | cut -d: -f1)
  audit1_line=$(grep -n '\*\*Audit 1' "$RELEASE_CMD" | head -1 | cut -d: -f1)
  [ -n "$precompute_line" ]
  [ -n "$audit1_line" ]
  [ "$precompute_line" -lt "$audit1_line" ]
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

@test "audit 5 inserts under versioned header directly" {
  local audit5
  audit5=$(extract_audit5)
  # Entries go under ## [{new-version}] not [Unreleased]
  echo "$audit5" | grep -qi '{new-version}'
  ! echo "$audit5" | grep -q '\[Unreleased\]'
}

@test "audit 5 groups entries under conventional sub-headers" {
  local audit5
  audit5=$(extract_audit5)
  echo "$audit5" | grep -q 'Added'
  echo "$audit5" | grep -q 'Changed'
  echo "$audit5" | grep -q 'Fixed'
}

# --- Step 4: Removed (was header rename) ---

@test "no Step 4 header rename exists (eliminated with [Unreleased])" {
  # Step 4 was "Update CHANGELOG header" which renamed [Unreleased] to version.
  # Since [Unreleased] is eliminated, this step no longer exists.
  ! grep -q 'Update CHANGELOG header' "$RELEASE_CMD"
}

@test "no [Unreleased] references remain in the release command" {
  # The entire [Unreleased] indirection was removed
  ! grep -q '\[Unreleased\]' "$RELEASE_CMD"
}
