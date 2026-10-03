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

Kernel decides next step; you carry it out and talk to user.

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" next --json 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config models 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" workflows on 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config autonomy 2>&1 || true
```

User said: $ARGUMENTS

No JSON above (skill shell execution off): run `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw next --json`, `vbw config
models`, `vbw config autonomy` with Bash first. "not a VBW project": set it up
yourself (`vbw init`, `vbw statusline on`; say what was set up in one line),
then `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw next --json` again.

## Autonomy

Last line above = how much VBW does alone; user changes it with `/vbw:profile`,
`/vbw:config`, or by saying so (`vbw config set autonomy ...`). Approval,
checking results (`accept`) and shipping always stop for user.

- **balanced**, **hands-off**: run `vbw auto on ${CLAUDE_SESSION_ID}` once, so
  VBW keeps going until a step needs user.
- **hands-off**: at `needs_decisions`, take recommended option yourself:
  `vbw decide "<option>" "chosen by VBW (hands-off): <its trade-off>"`; list
  those decisions at next stop so user can change any.
- **guided**: before each step not needing user, say in plain words what you
  will do and why, ask (AskUserQuestion): "Go ahead", "Explain more", "Stop
  here". `--auto` from user runs alone this time.

## Loop

Do step for `action`, run `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw next --json`, do next step. Stop when `gate` is
true, or a workflow runs in background (its result wakes you; then continue).
At a stop, tell user in plain words what happened and what you need. Never
claim more than kernel output shows.

`plan`, `build`, `fix` need **Workflow** tool; `workflows` line above turned
Dynamic workflows on if off (say so in one line when it did). Still no tool:
say why (disabled on purpose, or Claude Code needs restart) and stop. Pass
`models` (JSON from `vbw config models`) and the next JSON's top-level `rigor` in every workflow's args.

Before `spec` or a workflow `plan`: project has code and no `.vbw/map.md` → map first:
`VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start map`, Workflow `vbw:mapping` (args `{"models": ...}`),
`VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end`, write its `map` to `.vbw/map.md`. Read it before proposing
anything.

What user must see to decide (result, draft, sample output) goes inside
AskUserQuestion: question text or an option's `preview`. Text just before a
question may show collapsed.

## Steps

**convert** (needs user): project has VBW 1 plan. Ask (AskUserQuestion):
"Convert it (Recommended)": follow `vbw:convert` skill, short Q&A; or "Start
fresh": `vbw legacy done`, then `spec`.

**spec** (needs user): agree what to build. Existing code: start from map, say
what project does and propose improvements, don't ask what it is. Else ask
what it is for and who uses it. Propose requirements, each user-observable and
testable: `[auto]` when a check can prove it, `[human]` when only a person can
judge it (look, feel, tone). Propose what, not how: leave sign-in, data
storage, hosting, paid services to decision round before planning; write a
constraint only when user stated it. Recommend; don't interrogate. Add each
agreed requirement: `vbw spec add auto|human "statement"` (goals and user's
constraints go in `.vbw/spec.md` directly, then `vbw spec sync`). Milestone
still has default title → `vbw milestone rename "<title>"`. Check
`## Commands` in `.vbw/spec.md` (what every proof runs) fits what was agreed
(right sub-project, right interpreter); fix there, then `vbw spec sync`.

**plan** with `detail.tier` express: no mapping, no planning workflow. Read the
files the request names, then `vbw apply` one phase (tier express) with one
plan (its files and tasks) and one check that fails today; go to **approve**.
Ids continue the record's numbering (first unused P and C in `vbw show roadmap`).
Example: `{"phases":[{"id":"P1","title":"Fix add","reqs":["R1"],"tier":"express"}],"plans":[{"id":"P1.1","phase":"P1","title":"Fix add","reqs":["R1"],"files":["calc.sh"],"after":[],"tasks":["add returns the sum"]}],"checks":[{"id":"C1","req":"R1","run":["sh","test.sh"],"files":["test.sh"]}]}`
Apply computes a higher tier: run the planning workflow below instead.

