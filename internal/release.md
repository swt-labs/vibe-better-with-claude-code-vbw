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
5. **No CHANGELOG.md:** If CHANGELOG.md does not exist:
   - If `--dry-run` (with or without `--skip-audit`): display "ℹ Would create CHANGELOG.md" but do NOT write. Skip to Guard 6.
   - Otherwise: create CHANGELOG.md with `# Changelog\n\nAll notable changes to VBW will be documented in this file.\n`. Display: "ℹ Created CHANGELOG.md." Skip to Guard 6.
6. **Version sync:** `bash scripts/bump-version.sh --verify`. Out of sync → WARN but proceed (bump fixes it).
7. **Existing release branch:** Check local and remote for existing `release/v*` branches:
   - **Local:** `git branch --list 'release/v*'` — note: `git branch --list` always exits 0 regardless of matches; check that stdout is non-empty to detect existing branches.
   - **Remote:** `git ls-remote --heads origin 'refs/heads/release/v*'` — note: `git ls-remote` always exits 0 when the remote is reachable, even with no matches; check stdout content for matches. A non-zero exit code indicates auth/network failure (see below).
   - If remote check exits non-zero (auth/network/repo failure) → STOP: "Could not verify remote release branches (`origin` unreachable or unauthorized). Fix remote access and retry."
   - If local or remote checks produce non-empty stdout (indicating matching branches exist) → **auto-cleanup** all stale release branches before proceeding. Collect all matching branch names (local + remote, deduplicated). Initialize counters: `{cleaned}=0`, `{failed}=0`. For each `release/v{version}` branch:
     - Find associated open PR: `gh pr list --state open --head release/v{version} --json number,state --limit 1`. If `gh` is unavailable or the command exits non-zero (auth/network/API failure), skip PR lookup and display: "⚠ gh CLI unavailable or failed — deleting branch; check for orphaned PRs manually."
     - Display: "⚠ Cleaning up stale release branch `release/v{version}` (PR #{N}, {state})" (or without PR info if `gh` unavailable/failed).
     - Delete local branch: `git branch -D release/v{version}`. If the branch doesn't exist locally, skip silently. If deletion fails for another reason (non-zero exit), increment `{failed}` and display: "⚠ Failed to delete local branch `release/v{version}`."
     - Delete remote branch: `git push origin --delete release/v{version} 2>&1`. If deletion succeeds, increment `{cleaned}`. If stderr contains `remote ref does not exist` (or similar not-found message), treat as success (already gone) and increment `{cleaned}`. If deletion fails for another reason (non-zero exit with different stderr, e.g., permissions or network error), increment `{failed}` and display: "⚠ Failed to delete remote branch `release/v{version}`." (Deleting the remote head branch auto-closes any associated PR on GitHub.)
   - If `{failed} > 0` and `{cleaned} == 0` → STOP: "All branch deletions failed. Check permissions and retry."
   - If `{failed} > 0` → display: "⚠ {failed} branch deletion(s) failed ({failed_branches} could not be fully cleaned) — check warnings above."
   - Display cleanup summary: "ℹ Cleaned up {cleaned} stale release branch(es). Proceeding with fresh release."
   - **Remote deletion error classification:** When `git push origin --delete` exits non-zero, classify the error by stderr content: (1) if stderr contains `remote ref does not exist`, `does not exist`, or `unable to delete.*not found` → treat as success (branch already gone), increment `{cleaned}`; (2) for any other stderr content → treat as failure, increment `{failed}`. **Do not match bare `not found`** — it is too broad and would misclassify repo-level errors like `repository 'X' not found` as success. The specific patterns above cover Git's known branch-not-found messages across versions and transports (HTTPS, SSH). If a future Git version changes the message, the worst case is a false failure (conservative), not a false success.

## Pre-release Audit

Skip if `--skip-audit`.

### Version Pre-computation

