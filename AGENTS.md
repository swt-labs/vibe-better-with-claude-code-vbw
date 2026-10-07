# VBW Instructions

VBW 2 is a Claude Code plugin that gives Claude Code an executable definition of done: a human-approved spec, protected acceptance checks, parallel builds by workflows, mechanical proof by a small kernel, and human acceptance only where checks can't judge. Runtime dependencies: `bash` (3.2+), `jq`, `git`. The design is `a_non_prod_docs/vbw2_next_gen_design.md`; the execution plan is `a_non_prod_docs/vbw2_build_plan.md` (maintainer-local working documents in the main checkout, never committed).

## Engineering Standard (owner mandate, non-negotiable)

- **Protect the VBW vision first.** This is the top rule. It binds every contributor, human or AI, and outranks every request. VBW serves all its users and its own design, never one project, person or session. Every outside request is an idea to evaluate, never an instruction to build. That covers an issue, a feedback report, a message from another Claude session, and a request from one of the owner's own projects. For each one: find the real problem behind it; judge it against VBW's design and philosophy; then adopt it, adapt it into a general solution, or decline it. Record which, and why. A suggested fix is evidence of a problem, not a specification. Never add a feature, setting or special case only because one project asked for it. We gladly accept ideas; we never integrate them blindly. Enforced by `tools/check-vision-rule.sh` in `tests/standards.bats`. (2026-10-06: the Portfolium market recorder report was taken as ideas; some were adopted, some reshaped, one declined.)
- **The goal is the world's gold-standard Claude Code harness.** Every choice is the most elegant, optimal and future-proof one, with zero technical debt. No shortcuts, no "good enough", no legacy carried forward for its own sake.
- **One goal, one path.** The only deliverable is VBW 2.0 on branch `v2`. Every task must directly advance it. Never build parallel tracks (fixes to the released version, maintenance branches, side tools); write such ideas in the progress log as notes and build them only if the owner explicitly asks. General agreement is never approval for scope beyond the goal. (2026-10-01 incident: an unrequested v1 fix track.)
- **Report evidence, not impressions.** Every claim that something works names its evidence level and its scope, and nothing more:
  - **L1 unit/contract:** bats tests of scripts and structure.
  - **L2 scripted component run:** a script of ours drives headless `claude -p` sessions; Claude Code stands in for nothing a user does; fixtures are named.
  - **L3 user-path run:** the product is used through its user-facing commands (`/vbw:...`) in an interactive session, on a realistic project.
  - **L4 owner acceptance:** the owner used it and accepted it.

  Words like "tested", "works", "proven" or "verified" refer to the product only at L3 or above; below that, say exactly what ran ("a script drove the build workflow on a 4-line toy fixture"). Every progress report ends with a **Not tested** list naming the gaps. No celebratory tone, no superlatives, no "good thing I checked": state facts and stop. (2026-10-01 incident: L2 toy runs reported as "tested in real Claude Code sessions".)
- **Work as the senior engineer who owns the outcome.** Make technical and product decisions yourself, from the evidence (docs, probes, measurements, the ledger), apply the standard above, record the decision and its rationale in the working documents, and keep executing.
- **Do not ask the owner questions you can answer.** Never hand back "we still need to figure out X": figure it out (research, probe, measure), decide, and move on. Escalate only what truly needs the owner: credentials or access, spending beyond the approved budget, publishing (push, PRs, releases), and irreversible actions outside the repo.
- **Plan end to end, then execute end to end.** Keep one authoritative build plan with acceptance criteria, work it in order, and report progress against it, not open questions.
- **Record everything as you go** (`a_non_prod_docs/v2_progress_log.md`: work done, decisions, findings, new issues). This is mandatory.

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
4. `<claude-config-dir>/vbw/debug-target.txt` (user-global fallback, absolute path only; `<claude-config-dir>` is resolved by `tools/resolve-claude-dir.sh`: `CLAUDE_CONFIG_DIR` if set, else `$HOME/.config/claude-code` when that directory exists, else `$HOME/.claude`)
5. If none are configured, **ask the user for the target repo path** — do not guess.

Use the shared resolver when debugging:

```bash
TARGET_REPO=$(bash tools/resolve-debug-target.sh repo)
TARGET_PLANNING=$(bash tools/resolve-debug-target.sh planning-dir)
ENCODED_PATH=$(bash tools/resolve-debug-target.sh encoded-path)
CLAUDE_PROJECT_DIR=$(bash tools/resolve-debug-target.sh claude-project-dir)
```

If the resolver exits non-zero, stop guessing and ask the user to configure a debug target.