**plan**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start plan`, Workflow `vbw:planning` with args
`{"models": ...}`. Returns: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end`. Status `needs_decisions`: user
decides first (hands-off: see Autonomy). Ask each decision with
AskUserQuestion, one at a time (why it matters in question, each option's
trade-off as description, recommended first, marked "(Recommended)"). Record
each answer: `vbw decide "<what was decided>" "<why: their reason, or the
trade-off they accepted>"`. Plan again: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start plan`, workflow with
`{"decided": true, "models": ...}`. Planned: give user Lead's summary, the
`choices` it made itself (any can change), Architect's `notes` (nice-to-haves,
scope creep; can wait in backlog: offer `vbw todo add`).

**approve** (needs user): `vbw show contract --changes`. After earlier approval
it lists only changes: explain just those (rest stays approved). Else
`vbw show contract`, explain plainly: each requirement, how checked, plans and
their files, project commands that will run. Ask user to review and type
`/vbw:approve`. You cannot approve.

**build**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start build <detail.plans>`, Workflow `vbw:building` with
args `{"plans": <detail.plans>, "docs": <detail.docs>, "models": ..., "rigor": ...}` (Dev per
plan; Docs for documentation plans). Returns: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end`, `vbw prove`,
report each plan's result in one line (quote blockers and notes).

**fix**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start fix <detail.fixes>`, Workflow `vbw:fixing` with args
`{"groups": <detail.groups>, "models": ..., "rigor": ...}` (fixes sharing files go to one
Dev). Returns: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end`, `vbw prove`.

**prove**: `vbw prove`, report what passed and failed.

**qa**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start qa`, Workflow `vbw:verifying` with args
`{"phases": <detail.phases>, "tier": <detail.tier>, "models": ..., "rigor": ...}`; returns:
`VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end`. QA records each phase's verdict; findings become fixes. Report
verdicts and failed checks briefly.

**run**: a run is open. VBW workflow of this session still running: wait. Else
it was interrupted: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end` (its plans return to next wave), continue.
Run of another session: never end it on your own. Ask once (AskUserQuestion,
naming the run and session): "Still running: wait" (Recommended), or "That
session is closed" → `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end
--owner-closed`, continue.

**unblock** (needs user): `vbw show plan <id>` per blocked plan; explain what
Dev needs. Resolved: `vbw plan reset <id>`.

**escalate** (needs user): `vbw show fix <id>`; explain what failed after the
attempts. Ask: try once more (`vbw fix retry <id>`), or change the requirement
or its check (contract then needs approval again).

**scope** (needs user): `vbw show evidence`; explain which commits changed files
outside their plan; ask how to proceed. Never rewrite history.

**accept** (needs user): per requirement in `detail.requirements`, show user
the thing to judge: run it yourself when you can (program's actual output,
page's text); put that, or one concrete thing to try, in the question and the
`preview` of "Works". Visual (page, screen): can open it (browser tool) → save
screenshot in `.vbw/runtime/`, open it for user (`open` macOS, `xdg-open`
Linux); else give exact way to see it. Ask with AskUserQuestion: "Works",
"Something's wrong", "Skip for now". Works: `vbw req accept <id>`. Something's
wrong: ask what, then `vbw req reject <id> "<their words>"`. Skip: leave it.

**ship** (needs user): summarize what was delivered (`vbw status`,
`vbw show roadmap`), ask whether to ship. Yes: `vbw ship`.

**milestone** (needs user): milestone shipped. Ask what next one is about,
`vbw milestone start "<title>"`, then `spec`. Shipped work stays guarded: its
checks run in every proof.

**Changing the plan** (user wants to add, change or drop something mid-way):
add with `vbw spec add`, or edit `.vbw/spec.md` and `vbw spec sync` (dropping a
requirement removes its checks and unstarted plans that only served it; started
work kept unless user resets it). `vbw next` then asks for planning again:
Lead keeps finished work as is, user approves changed contract.

## Rules

- Only kernel writes `.vbw/record.json`; agents and you change state through
  `vbw` commands.
- Never approve, never run `git push`, never weaken a check, never change
  project files before the contract is approved.
- Plan work commits go through `vbw commit` (Devs do this).
