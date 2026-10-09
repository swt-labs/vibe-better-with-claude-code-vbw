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

Kernel decides next step; you carry it out. Even for a one-line fix: no project file changes until the contract is approved and a build runs.

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" next --json 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config models 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" workflows on 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" config autonomy 2>&1 || true
```

User said: $ARGUMENTS

Every new request, now or later, goes to `vbw:triage` first; "what's next" or "suggest next" follows `vbw:whats-next`.

No JSON above (skill shell execution off): run `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw next --json`, `vbw config
models`, `vbw config autonomy` with Bash first. "not a VBW project": set it up
yourself (`vbw init`, `vbw statusline on`; say what was set up in one line),
then `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw next --json` again.

## Autonomy

Last line above = how much VBW does alone (`/vbw:profile` changes it). Approval, `accept` and shipping always stop for user.

- **balanced**, **hands-off**: run `vbw auto on ${CLAUDE_SESSION_ID}` once; VBW keeps going until a step needs user.
- **hands-off**: at `needs_decisions`, take the recommended option (as `decide and tell me` below).
- **guided**: before each step not needing user, say what and why, ask
  (AskUserQuestion): "Go ahead", "Explain more", "Stop here". `--auto` runs alone this time.

## Loop

Do step for `action`, run `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw next --json`, do next step. Stop when `gate` is
true, or a workflow runs in background (its result wakes you; continue).
At a stop, say what happened.
Every stop ends with a last line, **What I need from you:** <the one thing user must do now>, or "nothing".
Claim only what kernel shows.

`plan`, `build`, `fix` need the **Workflow** tool (the `workflows` line above turned it on). None: say why, stop. Pass
`session` (`${CLAUDE_SESSION_ID}`: the workflow confirms what its agents recorded and ends its own run), `models` (from `vbw config models`), the next JSON's top-level `rigor`, `effort` and its `profile` in every workflow's args.

Before `spec` or a workflow `plan`: code and no `.vbw/map.md` → map first:
`VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start map`, Workflow `vbw:mapping` (args as above),
write its `map` to `.vbw/map.md`, read it.

Then, `profile.ask` true: follow `vbw:interview` before any spec or convert work; resume at
`profile.pending`; unrecognised answer: ask again, record nothing.

What user must see to decide goes inside AskUserQuestion.

## Profile

Next JSON's `profile` = user's level, explanation depth, involvement. Speak at that level and depth. At
`needs_decisions`, by `profile.involvement`:

- **decide and tell me**: decide with the recommended option,
  `vbw decide "<option>" "chosen by VBW: <its trade-off>"`, report each at next stop.
- **options with a recommendation**: ask each as described under plan.
- **I make the calls**: put every decision to user before proceeding; nothing decided for them.

## Steps

**convert** (needs user): VBW 1 plan, no choice recorded yet. Follow the old-folder step of `vbw:interview` (review,
recommendation, question); convert runs `vbw:convert`, fresh records `vbw legacy choose fresh`, then `spec`.

**spec** (needs user): agree what to build. Existing code: start from map, say
what it does, propose improvements. Else ask what it is for and who uses it. Propose user-observable,
testable requirements: `[auto]` when a check can prove it, `[human]` when only a person can
judge it (look, feel, tone); a document that must contain something is `[auto]`, how it reads is `[human]`. Propose what, not how: leave sign-in, storage, hosting, paid services
to the decision round; write a constraint only if user stated it. Recommend; don't interrogate. Follow `vbw:suggest`. Add each
agreed requirement: `vbw spec add auto|human "statement"` (goals and constraints go in `.vbw/spec.md`, then `vbw spec sync`). Default milestone title → `vbw milestone rename "<title>"`. Check
`## Commands` in `.vbw/spec.md` (what every proof runs) fits what was agreed (right sub-project, right interpreter); fix there, then `vbw spec sync`.

**plan** with `detail.tier` express or `detail.small`: no mapping, no planning workflow. Read the
files the request names, then `vbw apply --add` (with or without earlier phases) one phase at `detail.tier` with one
plan (one or two files, tasks), one check that fails today, and the `rules` (each condition, edge and error case the requirement states, each with its check); go to **approve**.
New ids start at P<next_phase>; `"tier"` is `detail.tier` (here express).
Example: `vbw apply --add` with `{"phases":[{"id":"P1","title":"Fix add","reqs":["R1"],"tier":"express"}],"plans":[{"id":"P1.1","phase":"P1","title":"Fix add","reqs":["R1"],"files":["calc.sh"],"after":[],"tasks":["add returns the sum"]}],"checks":[{"id":"C1","req":"R1","run":["sh","test.sh"],"files":["test.sh"]}],"rules":[{"req":"R1","text":"add returns the sum","check":"C1"}]}`
Over two files, a risk path or a tier: apply refuses; use the planning workflow.

