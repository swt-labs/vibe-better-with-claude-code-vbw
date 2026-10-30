# `vbw next`: the one answer to "what happens now"

`vbw next` is a pure function of `.vbw/record.json` and whether the current
contract hash has the user's consent (docs/proof.md). The `/vbw:vibe` router,
the autonomy Stop gate and the statusline all ask it; nothing else decides the
lifecycle. `vbw next --json` returns:

```json
{ "action": "build", "gate": false, "instruction": "Run the build workflow for P1.2, P1.3",
  "detail": { "plans": ["P1.2", "P1.3"] } }
```

`gate: true` means a person must act; autonomous runs stop there.

Every answer also carries `requirements`: the requirements of the current
(active) milestone, each with `id`, `text` and `proof`. Requirements of shipped
milestones are left out, and one carried over to the active milestone is
included. A requirement with no milestone is an error that names it
(`requirements with no milestone: R48`), so none is dropped silently. The
router passes the list to the planning workflow as `args.requirements`
(docs/workflows.md).

```json
"requirements": [ { "id": "R47", "text": "QA checks only changed phases", "proof": "auto" } ]
```

Every answer also carries `rigor`, keyed by the current milestone's phase ids:
each phase's tier and its row of the profile's tier table (docs/rigor.md). A
phase with no tier counts as `standard`. The router passes it to every
workflow as `args.rigor`.

```json
"rigor": { "P1": { "tier": "express", "agents": { "dev": 1 }, "qa": "quick",
                   "models": { "dev": "sonnet", "qa": "sonnet" } } }
```

`models` is the table's cell with your `vbw config set model.dev` and
`model.qa` overrides applied.

Every answer also carries `profile`: your interview answers (docs/interview.md)
with the neutral middle choice for any question not yet answered, so a reader
never meets a missing value.

```json
"profile": { "level": "professionally", "depth": "plain with technical terms explained",
             "involvement": "I make the calls", "kept": "private",
             "interviewed": true, "pending": null, "ask": false }
```

`interviewed` is true once the set is complete and kept. `pending` names the
first unanswered question (`level`, `depth`, `involvement`, or `keep`), or is
`null`. `ask` is true only when the action is `spec` and the project is not
interviewed: the router then follows the interview skill before any spec work.
A workflow reads `args.profile` for its wording and falls back to the middle
choices without it.

Every answer also carries `declined`: the texts of the suggestions you
declined in this project (docs/interview.md), oldest first, or `[]`. The
`suggest` skill never offers one of them again.

```json
"declined": ["Should visitors be able to search the page?"]
```

Every answer also carries `next_phase`: the number the next new phase takes,
one after the highest phase number the record knows. It counts shipped phases,
started phases, plan ids and phases that a decision names (so a removed phase
whose number a decision records is not reused). A sub-phase counts as its whole
number: `P65.1` counts as 65. The planning workflow passes it to the Architect,
which numbers new phases from it (docs/workflows.md).

```json
"next_phase": 73
```

Every answer also carries `effort`: the current profile's effort table, the
level each role and step runs at (`vbw config effort` prints the same table;
docs/workflows.md). The router passes it to every workflow as `args.effort`.

```json
"effort": { "architect": { "decide": "xhigh", "scope": "high" },
            "lead": { "plan": "high", "close": "low" }, "dev": { "build": "medium", "fix": "medium" } }
```

(Shortened here; the real table has every role and step.) A table with a wrong
value stops `vbw next` with an error that names the role and step.

An answer that stops for you (`gate` true) also carries `since`: the time VBW
first reached that stop. It stays the same while the same stop stands (the same
`action` and `detail`), whichever session asks and however often Claude Code
restarts, so the status line and the panel date the wait from the stop itself.
A new stop starts its own time; a step that needs nobody carries no `since`.

```json
"since": "2026-10-21T15:41:07Z"
```

At the `approve` stop, `detail.changed` is `true` when you approved this
milestone's plan before and it changed since (the last approval in this clone
already held this milestone's requirements). VBW then says the plan changed and
shows only the changes (`vbw show contract --changes`), instead of presenting it
as a new plan. The first approval of a milestone carries no `changed`.

At the `approve` stop, `detail.replan` is the sentence for a planning run of the
milestone's open requirements plus one, worded as `step.say` is for a plan step
(for example `Planning the work: about 20 min, until around 14:35`, or `no end
time yet` with fewer than 3 timed planning steps). It is the cost of a yes to a
suggestion that adds a requirement now: a new planning run. No other step
carries the key.

