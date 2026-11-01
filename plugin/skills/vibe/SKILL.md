---
name: vibe
description: Take this VBW project to its next step (spec, plan, approve, build, prove, fix, accept, ship). Use it for any work on a VBW project.
argument-hint: "[--auto] [what you want]"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Workflow(vbw:mapping) Workflow(vbw:planning) Workflow(vbw:building) Workflow(vbw:fixing) Workflow(vbw:verifying)
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

Every new request, now or later, goes to `vbw:triage` first, before you read code or run anything for it; a fix too, even one that looks already fixed: triage checks that, says it and records it. "What's next" or "suggest next" follows `vbw:whats-next`.

No JSON above (skill shell execution off): run `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw next --json`, `vbw config
models`, `vbw config autonomy` with Bash first. "not a VBW project": set it up
yourself (`vbw init`, `vbw statusline on`; say what was set up in one line),
then `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw next --json` again.

## Setting stated in words

Before any step, read the user's words (now, or later in the session). Words naming guided, balanced or hands-off, or a plain phrase clearly meaning one ("ask me before each step" = guided, "do not ask, just go" = hands-off), run `vbw config set autonomy <value>` first. Say in one line what was set, then follow the Autonomy section with that value, not the line loaded above.

- A project not set up yet: record it right after `vbw init`, never before (outside a VBW project `vbw config` refuses, and the session would run on the default).
- Same as the current setting: it writes nothing and says nothing about it.
- Words that do not clearly name one setting change nothing: never guess.
- Stated later in the session: record it at once; it applies from the next step. A switch to guided while the autonomous run is armed runs `vbw auto off ${CLAUDE_SESSION_ID}`; a switch to balanced or hands-off runs `vbw auto on ${CLAUDE_SESSION_ID}` once.
- `--auto` runs alone this time only and never changes the setting.

## Autonomy

Last line above, or the value just set, = how much VBW does alone. Approval, `accept` and shipping always stop for user.

- **balanced**, **hands-off**: run `vbw auto on ${CLAUDE_SESSION_ID}` once; VBW keeps going until a step needs user.
- **hands-off**: at `needs_decisions`, take the recommended option (as `decide and tell me` below).
- **guided**: before each step not needing user, say what and why, ask
  (AskUserQuestion): "Go ahead", "Explain more", "Stop here". `--auto` runs alone this time.

## Loop

Do step for `action`, run `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw next --json`, do next step. Stop when `gate` is
true, or a workflow runs in background (its result wakes you). A workflow result is the object it returns; when Claude Code saves it to a file, the object sits under `result` (read a field with jq, never by hand).
At a stop, say what happened.
Every stop ends with a last line, **What I need from you:** <the one thing user must do now>, or "nothing".
Claim only what kernel shows.
A workflow result's `refused` (each `{by, text}`), and any `vbw` refusal you get yourself: show each `text` as written, whole, in a quote block naming `by`, before your summary; never paraphrase it.

Before starting a plan, build, fix, qa or prove step (a background proof too), say `step.say` and then `road.say` from `vbw next --json` as given, unchanged, on the same line or the next.

When `rename_hint` in `vbw next --json` is a sentence, say it once, as given. Never run /rename yourself: the user renames the chat.

`plan`, `build`, `fix` need the **Workflow** tool (the `workflows` line above turned it on). None: say why, stop. Pass
`session` (`${CLAUDE_SESSION_ID}`, so the workflow confirms and ends its own run), `models` (from `vbw config models`), the next JSON's top-level `rigor`, `effort`, `profile` and `root` (the project folder: agents of a session started in a subfolder work there) in every workflow's args.

