---
name: vbw:release
category: lifecycle
disable-model-invocation: true
description: Two-phase release — prepare a release branch + PR, then finalize after merge.
argument-hint: "[--finalize] [--dry-run] [--no-push] [--major] [--minor] [--skip-audit]"
allowed-tools: Read, Edit, Bash, Glob, Grep
---

# VBW Release $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Version: `!`cat VERSION 2>/dev/null || echo "No VERSION file"``
Current branch: `!`git branch --show-current 2>/dev/null || echo "detached"``
Git status:
```
!`git status --short 2>/dev/null || echo "Not a git repository"`
```

## Guard

1. **Not a VBW repo:** No VERSION file → STOP: "No VERSION file found. Must run from VBW plugin root."
2. **--finalize mode:** If `--finalize` is present **and any prepare-only flags are also present** (`--dry-run`, `--no-push`, `--major`, `--minor`, `--skip-audit`) → reject the mixed flags and STOP (hard error): "Incompatible flags: `{flags}` are prepare-only and cannot be combined with `--finalize`. Re-run with only `--finalize`." Do **not** continue to finalize when this guard fails.
3. **Not on main:** If current branch is not `main` → STOP: "Must be on main to prepare a release. Currently on `{branch}`."
4. **Dirty tree:** If `git status --porcelain` shows uncommitted changes (excluding .claude/ and CLAUDE.md), WARN + confirm: "Uncommitted changes detected. They will NOT be in the release commit. Continue?"
5. **No [Unreleased]:** If CHANGELOG.md lacks `## [Unreleased]`, automatically insert `## [Unreleased]` on a new line directly above the first `## [x.y.z]` entry (or at the top of the file after the `# Changelog` header if no version entries exist). Display: "ℹ Created [Unreleased] section — audit will populate it from commits." Then continue to the audit, which will generate and insert entries under it.
6. **Version sync:** `bash scripts/bump-version.sh --verify`. Out of sync → WARN but proceed (bump fixes it).
7. **Existing release branch:** Check local first (`git branch --list 'release/v*'`) and remote second (`git ls-remote --heads origin 'refs/heads/release/v*'`).
   - If remote check exits non-zero (auth/network/repo failure) → STOP: "Could not verify remote release branches (`origin` unreachable or unauthorized). Fix remote access and retry."
   - If local or remote checks return matches → STOP: "Release branch already exists (local or remote). Run `/vbw:release --finalize` after merging, or delete the stale branch."

## Pre-release Audit

Skip if `--skip-audit`.

**Audit 1:** Find commits since last release: `git log --oneline --grep="chore: release" -1`, extract hash (fallback: root commit). List all commits since: `git log {hash}..HEAD --oneline`.

**Audit 2:** Check changelog completeness. Extract [Unreleased] content. For each commit, check if scope/key terms appear. Classify as documented or undocumented.

**Audit 3:** README staleness: compare command count (`ls commands/*.md | wc -l`), hook count, and modified-command table coverage against README.

**Audit 4:** Display branded audit report: commit count, changelog coverage, undocumented commits (⚠), README staleness (⚠ or ✓).

**Audit 5: Remediation** (if issues found):
- **Changelog:** Generate entries by commit prefix (feat→Added, fix→Fixed, refactor/perf→Changed, other→Changed). Format: `- **\`{scope}\`** -- {description}`. Group entries under `### Added`, `### Changed`, `### Fixed` sub-headers matching the existing changelog style. Show for review. If `[Unreleased]` was auto-created by Guard 5 (empty section), insert entries automatically without confirmation since the section needs content. If `[Unreleased]` already had content, insert on user confirmation only.
- **README:** Show specific corrections, apply on confirmation.
- **Dry-run:** Show suggestions only, no writes: "○ Dry run -- no changes written."
Both require explicit user confirmation.

---

## Prepare Phase (default)

Creates a release branch, bumps version, opens a draft PR. Does NOT tag or create a GitHub release — that happens in the finalize phase after the PR is merged.

### Step 1: Parse arguments

| Flag         | Effect                                 |
| ------------ | -------------------------------------- |
| --finalize   | Run finalize phase instead (see below) |
| --dry-run    | Show plan, no mutations                |
| --no-push    | Bump+commit locally, no push or PR     |
| --major      | Major bump (1.0.70→2.0.0)              |
| --minor      | Minor bump (1.0.70→1.1.0)              |
| --skip-audit | Skip pre-release audit                 |

No flags = patch bump (default).

### Step 2: Create release branch

Compute new version (read VERSION, apply bump level).
Create and switch to release branch: `git checkout -b release/v{new-version}`

### Step 3: Bump version

--major/--minor: read VERSION, compute new version, write to all 4 files (VERSION, .claude-plugin/plugin.json, .claude-plugin/marketplace.json, marketplace.json).
Neither flag: `bash scripts/bump-version.sh`. Capture new version.

### Step 4: Update CHANGELOG header

If [Unreleased] exists: replace with `## [{new-version}] - {YYYY-MM-DD}`. Display ✓.
No [Unreleased]: display ○.

### Step 5: Verify version sync

`bash scripts/bump-version.sh --verify`. Fail → STOP: "Version sync failed after bump."

### Step 6: Commit

