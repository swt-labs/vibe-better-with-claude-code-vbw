---
name: vbw:release
category: lifecycle
disable-model-invocation: true
description: Bump version, finalize changelog, tag, commit, push, and create a GitHub release.
argument-hint: "[--dry-run] [--no-push] [--major] [--minor] [--skip-audit]"
allowed-tools: Read, Edit, Bash, Glob, Grep
---

# VBW Release $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Version: `!`cat VERSION 2>/dev/null || echo "No VERSION file"``
Git status:
```
!`git status --short 2>/dev/null || echo "Not a git repository"`
```

## Guard

1. **Not a VBW repo:** No VERSION file → STOP: "No VERSION file found. Must run from VBW plugin root."
2. **Dirty tree:** If `git status --porcelain` shows uncommitted changes (excluding .claude/ and CLAUDE.md), WARN + confirm: "Uncommitted changes detected. They will NOT be in the release commit. Continue?"
3. **No [Unreleased]:** If CHANGELOG.md lacks `## [Unreleased]`, WARN + confirm: "No [Unreleased] section. Release commit will only bump versions. Continue?"
4. **Version sync:** `bash scripts/bump-version.sh --verify`. Out of sync → WARN but proceed (bump fixes it).

## Pre-release Audit

Skip if `--skip-audit`.

**Audit 1:** Find commits since last release: `git log --oneline --grep="chore: release" -1`, extract hash (fallback: root commit). List all commits since: `git log {hash}..HEAD --oneline`.

**Audit 2:** Check changelog completeness. Extract [Unreleased] content. For each commit, check if scope/key terms appear. Classify as documented or undocumented.

**Audit 3:** README staleness: compare command count (`ls commands/*.md | wc -l`), hook count, and modified-command table coverage against README.

**Audit 4:** Display branded audit report: commit count, changelog coverage, undocumented commits (⚠), README staleness (⚠ or ✓).

**Audit 5: Remediation** (if issues found):
- **Changelog:** Generate entries by commit prefix (feat→Added, fix→Fixed, refactor/perf→Changed, other→Changed). Format: `- **\`{scope}\`** -- {description}`. Show for review, insert under [Unreleased] on confirmation.
- **README:** Show specific corrections, apply on confirmation.
- **Dry-run:** Show suggestions only, no writes: "○ Dry run -- no changes written."
Both require explicit user confirmation.

## Steps

### Step 1: Parse arguments

| Flag | Effect |
|------|--------|
| --dry-run | Show plan, no mutations |
| --no-push | Bump+commit, no push |
| --major | Major bump (1.0.70→2.0.0) |
| --minor | Minor bump (1.0.70→1.1.0) |
| --skip-audit | Skip pre-release audit |

No flags = patch bump (default).

### Step 2: Bump version

--major/--minor: read VERSION, compute new version, write to all 4 files (VERSION, .claude-plugin/plugin.json, .claude-plugin/marketplace.json, marketplace.json).
Neither flag: `bash scripts/bump-version.sh`. Capture new version.

### Step 3: Update CHANGELOG header

If [Unreleased] exists: replace with `## [{new-version}] - {YYYY-MM-DD}`. Display ✓.
No [Unreleased]: display ○.

### Step 4: Verify version sync

`bash scripts/bump-version.sh --verify`. Fail → STOP: "Version sync failed after bump."

### Step 5: Commit

Stage individually (only if modified): VERSION, .claude-plugin/plugin.json, .claude-plugin/marketplace.json, marketplace.json, CHANGELOG.md (if changed), README.md (if changed). Commit: `chore: release v{new-version}`

### Step 6: Tag

`git tag -a v{new-version} -m "Release v{new-version}"`

### Step 7: Push

--no-push: "○ Push skipped. Run `git push && git push --tags` when ready."
Otherwise: `git push` + `git push --tags`. Display ✓.

### Step 8: GitHub Release

--no-push: skip. Otherwise: extract changelog for this version. Auth resolution (try in order): (1) `gh auth token` — preferred, uses gh CLI's native auth; (2) extract token from git remote URL (`https://user:TOKEN@github.com/...`), set as `GH_TOKEN` env prefix; (3) existing `GH_TOKEN` env var. Run `gh release create v{new-version} --title "v{new-version}" --notes "{content}"`. If gh unavailable/fails: "⚠ GitHub release failed -- create manually."

### Step 9: Present summary

Display task-level box with: version old→new, audit result, changelog status, commit hash, tag, push status, release status, files updated list.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — task-level box (single-line), semantic symbols, no ANSI.