At the `plan` step, `detail.tier` is the early tier (docs/rigor.md): `express`
for one small, risk-free `auto` requirement in a repository of at most 30
tracked files, else `standard` (`deep` when forced). On `express` the router
plans without workflows: one `vbw apply` with one phase, plan and check.
`detail.small` is judged on the milestone's requirements with no phase yet
(earlier, planned work does not count): `true` for one or two `auto`
requirements that together name at most two files and no risk category or
risk path, in a repository of any size. The router plans those the same way,
adding the one phase with `vbw apply --add` (docs/rigor.md).

## Decision order (first match wins)

| # | Condition | action | gate |
|---|---|---|---|
| 0 | a run lease is open | `run` (wait for its workflow if it is running in this session; otherwise `vbw run end`; a run owned by another session: wait or check `vbw status`, never end it) | no |
| 1 | milestone `shipped` or `parked` (a parked one is left behind like a shipped one, docs/loop.md) | `milestone` (start the next one: `vbw milestone start TITLE`) | yes |
| 2a | no requirements in the current milestone, and a VBW 1 plan (`.vbw-planning/`) not converted yet | `convert` (`/vbw:convert`, or start fresh; docs/convert.md) | yes |
| 2 | no requirements in the current milestone | `spec` (write its requirements in `.vbw/spec.md`) | yes |
| 3 | the current milestone has no phases, an `auto` requirement has no check (a documentation-only requirement needs none: docs/rigor.md), or a current `auto` requirement is in no plan | `plan` (`detail.tier`: the early tier; plan workflow: phases, plans, contract checks, or direct `vbw apply` when express) | no |
| 3a | the contract is not approved and approval would refuse it (a check file is missing, the spec and the record differ) | `contract` (`detail.problems` names each problem; write the missing check files, `vbw spec sync`, then `vbw next` again; there is no approval question until the contract can be approved) | no |
| 4 | contract not approved (never approved, or its structure changed since: requirements, checks, plans) | `approve` (review and approve the contract; `detail.changed` when this milestone's plan was approved before) | yes |
| 4a | the contract is approved except for edits to the bytes of test files (a check's `files`), and a phase is built but not proved | `approve` with `detail.files`: the one approval of those test files, before they are proved (docs/proof.md) | yes |
| 5 | plans ready to build: not `done`, not `blocked`, every `after` plan `done` | `build` (one wave: the ready plans in order, skipping any that shares a file with one already in the wave). When a plan is `blocked`, the instruction names it with its reason and `detail.blocked` lists `{id, note}`; plans that depend on it wait, unrelated plans still run | no |
| 6 | no plan is ready and a plan is `blocked` | `unblock` (a Dev reported a blocker; `detail.plans` and `detail.blocked` name every blocked plan and its reason) | yes |
| 7 | a fix is `escalated` | `escalate` (the fix cap was reached) | yes |
| 8 | current evidence has scope violations | `scope` (commits changed files outside their plans; the user accepts one with a decision naming its commit and file, docs/proof.md) | yes |
| 9 | a fix is `open`, unless the evidence is stale and an open fix's failures come from the proof (an `[auto]` requirement's or a project command's; QA's, a restore's and a rejection's do not): then row 10 proves first, so a fix round never works from the failures of older code | `fix` (`detail.fixes`, and `detail.groups`: fixes whose files overlap, one Dev each; a project command's fix may touch any file) | no |
| 10 | an `auto` requirement is not `proven`, or the evidence is stale (another contract, or the project files changed since; docs/proof.md), or a fix whose failures come from the proof is open on stale evidence (row 9) | `prove` | no |
| 10c | a file a plan of the current milestone delivered changed outside any plan, with no decision of the user covering it and no restore under way for it (docs/proof.md, Delivered files) | `deviations` (`detail.deviations`: `{phase, file, plan, change, commit, by}` for each; the user keeps each change, `vbw decide` naming the file, or restores it, `vbw fix restore FILE...`) | yes |
| 10b | the latest proof is partial (it reused results or used the quick command) and a phase is about to go to QA, or the milestone to ship | `prove` with `detail.full` true: `Run vbw prove --full: ...` (docs/proof.md) | no |
| 10a | a phase of the current milestone is built and QA must check it again (never passed, failed, its own files, tests, goal or plan changed since it passed, the tests of a phase it builds on changed, or a file its plans delivered changed outside any plan with no decision of the user covering it, which row 10c settles first; docs/proof.md). An express phase is skipped when every requirement is `auto` and it has no escalations; a `human` requirement or an escalation brings QA back | `qa` (`detail.phases`: only the phases to check again, not the whole project, and `detail.tier`: the highest QA tier of those phases in the profile's table) | no |
| 11 | a `human` requirement is `open` and not skipped, or one moved from a shipped milestone is `open` | `accept` (one scenario at a time) | yes |
| 12 | otherwise | `ship` (`vbw ship`, which refuses while the proven work is not committed: the proof reads files on disk, a shipped milestone must be in git history; a submodule's files are read in the submodule, and its pointer moved by VBW's commits there is no change, docs/workflows.md "Submodules"); when the only unfinished requirements are `human` ones you skipped, `detail.later` lists them: ship now and judge them in the next milestone, or judge them now | yes |

## The loop step

`vbw loop next` is the loop's step (docs/loop.md). It runs the actions that
need no agent (open the milestone, approve by delegation, ship, mark the backlog
entry done) and returns the first that does. `vbw next` itself is unchanged: a
pure reading of the record, and the loop's answers carry the same `action`,
`instruction` and `detail`.

## The step

When the answer runs a step (planning, a build wave, a fix, QA, or a proof with
checks left to run), `vbw next --json` carries `step`; otherwise `step` is
`null`:

```json
{"kind": "build", "ids": ["P1.1", "P1.2"], "parts": 2, "seconds": 600,
 "end": "2026-10-16T14:20:00Z",
 "say": "Building P1.1 and P1.2: about 10 min, until around 14:20"}
```

`parts` is the number of plans, fixes or checks (a proof counts the checks left
after reused results); it is `null` for planning and QA. `seconds` and `end` come
from this clone's step history (see [Time left](panel.md#time-left)). `say` is
the sentence the router says as given before the step starts. With fewer than 3
finished steps of the kind, `seconds` and `end` are `null` and `say` reads
`Building P1.1, P1.2 and P1.3: no end time yet (VBW has timed fewer than 3 steps like this here)`.

A proof's step also carries `why`, the reason most of its units run again as
`{"reason": "plugin/lib/core.sh changed", "count": 41}` (absent when no unit
runs), and its `say` ends with it, so the sentence says why the proof is as long
as it is:
`Proving 52 checks: about 14 min, until around 14:20; top reason: plugin/lib/core.sh changed (41 units)`.
The reasons are the ones the proof's first and last report lines name
([the report lines](proof.md#the-two-report-lines-where-the-time-went)).

The proof's `parts` needs the list of units the next proof would run. Planning
it reads the run store and runs git, so `vbw next` caches the list in
`.vbw/runtime/proof-units.json`. The cache is keyed on the committed tree, the
git index's digest (SHA-256 of `git ls-files -s`: the test files are listed
from the index, so a staged new test file counts), the record's fingerprint
(SHA-256 of the record file) and the run store's digest (SHA-256 of its file;
an absent store counts as empty). It also records whether the proof is full
and the top reason.
When any of these changes (a new
commit, a staged file, a changed record, a changed run store), the list and the top reason are
recomputed and the file rewritten. A damaged cache file is recomputed too.

### The road

`vbw next --json` and `vbw status --json` also carry `road`: when the whole
milestone should end, not only the current step. It is `null` when no phase is
left (the milestone shipped).

```json
{"seconds": 2160, "end": "2026-10-18T14:56:00Z",
 "rounds": {"standard": 2, "deep": 0},
 "basis": "2 build waves, 2 proofs, 1 QA check and 2 usual fix rounds (median of the latest 10 finished phases of each tier)",
 "say": "Milestone end: about 36 min, until around 14:56, counting 2 fix rounds per standard phase (the usual here)"}
```

- `seconds` and `end`: the time still ahead and the clock time it ends. Both
  are `null` when any needed piece has no basis; a made-up time never appears.
- `rounds`: the usual fix rounds per tier, the rounded median of
  `outcome.fix_rounds` over the latest 10 finished phases of the tier (a tier
  with fewer than 3 finished phases counts 0).
- `basis`: what the time adds up, or the first kind with no basis.
- `road.say`: the sentence, said as given together with `step.say` before a
  step starts. Before planning it reads `Milestone end: planning about 2 min,
  until around 14:22; the rest follows once the work is planned`. With no basis
  it reads `no milestone end time yet (VBW has timed fewer than 3 plans here)`.

`vbw next` writes the road into `next.json` beside the step; `vbw run start`
writes it into the step's note, where a late plan done moves it with the step.
The note's road goes with the note when the run ends. See
[Time left](panel.md#time-left).

### The rename hint

`rename_hint` in `vbw next --json` is a string or `null`. It is a string when a
second chat is open on this project (a chat of Claude Code's list whose folder
is the project or a folder under it) and this chat still carries the name
Claude Code gave it. A name you chose with `/rename` gets no hint. The sentence
reads `Another chat is open on this project: /rename vbw · <project name> gives
this chat a name the other chats will see.` and comes once per clone: the mark
is `rename_hint` in this clone's settings, so the next answer carries `null`.
The router says it once, as given. VBW never runs or applies the rename itself
(D444): you rename the chat. Only the command computes it, not the Stop hook's
gate or the loop.

### The project folder

`root` in `vbw next --json` is the project folder: the top folder of the git
repository, which every VBW path (`.vbw/`, plan and check files) is relative
to. `vbw root` prints the same folder, outside a VBW project too. The router
passes it to every workflow as `args.root` (docs/workflows.md), so the agents of
a session started in a subfolder of the project work in the project folder.

## Build waves

`vbw show contract` prints the build's shape under `plans:`, before the
approval question: one line for the waves, then one line for each plan that
waits, naming the plans of the wave before it that hold it back and why:

```text
build waves: 3 (the widest runs 2 plans at once)
  P1.3 waits for P1.1 (planned after it)
  P1.4 waits for P1.2 (both change src/x.js)
  P1.5 waits for P1.3 (planned after it, both change c.js)
```

A plan waits because it is planned after another (`after`), or because the two
would change the same file. The file named is the more specific entry: a plan
on `src/` and a plan on `src/x.js` both change `src/x.js`. A plan that may
change any file (`*`) reads `either may change any file`. Only the wave just
before a plan is named, because that wave is what holds it back; a plan of the
first wave has no line.

The count follows row 5: the same rule that picks each wave when `vbw next`
schedules the build. A plan waits until every plan in its `after` is built.
Two plans that share a file never run in the same wave, and a directory in
`files` shares a file with everything under it. The line counts the plans of
the current milestone that are not `done`, so it shrinks as the build goes on.
The first number is how many waves the build takes; the second is the most
plans any one wave runs at the same time.

A phase that cannot be split shows the plain truth: when every plan waits for
the one before it, or all of them write the same file, the line reads
`build waves: 3 (the widest runs 1 plan at once)`. It never counts plans that
run one after another as parallel. Read it as the approval check on the
Lead's plan: a wide wave means plans build at the same time; a width of 1
means the work builds one plan at a time, and the wait lines say what you
could change ("Not yet") to let more plans build together.

The Lead (`plugin/agents/lead.md`) aims for that line to be as wide as the
work allows. It splits each phase into plans that touch separate files, lists
only real dependencies in `after`, and puts plans that must share a file in
separate waves. After applying the plan it reads `vbw show contract` and
splits further where the work allows.

While a Dev builds, edits to test files do not stop the build: only a change to
the contract's structure does (row 4). Row 4a is the one approval for all of
those edits, asked just before proof.

Every result also carries a `qa` key: `{recheck, standing, interleaved, problems}`.
`recheck` maps each built phase QA must check again to its reasons in plain words
(`{"P2": ["builds on P1, whose tests changed"]}`); `standing` lists the built phases
whose pass stands; `interleaved` lists the phases that build on each other
through their plans (a plan of each comes after a plan of the other: legitimate,
since the record refuses a plan cycle; each is checked again when the other's
tests change, and `vbw show qa` notes them); `problems` lists plan links that
point nowhere, and a loop among the plans themselves.

At the `qa` step the result also carries `round.suite`: the proof's one run of
the project's test command, `{command, status, exit, seconds, tail}`, or `null`
when the project has no test command. `status` is the proof's (`pass`, `fail`,
`timeout`, `skipped`), or `not run` when the proof did not include the command.
The router gives `round` to the QA workflow, which hands it to every QA agent so
none runs the suite again (docs/workflows.md).
`round.tiers` maps each phase to check to the QA depth chosen for its size and
risk (`quick`, `standard` or `deep`; docs/rigor.md). The QA workflow uses it
instead of the profile's depth, which `rigor` still carries.
`round.deviations` maps each phase to check that has any to the files its plans
delivered that the last proof found changed outside any plan, each `{file,
plan, change, commit, by, decision}` (`change` is `deleted` or `changed`, `by`
the commits that did it, `decision` the id of the user's decision that covers
it, or `null`). It is `{}` when there are none (docs/proof.md, Delivered files).
The QA workflow names each one to that phase's QA agent.

The router opens the QA run (`vbw run start qa`) before it starts the QA
workflow, and an open run turns the `qa` answer into `run` (row 0). While the
caller's own QA run is open, the `run` answer carries the same `round` the `qa`
answer did, so the router can read it on either side of `vbw run start qa`. A
`run` answer for another session's run, and for any run that is not QA, has
none. Without it a small change would be checked at its profile's depth
instead of the quick check its size earns, and the QA agents would be told
the project has no test command.

Rejecting a `human` requirement (`vbw req reject R2 "why"`) opens a fix item at
once, so it is worked by row 9; when the fix is done the requirement returns to
row 11 for acceptance.

Fix items and their attempt cap are defined in docs/proof.md.