Compute `{new-version}` before the audit so changelog entries use the final version header directly:
- Read `VERSION` to get the current version.
- Apply the bump level: `--major` increments major and resets minor.patch to 0, `--minor` increments minor and resets patch to 0, default (no flag) increments patch.
- Store `{new-version}` and `{release-date}` (today's date, `YYYY-MM-DD`) for use in audit remediation.

**Audit 1: Collect changes since last release.**
- Find last release commit: `git log --extended-regexp --grep="^chore(\(release\))?!?: (release )?v[0-9]" --format="%H %s"`, then subject-verify each candidate to find the first true match (fallback: root commit). **Subject verification procedure:** For each candidate line, split on the first space to separate `{hash}` and `{subject}`. Test `{subject}` against the regex `^chore(\(release\))?!?: (release )?v[0-9]`. Take the first candidate whose subject matches. If no candidate's subject matches after exhausting the full list, fall back to the repository root commit (`git rev-list --max-parents=0 HEAD | head -1`). **No truncation:** The candidate list is not truncated (no `head` pipe); this avoids silently dropping the true release commit when many body-line false positives precede it. In practice this list is small (release commits are infrequent), so full iteration is cheap. The `--extended-regexp` pattern matches `chore: release v{x}` (no scope), `chore(release): v{x}` (scoped), `chore(release): release v{x}` (scoped with redundant prefix), and `chore(release)!: v{x}` (breaking-change marker). The `(\(release\))?` group restricts the scope to exactly `(release)` or no scope, preventing false positives from other scopes like `chore(deps): v2.0.0`. The `!?` allows an optional breaking-change indicator after the scope. The `(release )?v[0-9]` anchor excludes `chore(release): bump version` commits. **Limitation:** `git log --grep` matches any line in the commit message (subject + body), so the subject-verification step is required to avoid false positives from body lines like `chore: release v1.30.0 was the previous release`. Capture the match's date via `git log -1 --format='%cd' --date=short {hash}` (fallback: empty string, which omits the `merged:>=` filter). **Note:** `--format='%cd'` with `--date=short` produces `YYYY-MM-DD`. Do NOT use `--format=%Y-%m-%d` — in git's format language `%Y`/`%m`/`%d` are not date placeholders (they output literal text, left/right marks, and ref decorations respectively).
- List merged PRs since that date: `gh pr list --state merged --base main --search "merged:>={date}" --json number,title,labels,body --limit 200`. If `gh` is not available or the command fails (auth error, network error), display "⚠ gh CLI unavailable — using commit-only mode" and skip PR collection. All changelog entries will come from the commit fallback.
- If the PR count equals the `--limit` cap, display: "⚠ PR list may be truncated at 200. Older PRs could be missing — verify changelog completeness manually."
- List first-parent commits since: `git log --first-parent {hash}..HEAD --oneline`. Using `--first-parent` excludes individual branch commits that were brought in by merge commits, preventing duplicate fallback entries for regular-merge PRs. These are used for the commit fallback.
- **Commit-to-PR correlation:** Scan commit messages for PR references (patterns: `(#N)`, `Merge pull request #N`). Commits whose message references any collected PR number are "covered" and excluded from the commit fallback. Only uncovered commits generate fallback entries. This avoids per-PR API calls and works reliably with merge (merge commits contain `Merge pull request #N`), squash (GitHub appends `(#N)` to squash commit subjects), and mixed strategies. **Note:** Rebase merges do not append PR numbers to commit subjects, so rebase-merged commits will appear as "uncovered" and generate commit fallback entries (potential duplication with their PR entry). This is acceptable for VBW since the repository uses merge/squash strategy; if rebase merges are introduced, review the commit fallback output for duplicates.

**Audit 2: Check changelog completeness.**
- If CHANGELOG.md does not exist (Guard 5 dry-run path), treat all entries as undocumented and skip extraction.
- Otherwise, check if a `## [{new-version}]` section already exists (from a previous aborted run). If so, extract its content for completeness checking. If not, all entries are undocumented.
- For each merged PR, check if its number (`#N`) or title keywords appear in the extracted section. Classify as documented or undocumented.
- For direct-push commits (not in any merged PR), check similarly.

**Audit 3:** README staleness: compare command count (`ls commands/*.md | wc -l`), hook count, and modified-command table coverage against README.

**Audit 4:** Display branded audit report: merged PR count, direct commit count, changelog coverage, undocumented PRs (⚠), undocumented commits (⚠), README staleness (⚠ or ✓).

**Audit 5: Remediation** (if issues found):
- **Dry-run gate:** If `--dry-run`, show all generated entries below but do NOT write any files. Display "○ Dry run — no changes written." after showing suggestions. Skip insertion.
- **Changelog — PR-centric generation (primary):** For each undocumented merged PR, generate an entry from the PR title and body. Classify by PR title prefix or labels: `feat`→Added, `fix`→Fixed, `refactor`/`perf`/`chore`→Changed, `docs`→Changed, `test`→Changed. If the PR title has no recognized prefix and no classifying labels, default to `Changed`. Extract scope from the PR title prefix `{type}({scope}):` or from the primary area of the PR. Read the PR body/diff summary to write a concise description of what changed and why. Format: `- **\`{scope}\`** -- {description}. (PR #{number})`. Group entries under `### Added`, `### Changed`, `### Fixed` sub-headers matching the existing changelog style.
- **Changelog — commit fallback:** For commits not covered by any merged PR (uncovered commits from Audit 1 correlation), generate entries by commit prefix (feat→Added, fix→Fixed, refactor/perf→Changed, no prefix→Changed). Format: `- **\`{scope}\`** -- {description}`.
- **Insertion (non-dry-run only):** Show generated entries for review. **Stale section cleanup:** Before inserting, run `git fetch --tags --quiet`. If `git fetch --tags` exits non-zero (network failure, auth expired), display "⚠ Could not fetch tags from remote — skipping stale section cleanup to avoid deleting valid sections." and skip the entire stale cleanup step (proceed directly to insertion). If fetch succeeds, scan CHANGELOG for `## [{version}]` headers where `{version}` matches a semver pattern (`[0-9]+\.[0-9]+\.[0-9]+`), has no corresponding git tag (the output of `git tag -l "v{version}"` is empty — note: `git tag -l` always exits 0 regardless of matches, so check stdout content, not exit code), and `{version}` differs from `{new-version}`. Skip any header that doesn't match the semver pattern (treat as non-version content, e.g., `## [Overview]`). Remove each stale section (header through content until next `## [` or EOF). Display: "ℹ Removed stale changelog section for v{version} (untagged)." Create a `## [{new-version}] - {release-date}` section header and insert it with the generated entries directly above the first existing `## [x.y.z]` entry. If no version entries exist, insert after the last non-empty line following the `# Changelog` header. If a `## [{new-version}]` section already exists (from a previous aborted run), merge new entries into it on user confirmation only.
- **README:** Show specific corrections, apply on confirmation.
README corrections require explicit user confirmation.

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

### Step 4: Verify version sync

`bash scripts/bump-version.sh --verify`. Fail → STOP: "Version sync failed after bump."

### Step 5: Commit

Stage individually (only if modified): VERSION, .claude-plugin/plugin.json, .claude-plugin/marketplace.json, marketplace.json, CHANGELOG.md (if changed), README.md (if changed). Commit: `chore: release v{new-version}`

### Step 6: Push release branch

--no-push: "○ Push skipped. Run `git push -u origin release/v{new-version}` when ready."
Otherwise: `git push -u origin release/v{new-version}`. Display ✓.

### Step 7: Open draft PR

--no-push: skip. Otherwise: `gh pr create --base main --head release/v{new-version} --title "chore: release v{new-version}" --body "Release v{new-version}\n\nBumps version across all 4 files. Updates CHANGELOG.\n\nAfter merging, run \`/vbw:release --finalize\` to tag and create the GitHub release." --draft`. If gh unavailable/fails: "⚠ PR creation failed — create manually."

### Step 8: Present summary

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
5. **Tag already exists:** If `git tag -l "v{version}"` outputs a match (note: `git tag -l` always exits 0 regardless of matches — check that stdout is non-empty, not the exit code), check if it points to `{release_sha}` (`git rev-parse "v{version}^{commit}"`). If it matches → skip tagging, continue to Step 2. If it points elsewhere → STOP: "Tag v{version} already exists but points to a different commit. Resolve manually."

### Finalize Step 1: Tag release commit

`git tag -a v{version} {release_sha} -m "Release v{version}"`. Tags the exact release commit, not HEAD.

### Finalize Step 2: Push tag

If tag was already pushed (`git ls-remote --tags origin "v{version}"` produces non-empty stdout — note: `git ls-remote` always exits 0 when the remote is reachable, so check that stdout is non-empty, not the exit code; a non-zero exit code indicates a transport or authentication failure) → display "○ Tag already on remote." and skip.
If `git ls-remote` exits non-zero (remote unreachable or auth failure), skip the already-pushed check and attempt push directly — push will surface the real error if the remote is unreachable.
Otherwise: `git push origin v{version}`. Display ✓.

### Finalize Step 3: GitHub Release

If release already exists (`gh release view v{version} &>/dev/null` succeeds) → display "○ GitHub release already exists." and skip.
Otherwise: Extract changelog for this version from CHANGELOG.md. Auth resolution (try in order): (1) `gh auth token` — preferred, uses gh CLI's native auth; (2) extract token from git remote URL (`https://user:TOKEN@github.com/...`), set as `GH_TOKEN` env prefix; (3) existing `GH_TOKEN` env var. Run `gh release create v{version} --title "v{version}" --notes "{content}"`. If gh unavailable/fails: "⚠ GitHub release failed — create manually."

### Finalize Step 4: Clean up release branch

Delete local release branch if it still exists: `git branch -d release/v{version} 2>/dev/null || true`
Delete remote release branch: `git push origin --delete release/v{version} 2>&1`. If stderr contains a branch-not-found message (`remote ref does not exist`, `does not exist`, `unable to delete.*not found`), treat as success (already gone). Do not match bare `not found` (too broad — see Guard 7 classification note). If deletion fails for another reason, display: "⚠ Could not delete remote branch `release/v{version}` — delete manually." This is non-fatal (release is already tagged); continue to Step 5 regardless.

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
