<div align="center">

# Vibe Better With Claude Code - VBW

*You're not an engineer anymore.*

*You're a prompt jockey with commit access.*

*At least do it properly.*

<img src="assets/abraham.jpeg" alt="Abraham Lincoln portrait" width="300"/>

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-v2.1.286+-blue.svg)](https://code.claude.com)
[![Models](https://img.shields.io/badge/Model-Sonnet_%7C_Opus_%7C_Fable-purple.svg)](https://anthropic.com)
[![Discord](https://img.shields.io/badge/Discord-Join%20Us-5865F2.svg?logo=discord&logoColor=white)](https://discord.gg/zh6pV53SaP)

</div>

## What Is This

> **Platform:** macOS and Linux. Windows is not supported natively: VBW runs on bash. On Windows, run Claude Code inside [WSL](https://learn.microsoft.com/en-us/windows/wsl/install).

VBW is a Claude Code plugin that turns "build me an app" into software that actually works, and shows you that it does.

**The problem.** AI coding assistants are confident. They write the code, say "done", and move on. Sometimes it's done. Sometimes it's a button that does nothing, a feature you never asked for, or a test quietly changed until it passes. You find out a week later, usually in front of someone.

**What VBW does about it.** You say what you want, in plain words. VBW turns it into a short list of requirements and asks you the few decisions that matter. It plans the work, and for every requirement it writes a check: a small program that says yes or no. You approve the plan, and from that moment the checks are locked. A team of AI agents builds the parts in parallel. Then VBW runs the checks itself. A requirement is done when its check passes on the real, committed code. Not when the AI says so. What no program can judge (how it looks, how it feels) comes back to you.

**Why it matters.** "Done" stops being a feeling. You get working software, a plan you agreed to, and a git history that says which change delivers which requirement. If you're new to this, VBW explains every step in your words and asks only what a person has to decide. If you've been doing this for twenty years, it does the parts you always skip, and doesn't let anyone (including the AI, including you at 6 p.m. on a Friday) bend the rules to make a deadline.

**How you use it.** One command: `/vbw:vibe`. It always knows the next step, does it, and stops only when it needs you.

It's the entire software development lifecycle, except the engineering team is a plugin and the QA department is a program that has never once been talked into anything.

### **Think of it as project management for the post-dignity era of software development.**

Inspired by **[Ralph](https://github.com/frankbria/ralph-claude-code)** and **[Get Shit Done](https://github.com/glittercowboy/get-shit-done)**, however, an entirely new architecture.

## Token Efficiency

### VBW 2 measurements (coming soon)

> **Coming soon.** VBW 2's token and cost analysis ships with **2.1.0**.

### VBW 1.x vs Stock Opus 4.6 Agent Teams

*Legacy measurements from VBW 1.x.*

Every capability was shell-only: 85 scripts ran as bash subprocesses at zero model token cost. The codebase grew 42% since v1.21.30 while per-request overhead grew just 12% (still 7% below v1.20.0). 845 bats tests validated the stack.

**Analysis reports:** [v1.30.0](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/blob/main/docs/vbw-1-30-0-full-spec-token-analysis.md) | [v1.21.30](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/blob/main/docs/vbw-1-21-30-full-spec-token-analysis.md) | [v1.20.0](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/blob/main/docs/vbw-1-20-0-full-spec-token-analysis.md) | [v1.10.7](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/blob/main/docs/vbw-1-10-7-context-compiler-token-analysis.md) | [v1.10.2](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/blob/main/docs/vbw-1-10-2-vs-stock-agent-teams-token-analysis.md) | [v1.0.99](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/blob/main/docs/vbw-1-0-99-vs-stock-teams-token-analysis.md)

| Category | Stock Agent Teams | VBW 1.x | Saving |
| :--- | ---: | ---: | ---: |
| Base context overhead | 10,800 tokens | 1,500 tokens | **86%** |
| State computation per command | 1,300 tokens | 200 tokens | **85%** |
| Agent coordination (x4 agents) | 16,000 tokens | 1,200 tokens | **93%** |
| Compaction recovery | 5,000 tokens | 700 tokens | **86%** |
| Context duplication (shared files) | 16,500 tokens | 900 tokens | **95%** |
| Agent model cost per phase | $2.78 | $1.40 | **50%** |
| **Total coordination overhead** | **87,100 tokens** | **12,100 tokens** | **86%** |

| Scenario | Without VBW | With VBW 1.x (Balanced) | Impact |
| :--- | ---: | ---: | ---: |
| API: single project (10 phases) | ~$28 | ~$14 | **~$14 saved** |
| API: active dev (20 phases/mo) | ~$56/mo | ~$28/mo | **~$28/mo saved (~$336/yr)** |
| API: heavy dev (50 phases/mo) | ~$139/mo | ~$70/mo | **~$69/mo saved (~$828/yr)** |
| API: team (100 phases/mo) | ~$278/mo | ~$139/mo | **~$139/mo saved (~$1,668/yr)** |
| Pro / Max subscription | baseline capacity | ~3x phases per cycle | **200% more work done** |

*Based on [API pricing](https://claude.com/pricing) at the time of each report.*

## Manifesto

VBW is open source because the best tools are built by the people who use them.

This project exists to make AI coding better for everyone, and "everyone" means exactly that.

**For absolute beginners:** VBW may look intimidating, especially if you've never used Claude Code, but it is, in fact, incredibly easy to use. You type what you want. VBW asks you a few questions in plain words, builds it, and shows you it works. You will ship software that works and have no idea why. That puts you level with most of the industry.

**For seasoned developers:** You've been meaning to write the tests first since 2009. VBW just does it. Models, autonomy and rigor are all switches, exposed as a control surface, not hidden behind prompts. The beginners get guardrails; you get the switches behind the guardrails.

**For contributors:** VBW is a living project. The kernel, the workflows, the agents, the guards: all of it is open to improvement. If you've found a better way to plan, build, or prove code with Claude, bring it. File an issue, open a PR, or just show up and share what you've learned. Every contribution makes the next person's experience better.

**[Join the Discord](https://discord.gg/zh6pV53SaP)** -- whether you want to help build VBW or just want VBW to help you build.

## Table of Contents

- [What Is This](#what-is-this)
- [Token Efficiency](#token-efficiency)
- [Manifesto](#manifesto)
- [Features](#features)
- [Install](#install)
- [How It Works](#how-it-works)
- [Start](#start)
- [Commands](#commands)
- [The Agents](#the-agents)
- [How It Stays Safe](#how-it-stays-safe)
- [Configuration](#configuration)
- [Project Structure](#project-structure)
- [Requirements](#requirements)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Features

### One command, the whole lifecycle

`/vbw:vibe` reads where your project stands and does the next step: agree on what to build, plan, get your approval, build, check, fix, review, ship. You never need to know which step you're on. VBW knows. You just keep typing `/vbw:vibe`, which is also what you were doing before, except now it works.

### Done means checked

Every requirement is one of two kinds: something a program can check, or something only you can judge. The first kind gets a check, written before the code, that fails until the work is right. The second kind comes back to you at the end. Nothing is marked done because an AI felt good about it.

### Your approval means something

VBW shows you the plan and its checks and asks one question: **Approve** or **Not yet**. Once you approve, the checks are locked. If the code doesn't pass, the code changes. Revolutionary, we know.

### Decisions, not surprises

Before planning, VBW asks the decisions that actually matter (cost, where data lives, security, what's hard to change later), one at a time, with plain trade-offs and a recommendation, and records what you chose and why. Six months from now, when someone asks "who decided this?", the answer will be in git. It will be you.

### A team that builds in parallel

Seven specialist agents: an Architect, a Lead, Devs, QA, Scouts, a Debugger and a Docs writer. Independent parts are built at the same time, each Dev in its own files, so nobody overwrites anybody. One commit per task, each naming the requirement it delivers. `git log` reads like an audit, not a crime scene.

### Rigor that fits the work

VBW sizes the process to the job. A one-line fix gets one Dev and one approval. A payments migration gets research, a full team and deep review. VBW decides from what the work touches (how many requirements and files, and risky areas like sign-in, payments, secrets or deletion), raises the bar on its own when a build goes badly, and tells you why. A typo doesn't get a committee. Your billing code doesn't get a shrug. See [docs/rigor.md](docs/rigor.md).

### It talks at your level

Once per project, VBW asks three quick questions: how much software you've built, how much it should explain, and how involved you want to be. Every message after that fits. Beginners get plain words. Seniors get terse output and the trade-offs, which is what they'd have asked for if they ever read the docs.

### Guards that don't negotiate

Before every command Claude runs, VBW's guards block what would destroy work (force-push, `git reset --hard`, deleting the project), touch secret files like `.env` or keys, or let an agent write outside its part of the plan. See [How It Stays Safe](#how-it-stays-safe).

### Real-time statusline that knows more about your project than you do

![VBW statusline example](assets/statusline.png)

Progress, what's proven and what VBW needs from you, rendered after every response. Everything a senior engineer would track on a whiteboard, except the whiteboard has been replaced by a terminal and the senior engineer has been replaced by you. On Claude Code 2.1.287+, a panel next to it says in plain words what VBW is doing and when it needs you, with an optional sound so you can stop pretending to watch it work ([docs/panel.md](docs/panel.md)).

### Pick up where you left off

Everything VBW knows lives in your project, in `.vbw/`, not in a chat window. Close the terminal, switch branches, disappear for a weekend of pretending you have hobbies. Type `/vbw:vibe` and it continues exactly where things stand.

---

## Install

Open Claude Code and run these two commands inside the session, **one at a time**:

**Step 1:** Add the marketplace

```text
/plugin marketplace add swt-labs/vibe-better-with-claude-code-vbw
```

**Step 2:** Install the plugin

```text
/plugin install vbw@vbw-marketplace
```

That's it. Two commands, two separate inputs. Do not paste them together: Claude Code will treat both lines as a single command and the URL will break.

Restart Claude Code. VBW turns on what it needs (Dynamic workflows and its status line) the first time you use it. `/vbw:doctor` checks the rest.

To update later:

```text
/vbw:update
```

### Running VBW

**Option A: Supervised mode** (recommended for the cautious)

```bash
claude
```

Claude Code asks permission before file writes and commands. You approve once per tool, per project, and it remembers. VBW's own guards are a second safety net. First session has some clicking. After that, smooth sailing.

**Option B: Auto mode** (recommended for the brave)

Use a Sonnet, Opus or Fable model and press Shift+Tab to switch Claude Code to auto mode. Agents keep building until the work is done or your budget isn't. VBW still stops for the things only you can do: decisions, approval, checking and shipping.

This is how most vibe coders run it. The agents work longer, the flow stays unbroken, and you get to pretend you're supervising while scrolling Twitter.

> **Disclaimer:** If you go further and use `--dangerously-skip-permissions`: it is called that for a reason. It is not called `--everything-will-be-fine` or `--trust-the-AI-it-knows-what-its-doing`. VBW's guards are guard rails, not a sandbox; the Claude Code sandbox and permission rules remain the security boundary. You are trusting software written by an AI, managed by an AI, and checked by a program an AI also wrote. If this arrangement doesn't concern you, you are exactly the target audience for this plugin.

---

## How It Works

VBW operates on a simple loop that will feel familiar to anyone who's ever shipped software. Or read about it on Reddit.

```text
    ┌────────────────────────────────────────┐
    │ YOU HAVE AN IDEA                       │
    │ (dangerous, but continue)              │
    └────────────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────┐
    │ /vbw:vibe                              │
    │ First time: sets VBW up and asks       │
    │ 3 quick questions about you.           │
    │ Existing code: maps it first.          │
    └────────────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────┐
    │ 1. AGREE                               │
    │ What you want, in plain words.         │
    │ The decisions that matter, one at      │
    │ a time, each with a recommendation.    │
    └────────────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────┐
    │ 2. PLAN                                │
    │ Small parts. A check for every         │
    │ requirement, written before code.      │
    └────────────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────┐            ┌────────────────────────┐
    │ 3. YOU APPROVE                         │            │ "Not yet"?             │
    │ Enter = Approve. From here on the      │ ◀──────────│ VBW changes the plan   │
    │ checks are locked. Nobody edits        │            │ and asks again         │
    │ them to make work "pass".              │            └────────────────────────┘
    └────────────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────┐
    │ 4. BUILD                               │
    │ Agents build the parts in parallel,    │
    │ each in its own files.                 │
    │ One commit per task.                   │
    └────────────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────┐            ┌────────────────────────┐
    │ 5. PROVE                               │ ── fail ──▶│ FIX                    │
    │ VBW runs the locked checks itself,     │            │ Agents fix the code,   │
    │ on a clean copy of the code.           │ ◀──────────│ never the checks       │
    │ Pass means done. Nothing else does.    │            └────────────────────────┘
    └────────────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────┐            ┌────────────────────────┐
    │ 6. REVIEW                              │            │ Problems?              │
    │ QA reviews against the goal.           │ ──────────▶│ They become fixes      │
    │ You check what no program can          │            │ (back to FIX)          │
    │ judge: look, feel, wording.            │            └────────────────────────┘
    └────────────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────┐
    │ 7. SHIP                                │
    │ More to build? /vbw:vibe again.        │
    └────────────────────────────────────────┘
```

Every stop ends with one plain line: **What I need from you:** and the one thing you must do now, or "nothing". You will never again wonder whether the AI is waiting for you. It will tell you. Repeatedly.

---

## Start

You only need to remember one command. Seriously.

In any git repository, new or existing:

```text
/vbw:vibe I want a command-line expense tracker in Node.js
```

1. **Setup.** The first time, `/vbw:vibe` sets up the project and the VBW status line. No separate init step to forget.

2. **Questions.** Three about you, once per project. Then what you want, and the decisions that matter, one at a time.

   ![VBW asking a decision with a recommendation](assets/first-question.png)

3. **Plan and approve.** VBW shows the plan and its checks. Read them. (Seniors: you'll skim. We know. They're short so that skimming is enough.) **Approve** is the first choice, so Enter approves. **Not yet** or your own words tell VBW what to change. Typing `/vbw:approve` also works.

   ![The plan and its checks, ready for approval](assets/approve.png)

4. **Build and prove.** `/vbw:vibe` builds the parts in parallel and runs the checks. `/vbw:status` shows where things stand.

   ![Requirements proven by passing checks](assets/proof.png)

That's it. Type `/vbw:vibe` whenever you come back; it continues where things stand. `/vbw:profile` changes how VBW works in one go: **Careful**, **Standard** or **Fast**.

Used an earlier VBW in this project? VBW reviews the old folder, recommends converting or starting fresh, and you choose: see [docs/convert.md](docs/convert.md).

---

## Commands

You need one: `/vbw:vibe`. The rest exist for people who like to feel in control.

| Command | What it does |
|---|---|
| `/vbw:vibe [what you want]` | The one command: the next step, every time |
| `/vbw:help` | List the commands |
| `/vbw:approve` | Approve the plan and its checks (only you can) |
| `/vbw:status` | Where the project stands |
| `/vbw:discuss`, `/vbw:research` | Think a decision through; a sourced answer to a question |
| `/vbw:todo [idea]`, `/vbw:list-todos` | Park an idea for later; see the list. For all those "we should really..." thoughts that used to die in a terminal tab |
| `/vbw:qa`, `/vbw:verify` | Run every check now; check what only you can judge |
| `/vbw:debug [problem]`, `/vbw:fix [what]` | Find a bug's root cause from three angles at once; a quick fix with every check re-run, for when you don't need seven agents to add a missing comma |
| `/vbw:init`, `/vbw:convert` | Set up VBW (vibe does it too); bring in a project from an earlier VBW |
| `/vbw:map`, `/vbw:teach [convention]` | Map an existing codebase; teach VBW your conventions |
| `/vbw:pause`, `/vbw:resume` | Stop safely; pick up where you left off |
| `/vbw:profile`, `/vbw:config` | How VBW works (how it talks to you, models, how much it does on its own); each setting |
| `/vbw:skills`, `/vbw:rtk`, `/vbw:compress` | Look for the best tools for your project ([docs/tools.md](docs/tools.md)); output compression; terser instruction files |
| `/vbw:panel`, `/vbw-panel`, `/vbw-sound` | Whether the panel works here; open the panel; turn the "needs you" sound on or off |
| `/vbw:doctor`, `/vbw:report` | Check the setup; prepare a bug report |
| `/vbw:update`, `/vbw:whats-new`, `/vbw:uninstall` | Keep VBW current, or remove it and go back to prompting manually like it's 2024 |

---

## The Agents

VBW uses 7 specialized agents. Each one is a short specification of what good work looks like, plus the tools it's allowed to touch, which is more than can be said for most interns.

| Agent | Role | Tools |
| :--- | :--- | :--- |
| **Architect** | Finds the decisions you must make, then scopes the work into phases with clear success criteria. Plans only, never code. | Read, Grep, Glob, Bash |
| **Lead** | Breaks each phase into small plans with checks that fail today, and reviews its own work. The one who actually makes decisions. | Read, Grep, Glob, Bash, Write, Edit, WebFetch |
| **Dev** | Builds one plan within its files, one commit per task. Handle with care. | Read, Grep, Glob, Bash, Write, Edit |
| **QA** | Reviews a built phase against its goal. Any deviation from the plan is a failure. Changes nothing. Trusts nothing. | Read, Grep, Glob, Bash |
| **Scout** | Researches one angle (your code, the web, documentation) and reports findings with sources. The responsible one. | Read, Grep, Glob, Bash, WebSearch, WebFetch |
| **Debugger** | Scientific method: reproduce, hypothesize, gather evidence, diagnose; then a minimal root-cause fix with a regression test. The one you still worry about. | Read, Grep, Glob, Bash, Write, Edit |
| **Docs** | READMEs, changelogs, guides. Documentation files only. | Read, Grep, Glob, Bash, Write, Edit |

Here's when each one shows up to work:

| Workflow | Started by | Who runs |
| :--- | :--- | :--- |
| Planning | `/vbw:vibe` at the plan step | Architect (decisions) → Architect (scope) → Lead |
| Building | `/vbw:vibe` at the build step | a Dev per ready plan (Docs for documentation), in parallel |
| Fixing | `/vbw:vibe` when a check fails | a Dev per group of related fixes, in parallel |
| Verifying | `/vbw:vibe` after the checks pass | a QA agent per built phase, in parallel |
| Mapping | `/vbw:map`, or planning on existing code | a Scout per angle, then one merged map |
| Researching | `/vbw:research` | four Scouts, then one sourced answer |
| Investigating | `/vbw:debug` | three Debuggers (reproduce, trace, history), one diagnosis, then one fix |

The full reference is [docs/workflows.md](docs/workflows.md).

---

## How It Stays Safe

- **Guards** run before every command Claude runs and block what would destroy work (force-push, `git reset --hard`, deleting the project), touch secret files, or let an agent write outside its part of the plan. They read what the shell would actually run, not just the text: `git commit -m "never rm -rf /"` is fine, `sh -c 'rm -rf .'` is not.
- **Approval is yours.** The AI cannot approve its own plan, however creatively it spells the command. Checks and project commands run only after you approve them, and the approval lives in your clone's `.git` folder: a repository you download cannot approve itself.
- **Checks can't be bent.** While building, no agent may edit an approved check.
- **Everything is in git.** The plan, the checks and every change are committed with the requirement they serve, so `git log` tells the story.

See [docs/guards.md](docs/guards.md) for every rule and why it exists.

---

## Configuration

Three presets cover most people. `/vbw:profile` switches them; `/vbw:config` changes one setting at a time.

| Preset | Models | Autonomy | Good for |
| :--- | :--- | :--- | :--- |
| **Careful** | `quality`: Opus for Architect, Lead, Dev and Debugger | `guided`: explains each step and waits for "go" | Learning, a first project, risky changes |
| **Standard** | `balanced`: Sonnet for every agent | `balanced`: keeps going, stops for your decisions, approval, checking and shipping | Most work (the default) |
| **Fast** | `budget`: Haiku for Scout, Sonnet for the rest | `hands-off`: takes its own recommendations and lists them for you | Small changes, once you trust it |

Approval, checking and shipping always stop for you, whatever the preset. Autonomy controls friction, not safety.

| Setting | Values | What it does |
| :--- | :--- | :--- |
| `profile` | `quality` / `balanced` / `budget` | Which models the agents run on |
| `model.<role>` | `opus` / `sonnet` / `haiku` / a model id / `default` | Override one agent. QA never runs on Haiku: whatever judges your work doesn't get the cheap seat |
| `autonomy` | `guided` / `balanced` / `hands-off` | How much `/vbw:vibe` does on its own |
| `autonomy_cap` | a number | Steps one autonomous run takes before stopping |
| `rigor` | `auto` / `express` / `standard` / `deep` | How thorough each phase is: sized to the work (`auto`, the default) or forced |
| status line | `vbw statusline on` / `off` | The status line |

Your own session keeps the model you chose with `/model`; it must be Sonnet, Opus or Fable for auto mode.

---

## Project Structure

What VBW creates in your project:

```text
.vbw/
  spec.md        What you want: the requirements, in plain words. You own this file
  record.json    The plan of record: phases, plans, checks, results. Only VBW writes it
  map.md         The map of your codebase, when there is existing code
```

Your AI-managed project now has more structure than most startups that raised a Series A.

The plugin itself:

```text
plugin/
  bin/vbw        The kernel: decides the next step, runs the checks, keeps the record
  lib/           Kernel libraries (bash, jq, git)
  workflows/     Planning, building, fixing, verifying, mapping, researching, investigating
  agents/        Architect, Lead, Dev, QA, Scout, Debugger, Docs
  skills/        /vbw:vibe and every other command
  hooks/         The guards
  scripts/       The status line
```

---

## Requirements

- **Claude Code** 2.1.286 or later (2.1.287+ for the panel)
- A **Sonnet, Opus or Fable** model
- **`jq`** and **`git`**. Install with `brew install jq` (macOS) or `apt install jq` (Linux). `/vbw:doctor` checks all of this
- A git repository (new or existing)
- The willingness to let an AI build your software, and a program check its homework

That last one is the real barrier to entry.

---

## Documentation

- [docs/proof.md](docs/proof.md): requirements, checks, approval and proof
- [docs/next.md](docs/next.md): how VBW decides the next step
- [docs/rigor.md](docs/rigor.md): how VBW sizes the process to the work
- [docs/workflows.md](docs/workflows.md): the team and the workflows
- [docs/guards.md](docs/guards.md): the safety guards
- [docs/interview.md](docs/interview.md): the questions about you, and how they shape every message
- [docs/record.md](docs/record.md): the plan of record (`.vbw/record.json`)
- [docs/statusline.md](docs/statusline.md): the status line
- [docs/panel.md](docs/panel.md): the panel, a plain-words view of progress and what needs you
- [docs/diagnostics.md](docs/diagnostics.md): `vbw report` for bug reports and `vbw rtk`
- [docs/tools.md](docs/tools.md): the offer to find the best tools for your project (asked once, nothing installed without your approval)
- [docs/convert.md](docs/convert.md): coming from an earlier VBW, the review of its old folder, and the choice to convert or start fresh
- [plugin/CHANGELOG.md](plugin/CHANGELOG.md): what changed

---

## Contributing

Tests: `bash tools/test.sh` (runs under macOS bash 3.2 and bash 5). See [CONTRIBUTING.md](CONTRIBUTING.md) for local development and pull requests.

## Contributors

[![Contributors](https://contrib.rocks/image?repo=swt-labs/vibe-better-with-claude-code-vbw)](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/graphs/contributors)

## License

MIT -- see [LICENSE](LICENSE) for details.

Built by a team of researchers obsessed with saving tokens.
