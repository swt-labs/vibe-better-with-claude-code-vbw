# VBW Instructions

A Claude Code plugin adding structured development workflows (plan → execute → verify) via 7 specialized agent teams. Zero external dependencies beyond `jq` and `git`. All logic is bash scripts + markdown.

## Communication Style

- **No AI fluff.** Skip phrases like "Thanks for the thoughtful feedback!", "Happy to help!", "I appreciate...", etc.
- **No soliciting opinions.** Don't end responses with "Would you like me to...", "Let me know if...", "What do you think?", etc.
- **Direct and terse.** State facts, provide options when relevant, then stop.

## Debugging VBW Behavior

When the user reports VBW misbehavior — pasting Claude Code session output, describing incorrect command behavior, or showing unexpected file state — first resolve the contributor's **local debug target repo** instead of guessing a maintainer-specific path.

### Local debug target configuration (private, not committed)

Preferred setup in the VBW clone's shared Git common dir:

```text
$(git rev-parse --git-common-dir)/info/vbw-debug-target.txt
```

In a standard non-worktree clone, this usually resolves to:

```text
.git/info/vbw-debug-target.txt
```

The first non-empty, non-comment line must be the absolute path to the contributor's primary VBW consumer/test repo.
Relative paths are rejected so the resolver produces the same result regardless of the caller's current working directory.

Example local file content:

```text
/absolute/path/to/your-test-repo
```

This file lives under the clone's shared Git metadata, so it stays private and all worktrees created from that clone can read it automatically.

Legacy fallback for a single checkout only:

```text
.claude/vbw-debug-target.txt
```

That legacy file remains supported and gitignored, but it is scoped to one checkout/worktree and will not be copied into new worktrees.

Resolution order:
1. `VBW_DEBUG_TARGET_REPO` env var (one-off override, absolute path only)
2. `$(git rev-parse --git-common-dir)/info/vbw-debug-target.txt` in the current clone (preferred persistent local config, shared across worktrees)
3. `./.claude/vbw-debug-target.txt` in the current checkout/worktree (legacy fallback, absolute path only)
4. `<claude-config-dir>/vbw/debug-target.txt` (user-global fallback, absolute path only; `<claude-config-dir>` is resolved by `scripts/resolve-claude-dir.sh`: `CLAUDE_CONFIG_DIR` if set, else `$HOME/.config/claude-code` when that directory exists, else `$HOME/.claude`)
5. If none are configured, **ask the user for the target repo path** — do not guess.

Use the shared resolver when debugging:

```bash
TARGET_REPO=$(bash scripts/resolve-debug-target.sh repo)
TARGET_PLANNING=$(bash scripts/resolve-debug-target.sh planning-dir)
ENCODED_PATH=$(bash scripts/resolve-debug-target.sh encoded-path)
CLAUDE_PROJECT_DIR=$(bash scripts/resolve-debug-target.sh claude-project-dir)
```

If the resolver exits non-zero, stop guessing and ask the user to configure a debug target.

### Claude Code Log Locations (canonical Claude config root)

In the paths below, `<claude-config-dir>` means the same Claude config root resolved by `scripts/resolve-claude-dir.sh`: `CLAUDE_CONFIG_DIR` if set, else `$HOME/.config/claude-code` when that directory exists, else `$HOME/.claude`.

After resolving the target repo, derive the encoded Claude project path by replacing `/` with `-` in the absolute target-repo path. For an absolute path, the result begins with `-`.

Example rule:

```text
/absolute/path/to/project  ->  -absolute-path-to-project
```

When debugging, search these directories for evidence of what actually happened:

