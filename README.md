# VBW: Vibe Better With Claude Code

**You say what you want. VBW proves it is done.**

AI coding assistants fail in a familiar way: they say "done" and the code
does not work, or they quietly change the tests until everything passes. You
find out later.

VBW is a Claude Code plugin built on one idea: **done is something a program
checks, not something the assistant claims.** Before any code is written,
you and VBW agree on what to build and write a test for each requirement.
You approve the plan, and the tests are frozen. VBW then builds, runs the
tests itself, and marks a requirement done only when its tests pass on the
current code. What only a person can judge (how it looks, how it feels) stays
with you.

![The VBW flow: requirements, tests, approval, build, proof, acceptance](assets/flow.png)

## How it works

1. **Agree on what to build, and decide what matters.** VBW helps you write
   requirements: each is either something a test can prove, or something only
   you can judge. Before planning, it asks the decisions that matter (cost,
   where data lives, security, what is hard to change later), one at a time,
   with plain trade-offs and a recommendation, and records what you chose and why.
2. **Plan it, with tests first.** VBW plans the work in small parts and writes
   a test for every requirement, and for every rule a requirement states (each
   condition, edge and error case). The tests fail today; that is the point.
3. **You approve.** One choice, with Approve first so Enter approves (or type
   `/vbw:approve`). Nothing VBW runs is unapproved, and the
   tests cannot be weakened afterwards to make work "pass".
4. **Build in parallel.** Independent parts are built at the same time by
   separate Dev agents, each until its own tests pass. Every commit names the
   part and the requirement it delivers.
5. **Prove.** VBW runs the tests itself, on a clean copy of the committed code,
   so leftover files cannot change the result. Not before, and not on anyone's
   say-so.
6. **Accept and ship.** You check what only a person can judge, and ship.

All of that is one command: **`/vbw:vibe`**. It always knows the next step,
does it, and stops only when it needs you.

## Install

In Claude Code:

```
/plugin marketplace add swt-labs/vibe-better-with-claude-code-vbw
/plugin install vbw@vbw-marketplace
```

Restart Claude Code. VBW turns on the Claude Code features it needs (Dynamic
workflows and its status line) the first time you use it.

You need Claude Code 2.1.286 or later, `jq` and `git`. Use a Sonnet, Opus or
Fable model, in auto mode (Shift+Tab) for hands-off building. `/vbw:doctor`
checks all of this for you.

## Start

Your first project. In your project's folder (any git repository, new or existing):

```
/vbw:vibe I want a command-line expense tracker in Node.js
```

1. **Setup.** The first time, `/vbw:vibe` sets up the project and the VBW
   status line.

   ![The VBW status line showing the project's progress](assets/statusline.png)

   On Claude Code 2.1.287 or newer, a panel next to it says in plain words
   what VBW is doing and when it needs you ([docs/panel.md](docs/panel.md)).

2. **Questions.** Once per project, VBW first asks three quick questions about
   you (how much software you have built, how it should explain things, how
   involved you want to be), so every message fits your level. Then it asks
   what you want and the decisions that matter, one at a time.

   ![VBW asking a decision with a recommendation](assets/first-question.png)

3. **Plan and approve.** VBW shows the plan and its tests. Read them, then answer
   the question it asks: **Approve** is the first choice, so Enter approves
   the contract shown. **Not yet** or your own words tell VBW what to change.
   Typing `/vbw:approve` still works.

   ![The plan and its tests, ready for approval](assets/approve.png)

4. **Build and prove.** `/vbw:vibe` builds the parts in parallel and runs the
   tests. `/vbw:status` shows where things stand.

   ![Requirements proven by passing tests](assets/proof.png)

Type `/vbw:vibe` whenever you come back; it continues where things stand.
`/vbw:profile` changes your answers and how much it does by itself (Careful, Standard, Fast).

Coming from an earlier VBW? See [docs/convert.md](docs/convert.md).

## Commands

| Command | What it does |
|---|---|
| `/vbw:vibe [what you want]` | The one command: the next step, every time |
| `/vbw:help` | List the commands |
| `/vbw:approve` | Approve the plan and its tests (only you can) |
| `/vbw:status` | Where the project stands |
| `/vbw:discuss`, `/vbw:research` | Think a decision through; a sourced answer to a question |
| `/vbw:todo [idea]`, `/vbw:list-todos` | Park an idea for later; see the list |
| `/vbw:qa`, `/vbw:verify` | Run every proof now; check what only you can judge |
| `/vbw:debug [problem]`, `/vbw:fix [what]` | Find a bug's root cause; a quick fix with every proof re-run |
| `/vbw:init`, `/vbw:convert` | Set up VBW (vibe does it too); bring in a project from an earlier VBW |
| `/vbw:map`, `/vbw:teach [convention]` | Map an existing codebase; teach your conventions |
| `/vbw:pause`, `/vbw:resume` | Stop safely; pick up where you left off |
| `/vbw:profile`, `/vbw:config` | How VBW works (how it talks to you, models, how much it does on its own); each setting |
| `/vbw:skills`, `/vbw:rtk`, `/vbw:compress` | Look for the best tools for your project ([docs/tools.md](docs/tools.md)); output compression; terser instruction files |
| `/vbw:panel`, `/vbw-panel`, `/vbw-sound` | Whether the panel works here; open the panel; turn the "needs you" sound on or off |
| `/vbw:doctor`, `/vbw:report` | Check the setup; prepare a bug report |
| `/vbw:update`, `/vbw:whats-new`, `/vbw:uninstall` | Keep VBW current, or remove it |

## How it stays safe

- **Guards** run before every command Claude runs and block what would destroy
  work (force-push, `git reset --hard`, deleting the project), touch secret files,
  or let an agent write outside its part of the plan.
- **Approval is yours.** Tests and project commands run only after you approve
  them, and the approval lives in your clone's `.git` folder: a repository you
  download cannot approve itself.
- **Everything is in git.** The plan, the tests and every change are committed
  with the requirement they serve, so `git log` tells the story.

## Documentation

- [docs/record.md](docs/record.md): the plan of record (`.vbw/record.json`)
- [docs/proof.md](docs/proof.md): requirements, tests, approval and proof
- [docs/next.md](docs/next.md): how VBW decides the next step
- [docs/workflows.md](docs/workflows.md): the team (Architect, Lead, Dev, QA, Scout, Debugger, Docs) and the workflows
- [docs/guards.md](docs/guards.md): the safety guards
- [docs/statusline.md](docs/statusline.md): the status line
- [docs/panel.md](docs/panel.md): the panel, a plain-words view of progress and what needs you
- [docs/diagnostics.md](docs/diagnostics.md): `vbw report` for bug reports and `vbw rtk`
- [docs/tools.md](docs/tools.md): the offer to find the best tools for your project (asked once, nothing installed without your approval)
- [docs/convert.md](docs/convert.md): updating from an earlier VBW and bringing in its projects
- [plugin/CHANGELOG.md](plugin/CHANGELOG.md): what changed

## Contributing

Tests: `bash tools/test.sh` (runs under macOS bash 3.2 and bash 5). See
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
