<div align="center">

# Vibe Better With Claude Code (Opus 4.6+) - VBW

*You're not an engineer anymore.*

*You're a prompt jockey with commit access.*

*At least do it properly.*

<br>

<img src="assets/abraham.jpeg" width="300" />

<br>

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-v1.0.33+-blue.svg)](https://code.claude.com)
[![Opus 4.6+](https://img.shields.io/badge/Model-Opus_4.6+-purple.svg)](https://anthropic.com)
[![Discord](https://img.shields.io/badge/Discord-Join%20Us-5865F2.svg?logo=discord&logoColor=white)](https://discord.gg/zh6pV53SaP)

</div>

<br>

## VBW Token Efficiency vs Stock Opus 4.6 Agent Teams

Every new capability is shell-only — 85 scripts run as bash subprocesses at zero model token cost. The codebase grew 64% since v1.20.0 while per-request overhead *dropped* 17%. 783 bats tests validate the stack.

**Analysis reports:** [v1.21.30](docs/vbw-1-21-30-full-spec-token-analysis.md) | [v1.20.0](docs/vbw-1-20-0-full-spec-token-analysis.md) | [v1.10.7](docs/vbw-1-10-7-context-compiler-token-analysis.md) | [v1.10.2](docs/vbw-1-10-2-vs-stock-agent-teams-token-analysis.md) | [v1.0.99](docs/vbw-1-0-99-vs-stock-teams-token-analysis.md)

| Category | Stock Agent Teams | VBW | Saving |
| :--- | ---: | ---: | ---: |
| Base context overhead | 10,800 tokens | 1,500 tokens | **86%** |
| State computation per command | 1,300 tokens | 200 tokens | **85%** |
| Agent coordination (x4 agents) | 16,000 tokens | 1,200 tokens | **93%** |
| Compaction recovery | 5,000 tokens | 700 tokens | **86%** |
| Context duplication (shared files) | 16,500 tokens | 900 tokens | **95%** |
| Agent model cost per phase | $2.78 | $1.40 | **50%** |
| **Total coordination overhead** | **87,100 tokens** | **12,100 tokens** | **86%** |

**What this means for your bill:** Each phase eliminates ~86% of coordination tokens. For API users, per-phase cost drops from $2.78 to $1.40 (Balanced) or $0.70 (Budget). For subscription plans, ~3x more phases per rate limit cycle — **200% more development capacity for the same price**.

| Scenario | Without VBW | With VBW (Balanced) | Impact |
| :--- | ---: | ---: | ---: |
| API: single project (10 phases) | ~$28 | ~$14 | **~$14 saved** |
| API: active dev (20 phases/mo) | ~$56/mo | ~$28/mo | **~$28/mo saved (~$336/yr)** |
| API: heavy dev (50 phases/mo) | ~$139/mo | ~$70/mo | **~$69/mo saved (~$828/yr)** |
| API: team (100 phases/mo) | ~$278/mo | ~$139/mo | **~$139/mo saved (~$1,668/yr)** |
| Pro / Max subscription | baseline capacity | ~3x phases per cycle | **200% more work done** |

*Budget profile ($0.70/phase) doubles API savings. Quality profile ($2.80/phase) matches stock cost but adds V2/V3 enforcement at zero premium. Based on [current API pricing](https://claude.com/pricing).*
<br>

## Manifesto

VBW is open source because the best tools are built by the people who use them.

This project exists to make AI coding better for everyone, and "everyone" means exactly that.

**For absolute beginners:** VBW may look intimidating, especially if you've never used Claude Code, but it is, in fact, incredibly easy to use. And your results will be significantly better than using an IDE with a chatbot.

**For seasoned developers:** Everything is configurable — effort profiles, autonomy levels, model routing, verification depth, work presets — all exposed as a control surface, not hidden behind prompts. The beginners get guardrails; you get the switches behind the guardrails.

**For contributors:** VBW is a living project. The plugin system, the agents, the verification pipeline - all of it is open to improvement. If you've found a better way to plan, build, or verify code with Claude, bring it. File an issue, open a PR, or just show up and share what you've learned. Every contribution makes the next person's experience better.

**[Join the Discord](https://discord.gg/zh6pV53SaP)** -- whether you want to help build VBW or just want VBW to help you build.

<br>

## What Is This

> **Platform:** macOS and Linux only. Windows is not supported natively — all hooks, scripts, and context blocks require bash. If you're on Windows, run Claude Code inside [WSL](https://learn.microsoft.com/en-us/windows/wsl/install).

Inspired by **[Ralph](https://github.com/frankbria/ralph-claude-code)** and **[Get Shit Done](https://github.com/glittercowboy/get-shit-done)**, however, an entirely new architecture.

VBW is a Claude Code plugin that bolts an actual development lifecycle onto your vibe coding sessions.

You describe what you want. VBW breaks it into phases. Agents plan, write, and verify the code. Commits are atomic. Verification is goal-backward. State persists across sessions. It's the entire software development lifecycle, except you replaced the engineering team with a plugin and a prayer.

Think of it as project management for the post-dignity era of software development.

<br>

## Table of Contents

- [VBW Token Efficiency vs Stock Opus 4.6 Agent Teams](#vbw-token-efficiency-vs-stock-opus-46-agent-teams)
- [Manifesto](#manifesto)
- [Features](#features)
- [Installation](#installation)
- [How It Works](#how-it-works)
- [Quick Tutorial](#quick-tutorial)
- [Commands](#commands)
- [The Agents](#the-agents)
- [Effort Profiles](#effort-profiles)
- [Autonomy Levels](#autonomy-levels)
- [Planning & Git](#planning--git)
- [Settings Reference](#settings-reference)
- [Feature Flags Reference](#feature-flags-reference)
- [Cost Optimization](#cost-optimization)
- [Project Structure](#project-structure)
- [Requirements](#requirements)
- [Contributing](#contributing)
- [Contributors](#contributors)
- [License](#license)

<br>

---

<br>

## Features

### Built for Opus 4.6+, not bolted onto it

Most Claude Code plugins were built for the subagent era, one main session spawning helper agents that report back and die. Much like the codebases they produce. VBW is designed from the ground up for the platform features that changed the game:

- **Agent Teams for real parallelism.** `/vbw:vibe` creates a team of Dev teammates that execute tasks concurrently, each in their own context window. `/vbw:map` runs 4 Scout teammates in parallel to analyze your codebase. This isn't "spawn a subagent and wait" -- it's coordinated teamwork with a shared task list and direct inter-agent communication. Agent health monitoring tracks lifecycle events, detects orphaned teammates, and recovers stuck agents via circuit breakers.

- **Native hooks for continuous verification.** 21 hooks across 11 event types run automatically -- validating SUMMARY.md structure, checking commit format, validating frontmatter descriptions, gating task completion, blocking sensitive file access, enforcing plan file boundaries, managing session lifecycle, tracking agent health and cost attribution, tracking session metrics, pre-flight prompt validation, and post-compaction context verification. No more spawning a QA agent after every task. The platform enforces it, not the prompt.

- **Platform-enforced tool permissions.** Each agent has `tools`/`disallowedTools` in their YAML frontmatter -- 4 of 7 agents have platform-enforced deny lists. Scout and QA literally cannot write files. Sensitive file access (`.env`, credentials) is intercepted by the `security-filter` hook. `disallowedTools` is enforced by Claude Code itself, not by instructions an agent might ignore during compaction.

- **Database safety guard.** A PreToolUse hook (`bash-guard.sh`) intercepts every Bash command before it reaches the shell and blocks known destructive patterns -- `migrate:fresh`, `db:drop`, `TRUNCATE TABLE`, `FLUSHALL`, and 40+ patterns across Laravel, Rails, Django, Prisma, Knex, Sequelize, TypeORM, Drizzle, Diesel, SQLx, Ecto, raw SQL clients, Redis, MongoDB, and Docker volumes. All five agents with Bash access (Dev, QA, Lead, Debugger, Docs) are filtered equally. Override with `VBW_ALLOW_DESTRUCTIVE=1` env var or `bash_guard=false` in config. Extend with `.vbw-planning/destructive-commands.local.txt` for project-specific patterns. See **[Database Safety Guard](docs/database-safety-guard.md)** for the full design, flowchart, and pattern list.

- **Structured handoff schemas.** Agents communicate via JSON-structured SendMessage with typed schemas (`scout_findings`, `dev_progress`, `dev_blocker`, `qa_result`, `debugger_report`). No more hoping the receiving agent can parse free-form markdown. Schema definitions live in a single reference document with backward-compatible fallback to plain text.

<br>

### Solves Agent Teams limitations out of the box

Agent Teams are [experimental with known limitations](https://code.claude.com/docs/en/agent-teams#limitations). VBW handles them so you don't have to:

- **Session resumption.** Agent Teams teammates don't survive `/resume`. VBW's `/vbw:resume` reads ground truth directly from `.vbw-planning/` -- STATE.md, ROADMAP.md, PLAN.md and SUMMARY.md files -- without requiring a prior `/vbw:pause`. It detects interrupted builds via `.execution-state.json`, reconciles stale execution state by detecting tasks completed between sessions via SUMMARY.md files, and suggests the right next action.

- **Task status lag.** Teammates sometimes forget to mark tasks complete. VBW's `TaskCompleted` hook verifies task-related commits exist via keyword matching, with a circuit breaker that allows completion after a repeated false-positive block (prevents infinite hook loops). The `TeammateIdle` hook runs a tiered SUMMARY.md gate — all summaries present passes immediately, conventional commit format only grants a 1-plan grace period, and 2+ missing summaries block regardless.

- **Shutdown coordination.** VBW defines `shutdown_request`/`shutdown_response` schemas in the typed communication protocol. After phase work completes, the orchestrator sends `shutdown_request` to every teammate, waits for acknowledgment, then calls `TeamDelete`. All 7 team-participating agents (Dev, QA, Scout, Lead, Debugger, Docs, Architect) have explicit shutdown handlers — respond, finish in-progress work, stop. No lingering agents consuming API credits in tmux panes.

- **File conflicts.** Plans decompose work into tasks with explicit file ownership. Dev teammates operate on disjoint file sets by design, enforced at runtime by the `file-guard.sh` hook that blocks writes to files not declared in the active plan.

Agent Teams ship with seven known limitations. VBW addresses all of them. The eighth... that you're using AI to write software doesn't need a fix. It needs an intervention.

<br>

### Skills.sh integration

VBW integrates with [Skills.sh](https://skills.sh), the open-source skill registry for AI agents with 20+ supported platforms and thousands of community-contributed skills:

- **Automatic stack detection.** `/vbw:init` scans your project during setup, identifies your tech stack (Next.js, Django, Prisma, Tailwind, etc.), and recommends relevant skills from a curated mapping.

- **On-demand skill discovery.** Run `/vbw:skills` anytime to detect your stack, browse curated suggestions, search the Skills.sh registry, and install skills in one step. Use `--search <query>` for direct registry lookups.

<br>

### Real-time statusline that knows more about your project than you do

<img src="assets/statusline.png" width="100%" />

Five or six lines of pure situational awareness, rendered after every response. Phase progress, plan completion, effort profile, QA status... everything a senior engineer would track on a whiteboard, except the whiteboard has been replaced by a terminal and the senior engineer has been replaced by you.

<br>

---

<br>

## Installation

Open Claude Code and run these two commands inside the Claude Code session, **one at a time**:

**Step 1:** Add the marketplace
```
/plugin marketplace add yidakee/vibe-better-with-claude-code-vbw
```

**Step 2:** Install the plugin
```
/plugin install vbw@vbw-marketplace
```

That's it. Two commands, two separate inputs. Do not paste them together — Claude Code will treat both lines as a single command and the URL will break.

To update later, inside Claude Code:

```
/vbw:update
```

### Running VBW

**Option A: Supervised mode** (recommended for the cautious)

```bash
claude
```

Claude Code will ask permission before file writes, bash commands, etc. You approve once per tool, per project -- it remembers after that. VBW has its own security layer (agent tool permissions, file access hooks), so the permission prompts are a second safety net. First session has some clicking. After that, smooth sailing.

**Option B: Full auto mode** (recommended for the brave)

```bash
claude --dangerously-skip-permissions
```

No permission prompts. No interruptions. Agents run uninterrupted until the work is done or your API budget isn't. VBW's built-in security controls (read-only agents can't write, `security-filter.sh` blocks `.env` and credentials, QA gates on every task) still apply. The platform just stops asking "are you sure?" every time an agent wants to create a file.

This is how most vibe coders run it. The agents work longer, the flow stays unbroken, and you get to pretend you're supervising while scrolling Twitter.

> **Disclaimer:** The `--dangerously-skip-permissions` flag is called that for a reason. It is not called `--everything-will-be-fine` or `--trust-the-AI-it-knows-what-its-doing`. By using it, you are giving an AI unsupervised write access to your filesystem. VBW does its best to keep agents on a leash, but at the end of the day you are trusting software written by an AI, managed by an AI, and verified by a different AI. If this arrangement doesn't concern you, you are exactly the target audience for this plugin.

<br>

---

<br>

## How It Works

VBW operates on a simple loop that will feel familiar to anyone who's ever shipped software. Or read about it on Reddit.

```
                        ┌─────────────────────────────┐
                        │  YOU HAVE AN IDEA           │
                        │  (dangerous, but continue)  │
                        └──────────────┬──────────────┘
                                       │
                        ┌──────────────┴──────────────┐
                        │ Greenfield?   │  Brownfield? │
                        └──────┬───────┴──────┬───────┘
                               │              │
                  ┌────────────┘              └────────────┐
                  │                                        │
                  ▼                                        ▼
     ┌───────────────────────┐               ┌───────────────────────┐
     │  /vbw:init            │               │  /vbw:init            │
     │  Environment setup    │               │  Environment setup    │
     │  Scaffold             │               │  Scaffold             │
     │  Skills               │               │                       │
     │                       │               │  ⚠ Codebase detected  │
     │  Auto-chains:         │               │  Auto-chains:         │
     │    → /vbw:vibe        │               │    → /vbw:map         │
     └──────────┬────────────┘               │    → Skills (informed │
                │                            │      by map data)     │
                │                            │    → /vbw:vibe        │
                │                            └──────────┬────────────┘
                │                                       │
                └───────────────────┬───────────────────┘
                                    │
                                    ▼
                 ┌──────────────────────────────────────┐
                 │  /vbw:vibe                           │
                 │  The one command — auto-detects:     │
                 │                                      │
                 │  No project?  → Bootstrap setup      │
                 │  No phases?   → Scope & plan work    │
                 │  Unplanned?   → Plan next phase      │
                 │  Planned?     → Execute next phase   │
                 │  All done?    → Suggest archive      │
                 └──────────────────┬───────────────────┘
                                    │
                                    │  Or use flags:
                                    │  /vbw:vibe --discuss
                                    │  /vbw:vibe --plan --execute
                                    │
                                    ▼
                     ┌──────────────────────────────┐
                     │  /vbw:qa [phase]             │
                     │  Three-tier verification     │
                     │  Goal-backward methodology   │
                     │  Outputs: VERIFICATION.md    │
                     └──────────────┬───────────────┘
                                    │
                           ┌────────┴────────┐
                           │  More phases?   │
                           └────────┬────────┘
                          yes │          │ no
                              │          │
                     ┌────────┘          └────────┐
                     │                            │
                     ▼                            ▼
          ┌──────────────────┐        ┌──────────────────┐
          │ Loop back to     │        │ /vbw:vibe        │
          │ /vbw:vibe        │        │ --archive        │
          │ for next phase   │        │ Audits, archives │
          └──────────────────┘        │ Tags the release │
                                      │ Work archived    │
                                      └──────────────────┘
```

<br>

---

<br>

## Quick Tutorial

You only need to remember two commands. Seriously. VBW auto-detects where your project is and does the right thing. No decision trees, no memorizing workflows. Just init, then vibe until it's done.

### Starting a brand new project

```
/vbw:init
```

Run this once. VBW sets up your environment — Agent Teams, statusline, git hooks — and scaffolds a `.vbw-planning/` directory. It detects your tech stack and suggests relevant Claude Code skills. You answer a few questions, and you're ready to build.

```
/vbw:vibe
```

This is the one command. Run it, and VBW figures out what to do next:

- **No project defined?** It asks about your project, gathers requirements, and creates a phased roadmap.
- **Phases ready but not planned?** The Lead agent researches, decomposes, and produces plans.
- **Plans ready but not built?** Dev teammates execute in parallel with atomic commits and continuous verification.
- **Everything built?** It tells you and suggests wrapping up.

You don't need to know which state your project is in. VBW knows. Just keep running `/vbw:vibe` and it handles the rest — planning, building, verifying — one phase at a time. Or if you're feeling brave, set your autonomy to `pure-vibe` and it'll loop through every remaining phase without stopping.

```
/vbw:vibe
```

Yes, the same command again. When Phase 1 finishes, run it again for Phase 2. And again for Phase 3. Each invocation picks up where the last one left off. State persists in `.vbw-planning/` across sessions, so you can close your terminal, come back tomorrow, and `/vbw:vibe` still knows exactly where you are.

```
/vbw:vibe --archive
```

When all phases are built, archive the work. VBW runs a completion audit, archives state to `.vbw-planning/milestones/`, tags the git release, and updates project docs. You shipped. With actual verification. Your future self won't want to set the codebase on fire. Probably.

```
/vbw:release
```

Ready to publish? This runs a pre-release audit first — checking that your changelog covers all commits since the last release and that README counts aren't stale. If anything's missing, it offers to generate entries for your review. Then it bumps the version, finalizes the changelog, creates an annotated git tag, commits, pushes, and creates a GitHub release with the changelog notes. Supports `--dry-run` to preview, `--skip-audit` to bypass the audit, `--major` or `--minor` for non-patch bumps.

That's it. `init` → `vibe` (repeat) → `vibe --archive` → `release`. Three commands for an entire development lifecycle.

### Picking up an existing codebase

Same flow, one difference:

```
/vbw:init
```

VBW detects the existing codebase and auto-chains everything: `/vbw:map` launches 4 Scout teammates to analyze your code across tech stack, architecture, quality, and concerns. Skill suggestions are based on what's actually in your codebase, not just which manifest files exist. Then `/vbw:vibe` runs automatically with full codebase awareness. One command, four workflows, zero manual sequencing.

From there, it's the same loop: `/vbw:vibe` until done, `/vbw:vibe --archive`, `/vbw:release`.

### Coming back to a project

```
/vbw:resume
```

Closed your terminal? Switched branches? Came back after a weekend of pretending you have hobbies? `/vbw:resume` reads ground truth directly from `.vbw-planning/` -- STATE.md, ROADMAP.md, plans, summaries -- and rebuilds your full project context. No prior `/vbw:pause` needed. It detects interrupted builds, reconciles stale execution state, and tells you exactly what to do next. One command, full situational awareness, zero guessing.

> **⚠️ Do not use `/clear`.**
>
> Opus 4.6 auto-compacts your context window when it fills up. It intelligently summarizes older conversation turns while preserving critical state — active plan tasks, file paths, commit history, deviation decisions, error context — so the session continues seamlessly with full project awareness. VBW enhances this further with `PreCompact` hooks and post-compaction verification that inject agent-specific preservation priorities and verify nothing critical was lost.
>
> `/clear` bypasses all of this. It destroys your entire context — every file read, every decision made, every task in progress — and drops you into a blank session with no memory of what just happened. Auto-compaction is surgical; `/clear` is a sledgehammer.
>
> **If you accidentally `/clear`**, run `/vbw:resume` immediately. It restores project context from ground truth files in `.vbw-planning/` — state, roadmap, plans, summaries — and tells you exactly where to pick up.

> **For advanced users:** The [full command reference](#commands) below has 24 commands for granular control — `/vbw:vibe` with flags for explicit mode selection (`--plan`, `--execute`, `--discuss`, `--assumptions`), `/vbw:discuss` for standalone phase discussions, `/vbw:qa` for on-demand verification, `/vbw:debug` for systematic bug investigation, and more. But you never *need* the flags. `/vbw:vibe` with no arguments handles the entire lifecycle on its own.

<br>

---

<br>

## Commands

### Lifecycle -- The Main Loop

These are the commands you'll use every day. This is the job now.

| Command | Description |
| :--- | :--- |
| `/vbw:init` | Set up environment and scaffold `.vbw-planning/` directory with templates and config. Configures Agent Teams and statusline. Automatically installs git hooks (pre-push version enforcement). For existing codebases, maps the codebase first, then uses the map data to inform stack detection and skill suggestions before auto-chaining to `/vbw:vibe`. |
| `/vbw:vibe [intent or flags]` | The one command. Auto-detects project state, parses natural language intent, or accepts explicit flags. 12 modes: bootstrap, scope, discuss, assumptions, **UAT remediation**, plan, execute, add/insert/remove phase, archive. Discussion mode uses the unified discussion engine (auto-calibrates Builder/Architect, generates phase-specific gray areas). If a phase has unresolved UAT issues (`status: issues_found`), plain `/vbw:vibe` automatically loads `{phase}-UAT.md` and continues remediation without requiring `--discuss` or `--plan`—major/critical issues auto-chain **discuss → plan → execute**; minor-only issues use quick-fix remediation. Flags: `--plan`, `--execute`, `--discuss`, `--assumptions`, `--scope`, `--add`, `--insert`, `--remove`, `--archive`, `--yolo`, `--effort`, `--skip-qa`, `--skip-audit`. Phase numbers optional -- auto-detected when omitted. |
| `/vbw:release` | Bump version, finalize changelog, tag, commit, push, and create a GitHub release. Runs a pre-release audit that checks changelog completeness against commits since last release and detects stale README counts, offering to fix issues before shipping. Runs `bump-version.sh` across all 4 version files, renames `[Unreleased]` to the new version in CHANGELOG.md, creates an annotated git tag, pushes, and creates a GitHub release with changelog notes via `gh`. Supports `--dry-run`, `--no-push`, `--major`, `--minor`, `--skip-audit`. |

<br>

### Monitoring -- Trust But Verify

| Command | Description |
| :--- | :--- |
| `/vbw:status` | Progress dashboard showing all phases, completion bars, velocity metrics, and suggested next action. Add `--metrics` for token consumption breakdown per agent. |
| `/vbw:qa [phase]` | Deep verification on demand. Three tiers (Quick, Standard, Deep) with goal-backward methodology. Continuous QA runs automatically via hooks during builds -- this command is for thorough, on-demand verification. Produces VERIFICATION.md. Phase is auto-detected when omitted. |
| `/vbw:verify [phase]` | Human acceptance testing with per-test CHECKPOINT prompts. Presents success criteria one at a time, collects pass/fail/partial verdicts, supports resume if interrupted. Produces UAT.md. |

<br>

### Supporting -- The Safety Net

| Command | Description |
| :--- | :--- |
| `/vbw:discuss [phase]` | Standalone discussion engine for exploring phase decisions before planning. Auto-calibrates between Builder and Architect modes based on conversation signals. Generates phase-specific gray areas, explores selected ones conversationally, and captures decisions to `{phase}-CONTEXT.md`. Same engine as `/vbw:vibe --discuss`. |
| `/vbw:fix` | Quick task in Turbo mode. One commit, no ceremony. For when the fix is obvious and you don't need seven agents to add a missing comma. |
| `/vbw:debug` | Systematic bug investigation via the Debugger agent. At Thorough effort with ambiguous bugs, spawns 3 parallel debugger teammates for competing hypothesis investigation. Hypothesis, evidence, root cause, fix. Like the scientific method, except it actually finds things. |
| `/vbw:todo` | Add an item to a persistent backlog that survives across sessions. For all those "we should really..." thoughts that usually die in a terminal tab. |
| `/vbw:list-todos` | Browse pending todos, filter by priority, and pick one to act on. Computes ages, formats a numbered list, and offers routing to `/vbw:fix`, `/vbw:debug`, `/vbw:vibe`, or `/vbw:research`. |
| `/vbw:pause` | Save session notes for next time. State auto-persists in `.vbw-planning/` -- pause just lets you leave a sticky note for future you. |
| `/vbw:resume` | Restore project context from `.vbw-planning/` ground truth. Reads state, roadmap, plans, and summaries directly -- no prior `/vbw:pause` needed. |
| `/vbw:skills` | Browse and install community skills from skills.sh based on your project's tech stack. Detects your stack, suggests relevant skills, and installs them with one command. |
| `/vbw:config` | View and toggle VBW settings: effort profiles, autonomy levels (cautious/standard/confident/pure-vibe), plain-language summaries (`plain_summary`), skill suggestions, auto-install behavior, and skill-hook wiring. Detects profile drift and offers to save as new profile. |
| `/vbw:profile` | Switch between work profiles or create custom ones. 4 built-in presets (default, prototype, production, yolo) change effort, autonomy, and verification in one command. Interactive profile creation for custom workflows. |
| `/vbw:teach` | View, add, or manage project conventions. Auto-detected from codebase during init, manually teachable anytime. Shows what VBW already knows and warns about conflicts before adding. Conventions are injected into agent context via CLAUDE.md and verified by QA. |
| `/vbw:doctor` | Run 10 health checks on your VBW installation: jq, VERSION sync, plugin cache, hooks validity, agent files, config, script permissions, gh CLI, sort -V support. Diagnoses issues before they become mysteries. |
| `/vbw:help` | Command reference with usage examples. You are reading its output's spiritual ancestor right now. |

<br>

### Advanced -- For When You're Feeling Ambitious

| Command | Description |
| :--- | :--- |
| `/vbw:map` | Analyze a codebase with 4 parallel Scout teammates (Tech, Architecture, Quality, Concerns). Produces synthesis documents (INDEX.md, PATTERNS.md). Supports monorepo per-package mapping. Security-enforced via hooks: never reads `.env` or credentials. |
| `/vbw:research` | Standalone research task, decoupled from planning. For when you need answers but aren't ready to commit to a plan. |
| `/vbw:whats-new` | View changelog entries since your installed version. |
| `/vbw:update` | Update VBW to the latest version with automatic cache refresh. |
| `/vbw:uninstall` | Clean removal of VBW -- statusline, settings, and project data. For when you want to go back to prompting manually like it's 2024. |

<br>

---

<br>

## The Agents

VBW uses 7 specialized agents, each with native tool permissions enforced via YAML frontmatter. Three layers of control -- `tools` (what they can use), `disallowedTools` (what's platform-denied), and `permissionMode` (how they interact with the session) -- mean they can't do what they shouldn't, which is more than can be said for most interns.

| Agent | Role | Tools | Denied | Mode |
| :--- | :--- | :--- | :--- | :--- |
| **Scout** | Research and information gathering. The responsible one. | Read, Grep, Glob, WebSearch, WebFetch | Write, Edit, NotebookEdit, Bash | `plan` |
| **Architect** | Creates roadmaps and phase structure. Writes plans, not code. | Read, Glob, Grep, Write | Edit, WebFetch, Bash | `acceptEdits` |
| **Lead** | Merges research + planning + self-review. The one who actually makes decisions. | Read, Glob, Grep, Write, Bash, WebFetch | Edit | `acceptEdits` |
| **Dev** | Writes code, makes commits, builds things. Handle with care. | Full access | -- | `acceptEdits` |
| **QA** | Goal-backward verification. Trusts nothing. Can run commands but cannot write files. | Read, Grep, Glob, Bash | Write, Edit, NotebookEdit | `plan` |
| **Debugger** | Scientific method bug investigation. One issue, one session. | Full access | -- | `acceptEdits` |
| **Docs** | Documentation specialist. READMEs, changelogs, API docs, guides. | Read, Grep, Glob, Bash, Write, Edit | -- | `acceptEdits` |

**Denied** = `disallowedTools` -- platform-enforced denial. These tools are blocked by Claude Code itself, not by instructions an agent might ignore during compaction. **Mode** = `permissionMode` -- `plan` means read-only exploration (Scout, QA), `acceptEdits` means the agent can propose and apply changes.

<br>

Here's when each one shows up to work:

```
  /vbw:map                        /vbw:vibe --plan       /vbw:vibe --execute (or /vbw:vibe)
  ┌─────────┐                     ┌─────────┐                     ┌─────────┐
  │         │                     │         │                     │         │
  │  SCOUT  │ ──reads codebase──▶ │  LEAD   │ ──produces plan──▶  │   DEV   │
  │ (team)  │    INDEX.md         │(subagt) │    PLAN.md          │ (team)  │
  │         │    PATTERNS.md      │         │                     │         │
  └─────────┘                     └────┬────┘                     └────┬────┘
                                       │                               │
  /vbw:init                            │ reads context from            │ atomic
  ┌───────────┐                        │                               │ commits
  │           │                        ▼                               │
  │ ARCHITECT │ ──────────▶ ROADMAP.md, REQUIREMENTS.md                │
  │           │             SUCCESS CRITERIA                           ▼
  └───────────┘                                                   ┌─────────┐
                                                                  │         │
                                                                  │   QA    │
  /vbw:debug                                                      │(subagt) │
  ┌──────────┐                                                    └────┬────┘
  │          │                                                         │
  │ DEBUGGER │ ──one bug, one session, one fix──▶ commit               │ deep
  │(subagt)  │   (scope creep is for amateurs)                         │ verify
  └──────────┘                                                         │
                                                                       ▼
  HOOKS (11 event types, 21 handlers)                              VERIFICATION.md
  ┌───────────────────────────────────────────────────────────────────────────────┐
  │  Verification                                                                 │
  │    PostToolUse ──── Validates SUMMARY.md on write, checks commit format,      │
  │                     validates frontmatter descriptions, dispatches skill      │
  │                     hooks, updates execution state                            │
  │    SubagentStart ── Writes agent marker (role normalization, concurrency-safe)│
  │    SubagentStop ─── Validates SUMMARY.md, cleans markers, corruption recovery│
  │    TeammateIdle ─── Tiered SUMMARY.md gate (1-plan grace, 2+ gap blocks)     │
  │    TaskCompleted ── Verifies task-related commit via keyword matching         │
  │                                                                               │
  │  Security                                                                     │
  │    PreToolUse ──── Blocks destructive Bash commands (migrate:fresh, db:drop,  │
  │                    TRUNCATE, FLUSHALL, 40+ patterns across all frameworks),   │
  │                    blocks sensitive file access (.env, keys), enforces plan   │
  │                    file boundaries, dispatches skill hooks                    │
  │                                                                               │
  │  Lifecycle                                                                    │
  │    SessionStart ──── Detects project state, checks map staleness              │
  │    PreCompact ────── Injects agent-specific compaction priorities             │
  │    SessionStart(compact) Verifies critical context survived compaction        │
  │    Stop ──────────── Logs session metrics, persists cost ledger               │
  │    UserPromptSubmit  Pre-flight prompt validation                             │
  │    Notification ──── Logs teammate communication                              │
  └───────────────────────────────────────────────────────────────────────────────┘

  ┌───────────────────────────────────────────────────────────────────────────────┐
  │  PERMISSION MODEL                                                             │
  │                                                                               │
  │  Scout ─────────── True read-only (plan mode). Can look, can't touch.         │
  │  QA ───────────── Read + Bash. Can verify, can't write. The auditor.          │
  │  Architect ─────── Edit/Bash blocked by platform. Write limited to plans      │
  │                    by instruction. Writes roadmaps, not code. Mostly.         │
  │  Lead ─────────── Read, Write, Bash, WebFetch. The middle manager.            │
  │  Docs ─────────── Read, Write, Edit, Bash. Doc files only by instruction.     │
  │  Dev, Debugger ─── Full access. The ones you actually worry about.            │
  │                                                                               │
  │  Platform-enforced: tools / disallowedTools (cannot be overridden)            │
  │  Instruction-enforced: behavioral constraints in agent prompts                │
  └───────────────────────────────────────────────────────────────────────────────┘
```

<br>

---

<br>

## Effort Profiles

Not every task deserves the same level of scrutiny. Most of yours don't. VBW provides four effort profiles that control how much your agents think before they act.

| Profile | What It Does | When To Use It |
| :--- | :--- | :--- |
| **Thorough** | Maximum agent depth. Full Lead planning, deep QA, comprehensive research. Dev teammates require plan approval before writing code. Competing hypothesis debugging for ambiguous bugs. | Architecture decisions. Things that would be embarrassing to get wrong. |
| **Balanced** | Standard depth. Good planning, solid QA. The default. | Most work. The sweet spot between quality and not burning your API budget. |
| **Fast** | Lighter planning, quicker verification. | Straightforward phases where the path is obvious. |
| **Turbo** | Single Dev agent, no Lead or QA. Just builds. | Trivial changes. Adding a config value. Fixing a typo. Things that don't need a committee. |

```
/vbw:vibe --plan 3 --effort=turbo
/vbw:vibe --effort=thorough
```

Or switch effort, autonomy, and verification together with `/vbw:profile`:

```
/vbw:profile prototype    → fast + confident + quick
/vbw:profile production   → thorough + cautious + deep
/vbw:profile yolo         → turbo + pure-vibe + skip
```

<br>

---

<br>

## Autonomy Levels

Effort controls how hard your agents think. Autonomy controls how often they stop to ask you about it.

Four levels, from "review everything" to "just build the whole thing while I get coffee":

| Level | What It Does | When To Use It |
| :--- | :--- | :--- |
| **Cautious** | Stops between plan and execute. Plan approval at Thorough AND Balanced effort. All confirmations enforced. | First time on a codebase. Production-critical work. When you want to review every step before it happens. |
| **Standard** | Auto-chains plan into execute within a phase. Plan approval at Thorough only. Stops between phases. The default. | Most work. You trust the plan but want to see results before continuing. |
| **Confident** | Skips "already complete" confirmations. Plan approval OFF even at Thorough. QA warnings non-blocking. | Experienced with VBW, rebuilding known-good phases, iteration speed matters more than gate checks. |
| **Pure Vibe** | Loops ALL remaining phases in a single `/vbw:vibe`. No confirmations. No plan approval. Only error guards (missing roadmap, uninitialized project) stop execution. | When you want to walk away and come back to a finished project. Full autonomy with VBW's safety nets still active. |

```
/vbw:config autonomy confident
/vbw:config autonomy pure-vibe
```

Autonomy interacts with effort profiles. At `cautious`, plan approval expands to cover Balanced effort (not just Thorough). At `confident` and `pure-vibe`, plan approval is disabled regardless of effort level. Error guards — missing roadmap, uninitialized project, missing plans — always halt at every level. Autonomy controls friction, not safety.

| Gate | Cautious | Standard | Confident | Pure Vibe |
| :--- | :--- | :--- | :--- | :--- |
| Plan to execute | Stop and ask | Auto-chain | Auto-chain | Auto-chain |
| Between phases | Stop | Stop | Stop | Auto-loop |
| "Already complete" warning | Confirm | Confirm | Skip | Skip |
| Plan approval (Thorough) | Required | Required | Off | Off |
| Plan approval (Balanced) | Required | Off | Off | Off |

<br>

---

<br>

## Planning & Git

VBW generates 15+ files in `.vbw-planning/` during bootstrap, planning, execution, and QA — but by default none of them are committed. The Dev agent only commits source code files listed in each task's `Files:` section. Two settings control what happens to planning artifacts and when code gets pushed.

### `planning_tracking`

Controls whether `.vbw-planning/` artifacts are committed, gitignored, or left for you to manage.

```
/vbw:config planning_tracking commit
```

| Value | What It Does | When To Use It |
| :--- | :--- | :--- |
| **`manual`** | Default. No commits, no gitignore. Planning files accumulate as untracked in `git status`. You manage them yourself. | When you want full control, or aren't sure yet. |
| **`ignore`** | Adds `.vbw-planning/` to `.gitignore` during `/vbw:init`. Planning files exist locally but never enter version control. Clean `git status`. | Solo projects, prototyping, or when planning history doesn't matter. |
| **`commit`** | Auto-commits `.vbw-planning/` artifacts at lifecycle boundaries — after bootstrap, after planning, after archive. Commit format: `chore(vbw): {action}`. Transient files (`.execution-state.json`, `.contracts/`, `.locks/`, `.token-state/`, compiled context) are excluded via `.vbw-planning/.gitignore`. | Teams that want an audit trail of planning decisions in version control. |

> **Note:** `auto_commit` (the existing boolean) only controls source-task commits during Execute mode. It has no effect on planning artifacts — that's what `planning_tracking` is for.

### `auto_push`

Controls whether VBW pushes commits automatically, and when.

```
/vbw:config auto_push after_phase
```

| Value | What It Does | When To Use It |
| :--- | :--- | :--- |
| **`never`** | Default. Never pushes. Commits stay local until you explicitly run `git push`. Follows the "do not push until asked" rule. | When you review commits before sharing, or work on protected branches. |
| **`after_phase`** | Pushes once after phase execution completes, batching all task commits from that phase into a single push. | Power users who want remote backup after each phase without per-commit noise. |
| **`always`** | Pushes after every commit — both source-task commits and planning commits (if `planning_tracking=commit`). | CI/CD pipelines, pair programming setups, or when you want real-time remote visibility. |

<br>

---

<br>

## Settings Reference

Every setting below lives in `.vbw-planning/config.json` and can be changed with `/vbw:config <key> <value>`. Settings are created during `/vbw:init` and backfilled automatically when new ones are added in plugin updates.

### Core workflow

| Setting | Type | Default | Values |
| :--- | :--- | :--- | :--- |
| `effort` | string | `balanced` | `thorough` / `balanced` / `fast` / `turbo` |
| `autonomy` | string | `standard` | `cautious` / `standard` / `confident` / `pure-vibe` |
| `verification_tier` | string | `standard` | `quick` / `standard` / `deep` |

- **`effort`** — Controls how deeply agents plan, execute, and verify. See [Effort Profiles](#effort-profiles).
- **`autonomy`** — Controls how often agents stop to ask for confirmation. See [Autonomy Levels](#autonomy-levels).
- **`verification_tier`** — Controls QA depth. `quick` runs 5–10 checks (artifact existence, frontmatter validity). `standard` runs 15–25 (structure, imports, cross-consistency). `deep` runs 30+ (anti-patterns, requirement mapping, completeness audit). Effort profiles map to tiers automatically (`turbo`→skip, `fast`→quick, `balanced`→standard, `thorough`→deep), but this setting overrides that default. Forced to `deep` when >15 requirements or on the final phase.

### Commit and push

| Setting | Type | Default | Values |
| :--- | :--- | :--- | :--- |
| `auto_commit` | boolean | `true` | `true` / `false` |
| `planning_tracking` | string | `manual` | `manual` / `ignore` / `commit` |
| `auto_push` | string | `never` | `never` / `after_phase` / `always` |

- **`auto_commit`** — When `true`, the Dev agent auto-commits after each task with format `{type}({phase}-{plan}): {task-name}`, staging files individually. When `false`, changes accumulate uncommitted. **This only controls source-code commits during execution** — planning artifact commits are controlled by `planning_tracking`.
- **`planning_tracking`** — Controls `.vbw-planning/` artifact handling. See [Planning & Git](#planning--git).
- **`auto_push`** — Controls automatic pushing. See [Planning & Git](#planning--git).

### Agent behavior

| Setting | Type | Default | Values |
| :--- | :--- | :--- | :--- |
| `prefer_teams` | string | `always` | `always` / `when_parallel` / `auto` |
| `max_tasks_per_plan` | number | `5` | `1`–`7` |
| `context_compiler` | boolean | `true` | `true` / `false` |
| `plain_summary` | boolean | `true` | `true` / `false` |

- **`prefer_teams`** — Controls when VBW creates Agent Teams (multiple color-coded agents working together) vs spawning a single subagent. `always` creates teams for every operation — maximum agent visibility but higher token cost. `when_parallel` (and `auto`, which behaves identically) creates teams only when parallelism adds value: 2+ plans in execute, Scout needed in planning, ambiguous bugs in debug. Use `always` unless you're optimizing for token cost.
- **`max_tasks_per_plan`** — Maximum number of tasks the Lead agent should include in a single plan. Communicated to agents via session context. Lower values (2–3) produce more focused, easier-to-verify plans. Higher values (5–7) reduce planning overhead but increase blast radius per plan. Not enforced by a hard gate — it's an advisory constraint.
- **`context_compiler`** — When `true`, runs `compile-context.sh` to produce role-specific `.context-{role}.md` files so each agent gets curated context (Lead gets requirements, Dev gets phase goal + conventions, QA gets verification targets). When `false`, agents read project files directly without curation. Leave this on unless you're debugging context issues.
- **`plain_summary`** — When `true`, appends 2–4 plain-English sentences after QA completes in Execute mode, summarizing what happened in the phase without jargon. When `false`, output shows only the structured QA result.

### Skills and discovery

| Setting | Type | Default | Values |
| :--- | :--- | :--- | :--- |
| `skill_suggestions` | boolean | `true` | `true` / `false` |
| `auto_install_skills` | boolean | `false` | `true` / `false` |
| `discovery_questions` | boolean | `true` | `true` / `false` |

- **`skill_suggestions`** — When `true`, `/vbw:init` detects your tech stack and suggests relevant skills to install. When `false`, the entire skill suggestion flow is skipped during init.
- **`auto_install_skills`** — When `true`, suggested skills are installed automatically without asking. When `false`, VBW shows the install commands but lets you run them yourself. Has no effect if `skill_suggestions` is `false`.
- **`discovery_questions`** — When `true`, the discussion engine runs during bootstrap and `/vbw:discuss`, with depth controlled by your active profile (`default`→3–5 gray areas, `production`→4–6, `prototype`→2–3, `yolo`→skip). When `false`, skips the discussion engine entirely. Set this to `false` if you're bootstrapping projects where you already know what you want.

### Model routing

| Setting | Type | Default | Values |
| :--- | :--- | :--- | :--- |
| `model_profile` | string | `quality` | `quality` / `balanced` / `budget` |
| `model_overrides` | object | `{}` | `{"dev": "opus", "qa": "haiku", ...}` |
| `active_profile` | string | `default` | `default` / `prototype` / `production` / `yolo` / `custom` |
| `custom_profiles` | object | `{}` | User-defined profile presets |

- **`model_profile`** — Which Claude models agents use. See [Cost Optimization](#cost-optimization).
- **`model_overrides`** — Per-agent model overrides that take precedence over the profile. See [Per-Agent Overrides](#per-agent-overrides).
- **`active_profile`** — Bundles effort, autonomy, and verification tier into a switchable preset. `default` (balanced/standard/standard), `prototype` (fast/confident/quick), `production` (thorough/cautious/deep), `yolo` (turbo/pure-vibe/skip). Set automatically to `custom` when individual settings drift from their profile. Manage with `/vbw:profile`.
- **`custom_profiles`** — Stores user-created profile presets (name → effort/autonomy/verification_tier). Create, list, switch, and delete via `/vbw:profile`.

### Safety

| Setting | Type | Default | Values |
| :--- | :--- | :--- | :--- |
| `bash_guard` | boolean | `true` | `true` / `false` |

- **`bash_guard`** — When `true`, a PreToolUse hook blocks known destructive Bash commands (database drops, migration resets, volume wipes) before they execute. Covers 40+ patterns across all major frameworks and databases. Override per-command with `VBW_ALLOW_DESTRUCTIVE=1` env var, or disable entirely with `false`. Project-specific patterns can be added to `.vbw-planning/destructive-commands.local.txt`.

### Display

| Setting | Type | Default | Values |
| :--- | :--- | :--- | :--- |
| `visual_format` | string | `unicode` | `unicode` / `ascii` |
| `branch_per_milestone` | boolean | `false` | `true` / `false` |

- **`visual_format`** — Intended to switch between Unicode symbols (✓ ✗ ◆ ○ ⚡ ➜, box-drawing characters) and ASCII equivalents. Currently declared but not yet wired into agent output — agents always use Unicode.
- **`branch_per_milestone`** — Intended to auto-create a git branch per milestone during Bootstrap. Currently declared but not yet implemented — has no runtime effect.

<br>

---

<br>

## Feature Flags Reference

These are advanced runtime controls surfaced in `/vbw:config`. They are off by default and intended for staged rollout, diagnostics, and protocol hardening.

Toggle any flag with:

```bash
/vbw:config <flag_key> true
/vbw:config <flag_key> false
```

### V3 runtime flags

- **`v3_delta_context`** — When enabled, `compile-context.sh` includes a "Changed Files (Delta)" section and code slices from recently modified files in each agent's compiled context. Without this, agents only see the full project context and may miss what changed between phases. Useful when iterating on existing code where knowing *what just changed* matters more than the full codebase picture. Adds ~225–375 tokens per compiled context.

- **`v3_context_cache`** — Caches the compiled context index (`context-index.json`) between runs so `compile-context.sh` can skip recomputation when project files haven't changed. In large codebases (thousands of files), this avoids redundant shell work on every agent invocation. Has no effect if you're actively changing lots of files between runs — the cache invalidates and rebuilds anyway.

- **`v3_plan_research_persist`** — During planning, Scout researches the phase and returns structured findings. The orchestrating command writes these to a `RESEARCH.md` file in the phase directory (Scout has `disallowedTools: Write` and cannot write files itself). This makes planning decisions traceable — you can see *what Scout found* that informed the Lead's plan. Skipped when effort is set to `turbo` (which bypasses Scout entirely). Enable this if you want an audit trail of why plans look the way they do.

- **`v3_metrics`** — Instruments planning and execution with metric collection (timing, token usage, agent invocation counts). Data is written to `.vbw-planning/` and can be viewed with `/vbw:status --metrics`. Useful for understanding where time and tokens are spent. No effect on agent behavior — purely observational.

- **`v3_contract_lite`** — Before each task, generates a lightweight 5-field contract (phase, plan, task count, must-haves, allowed file paths) that the executing agent is expected to follow. Violations produce **advisory warnings only** (fail-open, exit 0) — the agent continues working but the warning is logged. This is the soft version of contract enforcement. Use this when you want guardrails without hard stops. See `v2_hard_contracts` for the strict version.

- **`v3_lock_lite`** — Enables lightweight file locks so Dev teammates can claim ownership of specific files during parallel execution. Prevents two teammates from writing to the same file simultaneously. Most useful with high `max_tasks_per_plan` values and `prefer_teams=always`. If your tasks rarely touch overlapping files, this adds overhead without much benefit. Superseded by `v3_lease_locks` if both are enabled.

- **`v3_validation_gates`** — Adds pre-task and post-task validation checks around execution steps. Without this, validation only happens at phase boundaries (QA after all tasks complete). With this enabled, each task gets entry/exit checks using dynamic gate policies from `resolve-gate-policy.sh`. Catches issues *during* execution rather than discovering them all at the end. Pairs well with `v2_hard_gates` for strict enforcement.

- **`v3_smart_routing`** — Routes tasks to agents based on task complexity analysis rather than using the same agent configuration for every task. Simple tasks may get routed to lighter agents; complex tasks get the full treatment. Reduces cost on straightforward work without sacrificing quality on hard problems. Most impactful when a phase mixes trivial and complex tasks.

- **`v3_event_log`** — Emits structured event entries (plan_created, task_started, task_completed, and 8 other event types) at lifecycle points throughout execution. Events are written to `.vbw-planning/` and provide a debug trail when something goes wrong mid-phase. **Required dependency** for `v3_event_recovery` and `v2_two_phase_completion`. Enable this first if you plan to use either of those flags.

- **`v3_schema_validation`** — Validates the structure of planning files (PLAN.md, SUMMARY.md) against expected schemas. Catches malformed artifacts early — before a downstream agent tries to parse a plan with missing fields or a summary with the wrong structure. Low overhead, high diagnostic value. Recommended for most projects.

- **`v3_snapshot_resume`** — Creates per-plan checkpoint snapshots during execution so interrupted work can resume from the last known-good state rather than restarting the entire phase. Useful if you frequently close sessions mid-phase or hit compaction issues. Without this, `/vbw:resume` still works (it reads ground truth from `.vbw-planning/`) but may need to re-derive more state.

- **`v3_lease_locks`** — Time-limited file locks (TTL=300 seconds) for task file ownership during parallel execution. Takes precedence over `v3_lock_lite` if both are enabled. Locks automatically expire, so a crashed teammate won't permanently block a file. Use this instead of `v3_lock_lite` if you've had issues with stale locks or if teammates are running long tasks.

- **`v3_event_recovery`** — When enabled and a failure is detected, attempts to recover execution state by replaying the event log (from `v3_event_log`). This is event-sourced recovery — it reconstructs what happened and where things stopped based on logged events rather than relying solely on file-based state. **Requires `v3_event_log=true`**. Only useful if you're hitting failures that corrupt `.vbw-planning/` state files.

- **`v3_monorepo_routing`** — Makes agent routing aware of monorepo package boundaries. Tasks scoped to `backend/` get routed with backend-relevant context; tasks scoped to `ios/` get iOS context. Without this, every agent loads the full project context regardless of which package a task targets. Enable this if your repo contains multiple distinct packages (e.g., frontend + backend, mobile + API).

### V2 protocol-hardening flags

- **`v2_hard_contracts`** — Upgrades contract enforcement from advisory (see `v3_contract_lite`) to strict. Generates full 11-field contracts with a `contract_hash` for integrity. Violations cause a **hard stop (exit 2)** — the agent cannot continue past a contract breach. Use this when agents are drifting from plan scope and soft warnings aren't enough. **Required dependency** for `v2_hard_gates`.

- **`v2_hard_gates`** — Upgrades validation gates from advisory to strict. When a pre-task or post-task validation check fails, execution **hard-stops (exit 2)** instead of logging a warning and continuing. Prevents broken work from propagating to the next task. Pairs with `v3_validation_gates` (which adds the gate checks) and **requires `v2_hard_contracts=true`**.

- **`v2_typed_protocol`** — Enforces strict typing on inter-agent messages and event log entries. Unknown event types are rejected instead of accepted with a warning. Catches protocol drift where agents send malformed or unexpected message types. Low overhead, useful as a diagnostic safeguard — if agents are communicating cleanly, you'll never notice it's on.

- **`v2_role_isolation`** — Enforces file-write boundaries based on agent role. Scout becomes strictly read-only (blocked from any writes). All roles are restricted to writing within `.vbw-planning/` for planning artifacts. Blocked writes are logged to stderr. Strengthens the platform-level `disallowedTools` enforcement with file-path-level granularity. Recommended for any project where you want guarantees that Scout/QA aren't accidentally modifying source code.

- **`v2_two_phase_completion`** — Tasks require two steps to complete: first register the output artifact (via `artifact-registry.sh`), then mark the task done (via `two-phase-complete.sh`). Prevents agents from claiming "done" without producing verifiable output. **Requires `v3_event_log=true`**. Most useful when tasks are completing without proper deliverables — this forces proof of work.

- **`v2_token_budgets`** — Enables per-agent token budget tracking and context truncation. Each agent gets a budget based on its role and the active model profile. When an agent approaches its budget, context is truncated to stay within limits. Useful for controlling costs on large projects where agents might consume excessive tokens. Without this, agents use as much context as they need with no ceiling.

### Flag dependencies

Some flags require other flags to be enabled first. VBW warns at session start if dependencies are missing:

- `v3_event_recovery` requires `v3_event_log=true` — recovery replays the event log, so there must be one.
- `v2_hard_gates` requires `v2_hard_contracts=true` — strict gates need strict contracts to enforce against.
- `v2_two_phase_completion` requires `v3_event_log=true` — artifact registration is tracked via events.

For implementation details, see `references/execute-protocol.md` and script-level checks in `scripts/session-start.sh`.

<br>

## Cost Optimization

VBW spawns specialized agents for planning, development, and verification. Model profiles let you control which Claude model each agent uses, trading cost for quality based on your needs.

### Three Preset Profiles

| Profile | Use Case | Lead | Dev | QA | Scout | Est. Cost/Phase |
| :--- | :--- | :--- | :--- | :--- | :--- | ---: |
| **Quality** | Production work, architecture decisions (default) | opus | opus | sonnet | haiku | ~$2.80 |
| **Balanced** | Standard development | sonnet | sonnet | sonnet | haiku | ~$1.40 |
| **Budget** | Prototyping, tight budgets | sonnet | sonnet | haiku | haiku | ~$0.70 |

*Debugger and Architect follow the same model as Lead. Estimates based on typical 3-plan phase.*

**Quality is the default.** It gives you maximum reasoning depth for architecture decisions and production-critical work. Switch to Balanced (`/vbw:config model_profile balanced`) for 50% cost savings on standard development.

**Quality** uses Opus for Lead, Dev, Debugger, and Architect -- maximum reasoning depth for critical work. QA stays on Sonnet (verification doesn't need Opus), Scout on Haiku (research throughput).

**Budget** keeps Dev and core agents on Sonnet (quality baseline) but drops QA to Haiku. Good for exploratory work where you're iterating fast and verification can be lighter.

### Switching Profiles

```bash
/vbw:config model_profile quality
/vbw:config model_profile balanced
/vbw:config model_profile budget
```

Each switch shows before/after cost impact. Changes apply to the next phase.

### Per-Agent Overrides

Need Opus for one agent without switching the whole profile?

```bash
/vbw:config model_override dev opus
/vbw:config model_override qa sonnet
```

Common patterns:
- Budget profile + Dev override to Opus for complex implementation tasks
- Balanced profile + Lead override to Opus for strategic planning phases
- Quality profile + QA override to Haiku when verification is straightforward

### Agent Turn Limits

Each agent has a default turn budget that scales with your effort level (thorough = 1.5×, balanced = 1×, fast = 0.8×, turbo = 0.6×). Defaults:

| Agent | Base Turns |
| :--- | ---: |
| Scout | 15 |
| QA | 25 |
| Architect | 30 |
| Lead | 50 |
| Dev | 75 |
| Debugger | 80 |

Override per-agent in `.vbw-planning/config.json`:

```json
{
  "agent_max_turns": {
    "dev": 100,
    "debugger": 120
  }
}
```

Set a value to `false` or `0` to give an agent unlimited turns (no turn cap is enforced):

```json
{
  "agent_max_turns": {
    "dev": false
  }
}
```

### Effort vs Model

**Model profile** controls which Claude model agents use (cost).
**Effort** controls how deeply agents think (workflow depth).

They're independent. You can run Thorough effort on Budget profile (deep workflow, cheap models) or Fast effort on Quality profile (quick workflow, expensive models). Most users match them:
- `thorough` effort + `quality` profile
- `balanced` effort + `balanced` profile
- `fast` effort + `budget` profile

Switch both at once with work profiles:

```bash
/vbw:profile production   → thorough + quality
/vbw:profile prototype    → fast + budget
```

See **[Model Profiles Reference](references/model-profiles.md)** for preset definitions, cost breakdown, and implementation details.

<br>

---

<br>

## Project Structure

```
.claude-plugin/    Plugin manifest (plugin.json)
agents/            7 agent definitions with native tool permissions
commands/          24 slash commands (commands/*.md)
config/            Default settings and stack-to-skill mappings
hooks/             Plugin hooks for continuous verification
scripts/           Hook handler scripts (security, validation, QA gates)
references/        Brand vocabulary, verification protocol, effort profiles, handoff schemas
templates/         Artifact templates (PLAN.md, SUMMARY.md, etc.)
assets/            Images and static files
```

<br>

When you run `/vbw:init` in your project, it creates:

```
.vbw-planning/
  PROJECT.md       Project definition, core value, requirements, decisions
  REQUIREMENTS.md  Versioned requirements with traceability
  ROADMAP.md       Phases, plans, success criteria, progress tracking
  STATE.md         Current position, velocity metrics, session continuity
  config.json      Local VBW configuration
  phases/          Execution artifacts (PLAN.md, SUMMARY.md per phase)
  milestones/      Archived milestone records
```

Your AI-managed project now has more structure than most startups that raised a Series A.

<br>

---

<br>

## Requirements

- **Claude Code** with **Opus 4.6+** model
- **jq** -- the only external dependency. Install via `brew install jq` (macOS) or `apt install jq` (Linux). VBW checks for jq during `/vbw:init` and session start, and warns clearly if it's missing.
- **Agent Teams** enabled (`/vbw:init` will offer to set this up for you)
- A project directory (new or existing)
- The willingness to let an AI manage your development lifecycle

That last one is the real barrier to entry.

<br>

---

<br>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on local development, project structure, and pull requests.

<br>

## Contributors

<a href="https://github.com/yidakee/vibe-better-with-claude-code-vbw/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=yidakee/vibe-better-with-claude-code-vbw" />
</a>

<br>

## License

MIT -- see [LICENSE](LICENSE) for details.

Built by [Tiago Serôdio](https://github.com/yidakee).