| Path | Contents | Use When |
| ------ | ---------- | ---------- |
| `<target-repo>/.vbw-planning/` | Project state (phases, milestones, config, `STATE.md`) | Ground the investigation in actual workflow state |
| `<claude-config-dir>/projects/{encoded-path}/*.jsonl` | Session transcripts | Replaying what the LLM said/did in a session |
| `<claude-config-dir>/projects/{encoded-path}/{session-id}/subagents/agent-*.jsonl` | Subagent transcripts | Checking what VBW agent team members did |
| `<claude-config-dir>/projects/{encoded-path}/{session-id}/tool-results/` | Tool output snapshots | Seeing exact tool outputs from a session |
| `<claude-config-dir>/debug/{session-id}.txt` | Debug logs (`[DEBUG]`/`[WARN]`) | Startup issues, plugin loading, hook execution failures |
| `<claude-config-dir>/sessions/{pid}.json` | Active session metadata | Mapping a PID to a session ID |
| `<claude-config-dir>/session-env/{session-id}/` | Hook-exported env vars | Verifying `CLAUDE_SESSION_ID` and other env vars |
| `<claude-config-dir>/tasks/{session-id}/` | Task/subagent lock files | Checking for stuck or concurrent task issues |
| `<claude-config-dir>/settings.json` | User-level Claude Code settings and hooks | Verifying hook definitions, permissions, MCP config |

### Common search patterns

```bash
TARGET_REPO=$(bash scripts/resolve-debug-target.sh repo)
CLAUDE_PROJECT_DIR=$(bash scripts/resolve-debug-target.sh claude-project-dir)
CLAUDE_CONFIG_ROOT="$(dirname "$(dirname "$CLAUDE_PROJECT_DIR")")"

# Find sessions for the configured target repo
ls "$CLAUDE_PROJECT_DIR"/*.jsonl

# Search session transcripts for a VBW hook or command
grep -l 'vbw' "$CLAUDE_PROJECT_DIR"/*.jsonl

# Find hook errors in debug logs
grep -El 'hook.*error|hook.*fail' "$CLAUDE_CONFIG_ROOT"/debug/*.txt

# Search for a specific tool invocation across sessions
grep -Erl 'bootstrap-state|state-updater' "$CLAUDE_PROJECT_DIR"/*.jsonl

# Check what a subagent did in a specific session
cat "$CLAUDE_PROJECT_DIR"/<session-id>/subagents/agent-*.jsonl
```

## Conventions

- **Naming**: Commands are kebab-case `.md`, agents are `vbw-{role}.md`, scripts are kebab-case `.sh`, phase dirs are `{NN}-{slug}/`
- **Commits**: `{type}({scope}): {description}` — one atomic commit per task, stage files explicitly (never `git add .`)
- **JSON parsing**: Always use `jq`, never grep/sed on JSON
- **No dependencies**: No package.json, npm, or build step. Everything is bash + markdown
- **YAML frontmatter**: `description` field must be single-line. Use `.prettierignore` for formatting exclusions (no `prettier-ignore` comments)
- **Plugin isolation**: VBW files live in `.vbw-planning/`, GSD files in `.planning/` — never cross-reference between them
- **Token reduction**: When the LLM needs context to make decisions, prefer pre-extracting data via bash scripts (injected in command template expansions) over instructing the LLM to read files at runtime. Scripts produce compact, deterministic output and avoid burning tokens on file reads the agent doesn't need to reason about. Apply this principle whenever adding context to commands.
- **Claude Code template expansion semantics**: Standalone one-line `` !`command` `` directives and fenced `` !`command` `` blocks execute. Embedded `` !`command` `` spans inside prose, paths, or larger strings do **not** execute — Claude passes them through literally. Never build runtime paths or sentence fragments with embedded `!` spans; precompute the value in a fenced block or helper script and reference the resolved output instead.
- **Root-cause fixes only (non-negotiable)**: Every fix must address the underlying root cause. Masking/symptom-only fixes are not allowed. If a temporary mitigation is added, it must be accompanied by a root-cause fix in the same work item (or the task is incomplete).
- **No Python in terminal**: Never run `python3` or `python` via the terminal. Use the available Python execution tool instead. **Exception**: the `.github/scripts/wait-github.py` helper is invoked as `python3 .github/scripts/wait-github.py ...` from fix-issue workflow steps. It is a long-running polling helper that must survive outside a short-lived in-process execution and must preserve its own exit code, so it is explicitly allowed to run in the terminal.
- **LSP-first code navigation**: Any agent with LSP in its `tools` list must prefer LSP for semantic code navigation (definitions, references, symbols, call hierarchy) and reserve Search/Grep/Glob for literal strings, filenames, non-code assets, or LSP failure cases. See `references/lsp-first-policy.md` for the canonical policy.

