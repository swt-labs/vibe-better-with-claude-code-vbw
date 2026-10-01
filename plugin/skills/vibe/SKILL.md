---
name: vibe
description: Take this VBW project to its next step (spec, plan, approve, build, prove, fix, accept, ship). Use it for any work on a VBW project.
argument-hint: "[--auto] [what you want]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Workflow(vbw:map) Workflow(vbw:plan) Workflow(vbw:build) Workflow(vbw:fix)
hooks:
  Stop:
    - hooks:
        - type: command
          command: "\"${CLAUDE_PLUGIN_ROOT}/bin/vbw\" auto gate 2>/dev/null || true"
---

# VBW

The kernel decides what happens next; you carry it out and talk to the user.

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" next --json 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config models 2>&1 || true
```

The user said: $ARGUMENTS

If no JSON appears above (shell execution in skills is off), run `vbw next --json`
and `vbw config models` with Bash first. "not a VBW project": set it up with
`vbw init`, then continue with `spec`. If the user passed `--auto`, run
`vbw auto on ${CLAUDE_SESSION_ID}` once: from then on VBW keeps going on its own
until a step needs the user.

## Loop

Do the step for `action`, then run `vbw next --json` and do the next step. Stop
when `gate` is true, or when a workflow is running in the background (its
result wakes you; then continue). At a stop, tell the user in plain words what
happened and what you need from them. Never claim more than the kernel's output
shows.

`plan`, `build` and `fix` need the **Workflow** tool. If you don't have it, tell
the user: "VBW needs Dynamic workflows: turn them on in /config (or set
`enableWorkflows: true`)", and stop. Pass `models` (the JSON from
`vbw config models`) in every workflow's args.

## Steps

**spec** (needs the user): agree on what to build. Ask what it is for and who
uses it, then propose requirements, each one user-observable and testable:
`[auto]` when a check can prove it, `[human]` when only a person can judge it
(look, feel, tone). Recommend; don't interrogate. Add each agreed requirement
with `vbw spec add auto|human "statement"` (goals and constraints go in
`.vbw/spec.md` directly, then `vbw spec sync`).

**plan**: if the project already has code and `.vbw/map.md` does not exist, map
it first: start the Workflow `vbw:map` (args `{"models": ...}`) and write its
`map` to `.vbw/map.md`. Then `vbw run start plan` and start the Workflow
`vbw:plan` with args `{"models": ...}`. When it returns: `vbw run end`, then give the user its summary
and any critic issues.

**approve** (needs the user): run `vbw show contract` and explain it plainly:
each requirement, how it will be checked, the plans and their files, the project
commands that will run. Then ask the user to review and type `/vbw:approve`.
You cannot approve.

**build**: `vbw run start build <detail.plans>`, then start the Workflow
`vbw:build` with args `{"plans": [...], "models": ...}`. When it returns:
`vbw run end`, `vbw prove`, and report each plan's result in one line (quote
blockers and notes).

**fix**: `vbw run start fix <detail.fixes>`, then the Workflow `vbw:fix` with args
`{"fixes": [...], "models": ...}`. When it returns: `vbw run end`, `vbw prove`.

**prove**: `vbw prove`, then report what passed and what failed.

**run**: a run lease is open. If a VBW workflow from this session is still
running, wait for it and do nothing now. Otherwise it was interrupted:
`vbw run end` (its plans return to the next wave), then continue.

**unblock** (needs the user): `vbw show plan <id>` for each blocked plan;
explain what the builder needs. Once the user has resolved it, `vbw plan reset <id>`.

**escalate** (needs the user): `vbw show fix <id>`; explain what failed after
the attempts. Ask: try once more (`vbw fix retry <id>`), or change the
requirement or its check (edit the spec; the contract will need approval
again).

**scope** (needs the user): `vbw show evidence`; explain which commits changed
files outside their plan, and ask how to proceed. Do not rewrite history.

**accept** (needs the user): for each requirement in `detail.requirements`,
describe one concrete thing to try, then ask with AskUserQuestion: "Works",
"Something's wrong", "Skip for now". Works: `vbw req accept <id>`. Something's
wrong: ask what, then `vbw req reject <id> "<their words>"`. Skip: leave it.

**ship** (needs the user): summarize what was delivered (`vbw status`,
`vbw show roadmap`) and ask whether to ship. Yes: `vbw ship`.

**milestone** (needs the user): the milestone is shipped. Ask what the next one is
about, start it with `vbw milestone start "<title>"`, then continue with `spec`
for its requirements. Shipped requirements stay in the spec and their checks
keep running in every proof, so new work cannot silently break shipped work.

**Changing the plan** (the user wants to add, change or drop something mid-way):
add with `vbw spec add`, or edit `.vbw/spec.md` and run `vbw spec sync`
(dropping a requirement removes its checks and the unstarted plans that only
served it; work already started is kept unless the user resets it). Then
`vbw next` asks for planning again: the planner keeps finished work as it is,
and the user approves the changed contract.

## Rules

- Only the kernel writes `.vbw/record.json`; agents and you change state through
  `vbw` commands.
- Never approve, never run `git push`, and never weaken a check.
- Commits of plan work go through `vbw commit` (builders do this).
