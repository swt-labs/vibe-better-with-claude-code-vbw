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

@test "guard 7 auto-cleans existing release branches" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  [ -n "$guard7" ]
  # Should describe auto-cleanup, not hard STOP
  echo "$guard7" | grep -qi 'cleanup\|clean up\|delet'
  ! echo "$guard7" | grep -qi 'STOP.*already exists'
}

@test "guard 7 deletes local and remote branches" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  echo "$guard7" | grep -qi 'git branch -D\|git branch.*delete'
  echo "$guard7" | grep -qi 'git push origin --delete'
}

@test "guard 7 finds associated PRs via gh" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  echo "$guard7" | grep -qi 'gh pr list'
}

@test "guard 7 handles gh CLI unavailability or failure" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  echo "$guard7" | grep -qi 'gh.*unavailable\|gh.*not available\|orphan'
  # Must also handle gh returning non-zero (auth/network/API failure)
  echo "$guard7" | grep -qi 'non-zero\|exit.*fail\|command.*fail\|exits non-zero'
}

@test "guard 7 reports deletion failures instead of suppressing" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  # Must track and report deletion failures, not suppress with || true
  echo "$guard7" | grep -qi 'fail.*delet\|delet.*fail\|Failed to delete'
  ! echo "$guard7" | grep -q '|| true'
  # Must have failure counters or tracking
  echo "$guard7" | grep -qi 'failed.*>.*0\|{failed}'
}

@test "guard 7 distinguishes remote not-found from network error" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  # Must parse stderr to distinguish 'remote ref does not exist' (success)
  # from network/permission errors (failure)
  echo "$guard7" | grep -qi 'remote ref does not exist\|not-found\|stderr'
  # Must list multiple known not-found message patterns for cross-version robustness
  echo "$guard7" | grep -qi 'does not exist'
  echo "$guard7" | grep -qi 'not found'
}

@test "guard 7 stops when all deletions fail" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  echo "$guard7" | grep -qi 'STOP.*All branch deletions failed\|All.*deletions failed.*STOP'
}

@test "guard 7 summary reports remaining uncleanable branches" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  # When partial failures occur, summary must indicate which branches remain
  echo "$guard7" | grep -qi 'could not be fully cleaned\|failed_branches\|remaining'
}

@test "guard 7 handles multiple release branches" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  # Must mention handling all/each release branch, not just one
  echo "$guard7" | grep -qi 'each\|all\|every'
}

@test "guard 7 still stops on remote unreachable" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  echo "$guard7" | grep -qi 'STOP.*unreachable\|STOP.*unauthorized\|Could not verify'
}

# --- Audit 1: Change collection ---

@test "audit 1 collects merged PRs as primary changelog source" {
  local audit1
  audit1=$(extract_audit1)
  [ -n "$audit1" ]
  echo "$audit1" | grep -q 'gh pr list.*merged'
  echo "$audit1" | grep -q 'git log'
}

@test "audit 1 grep pattern matches all release commit formats" {
  local audit1
  audit1=$(extract_audit1)
  # Must use extended-regexp with scope restricted to (release) or no scope
  echo "$audit1" | grep -q 'extended-regexp\|extended.regexp'
  # Must restrict scope via (\\(release\\))? or equivalent
  echo "$audit1" | grep -qE '\(release\)\)|\(\\\(release\\\)\)'
  # Must support breaking-change marker via !?
  echo "$audit1" | grep -q '!?'
}

@test "audit 1 grep pattern excludes version bump commits" {
  local audit1
  audit1=$(extract_audit1)
  echo "$audit1" | grep -qi 'bump.*exclud\|exclud.*bump'
}