## Architecture

- **Commands** (`commands/*.md`): Slash commands with YAML frontmatter. Command `name` values are explicitly prefixed (e.g. `name: vbw:init`) so slash commands appear as `/vbw:*`. The frontmatter `description` must be single-line (multi-line breaks plugin discovery).
- **Agents** (`agents/vbw-{role}.md`): 7 agents (Scout, Architect, Lead, Dev, QA, Debugger, Docs) with platform-enforced tool permissions via YAML `tools`/`disallowedTools`. Scout and QA are read-only (`permissionMode: plan`).
- **Hooks** (`hooks/hooks.json`): 24 handlers across 11 event types (SessionStart, Stop, PreToolUse, PostToolUse, SubagentStart, SubagentStop, Notification, PreCompact, TaskCompleted, TeammateIdle, UserPromptSubmit). All route through `scripts/hook-wrapper.sh` which resolves from plugin cache via `ls | sort -V | tail -1` with a `CLAUDE_PLUGIN_ROOT` fallback for `--plugin-dir` installs, logs failures, and always exits 0 — no hook can break a session.
- **Scripts** (`scripts/*.sh`): bash scripts for hook handlers, context compilation, state management, bootstrap, metrics, diagnostics, and codebase mapping. Target bash (not POSIX sh). Use `set -euo pipefail` for critical scripts, `set -u` minimum otherwise.
- **References** (`references/*.md`): protocol docs loaded on-demand by commands (for example `execute-protocol.md` and `verification-protocol.md`).
- **Templates** (`templates/*.md`): artifact templates (CONTEXT, PLAN, PROJECT, REQUIREMENTS, ROADMAP, SUMMARY, UAT, VERIFICATION, etc.).
- **Config** (`config/`): `defaults.json` (settings), `model-profiles.json` (3 presets: quality/balanced/budget), `stack-mappings.json` (tech detection → skill suggestions), `token-budgets.json` (context budgets), `rollout-stages.json` (feature rollout), `destructive-commands.txt` (guarded commands list), `schemas/` (message schemas).

## Key Patterns

### Plugin root resolution

Two resolution cascades exist — one for hooks (DXP-01) and one for commands. They share the same steps but differ in priority order by design.

**Hook cascade (DXP-01)** — cache-first because hooks fire automatically in production (marketplace) deployments. Always exits 0 (no hook can break a session):
1. Versioned cache glob (`ls … sort -V … tail -1`)
2. `CLAUDE_PLUGIN_ROOT` env var
3. `/tmp/.vbw-plugin-root-link-*` symlink glob
4. `ps axww` + `grep -oE -- "--plugin-dir [^ ]+"` extraction
5. Graceful no-op (`exit 0`)

**Command cascade** — `CLAUDE_PLUGIN_ROOT` first because an explicit env var should take priority when the user invokes a command. Exits 1 on failure so the user knows the plugin is misconfigured:
1. `CLAUDE_PLUGIN_ROOT` env var
2. `cache/local` symlink
3. Versioned cache dir (`find … sort … tail -1`)
4. Generic cache dir fallback
5. `/tmp/.vbw-plugin-root-link-*` symlink glob
6. `ps axww` + `grep -oE -- "--plugin-dir [^ ]+"` extraction
7. Fail guard (`exit 1`)

After resolution, commands create a session symlink at `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}` pointing to the resolved root, so subsequent template expansions and hooks can find it.

