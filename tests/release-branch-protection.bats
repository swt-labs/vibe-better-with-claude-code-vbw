#!/usr/bin/env bats

# Tests that internal/release.md supports branch-protection-aware workflow.
# The release command must NOT push directly to main. Instead it should:
# - Create a release branch and open a draft PR (prepare phase)
# - Finalize (tag + GitHub release) after the PR is merged (--finalize phase)
#
# Fixes #162

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RELEASE_CMD="$REPO_ROOT/internal/release.md"

@test "release command file exists" {
  [ -f "$RELEASE_CMD" ]
}

@test "release command supports --finalize flag" {
  # argument-hint in frontmatter must list --finalize
  local frontmatter
  frontmatter=$(awk '/^---$/{ d++; next } d==1' "$RELEASE_CMD")
  echo "$frontmatter" | grep -q '\-\-finalize'
}

@test "release command creates a release branch instead of committing to main" {
  # Step 2 must contain git checkout -b release/ instruction
  local step2
  step2=$(awk '/^### Step 2: Create release branch/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$step2" ]
  echo "$step2" | grep -qi 'checkout.*release/'
}

@test "release command opens a draft PR" {
  # Step 7 must contain gh pr create --draft
  local step7
  step7=$(awk '/^### Step 7: Open draft PR/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$step7" ]
  echo "$step7" | grep -qi 'draft'
  echo "$step7" | grep -qi 'pr.*create\|gh.*pr'
}

@test "release command does NOT push directly to current branch in prepare mode" {
  # Step 6 should NOT contain a bare 'git push' that pushes to the current branch.
  # It should push the release branch, not main.
  # Extract the push step content (between "Push release branch" and next heading)
  local push_section
  push_section=$(awk '/^### Step 6: Push release branch/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  # The prepare-mode push must reference the release branch and explicit origin target
  echo "$push_section" | grep -q 'git push -u origin release/v{new-version}'
  echo "$push_section" | grep -qi 'release/'
  # Must not include unsafe direct-main or bare push semantics
  ! echo "$push_section" | grep -Eq 'git push[[:space:]]*$'
  ! echo "$push_section" | grep -Eq 'git push[[:space:]]+origin[[:space:]]+main'
}

@test "release finalize tags on main after merge" {
  # Finalize phase must verify merged release artifact on main before tagging
  local finalize_section
  finalize_section=$(awk '/^## Finalize Phase/{found=1} found{print}' "$RELEASE_CMD")
  [ -n "$finalize_section" ]
  echo "$finalize_section" | grep -qi 'merged release artifact on main'
  echo "$finalize_section" | grep -qi 'first-parent'
}

@test "release command argument-hint includes --finalize" {
  # Frontmatter argument-hint must list --finalize
  local frontmatter
  frontmatter=$(awk '/^---$/{ d++; next } d==1' "$RELEASE_CMD")
  echo "$frontmatter" | grep -q '\-\-finalize'
}

@test "finalize tags exact release commit, not HEAD" {
  # The tag command must reference {release_sha} or equivalent, not bare HEAD
  local tag_step
  tag_step=$(awk '/^### Finalize Step 1/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  # Must contain a SHA variable reference in the tag command (not just HEAD)
  echo "$tag_step" | grep -qi 'release_sha\|commit'
  # Must NOT contain "current HEAD" or tag bare HEAD
  ! echo "$tag_step" | grep -qi 'current HEAD'
}

@test "finalize uses first-parent selection and stops on ambiguity" {
  # Finalize guard must select the merged artifact from first-parent main history
  # and STOP when multiple candidates are found.
  local finalize_guard
  finalize_guard=$(awk '/^### Finalize Guard/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  echo "$finalize_guard" | grep -qi 'git log.*--first-parent.*grep'
  echo "$finalize_guard" | grep -qi 'Multiple merge commits found\|Multiple release commits match'
  echo "$finalize_guard" | grep -qi 'Resolve ambiguity manually\|Resolve manually before finalizing'
  # Must NOT use HEAD~N fixed window
  ! echo "$finalize_guard" | grep -q 'HEAD~[0-9]'
}

@test "finalize is restart-safe (idempotent tag and release)" {
  # Re-running finalize after partial failure must not fail on existing tag/release
  local finalize_section
  finalize_section=$(awk '/^## Finalize Phase/{found=1} found{print}' "$RELEASE_CMD")
  # Must check if tag already exists before creating
  echo "$finalize_section" | grep -qi 'tag.*already\|already.*exists\|tag -l'
  # Must check if release already exists before creating
  echo "$finalize_section" | grep -qi 'release.*already\|release view'
}

@test "finalize enforces clean working tree" {
  # Finalize guard must check for dirty tree before pull/tag operations
  local finalize_guard
  finalize_guard=$(awk '/^### Finalize Guard/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  echo "$finalize_guard" | grep -qi 'dirty\|porcelain\|clean'
}

@test "guard rejects prepare-only flags in finalize mode" {
  # Guard #2 must hard-stop when --finalize is mixed with prepare-only flags
  local guard_section
  guard_section=$(awk '/^## Guard/{found=1; next} /^## [^G]/{found=0} found{print}' "$RELEASE_CMD")
  echo "$guard_section" | grep -qi 'Incompatible flags'
  echo "$guard_section" | grep -qi 'hard error'
  echo "$guard_section" | grep -qi 'prepare-only'
  echo "$guard_section" | grep -qi '\-\-dry-run'
  echo "$guard_section" | grep -qi '\-\-no-push'
  echo "$guard_section" | grep -qi '\-\-major'
  echo "$guard_section" | grep -qi '\-\-minor'
  echo "$guard_section" | grep -qi '\-\-skip-audit'
  echo "$guard_section" | grep -qi 'cannot be combined with `--finalize`'
  echo "$guard_section" | grep -qi 'Do \*\*not\*\* continue to finalize'
  echo "$guard_section" | grep -qi 'reject'
}

@test "guard auto-cleans existing release branches instead of stopping" {
  # Guard #7 must auto-cleanup, not hard STOP
  local guard_section
  guard_section=$(awk '/^## Guard/{found=1; next} /^## [^G]/{found=0} found{print}' "$RELEASE_CMD")
  echo "$guard_section" | grep -qi 'git branch --list'
  echo "$guard_section" | grep -qi 'git ls-remote --heads origin'
  echo "$guard_section" | grep -qi 'Could not verify remote release branches'
  echo "$guard_section" | grep -qi 'origin.*unreachable\|unauthorized'
  # Should describe cleanup, not "already exists" STOP
  echo "$guard_section" | grep -qi 'cleanup\|clean up\|delet'
  ! echo "$guard_section" | grep -qi 'STOP.*Release branch already exists'
}

@test "finalize commit search does not use --all-match" {
  # --all-match is a no-op with single --grep; should not be present
  local finalize_guard
  finalize_guard=$(awk '/^### Finalize Guard/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  ! echo "$finalize_guard" | grep -q '\-\-all-match'
}

@test "flag compatibility table documents finalize restrictions" {
  # Must have a compatibility table with explicit mixed-flag hard-stop policy
  local compat_section
  compat_section=$(awk '/^## Flag Compatibility/{found=1; next} /^## [^F]/{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$compat_section" ]
  echo "$compat_section" | grep -q '| --finalize'
  echo "$compat_section" | grep -q '| --dry-run'
  echo "$compat_section" | grep -q '| --no-push'
  echo "$compat_section" | grep -q '| --major'
  echo "$compat_section" | grep -q '| --minor'
  echo "$compat_section" | grep -q '| --skip-audit'
  echo "$compat_section" | grep -qi 'hard STOP'
  echo "$compat_section" | grep -qi 'yes\|no\|n/a'
}

@test "release doc has a single Output Format heading" {
  local count
  count=$(grep -c '^## Output Format$' "$RELEASE_CMD")
  [ "$count" -eq 1 ]
}

# --- Finalize Step 4: cleanup visibility (Finding 5) ---

@test "finalize step 4 does not suppress remote deletion errors silently" {
  local step4
  step4=$(awk '/^### Finalize Step 4/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  [ -n "$step4" ]
  # Remote deletion must not use blanket || true suppression
  ! echo "$step4" | grep -q 'push origin --delete.*|| true'
  # Must warn on failure instead
  echo "$step4" | grep -qi 'warn\|Could not delete\|delete manually'
}

@test "finalize step 4 classifies remote not-found as success" {
  local step4
  step4=$(awk '/^### Finalize Step 4/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  echo "$step4" | grep -qi 'not-found\|not found\|does not exist\|already gone'
}

@test "finalize step 4 continues on cleanup failure (non-fatal)" {
  local step4
  step4=$(awk '/^### Finalize Step 4/{found=1; next} /^###/{found=0} found{print}' "$RELEASE_CMD")
  echo "$step4" | grep -qi 'non-fatal\|continue.*Step 5\|continue.*regardless'
}
