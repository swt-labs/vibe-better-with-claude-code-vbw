# VBW: Vibe Better With Claude Code

**You say what you want. VBW proves it is done.**

VBW is a Claude Code plugin that turns an idea into working, tested, committed
code, and shows you the proof:

1. **Agree on what to build, and decide what matters.** VBW helps you write
   it down as requirements: each is either something a test can prove, or
   something only you can judge (how it looks, how it feels). Before planning,
   it asks you the decisions that matter (cost, where data lives, security,
   what is hard to change later), one at a time, with plain trade-offs and a
   recommendation, and records what you chose and why.
2. **Plan it, with tests first.** VBW plans the work in small parts and writes
   a test for every requirement. The tests fail today; that is the point.
3. **You approve.** `/vbw:approve`. Nothing VBW runs is unapproved, and the
   tests are frozen from here on: they cannot be weakened to make work "pass".
4. **Build in parallel.** Independent parts are built at the same time by
   separate Devs (VBW 1's team), each until its own tests pass. Every commit names the
   part and the requirement it delivers.
5. **Prove.** VBW runs the tests itself. A requirement is done when its tests
   pass on the current code; not before, and not on anyone's say-so.
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

In your project's folder (any git repository, new or existing):

```
/vbw:vibe I want a command-line expense tracker in Node.js
```

The first time, `/vbw:vibe` sets up the project and the VBW status line. Type
`/vbw:vibe` whenever you come back; it continues where things stand. It keeps
going on its own until a step needs you; `/vbw:profile` changes how much it
does by itself (Careful, Standard, Fast).

**Coming from VBW 1?** Update as usual (`/vbw:update`). Your projects are safe:
VBW 1's `.vbw-planning/` folder is never changed. `/vbw:vibe` offers to bring
it into VBW 2 through a few questions, then asks whether to keep the old folder.

## Commands

| Command | What it does |
|---|---|
| `/vbw:vibe [what you want]` | The one command: the next step, every time |
| `/vbw:approve` | Approve the plan and its tests (only you can) |
| `/vbw:status` | Where the project stands |
| `/vbw:discuss`, `/vbw:research` | Think a decision through; a sourced answer to a question |
| `/vbw:todo [idea]`, `/vbw:list-todos` | Park an idea for later; see the list |
| `/vbw:qa`, `/vbw:verify` | Run every proof now; check what only you can judge |
| `/vbw:debug [problem]`, `/vbw:fix [what]` | Find a bug's root cause; a quick fix with every proof re-run |
| `/vbw:init`, `/vbw:convert` | Set up VBW (vibe does it too); bring in a VBW 1 project |
| `/vbw:map`, `/vbw:teach [convention]` | Map an existing codebase; teach your conventions |
| `/vbw:pause`, `/vbw:resume` | Stop safely; pick up where you left off |
| `/vbw:profile`, `/vbw:config` | How VBW works (models, how much it does on its own); each setting |
| `/vbw:skills`, `/vbw:rtk`, `/vbw:compress` | Community skills, output compression, terser instruction files |
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
- [docs/convert.md](docs/convert.md): updating from VBW 1 and bringing in its projects
- [plugin/CHANGELOG.md](plugin/CHANGELOG.md): what changed

## Contributing

Tests: `bash tools/test.sh` (runs under macOS bash 3.2 and bash 5). See
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