Stage individually (only if modified): VERSION, .claude-plugin/plugin.json, .claude-plugin/marketplace.json, marketplace.json, CHANGELOG.md (if changed), README.md (if changed). Commit: `chore: release v{new-version}`

### Step 7: Push release branch

--no-push: "○ Push skipped. Run `git push -u origin release/v{new-version}` when ready."
Otherwise: `git push -u origin release/v{new-version}`. Display ✓.

### Step 8: Open draft PR

--no-push: skip. Otherwise: `gh pr create --base main --head release/v{new-version} --title "chore: release v{new-version}" --body "Release v{new-version}\n\nBumps version across all 4 files. Updates CHANGELOG.\n\nAfter merging, run \`/vbw:release --finalize\` to tag and create the GitHub release." --draft`. If gh unavailable/fails: "⚠ PR creation failed — create manually."

### Step 9: Present summary

Display task-level box with: version old→new, audit result, changelog status, commit hash, release branch name, push status, draft PR status, next step.

Include: "Next: merge the PR, then run `/vbw:release --finalize` to tag and create the GitHub release."

---

## Finalize Phase (`--finalize`)

Run after the release PR has been merged into `main`. Tags the exact release commit and creates the GitHub release.

### Finalize Guard

1. **Must be on main:** If current branch is not `main` → STOP: "Must be on main to finalize. Currently on `{branch}`."
2. **Dirty tree:** If `git status --porcelain` shows uncommitted changes → STOP: "Working tree is dirty. Commit or stash changes before finalizing."
3. **Pull latest:** `git pull origin main` to ensure the merge commit is local.
4. **Locate merged release artifact on main:** Read VERSION to get `{version}`.
   - **Primary path (merge commit):** Search first-parent `main` history for merge commits referencing `release/v{version}`: `git log main --first-parent --grep="Merge pull request .*release/v{version}" --format="%H"`.
     - Exactly one match → store as `{release_sha}`.
     - More than one match → STOP: "Multiple merge commits found for release/v{version}. Resolve manually before finalizing."
   - **Fallback path (squash/rebase):** If no merge-commit match, search first-parent `main` history for commit subject prefix `chore: release v{version}`: `git log main --first-parent --grep="^chore: release v{version}" --format="%H"`.
     - Zero matches → STOP: "Release commit for v{version} not found on main. Was the PR merged?"
     - More than one match → STOP: "Multiple release commits match v{version} on main. Resolve ambiguity manually before finalizing."
     - Exactly one match → store as `{release_sha}`.

> **Merge strategy note:** `--first-parent` ensures finalize tags the merged release artifact on `main` (merge commit for merge strategy, squash commit for squash strategy), not a pre-merge branch commit. This avoids ambiguous tagging when extra commits were added on `release/v{version}` before merge.
5. **Tag already exists:** If `git tag -l "v{version}"` returns a match, check if it points to `{release_sha}` (`git rev-parse "v{version}^{commit}"`). If it matches → skip tagging, continue to Step 2. If it points elsewhere → STOP: "Tag v{version} already exists but points to a different commit. Resolve manually."

### Finalize Step 1: Tag release commit

`git tag -a v{version} {release_sha} -m "Release v{version}"`. Tags the exact release commit, not HEAD.

### Finalize Step 2: Push tag

If tag was already pushed (`git ls-remote --tags origin "v{version}"` returns a match) → display "○ Tag already on remote." and skip.
Otherwise: `git push origin v{version}`. Display ✓.

### Finalize Step 3: GitHub Release

If release already exists (`gh release view v{version} &>/dev/null` succeeds) → display "○ GitHub release already exists." and skip.
Otherwise: Extract changelog for this version from CHANGELOG.md. Auth resolution (try in order): (1) `gh auth token` — preferred, uses gh CLI's native auth; (2) extract token from git remote URL (`https://user:TOKEN@github.com/...`), set as `GH_TOKEN` env prefix; (3) existing `GH_TOKEN` env var. Run `gh release create v{version} --title "v{version}" --notes "{content}"`. If gh unavailable/fails: "⚠ GitHub release failed — create manually."

### Finalize Step 4: Clean up release branch

Delete local release branch if it still exists: `git branch -d release/v{version} 2>/dev/null || true`
Delete remote release branch: `git push origin --delete release/v{version} 2>/dev/null || true`

### Finalize Step 5: Present summary

Display task-level box with: version, tag (commit SHA), GitHub release status, branch cleanup status.

## Flag Compatibility

| Flag         | Prepare | Finalize | Notes                                             |
| ------------ | ------- | -------- | ------------------------------------------------- |
| --finalize   | n/a     | yes      | Switches to finalize phase                        |
| --dry-run    | yes     | no       | Prepare-only; hard STOP with `--finalize`         |
| --no-push    | yes     | no       | Prepare-only; hard STOP with `--finalize`         |
| --major      | yes     | no       | Prepare-only; hard STOP with `--finalize`         |
| --minor      | yes     | no       | Prepare-only; hard STOP with `--finalize`         |
| --skip-audit | yes     | no       | Prepare-only; hard STOP with `--finalize`         |

**Mixed-flag policy:** `--finalize` + any prepare-only flag is an immediate hard STOP. No prepare-only flag is ignored in finalize mode.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — task-level box (single-line), semantic symbols, no ANSI.
