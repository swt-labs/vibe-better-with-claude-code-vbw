---
name: vibe
description: Take this VBW project to its next step (spec, plan, approve, build, prove, fix, accept, ship). Use it for any work on a VBW project.
argument-hint: "[--auto] [what you want]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Workflow(vbw:mapping) Workflow(vbw:planning) Workflow(vbw:building) Workflow(vbw:fixing) Workflow(vbw:verifying)
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
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" workflows on 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config autonomy 2>&1 || true
```

The user said: $ARGUMENTS

If no JSON appears above (shell execution in skills is off), run `vbw next --json`,
`vbw config models` and `vbw config autonomy` with Bash first. "not a VBW
project": set it up yourself with `vbw init` and `vbw statusline on` (say what
was set up in one line), then run `vbw next --json` again.

## Autonomy

The last line above is how much VBW does on its own; the user changes it with
`/vbw:profile`, `/vbw:config`, or by saying so (`vbw config set autonomy ...`).
Approval, checking results (`accept`) and shipping always stop for the user.

- **balanced** and **hands-off**: run `vbw auto on ${CLAUDE_SESSION_ID}` once,
  so VBW keeps going on its own until a step needs the user.
- **hands-off**: at `needs_decisions`, take the recommended option yourself:
  `vbw decide "<option>" "chosen by VBW (hands-off): <its trade-off>"`, and
  list those decisions at the next stop so the user can change any.
- **guided**: before each step that does not need the user, say in plain words
  what you will do and why, and ask (AskUserQuestion): "Go ahead", "Explain
  more", "Stop here". `--auto` from the user runs on its own this time.

## Loop

Do the step for `action`, then run `vbw next --json` and do the next step. Stop
when `gate` is true, or when a workflow is running in the background (its
result wakes you; then continue). At a stop, tell the user in plain words what
happened and what you need from them. Never claim more than the kernel's output
shows.

`plan`, `build` and `fix` need the **Workflow** tool; the `workflows` line above
turned Dynamic workflows on if they were off (say so in one line when it did).
If you still don't have the tool, say why (the line says they were disabled on
purpose; or a restart of Claude Code picks up the setting) and stop. Pass
`models` (the JSON from `vbw config models`) in every workflow's args.

Before `spec` or `plan`: if the project already has code and `.vbw/map.md` does
not exist, map it first: `vbw run start map`, the Workflow `vbw:mapping` (args
`{"models": ...}`), `vbw run end`, then write its `map` to `.vbw/map.md`. Read
it before proposing anything.

What the user must see to decide (a result, a draft, a sample output) goes
inside the AskUserQuestion: the question text or an option's `preview`. Text
written just before a question may be shown collapsed.

## Steps

**convert** (needs the user): the project has a VBW 1 plan. Ask (AskUserQuestion):
"Convert it (Recommended)": follow the `vbw:convert` skill, a short Q&A; or
"Start fresh": `vbw legacy done`, then continue with `spec`.

**spec** (needs the user): agree on what to build. For existing code, start
from the map: say what the project does and propose what to improve, rather
than asking what it is. Otherwise ask what it is for and who uses it. Then
propose requirements, each one user-observable and testable:
`[auto]` when a check can prove it, `[human]` when only a person can judge it
(look, feel, tone). Propose what to build, not how: leave choices such as
sign-in, where data is stored, hosting or paid services to the decision round
before planning, and write a constraint only when the user stated it.
Recommend; don't interrogate. Add each agreed requirement with
`vbw spec add auto|human "statement"` (goals and the user's constraints go in
`.vbw/spec.md` directly, then `vbw spec sync`). If the milestone still has its
default title, name it after what was agreed: `vbw milestone rename "<title>"`.

**plan**: `vbw run start plan` and start the Workflow `vbw:planning` with args
`{"models": ...}`. When it returns: `vbw run end`. If its status is
`needs_decisions`, the user decides first (hands-off: see Autonomy): ask each decision with
AskUserQuestion, one question at a time (why it matters in the question, each
option's trade-off as its description, the recommended one first, marked
"(Recommended)"). Record each answer: `vbw decide "<what was decided>" "<why:
their reason, or the trade-off they accepted>"`. Then plan again: `vbw run
start plan` and the workflow with `{"decided": true, "models": ...}`. When it
has planned: give the user the Lead's summary, the `choices` it made itself (any
of them can be changed), and the Architect's `notes` (nice-to-haves and scope
creep, which can wait in the backlog: offer `vbw todo add`).

**approve** (needs the user): run `vbw show contract --changes`. After an earlier
approval it lists only what changed: explain just that (everything else stays
as approved). Otherwise run `vbw show contract` and explain it plainly: each
requirement, how it will be checked, the plans and their files, the project
commands that will run. Then ask the user to review and type `/vbw:approve`.
You cannot approve.

**build**: `vbw run start build <detail.plans>`, then start the Workflow
`vbw:building` with args `{"plans": <detail.plans>, "docs": <detail.docs>,
"models": ...}` (a Dev per plan; Docs for documentation plans). When it returns:
`vbw run end`, `vbw prove`, and report each plan's result in one line (quote
blockers and notes).

**fix**: `vbw run start fix <detail.fixes>`, then the Workflow `vbw:fixing` with args
`{"groups": <detail.groups>, "models": ...}` (fixes that share files go to one
Dev). When it returns: `vbw run end`, `vbw prove`.

**prove**: `vbw prove`, then report what passed and what failed.

**qa**: `vbw run start qa`, then the Workflow `vbw:verifying` with args
`{"phases": <detail.phases>, "tier": <detail.tier>, "models": ...}`; when it
returns, `vbw run end`. QA records each phase's verdict; findings become fixes.
Report verdicts and failed checks briefly.

**run**: a run is open. A VBW workflow of this session still running: wait.
Otherwise it was interrupted: `vbw run end` (its plans return to the next
wave), then continue.

**unblock** (needs the user): `vbw show plan <id>` for each blocked plan;
explain what the Dev needs. Once resolved: `vbw plan reset <id>`.

**escalate** (needs the user): `vbw show fix <id>`; explain what failed after
the attempts. Ask: try once more (`vbw fix retry <id>`), or change the
requirement or its check (the contract then needs approval again).

**scope** (needs the user): `vbw show evidence`; explain which commits changed
files outside their plan; ask how to proceed. Never rewrite history.

**accept** (needs the user): for each requirement in `detail.requirements`,
show the user the thing to judge: run it yourself when you can (the program's
actual output, the page's text) and put that, or one concrete thing to try, in
the question and the `preview` of "Works". Something visual (a page, a screen):
if you can open it (a browser tool), save a screenshot in `.vbw/runtime/` and
open it for the user (`open` on macOS, `xdg-open` on Linux); otherwise give the
exact way to see it. Ask with AskUserQuestion: "Works", "Something's wrong",
"Skip for now". Works: `vbw req accept <id>`. Something's
wrong: ask what, then `vbw req reject <id> "<their words>"`. Skip: leave it.

**ship** (needs the user): summarize what was delivered (`vbw status`,
`vbw show roadmap`) and ask whether to ship. Yes: `vbw ship`.

**milestone** (needs the user): the milestone is shipped. Ask what the next one is
about, start it with `vbw milestone start "<title>"`, then continue with `spec`.
Shipped work stays guarded: its checks run in every proof.

**Changing the plan** (the user wants to add, change or drop something mid-way):
add with `vbw spec add`, or edit `.vbw/spec.md` and run `vbw spec sync`
(dropping a requirement removes its checks and the unstarted plans that only
served it; work already started is kept unless the user resets it). Then
`vbw next` asks for planning again: the Lead keeps finished work as it is,
and the user approves the changed contract.

## Rules

- Only the kernel writes `.vbw/record.json`; agents and you change state through
  `vbw` commands.
- Never approve, never run `git push`, and never weaken a check.
- Commits of plan work go through `vbw commit` (the Devs do this).