**plan**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start plan`, Workflow `vbw:planning` with args
`{"requirements": <requirements>, "next_phase": <next_phase>, "models": ...}`. Status `needs_decisions`: user
decides first. Ask each with AskUserQuestion, one at a time (why it matters in the question, each option's
trade-off as description, recommended first, "(Recommended)"). Record
each: `vbw decide "<what was decided>" "<their reason, or the trade-off they accepted>"`. Plan again: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start plan`, workflow with
`{"requirements": <requirements>, "next_phase": <next_phase>, "decided": true, "models": ...}`. Planned: give Lead's summary, the
`choices` it made itself (any can change), Architect's `notes` (offer `vbw todo add`). Then the approval menu, never a typed command.

**approve** (needs user): `vbw show contract --changes` (after an earlier approval: explain just those). Else
`vbw show contract`: explain each requirement, how checked, plans, files, commands that will run. Follow `vbw:suggest`, then AskUserQuestion with the approval question `vbw show contract` prints: "Approve" (first), "Not yet". Only this menu; never ask the user to type /vbw:approve (typing it still works). Approve: hook recorded it; continue. Not yet: ask what to change. User's own words (own-answer slot): what to change, or a question. You cannot approve.
Test files edited during the build wait for one approval just before proof (`detail.files`): say which and why, then ask the same way.

**build**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start build <detail.plans>`, Workflow `vbw:building` with
args `{"plans": <detail.plans>, "docs": <detail.docs>, "models": ..., "rigor": ...}` Returns: report each plan's result in one line (quote blockers, notes) and anything not recorded, then `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw prove`.

**fix**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start fix <detail.fixes>`, Workflow `vbw:fixing` with args
`{"groups": <detail.groups>, "models": ..., "rigor": ...}` Returns: report anything it says was not recorded, then `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw prove`.

**prove**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw prove --full` when `detail.full` is true, else `vbw prove`; report what passed and failed.

**qa**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start qa`, Workflow `vbw:verifying` with args
`{"phases": <detail.phases>, "tier": <detail.tier>, "round": <round, as in vbw next --json>, "models": ..., "rigor": ...}`. QA records each phase's verdict; findings become fixes. Report verdicts, failed checks, anything not recorded.

**run**: a run is open. This session's workflow still running: wait. Else
interrupted: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end`, continue.
Another session's run: never end it. Ask once (AskUserQuestion): "Still running: wait" (Recommended), or "That session is closed" →
`VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end --owner-closed`, continue.

**unblock** (needs user): `vbw show plan <id>` per blocked plan; say what Dev needs. Resolved: `vbw plan reset <id>`.

**escalate** (needs user): `vbw show fix <id>`; explain what failed. Ask: try
once more (`vbw fix retry <id>`), or change the requirement or its check
(contract then needs approval again).

**scope** (needs user): `vbw show evidence`; say which commits changed files outside their plan; ask how to proceed; never rewrite history.

**accept** (needs user): per requirement in `detail.requirements`, show the
thing to judge: run it yourself when you can; put its output, or one concrete thing to try, in the question and the
`preview` of "Works". Visual: screenshot into `.vbw/runtime/` and open it. Ask with AskUserQuestion: "Works",
"Something's wrong", "Skip for now". Works: `vbw req accept <id>`. Something's
wrong: ask what, then `vbw req reject <id> "<their words>"`. Skip: leave it.

**ship** (needs user): summarize what was delivered (`vbw status`, `vbw show roadmap`); ask whether to ship. Yes: `vbw ship`; then follow `vbw:whats-next` (the ship never waits for it).

**milestone** (needs user): ask what next milestone is about,
`vbw milestone start "<title>"`, then `spec`.

**Changing the plan** (add, change or drop mid-way): `vbw spec add`, or edit `.vbw/spec.md` and `vbw spec sync` (a dropped
requirement removes its checks and unstarted plans). `vbw next` then asks for planning again (Lead keeps finished work); the approval menu follows.

## Rules

- Only kernel writes `.vbw/record.json`; agents and you change state through
  `vbw` commands.
- Never approve, never run `git push`, never weaken a check.