@test "audit 1 verifies subject line to avoid body-line false positives" {
  local audit1
  audit1=$(extract_audit1)
  # Must document the body-line matching limitation and describe subject verification
  echo "$audit1" | grep -qi 'subject.*verif\|verif.*subject\|subject-verif'
  echo "$audit1" | grep -qi 'body'
  # Must specify the split-on-first-space parsing procedure
  echo "$audit1" | grep -qi 'split.*first space\|separate.*hash.*subject'
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

@test "audit 5 removes stale untagged version sections from CHANGELOG" {
  local audit5
  audit5=$(extract_audit5)
  # Audit 5 must scan for and remove stale version sections with no git tag
  echo "$audit5" | grep -qi 'stale\|untagged\|no.*tag'
  echo "$audit5" | grep -qi 'remov'
}

@test "audit 5 fetches tags before stale section check" {
  local audit5
  audit5=$(extract_audit5)
  echo "$audit5" | grep -qi 'git fetch --tags\|fetch.*tags'
}

@test "audit 5 handles tag fetch failure gracefully" {
  local audit5
  audit5=$(extract_audit5)
  # If git fetch --tags fails, must skip stale cleanup to avoid deleting valid sections
  echo "$audit5" | grep -qi 'fetch.*fail\|non-zero\|exits non-zero'
  echo "$audit5" | grep -qi 'skip.*stale\|skip.*cleanup'
}

@test "audit 5 stale section cleanup uses semver pattern matching" {
  local audit5
  audit5=$(extract_audit5)
  # Must validate version headers match semver pattern to avoid false positives
  echo "$audit5" | grep -qi 'semver\|\[0-9\].*\..*\[0-9\]'
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

# --- Guard 5 + --skip-audit interaction ---

@test "guard 5 creates CHANGELOG without audit entries when --skip-audit" {
  local guard5
  guard5=$(extract_guard "5. No CHANGELOG.md")
  # Guard 5 must work with --skip-audit: create CHANGELOG.md and skip to Guard 6
  # without requiring audit to populate entries
  echo "$guard5" | grep -qi 'create.*CHANGELOG\|CHANGELOG.*create'
  echo "$guard5" | grep -qi 'Guard 6\|Skip to Guard 6'
  # The --skip-audit path is handled by the audit section, not Guard 5 itself.
  # Guard 5's 'Otherwise' branch creates the file and skips to Guard 6.
  # Verify Guard 5 does NOT condition creation on --skip-audit presence
  # (it always creates if CHANGELOG is missing and not dry-run).
  echo "$guard5" | grep -qi 'Otherwise.*create\|create CHANGELOG'
}

# --- Runtime behavior: candidate list not truncated (Finding 1) ---

@test "audit 1 does not truncate candidate list with head" {
  local audit1
  audit1=$(extract_audit1)
  # The git log command must NOT be piped through head
  # (truncation could drop the true release commit behind body-line false positives)
  ! echo "$audit1" | grep -q 'head -[0-9]'
  # Must explicitly state no truncation
  echo "$audit1" | grep -qi 'no truncation\|not truncated'
}

@test "audit 1 falls back to root commit when no subject matches" {
  local audit1
  audit1=$(extract_audit1)
  # Must specify root commit fallback via git rev-list --max-parents=0
  echo "$audit1" | grep -qi 'root commit\|rev-list.*max-parents=0'
}

# --- Runtime behavior: subject parsing precision (Finding 2) ---

@test "audit 1 specifies exact subject extraction from %H %s format" {
  local audit1
  audit1=$(extract_audit1)
  # Must specify split on first space to separate hash from subject
  echo "$audit1" | grep -qi 'split.*first space\|separate.*hash.*subject'
  # Must specify testing subject against the regex
  echo "$audit1" | grep -qi 'test.*subject.*regex\|subject.*against.*regex\|subject matches'
}

# --- Runtime behavior: breaking-change marker (Finding 3) ---

@test "audit 1 grep pattern supports breaking-change marker" {
  local audit1
  audit1=$(extract_audit1)
  # Pattern must include !? to handle chore(release)!: v1.33.0
  echo "$audit1" | grep -q '!?'
  # Must mention breaking-change in the explanation
  echo "$audit1" | grep -qi 'breaking.change'
}

# --- Runtime behavior: remote deletion classification (Finding 4) ---

@test "guard 7 lists multiple known not-found stderr patterns" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  # Must list multiple not-found patterns for cross-version/transport robustness
  echo "$guard7" | grep -qi 'remote ref does not exist'
  echo "$guard7" | grep -qi 'does not exist'
  echo "$guard7" | grep -qi 'unable to delete'
  # Must NOT use bare 'not found' (over-broad — catches repo-level errors)
  echo "$guard7" | grep -qi 'do not match bare\|too broad'
  # Must describe conservative fallback for unknown messages
  echo "$guard7" | grep -qi 'conservative\|false failure'
}

# --- Runtime behavior: finalize step 4 visibility (Finding 5) ---

@test "finalize step 4 reports remote deletion failure instead of suppressing" {
  local step4
  step4=$(awk '/^### Finalize Step 4/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$step4" ]
  # Must NOT use || true for remote deletion (old behavior)
  local remote_line
  remote_line=$(echo "$step4" | grep -i 'push origin --delete')
  [ -n "$remote_line" ]
  ! echo "$remote_line" | grep -q '|| true'
  # Must display a warning on failure
  echo "$step4" | grep -qi 'Could not delete\|delete manually'
  # Must be non-fatal (release is already tagged)
  echo "$step4" | grep -qi 'non-fatal\|continue'
}

# --- Bug #174: Date format and tag check ---

@test "audit 1 date extraction uses git format placeholder, not strftime" {
  local audit1
  audit1=$(extract_audit1)
  # Must NOT use --format=%Y-%m-%d (strftime specifiers, not git format)
  # %Y is literal in git, %m is left/right mark, %d is ref decoration
  ! echo "$audit1" | grep -q 'format=%Y-%m-%d'
  ! echo "$audit1" | grep -q "format='%Y-%m-%d'"
  # Must use a valid git date format: %cd with --date=short (spec-documented approach)
  echo "$audit1" | grep -qE '%cd.*--date=short'
}

@test "audit 5 stale section tag check warns about exit code pitfall" {
  local audit5
  audit5=$(extract_audit5)
  # Must explicitly warn that git tag -l always exits 0
  echo "$audit5" | grep -qi 'always exits 0\|exit code'
  # Must instruct to check stdout content
  echo "$audit5" | grep -qi 'stdout\|output.*empty'
}

@test "finalize guard 5 tag check warns about exit code pitfall" {
  local finalize_guard
  finalize_guard=$(awk '/^### Finalize Guard/{found=1; next} /^###/{found=0} /^## /{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$finalize_guard" ]
  # Narrow extraction: target Guard 5 specifically ("Tag already exists")
  local guard5_content
  guard5_content=$(echo "$finalize_guard" | awk '/^5\. \*\*Tag already exists/{found=1; print; next} found && /^[0-9]+\./{found=0} found && /^###/{found=0} found{print}')
  if [ -z "$guard5_content" ]; then
    # No fallback — if the Guard 5 anchor drifts (renumbered/reworded),
    # fail explicitly so the test is updated, rather than broadening scope.
    fail "Guard 5 anchor '5. **Tag already exists' not found in Finalize Guard section — update test if guard was renumbered/reworded"
  fi
  # Must explicitly warn that git tag -l always exits 0
  echo "$guard5_content" | grep -qi 'always exits 0\|exit code'
  # Must instruct to check stdout content
  echo "$guard5_content" | grep -qi 'stdout\|non-empty\|outputs a match'
}

@test "finalize step 2 ls-remote tag check warns about exit code pitfall" {
  local step2
  step2=$(awk '/^### Finalize Step 2/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$step2" ]
  # Must mention git ls-remote --tags
  echo "$step2" | grep -qi 'git ls-remote.*tags'
  # Intent: spec must convey that ls-remote exit code alone does not indicate match/no-match
  echo "$step2" | grep -qi 'always exits 0\|exit.code\|zero regardless\|succeeds regardless\|not the exit'
  # Intent: spec must direct the reader to check command output, not just exit status
  echo "$step2" | grep -qi 'stdout\|non-empty\|output.*empty\|check.*output\|produces.*output'
}

@test "guard 7 clarifies stdout-vs-exit-code for branch list checks" {
  local guard7
  guard7=$(extract_guard "7. Existing release branch")
  [ -n "$guard7" ]
  # Intent: spec must convey that branch --list exit code is not a reliable match indicator
  echo "$guard7" | grep -qi 'branch --list.*always exits 0\|branch --list.*stdout\|branch --list.*exit.code\|branch --list.*non-empty\|branch --list.*check.*output'
  # Intent: spec must convey that ls-remote exit code is not a reliable match indicator
  echo "$guard7" | grep -qi 'ls-remote.*always exits 0\|ls-remote.*stdout\|ls-remote.*exit.code\|ls-remote.*non-empty\|ls-remote.*reachable'
}
