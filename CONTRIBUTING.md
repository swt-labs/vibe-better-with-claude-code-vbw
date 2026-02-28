# Contributing to VBW

Thanks for considering a contribution. VBW is a Claude Code plugin, so the conventions are slightly different from a typical codebase.

## Prerequisites

- Claude Code v1.0.33+ with Opus 4.6+
- Agent Teams enabled
- Familiarity with the [Claude Code plugin system](https://code.claude.com/docs/en/plugins)

## Local Development

Clone the repo:

```bash
git clone https://github.com/yidakee/vibe-better-with-claude-code-vbw.git
```

### Loading your local VBW

If you have VBW installed from the marketplace, uninstall it first so the marketplace version doesn't conflict with your local copy:

```bash
# Inside a Claude Code session
/plugin uninstall vbw@vbw-marketplace

# Then back in your regular terminal — clear the command cache only
rm -rf ~/.claude/commands/vbw
```

> **Do NOT `rm -rf ~/.claude/plugins/cache/vbw-marketplace`** — you need the cache directory structure for the symlink in the next step.

### Setting up the plugin cache symlink (required)

VBW commands reference scripts at runtime via a cache glob path (`~/.claude/plugins/cache/vbw-marketplace/vbw/*/scripts/...`). The `--plugin-dir` flag only affects command and agent loading — it does **not** set the `CLAUDE_PLUGIN_ROOT` environment variable in bash subprocesses. Without a cache entry to glob, all runtime script references will fail.

The fix is a symlink from the cache directory to your local clone:

```bash
# Create the cache directory structure (safe even if it already exists)
mkdir -p ~/.claude/plugins/cache/vbw-marketplace/vbw

# Remove any existing versioned cache entries (from a previous marketplace install)
rm -rf ~/.claude/plugins/cache/vbw-marketplace/vbw/*/

# Create symlink — replace the path with your actual clone location
ln -s /absolute/path/to/vibe-better-with-claude-code-vbw \
  ~/.claude/plugins/cache/vbw-marketplace/vbw/local
```

Verify it worked:

```bash
ls -la ~/.claude/plugins/cache/vbw-marketplace/vbw/
# Should show: local -> /absolute/path/to/vibe-better-with-claude-code-vbw

# Quick sanity check — this should print a path to your clone
ls ~/.claude/plugins/cache/vbw-marketplace/vbw/*/scripts/hook-wrapper.sh
```

**Why this is needed:** VBW command templates contain fenced code blocks that execute at template-processing time to resolve the plugin root path. Claude Code's template processor runs `!` backtick expressions inside fenced code blocks via bash, but `CLAUDE_PLUGIN_ROOT` is only available as a template-engine variable (for `@${CLAUDE_PLUGIN_ROOT}/...` file inclusions) — it is **not** passed as a shell environment variable. So the resolution falls through to a glob of `~/.claude/plugins/cache/vbw-marketplace/vbw/*/`. The symlink ensures that glob finds your local clone.

**What fails without it:** The `Plugin root:` preamble in every command resolves to an empty string. The preamble creates a per-session symlink at `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}` pointing to the resolved root. All downstream script callsites construct this same symlink path deterministically — no shared temp file is involved. Without a valid cache entry, the symlink target is empty and all script calls fail.

### Launching Claude Code

Use `--plugin-dir` with the **absolute path** to your cloned VBW repo. This works from any directory — you don't need to be inside the VBW repo.

```bash
# From inside the VBW repo itself (quick smoke test)
claude --plugin-dir .

# From any other project (the typical case — testing VBW against a real codebase)
cd ~/repos/my-other-project
claude --plugin-dir /absolute/path/to/vibe-better-with-claude-code-vbw
```

All `/vbw:*` commands will load from your local copy. Restart Claude Code to pick up changes after editing VBW files.

> **Important:** `--plugin-dir` loads whatever is on disk in your VBW clone, which means whatever branch is currently checked out. Make sure you're on the branch with your changes before launching Claude Code — if you're on `main`, you'll be testing the unchanged version.

> **Known limitation:** Plugin hooks (the 21 event handlers in `hooks.json`) resolve scripts from the marketplace cache via the symlink. This means hooks will run (unlike before the symlink existed), but they execute from your local clone — changes to hook scripts take effect immediately without a cache refresh. The git pre-push hook is a separate mechanism — see [Version Management](#version-management).

## Project Structure

```text
.claude-plugin/    Plugin manifest (plugin.json)
agents/            7 agent definitions with native tool permissions
commands/          24 slash commands (commands/*.md)
config/            Default settings and stack-to-skill mappings
hooks/             Plugin hooks (hooks.json)
scripts/           Hook handler scripts
references/        Brand vocabulary, verification protocol, effort profiles
templates/         Artifact templates (PLAN.md, SUMMARY.md, etc.)
assets/            Images and static files
```

Key conventions:

- **Commands** live in `commands/*.md`. Use explicit prefixed names in frontmatter (e.g., `name: vbw:init`) so commands show as `/vbw:*`.
- **Agents** in `agents/` use YAML frontmatter for tool permissions enforced by the platform.
- **Hooks** in `hooks/hooks.json` self-resolve scripts via `ls | sort -V | tail -1` against the plugin cache.
- **Plugin root resolution:** `CLAUDE_PLUGIN_ROOT` is a template-engine variable only — it works for `@${CLAUDE_PLUGIN_ROOT}/...` file inclusions but is **not** available as a shell env var inside `!` backtick fenced blocks. Each command's preamble resolves the plugin root via a priority cascade (env var → `local` symlink → versioned cache → generic cache fallback → session symlink glob → process tree) and creates a deterministic key (session id when present; otherwise `pwd` hash), e.g. `/tmp/.vbw-plugin-root-link-${SESSION_KEY}`. Reader callsites construct this path deterministically — no shared mutable temp file is used. See [Setting up the plugin cache symlink](#setting-up-the-plugin-cache-symlink-required) for local dev setup.

## What to Contribute

Good candidates:

- Bug fixes in hook scripts or commands
- New slash commands that fit the lifecycle model (init, vibe, verify, release)
- Improvements to agent definitions or tool permissions
- Stack-to-skill mappings in `config/`
- Template improvements

Less good candidates:

- Rewrites of the core lifecycle flow without prior discussion
- Features that require dependencies or build steps (VBW is zero-dependency by design)
- Changes that break the effort profile system

## Making Changes

1. **Fork the repo** and create a feature branch from `main` (e.g., `fix/hook-path` or `feat/new-command`). **Never commit directly to `main`** — `main` has branch protection and direct pushes will be rejected.
2. **Test locally** with `claude --plugin-dir "<path-to-vbw-clone>"` against a real project before submitting.
   - Run automated checks: `bash testing/run-all.sh` (validates script conventions, command frontmatter, init workflow, and bootstrap)
3. **Keep commits atomic** -- one logical change per commit.
4. **Match the existing tone** in command descriptions and user-facing text. VBW is direct, dry, and self-aware. It doesn't use corporate language or unnecessary enthusiasm.
5. **Follow code style:**
   - Shell scripts: bash, no external dependencies beyond `jq` and `git`
   - Markdown commands: YAML frontmatter with single-line `description` field
   - No prettier on `.md` files with frontmatter (use `.prettierignore`)

## Pull Request Process

1. **Every PR must link a tracking issue.** Open an issue first (bug report or feature request), then reference it in the PR body. CI will fail if no linked issue is found. Accepted formats:
   - Closing keywords: `Fixes #N`, `Closes #N`, `Resolves #N`
   - Full GitHub issue URLs: `https://github.com/owner/repo/issues/N`
   - Bare issue references: `#N` (any `#` followed by a valid issue number)
   - Sidebar-linked issues (via the GitHub "Development" section on the PR)
2. Describe what changed and why. Include before/after if relevant.
3. Ensure `claude --plugin-dir "<path-to-vbw-clone>"` loads without errors.
4. Test your changes against at least one real project (not the VBW repo itself).
5. **Run QA review before marking ready.** Repeat this cycle at least 3 times (or until the latest report contains no confirmed critical/major issues):

   > **Docs-only or trivial PRs:** The QA round requirement only applies when the PR touches plugin logic paths (`agents/`, `commands/`, `config/`, `hooks/`, `references/`, `scripts/`, `templates/`, `testing/`, `tests/`). PRs that only change docs, CI config, or repo metadata skip the check automatically.

   **Step A — Run the QA prompt.** Open a **new** Claude Code (or other AI) session using a top-tier model — **Claude Opus 4.6**, **GPT-5.3 Codex high/xhigh**, or **Gemini 3.1 Pro**. Smaller models (Haiku, Sonnet, etc.) don't produce thorough enough reviews. Paste the prompt below (fill in the placeholders):

   ````text
   You are a read-only QA reviewer. Do NOT modify files, make commits, or push fixes — report only.

   PR: #<number>
   Branch: <branch-name>

   1. Review the commits in the PR to understand the change narrative.
   2. Read all files changed in the PR for full context.
   3. Act as a devil's advocate — find edge cases, missed regressions, and untested
      paths the implementer didn't consider.

   Do NOT prescribe what to test upfront. Discover what matters by reading the code.

   Report format (use a markdown code block):
   - Model used: (e.g., Claude Opus 4.6, GPT-5.3 Codex (high or xhigh), Gemini 3.1 Pro)
   - What was tested
   - Expected vs actual
   - Severity (critical / major / minor)
   - Confirmed vs hypothetical
   ````

   **Step B — Fix the findings.** Copy the QA report and paste it into your original working session (or a new session on the same branch). Tell it to fix the issues found. Each QA round's fixes must be a **separate commit** — do not amend previous commits. Use the format `fix(scope): address QA round N`.

   **Step C — Repeat.** Go back to Step A with a fresh session. The new QA round will see the fix commits from Step B and look for anything still missed. Continue until a round comes back clean or only has hypothetical/minor findings.

   **Proving your work:** Paste each round's QA report as a separate comment on the PR. Reviewers will cross-reference the reports against the fix commits in the PR history.

### Switching back to marketplace VBW

When you're done testing your local changes, remove the symlink and re-install the marketplace version:

```bash
# Remove the local dev symlink
rm ~/.claude/plugins/cache/vbw-marketplace/vbw/local

# Start Claude Code normally (without --plugin-dir)
claude
```

Then inside the Claude Code session:

```text
/plugin marketplace add yidakee/vibe-better-with-claude-code-vbw
/plugin install vbw@vbw-marketplace
```

## Version Management

VBW keeps the version in sync across four files:

| File | Field |
| ------ | ------- |
| `VERSION` | Plain text, single line |
| `.claude-plugin/plugin.json` | `.version` |
| `.claude-plugin/marketplace.json` | `.plugins[0].version` |
| `marketplace.json` | `.plugins[0].version` |

All four **must** match at all times.

**Version bumping happens at merge time.** When a PR is merged to `main`, the maintainer bumps the version across all 4 files using the bump script and commits the result. Contributors do not need to bump versions in their branches.

To bump the version (maintainer only):

```bash
bash scripts/bump-version.sh
git add VERSION .claude-plugin/plugin.json .claude-plugin/marketplace.json marketplace.json
git commit -m "chore: bump version to $(cat VERSION)"
```

To verify that all four files are in sync locally:

```bash
scripts/bump-version.sh --verify
```

This exits `0` if all versions match and `1` with a diff report if they diverge.

### Push Workflow

A git pre-push hook enforces that all 4 version files are **consistent** (same value). It does **not** require a version bump — that happens at merge time.

```bash
# Work freely, commit as needed
git commit -m "feat(commands): add new feature"
git push
```

The hook only blocks pushes if the 4 version files have mismatched values. Use `git push --no-verify` to bypass in rare cases.

The pre-push hook is auto-installed by `/vbw:init` when running the marketplace version. In local dev mode (via `--plugin-dir`), you can install it manually:

```bash
bash scripts/install-hooks.sh
```

To verify version consistency without the hook:

```bash
bash scripts/bump-version.sh --verify
```

> **Note:** The git pre-push hook installed by `scripts/install-hooks.sh` delegates to the marketplace cache. With the [symlink](#setting-up-the-plugin-cache-symlink-required) in place, the hook will run your local copy's version check. Without the symlink, the hook silently passes. Use the manual `--verify` command above before pushing if you haven't set up the symlink.

### Release Command (Maintainer Only)

`/vbw:release` lives in `internal/release.md` — outside the `commands/` directory so it's never auto-discovered by the plugin system. Marketplace consumers don't see it.

#### Release authorization (CODEOWNERS + branch protection)

Release is a two-phase, approval-gated workflow:

1. Run `/vbw:release` to prepare `release/v{version}` and open a **draft** PR to `main`. If stale release branches exist from a previous run, the command automatically cleans them up before proceeding.
2. Mark the PR ready for review and get required approvals from reviewers listed in `.github/CODEOWNERS` (source of truth).
3. Merge the release PR to `main` under branch protection.
4. On updated local `main`, run `/vbw:release --finalize` to create/push the tag and GitHub release.

**Authorization rule:** Release is authorized by the approved-and-merged PR. If the release PR is not approved/merged, do **not** run finalize.

#### Release flags quick reference (for contributors)

Use these flags with `/vbw:release`:

| Flag | Phase | Meaning |
| ---- | ----- | ------- |
| *(none)* | Prepare only | Default is a patch bump (e.g., `1.2.3 -> 1.2.4`). |
| `--finalize` | Finalize only | Run post-merge finalize flow (tag + GitHub release). |
| `--dry-run` | Prepare only | Show release plan/audit output without writing changes. |
| `--no-push` | Prepare only | Create release commit locally but do not push branch or open PR. |
| `--major` | Prepare only | Major bump (e.g., `1.2.3 -> 2.0.0`). |
| `--minor` | Prepare only | Minor bump (e.g., `1.2.3 -> 1.3.0`). |
| `--skip-audit` | Prepare only | Skip pre-release audit checks. |

Compatibility rule:

- `--finalize` **cannot** be combined with prepare-only flags (`--dry-run`, `--no-push`, `--major`, `--minor`, `--skip-audit`).
- Mixed usage is a hard stop, not "ignore and continue".

Default behavior notes:

- There is no `--patch` flag because patch is the default when neither `--major` nor `--minor` is provided.
- There is no `--push` flag because prepare mode pushes by default; `--no-push` is the explicit opt-out.

Common examples:

```text
/vbw:release
/vbw:release --minor
/vbw:release --dry-run
/vbw:release --no-push
/vbw:release --finalize
```

To make it available locally, copy it to your personal commands directory:

```bash
mkdir -p ~/.claude/commands
cp internal/release.md ~/.claude/commands/vbw-release.md
```

This registers it as `/vbw-release` (personal commands don't get the plugin namespace prefix). Re-copy after pulling changes that modify `internal/release.md`.

> **Note:** `${CLAUDE_PLUGIN_ROOT}` is only set for plugin-scoped commands. Personal commands won't resolve the `@${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md` brand reference — output formatting may differ slightly. The two-phase workflow (prepare: bump, commit, release branch, draft PR; finalize: tag, GitHub release after merge) is unaffected. For full fidelity, use `claude --plugin-dir .` instead.

To remove it:

```bash
rm ~/.claude/commands/vbw-release.md
```

## Reporting Bugs

Use the [bug report template](https://github.com/yidakee/vibe-better-with-claude-code-vbw/issues/new?template=bug_report.md). Include your Claude Code version, the command that failed, and any error output.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