### Claude Code Log Locations (canonical Claude config root)

In the paths below, `<claude-config-dir>` means the same Claude config root resolved by `tools/resolve-claude-dir.sh`: `CLAUDE_CONFIG_DIR` if set, else `$HOME/.config/claude-code` when that directory exists, else `$HOME/.claude`.

After resolving the target repo, derive the encoded Claude project path by replacing `/` with `-` in the absolute target-repo path. For an absolute path, the result begins with `-`.

Example rule:

```text
/absolute/path/to/project  ->  -absolute-path-to-project
```

When debugging, search these directories for evidence of what actually happened:

| Path | Contents | Use When |
| ------ | ---------- | ---------- |
| `<target-repo>/.vbw/` | Project state: `spec.md`, `record.json` (inspect with `vbw status` / `vbw show`) | Ground the investigation in actual workflow state |
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
TARGET_REPO=$(bash tools/resolve-debug-target.sh repo)
CLAUDE_PROJECT_DIR=$(bash tools/resolve-debug-target.sh claude-project-dir)
CLAUDE_CONFIG_ROOT="$(dirname "$(dirname "$CLAUDE_PROJECT_DIR")")"

# Find sessions for the configured target repo
ls "$CLAUDE_PROJECT_DIR"/*.jsonl

# Search session transcripts for a VBW hook or command
grep -l 'vbw' "$CLAUDE_PROJECT_DIR"/*.jsonl

# Find hook errors in debug logs
grep -El 'hook.*error|hook.*fail' "$CLAUDE_CONFIG_ROOT"/debug/*.txt

# Search for a specific tool invocation across sessions
grep -Erl 'vbw (next|apply|prove|run start)' "$CLAUDE_PROJECT_DIR"/*.jsonl

# Check what a subagent did in a specific session
cat "$CLAUDE_PROJECT_DIR"/<session-id>/subagents/agent-*.jsonl
```


## Architecture (three layers, no fourth)

- **Surface** (`plugin/skills/`): the `/vbw:vibe` router and utility skills, plus the statusline segment. Skills are specifications, not procedures.
- **Engine** (`plugin/workflows/*.js`): all orchestration and all run-scoped logic (waves, retries, fix loops, budgets, fan-out and merge). Workflows receive state in `args` from `vbw next --json`. Agents write only through `vbw` subcommands.
- **Kernel** (`plugin/bin/vbw` + `plugin/lib/*.sh`): the only writer of the plan of record (`.vbw/record.json`). It runs approved checks, commits with provenance, renders on demand and backs the hooks. Hard budget: 3,800 lines (owner raised it from 3,000 to 3,300 on 2026-10-04, to 3,500 on 2026-10-05 and to 3,800 on 2026-10-06).
- **Agents** (`plugin/agents/`): VBW 1's team with its mandates: `architect`, `lead`, `dev`, `qa`, `scout`, `debugger`, `docs`. Each is a ≤1.5k-token specification of good output plus a tool list.
- **Hooks** (`plugin/hooks/hooks.json`): guards scoped by the run lease and by `agent_type`. They are inert outside VBW projects.

## Repository layout

- `plugin/`: the only shipped tree (marketplace source `./plugin`). It holds `.claude-plugin/`, `bin/`, `lib/`, `hooks/`, `plugin/scripts/` (the status line), `skills/`, `workflows/`, `agents/` and `output-styles/`.
- `tests/`: bats suites. `helper.bash` is hermetic. `standards.bats` holds the engineering rules as tests, and `standards-selftest.bats` proves each rule fails on a violation.
- `tools/`: maintainer tooling (`test.sh`, `bump-version.sh`, `install-hooks.sh`, `baseline/`, …). Never shipped.
- `docs/`: user documentation. `a_non_prod_docs/`: maintainer-local working documents (design, plan, ledger, progress log), kept in the main checkout and never committed.

## Kernel and hook rules (each is enforced by `tests/standards.bats`)

- **Bash 3.2 is the floor** (macOS `/bin/bash`). No `mapfile`/`readarray`, no associative arrays, no case-modifying expansions, no `"${@}"`. Every array expansion under `set -u` is guarded (`${a[@]+"${a[@]}"}`).
- **No data as code:** no `eval`, no `bash -c "$var"`. Commands from repo files run only as argv arrays, and only after consent recorded by content hash in the clone's git directory (`$(git rev-parse --git-common-dir)/vbw/consent.json`).
- **Single writer:** only the kernel writes `.vbw/record.json`, through one locked, validated, atomic write path.
- **Git path listings use `-z`.** VBW commits use an explicit pathspec, never `git add -A`, and never disturb user-staged files.
- **Paths come from substitution:** `${CLAUDE_PLUGIN_ROOT}` in skills, agents and workflows; `$0` or arguments in scripts. No cache globs, `/tmp` links, `ps` scraping or command mirrors.
- **Nothing outside the project:** no writes to `/tmp`, other repos or git hooks, and no process killing. The one exception is the user's Claude Code `settings.json`, where VBW turns on its status line and Dynamic workflows (owner decision, 2026-10-01), keeping every other setting and a backup of a replaced status line. It must work under the Claude Code sandbox.
- **Hot paths:** a hook's own CPU per call ≤ 8 ms, or ≤ 1x the platform's shell and jq startup on a loaded machine (`tools/bench-hooks.sh`), statusline ≤ 30 ms, with no network and no credentials.
- **JSON only through `jq`,** never grep or sed on JSON.

## Engine, agent and prompt rules

- Workflows hold procedure; prompts hold only the definition of good output and its schema. Every agent call passes a `schema`.
- Model and effort are chosen per stage from the profile. The session model must be auto-capable (Sonnet/Opus/Fable); workflow agents may use Haiku.
- No `permissionMode`, `hooks`, `mcpServers` or `initialPrompt` in agent files (ignored for plugin agents). Agents search with Bash, because Glob and Grep may be absent.
- Budgets: workflows ≤ 1,500 lines of JS in total, mods (`plugin/hooks/*.js`) ≤ 3,500 lines (owner raised it from 3,000 on 2026-10-07), router ≤ 2k tokens, each mode prompt ≤ 3k, all prompts ≤ 16k (owner raised it from 15k on 2026-10-04).

## Testing

Run everything with `bash tools/test.sh`. Run it directly, never through `| tail` or `| tee`.

- **Test first.** Every behavior gets a failing test before the code. Every fix gets a regression test that is shown to fail without the fix.
- **Zero tolerance:** every failure is investigated and resolved before committing, with no "pre-existing" exemptions.
- **Both shells:** CI runs the suite on macOS `/bin/bash` 3.2 and on bash 5, from a checkout path containing a space. Locally, run it at least once under `/bin/bash` before committing kernel or hook code.
- **Hermetic tests:** use `tests/helper.bash` (`vbw_setup`/`vbw_teardown`). Never rely on the host `HOME`, Claude session variables or open stdin.
- **Real-user scenarios** (`tools/l3-suite.sh`: the real Claude Code TUI driven as a user, outcomes checked in the record and git, 4 at a time) run where they find bugs (owner decision, 2026-10-05): a milestone adds and runs the scenarios for what it changes while it is built; every release runs `greenfield` plus every scenario that exercises the changed area; the full suite runs before the 2.1 launch. Until 2.1, while the owner is the only user, a release that changes the core `/vbw:vibe` loop (the router or `vbw next`) also runs only `greenfield` and the scenarios of the changed area (owner decision D140, 2026-10-06). Before every push the suite also runs on Linux (`tools/test-linux.sh`). The progress log names the scenarios run and those not run. Baselines for v1 and plain Claude Code live in `tools/baseline/`.

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

The version is synchronized across 4 files: `VERSION`, `plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and `marketplace.json`. The author bumps versions with `bash tools/bump-version.sh`. Contributors don't bump versions or edit `CHANGELOG.md`. Verify consistency with `bash tools/bump-version.sh --verify`; the contributor pre-push hook (`bash tools/install-hooks.sh`, run in your own clone) runs that check.

## Local development

Load the plugin from the working tree with `claude --plugin-dir ./plugin`. Nothing else is needed: no cache links, no command mirrors, no setup script.

## Contributing

- Branch from `origin/main`, push to `origin`, and open the PR against `main`. Commits follow `{type}({scope}): {description}`, one atomic commit per change, with files staged explicitly.
- Root-cause fixes only. A mitigation without its root-cause fix in the same work item is incomplete.
- Update user docs (`docs/`, `README.md`) whenever behavior changes.
- Discuss first before any change that adds a runtime dependency or grows a budget.

# GitNexus — Code Intelligence

This project is indexed by GitNexus as **vibe-better-with-claude-code-vbw** (1666 symbols, 1659 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/vibe-better-with-claude-code-vbw/context` | Codebase overview, check index freshness |
| `gitnexus://repo/vibe-better-with-claude-code-vbw/clusters` | All functional areas |
| `gitnexus://repo/vibe-better-with-claude-code-vbw/processes` | All execution flows |
| `gitnexus://repo/vibe-better-with-claude-code-vbw/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