Before `spec` or a workflow `plan`: code and no `.vbw/map.md` → map first:
`VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start map`, Workflow `vbw:mapping` (args as above; it does not end its run),
then end the run with its `map` on stdin, which saves `.vbw/map.md` in the run's commit (from a saved file: `jq -er '.result.map' FILE | VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end --map`; else a quoted heredoc, `<<'VBW_MAP'`), then read `.vbw/map.md`.

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
judge it (look, feel, tone); a document that must contain something is `[auto]`, how it reads is `[human]`. Propose what, not how (sign-in, storage, hosting, paid services go
to the decision round); write a constraint only if user stated it. Recommend; don't interrogate. Follow `vbw:suggest`. Add each
agreed requirement: `vbw spec add auto|human "statement"` (goals and constraints go in `.vbw/spec.md`, then `vbw spec sync`). Default milestone title → `vbw milestone rename "<title>"`. Check
`## Commands` in `.vbw/spec.md` (what every proof runs) fits what was agreed (right sub-project, right interpreter); fix there, then `vbw spec sync`.
Choose `## Commands` from the map's Tests section: prefer a command the map ran and dated. A whole suite the map marks `Not run` is never written silently. Before planning, ask once per such suite (AskUserQuestion), naming it unverified with the expected time the map gives (else say the time is unknown), with exactly these options in this order: "Run it now (Recommended)", "Leave it out and use only the commands the map verified", "Add it unverified". Under hands-off take run it now yourself and say so in one line.
Run it now is its own step before any planning run: run the suite once (a long one in the background; read its whole result when it ends), tell the user green or red with the failing tests' names, and record it: `vbw decide "Commands: <command> ran <date> at <short commit>: green|red (<n> failing)"`. Never edit `.vbw/map.md`.
A suite red today (the map's dated result or the run just made) is named before planning, with the narrower command (the one test file form from the map's Tests section, or the sub-project's green command) as the recommended option. A red suite enters `## Commands` only on the user's choice; then say the first proof will be red. After the choice write the chosen lines under `## Commands` in `.vbw/spec.md` and run `vbw spec sync`.

**plan** with `detail.tier` express or `detail.small`: no mapping, no planning workflow. Read the
files the request names, then `vbw apply --add` one phase at `detail.tier` with one
plan (one or two files, tasks), one check that fails today, and the `rules` (each condition, edge and error case the requirement states, each with its check); go to **approve**.
New ids start at P<next_phase>; `"tier"` is `detail.tier`. A plan only writing documentation (README, CHANGELOG, `docs/`, guides) gets `"role":"docs"` (the Docs agent builds it); else no `role`.
Example: `vbw apply --add` with `{"phases":[{"id":"P1","title":"Fix add","reqs":["R1"],"tier":"express"}],"plans":[{"id":"P1.1","phase":"P1","title":"Fix add","reqs":["R1"],"files":["calc.sh"],"after":[],"tasks":["add returns the sum"]}],"checks":[{"id":"C1","req":"R1","run":["sh","test.sh"],"files":["test.sh"]}],"rules":[{"req":"R1","text":"add returns the sum","check":"C1"}]}`
Over two files, a risk path or a tier: apply refuses; use the planning workflow.

**plan**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start plan`, Workflow `vbw:planning` with args
`{"requirements": <requirements>, "next_phase": <next_phase>, "models": ...}`. Status `needs_decisions`: user
decides first. Ask each with AskUserQuestion, one at a time (why it matters in the question, each option's
trade-off as description, recommended first, "(Recommended)"). Record
each: `vbw decide "<what was decided>" "<their reason, or the trade-off they accepted>"`. A requirement already met, dropped or reworded: delete or edit its line in `.vbw/spec.md`, `vbw spec sync`, then take `requirements` from a new `vbw next --json`. Plan again: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start plan`, workflow with
`{"requirements": <requirements>, "next_phase": <next_phase>, "decided": true, "research": <research>, "models": ...}`, `<research>` the
`research` of the `needs_decisions` reply, so planning starts from what it already found. Planned: give Lead's summary, its
`choices` (any can change) and Architect's `notes` (offer `vbw todo add`); then the approval menu, never a typed command.
Status `blocked`: give its summary and blockers. A requirement already met: AskUserQuestion, drop it (delete its line in `.vbw/spec.md`, then `vbw spec sync`) or reword it to what is still missing (edit it there, then `vbw spec sync`); record `vbw decide`; plan again with `requirements` from a new `vbw next --json`.

**contract**: not ready for approval: do what `instruction` says (write the named check files, `vbw spec sync`), then `vbw next --json`.

**approve** (needs user): `detail.changed` (this plan was approved before): `vbw show contract --changes`, say the plan changed and explain just those. Else
`vbw show contract`: explain each requirement, how checked, plans, files, the build's shape (`build waves`: rounds, most plans at once, and each `waits for` line in plain words), commands that will run. Follow `vbw:suggest`, passing `detail.replan` as the cost of a yes, then AskUserQuestion with the approval question `vbw show contract` prints: "Approve" (first), "Not yet". Only this menu; never ask the user to type /vbw:approve (typing it still works). Approve: hook recorded it; continue. Not yet: ask what to change. User's own words (own-answer slot): what to change, or a question. You cannot approve.
A rule to reword, or one a newer requirement replaced (of any milestone): `vbw apply --patch` with `{"rules":[{"rule":"R1.2","text":"<new words>"}]}` or `{"rules":[{"rule":"R1.2","retire":"<why>"}]}` (`vbw show req R1` numbers its rules; a retired rule keeps its place), then the approval menu again.
Test files edited during the build wait for one approval just before proof (`detail.files`): run `vbw show contract --changes` and show each file's whole diff to the user, say which and why, then ask the same way.

**build**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start build <detail.plans>`, Workflow `vbw:building` with
args `{"plans": <detail.plans>, "docs": <detail.docs>, "models": ..., "rigor": ...}` Returns: one line per plan (quote blockers, notes), anything not recorded, then `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw prove`.

**fix**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start fix <detail.fixes>`, Workflow `vbw:fixing` with args
`{"groups": <detail.groups>, "models": ..., "rigor": ...}` Returns: anything not recorded, then `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw prove`.

**prove**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw prove --full` when `detail.full` is true, else `vbw prove`; report what passed and failed, then follow the proof's Next line (never a commit of your own).

**qa**: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run start qa`, Workflow `vbw:verifying` with args
`{"phases": <detail.phases>, "tier": <detail.tier>, "round": <the whole `round` object of vbw next --json (tiers, suite, focus), never a number>, "models": ..., "rigor": ...}`. `vbw next --json` carries `round` before and after `vbw run start qa`. Report verdicts, failed checks, anything not recorded.
A delivered file that changed or went missing outside VBW (the proof's deviations) is never repaired by you: the **deviations** step puts it to the user before QA.

**run**: a run is open. This session's workflow still running: wait. Else
interrupted: `VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end`, continue.
Another session's run: never end it. Ask once (AskUserQuestion): "Still running: wait" (Recommended), or "That session is closed" →
`VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw run end --owner-closed`, continue.

**unblock** (needs user): `vbw show plan <id>` per blocked plan; say what Dev needs. Resolved: `vbw plan reset <id>`.

**escalate** (needs user): `vbw show fix <id>`; explain the failure. Ask: try
once more (`vbw fix retry <id>`), or change the requirement or its check
(contract then needs approval again).

**scope** (needs user): `vbw show evidence`; say which commits changed files outside their plan and what each change does (`git show --stat <commit>`); ask (AskUserQuestion) whether to accept each. Accept: `vbw decide "Accept <commit>: <file> <why>" "<their reason>"`, naming the commit's 12 characters and the file, then `vbw prove`. Not accepted: the change goes back through its plan or a fix; never rewrite history.

**deviations** (needs user): files VBW's plans delivered were changed outside any plan (`detail.deviations`: file, plan, change, the commits `by`). Say per file what changed and by which commit (`git show --stat <commit>`), then ask once (AskUserQuestion): "Keep the changes" (they are the user's own work, recommended when the commits are theirs), "Restore them" (back to what the plan made), or per file in their own words. Keep: `vbw decide "Keep the changes to <each file> made outside any plan" "<their reason>"`, naming every kept file. Restore: `vbw fix restore <file>...`; the fix round brings each back. Never repair a file yourself.

**accept** (needs user): per requirement in `detail.requirements`, show the
thing to judge: run it yourself when you can; put its output, or one thing to try, in the question and the
`preview` of "Works". Visual: screenshot into `.vbw/runtime/` and open it. Ask with AskUserQuestion: "Works",
"Something's wrong", "Skip for now". Works: `vbw req accept <id>`. Something's
wrong: ask what, then `vbw req reject <id> "<their words>"`. Skip for now: `vbw req skip <id>`.

**ship** (needs user): summarize what was delivered (`vbw status`, `vbw show roadmap`); with `detail.later`, name them and ask once: ship now and judge them in the next milestone, or judge them now. Otherwise ask whether to ship. Yes: `vbw ship`; then follow `vbw:whats-next` (the ship never waits for it).

**milestone** (needs user): ask what next milestone is about,
`vbw milestone start "<title>"`, then `spec`.

**Changing the plan** (add, change or drop mid-way): `vbw spec add`, or edit `.vbw/spec.md` and `vbw spec sync`. `vbw next` then asks for planning again; the approval menu follows.

## Rules

- Only kernel writes `.vbw/record.json`; agents and you change state through
  `vbw` commands.
- Never approve, never run `git push`, never weaken a check.
- The chat never commits plan work by hand (no git commit, commit-tree, merge, rebase, cherry-pick, revert or am on plan files): commits go through `vbw commit` inside the run (the workflows' agents run it). After a proof the chat follows the proof's Next line, never a commit of its own.