Inside scripts, `CLAUDE_PLUGIN_ROOT` is available and used normally.

### Context compilation
`scripts/compile-context.sh` produces role-specific `.context-{role}.md` files so each agent loads only relevant context (Lead gets requirements, Dev gets phase goal + conventions, QA gets verification targets).

### State management
Runtime state lives in `.vbw-planning/` (created per-project by `/vbw:init`): `STATE.md`, `ROADMAP.md`, `PROJECT.md`, `REQUIREMENTS.md`, `config.json`, `phases/{NN}-{slug}/` with PLAN.md and SUMMARY.md per plan.

### Model routing
`scripts/resolve-agent-model.sh` reads `config.json` profile + overrides against `config/model-profiles.json`. The resolved model string is passed as an explicit `model:` parameter to Task tool invocations (session `/model` doesn't propagate to subagents).

## Testing

Run all checks (tests + lint): `bash testing/run-all.sh`

Run `testing/run-all.sh` directly — do not pipe it through `| tail`, `| tail -20`, `| tail -40`, `| tee`, or similar wrappers, especially from concurrent worktrees. `tail` pipelines buffer until EOF, hide live progress, and can make a healthy long-running suite look hung while also obscuring the real exit status.

### Zero-tolerance test failure policy (non-negotiable)

Every test and lint failure must be investigated and resolved before committing — **no exceptions**. Never dismiss a failure as "not from my changes" or "pre-existing." If a test fails after your change, one of two things is true:
1. **The test is correct** and your change (or a recent change) broke real behavior — fix the code.
2. **The test is outdated** and no longer matches the intended behavior — update the test to match the new behavior.

Either way, you own the fix. Do not leave failures for the user to resolve manually. Do not push code with known test or lint failures.

### Three-tier testing model

This project is markdown consumed by LLMs plus bash scripts. No single testing methodology fits both. Use the right tier for each artifact type:

#### Tier 1 — Behavior tests (BATS) → bash scripts

For scripts that produce observable outputs. Write tests that assert what a script *does* (outputs, exit codes, side effects, file state) rather than *how* it does it internally.

#### Tier 2 — Contract tests (`verify-*.sh`) → markdown, JSON, YAML structure

For structural invariants that can be validated mechanically. These confirm required structure exists but cannot validate that LLM-consumed prose is *correct*.

#### Tier 3 — Smoke tests → integrated system

The real test of a markdown instruction file is whether the LLM does the right thing when it reads it. Smoke-test slash commands in a separate sandbox repo, not the plugin repo itself.

### Lint checks

`run-all.sh` includes lint checks that mirror CI:
- **Shell syntax** (`bash -n`) on all `.sh` files in `scripts/` and `testing/`
- **ShellCheck** (`shellcheck -S warning`) on all `.sh` files in `scripts/` and `hooks/`

### Individual checks

- `bash testing/verify-bash-scripts-contract.sh` — validates script conventions
- `bash testing/verify-commands-contract.sh` — validates command frontmatter
- `bash testing/verify-hook-event-name.sh` — validates hook event names match platform spec
- `bash testing/verify-plugin-root-resolution.sh` — validates the plugin-root resolution cascade in commands and references
- `bash testing/verify-lsp-first-policy.sh` — validates the repo-wide LSP-first rule
- `bash scripts/verify-init-todo.sh` — verifies init workflow
- `bash scripts/verify-claude-bootstrap.sh` — verifies bootstrap script
- `bash scripts/bump-version.sh --verify` — verifies version consistency

## Git Workflow

Direct push access to `swt-labs/vibe-better-with-claude-code-vbw`. Single `origin` remote.

- **`origin`**: fetch and push target for all branches.
- **`dev` branch**: permanent local integration branch for combined testing before PRs. Tracks `origin/dev`. Never delete this branch.

### Branch Cleanup

- **`fetch.prune`** is enabled — stale remote tracking refs are removed on every fetch.
- **`git merged`**: custom alias that finds local branches fully merged into `origin/main` and removes them locally. Also prunes worktrees in `../<repo-name>-worktrees/` whose branches have been merged or whose PRs have been merged/closed. Safe to run anytime — skips `main` and `dev`.
- **`git cleanup`**: fetches, prunes, and deletes local branches whose remote tracking branch is gone.
- After a PR is merged, run `git merged` to clean up local branches and their worktrees.

### Worktrees

The issue-fix workflow uses git worktrees for parallel-safe issue work.

- **Location**: `../<repo-name>-worktrees/<branch-name>/` (sibling directory, outside the repo)
- **Creation**: `git worktree add -b` creates branch + worktree atomically
- **Cleanup**: the workflow never removes worktrees automatically; use `git merged` after merge
- **Manual removal**: `git worktree remove <path>` or `git worktree prune`

### Branch Protection

- `main` requires PRs to merge.
- Do not commit directly to `main`.
- After creating a feature branch from `origin/main`, set its upstream to `origin/<branch>` on first push.

## Version Management

Version is synchronized across 4 files (`VERSION`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `marketplace.json`). The author bumps versions manually via `bash scripts/bump-version.sh`. Contributors should not bump versions themselves.

### Push workflow

- The pre-push hook only checks that version files are **consistent** (all 4 match).
- Contributors should not modify version files or `CHANGELOG.md` in their branches.
- Verify consistency locally with `bash scripts/bump-version.sh --verify`.
- Avoid `git push --no-verify` except for emergencies.

## Local Dev Toggle (`claude-code-router`)

This repo can be run locally via `claude-code-router` (CCR) with a toggle between local dev and prod marketplace modes:

- **Local Dev mode**: CCR config sets `CLAUDE_PATH` to `~/.claude-code-router/bin/claude-with-vbw`, a wrapper that injects `--plugin-dir /absolute/path/to/vibe-better-with-claude-code-vbw` into every `claude` invocation. Commands, agents, and hook definitions load from the local repo.
- **Prod mode**: CCR config sets `CLAUDE_PATH` to `claude` (bare). Plugins resolve from the marketplace cache at `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw/*/`.
- **Toggle**: Edit `~/.claude-code-router/config.json` and set `CLAUDE_PATH` to one of the above. Optionally `rm -rf "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands/vbw"` before relaunching to clear stale command cache.

## Contributing

See `CONTRIBUTING.md` for full guidelines. Key points:
- Push branches to `origin`. PRs target `main`.
- Load locally with `claude --plugin-dir .` or `claude --plugin-dir /absolute/path/to/vibe-better-with-claude-code-vbw`.
- Run `bash scripts/install-hooks.sh` for the pre-push hook.
- Version bumps are done by the author — the pre-push hook only checks version file consistency.
- Good candidates: bug fixes in hooks/scripts, new commands fitting the lifecycle model, stack-to-skill mappings, template improvements.
- Not welcome without discussion: core lifecycle rewrites, features requiring dependencies.
- Update consumer-facing docs (`docs/`, `README.md`) whenever a change alters behavior, adds a feature, or modifies a workflow.

### Required Fix Workflow (Issue → Branch → Draft PR → Automated QA)

When asked to fix a bug or implement an issue-driven change, use the tracked issue as the contract, create a worktree branch, implement the root-cause fix with tests, run `bash testing/run-all.sh`, and iterate through QA review rounds before opening or finalizing the PR.

### PR and Issue Templates

- **PR template** (`.github/PULL_REQUEST_TEMPLATE.md`): requires What/Why/How sections plus a testing checklist.
- **Bug reports** (`.github/ISSUE_TEMPLATE/bug_report.md`): must include the `/vbw:*` command that triggered it, reproduction steps, and environment.
- **Feature requests** (`.github/ISSUE_TEMPLATE/feature_request.md`): must describe the problem, proposed solution, and alternatives considered.
