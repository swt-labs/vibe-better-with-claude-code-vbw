# VBW: Vibe Better With Claude Code

**You say what you want. VBW proves it is done.**

VBW is a Claude Code plugin that turns an idea into working, tested, committed
code, and shows you the proof:

1. **Agree on what to build.** VBW helps you write it down as requirements. Each
   is either something a test can prove, or something only you can judge (how
   it looks, how it feels).
2. **Plan it, with tests first.** VBW plans the work in small parts and writes
   a test for every requirement. The tests fail today; that is the point.
3. **You approve.** `/vbw:approve`. Nothing VBW runs is unapproved, and the
   tests are frozen from here on: they cannot be weakened to make work "pass".
4. **Build in parallel.** Independent parts are built at the same time by
   separate builders, each until its own tests pass. Every commit names the
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

Then turn on **Dynamic workflows** in `/config` (they are off by default on
the Pro plan), and restart Claude Code.

You need Claude Code 2.1.286 or later, `jq` and `git`. Use a Sonnet, Opus or
Fable model, in auto mode (Shift+Tab) for hands-off building. `/vbw:doctor`
checks all of this for you.

## Start

In your project's folder (any git repository, new or existing):

```
/vbw:init
/vbw:vibe I want a command-line expense tracker in Node.js
```

`/vbw:init` sets up the project and the VBW status line. `/vbw:vibe` takes it
from there. Type `/vbw:vibe` whenever you come back; it continues where things
stand. Add `--auto` to let it keep going on its own until a step needs you.

## Commands

| Command | What it does |
|---|---|
| `/vbw:vibe [what you want]` | The one command: the next step, every time |
| `/vbw:init` | Set up VBW in a project, with the status line |
| `/vbw:approve` | Approve the plan and its tests (only you can) |
| `/vbw:status` | Where the project stands |
| `/vbw:map` | Map an existing codebase before planning |
| `/vbw:debug [problem]` | Find a bug's root cause from three angles at once |
| `/vbw:todo [idea]` | Keep an idea for later |
| `/vbw:teach [convention]` | Teach VBW and Claude your project's conventions |
| `/vbw:config` | Models (quality, balanced, budget) and settings |
| `/vbw:skills`, `/vbw:rtk`, `/vbw:compress` | Community skills, output compression, terser instruction files |
| `/vbw:doctor`, `/vbw:report` | Check the setup; prepare a bug report |
| `/vbw:update`, `/vbw:whats-new`, `/vbw:uninstall` | Keep VBW current, or remove it |

## How it stays safe

- **Guards** run before every command Claude runs and block what would destroy
  work (force-push, `git reset --hard`, deleting the project), touch secret files,
  or let a builder write outside its part of the plan.
- **Approval is yours.** Tests and project commands run only after you approve
  them, and the approval lives in your clone's `.git` folder: a repository you
  download cannot approve itself.
- **Everything is in git.** The plan, the tests and every change are committed
  with the requirement they serve, so `git log` tells the story.

## Documentation

- [docs/record.md](docs/record.md): the plan of record (`.vbw/record.json`)
- [docs/proof.md](docs/proof.md): requirements, tests, approval and proof
- [docs/next.md](docs/next.md): how VBW decides the next step
- [docs/workflows.md](docs/workflows.md): the planner, critic, builder and workflows
- [docs/guards.md](docs/guards.md): the safety guards
- [docs/statusline.md](docs/statusline.md): the status line
- [plugin/CHANGELOG.md](plugin/CHANGELOG.md): what changed

## Contributing

Tests: `bash tools/test.sh` (runs under macOS bash 3.2 and bash 5). See
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
