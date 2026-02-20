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

If you have VBW installed from the marketplace, uninstall it and clear the caches first so the marketplace version doesn't conflict with your local copy:

```bash
# Inside a Claude Code session
/plugin uninstall vbw@vbw-marketplace

# Then back in your regular terminal
rm -rf ~/.claude/plugins/cache/vbw-marketplace
rm -rf ~/.claude/commands/vbw
```

Use `--plugin-dir` with the **absolute path** to your cloned VBW repo. This works from any directory — you don't need to be inside the VBW repo.

```bash
# From inside the VBW repo itself (quick smoke test)
claude --plugin-dir .

# From any other project (the typical case — testing VBW against a real codebase)
cd ~/repos/my-other-project
claude --plugin-dir "<path-to-vbw-clone>"
```

All `/vbw:*` commands will load from your local copy. Restart Claude Code to pick up changes after editing VBW files.

> **Important:** `--plugin-dir` loads whatever is on disk in your VBW clone, which means whatever branch is currently checked out. Make sure you're on the branch with your changes before launching Claude Code — if you're on `main`, you'll be testing the unchanged version.

> **Known limitation:** Plugin hooks (the 21 event handlers in `hooks.json`) resolve scripts from the marketplace cache (`~/.claude/plugins/cache/...`), not from `--plugin-dir`. In local dev mode the cache is empty, so **all plugin hooks are no-ops** — security filters, QA gates, commit validation, session-start migration, etc. will not run. Commands and agents load correctly; only plugin hooks are affected. Keep this in mind when testing hook-dependent features. (The git pre-push hook is a separate mechanism — see [Version Management](#version-management).)

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
- **Hooks** in `hooks/hooks.json` self-resolve scripts via `ls | sort -V | tail -1` against the plugin cache (they do not use `CLAUDE_PLUGIN_ROOT`).

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

1. Open an issue first for non-trivial changes so we can discuss the approach.
2. Reference the issue in your PR.
3. Describe what changed and why. Include before/after if relevant.
4. Ensure `claude --plugin-dir "<path-to-vbw-clone>"` loads without errors.
5. Test your changes against at least one real project (not the VBW repo itself).
6. **Run QA review before marking ready.** Repeat this cycle at least 2–4 times:

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

When you're done testing your local changes, re-install the marketplace version:

```bash
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

The pre-push hook is auto-installed by `/vbw:init` when running the marketplace version. In local dev mode (via `--plugin-dir`), plugin hooks are no-ops so auto-install won't trigger. You can still verify version consistency manually:

```bash
bash scripts/bump-version.sh --verify
```

> **Note:** The git pre-push hook installed by `scripts/install-hooks.sh` delegates to the marketplace cache, which is empty in local dev mode. The hook will silently pass without checking. Use the manual `--verify` command above before pushing if you've touched version files.

## Reporting Bugs

Use the [bug report template](https://github.com/yidakee/vibe-better-with-claude-code-vbw/issues/new?template=bug_report.md). Include your Claude Code version, the command that failed, and any error output.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
