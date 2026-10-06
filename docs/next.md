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

At the `plan` step, `detail.tier` is the early tier (docs/rigor.md): `express`
for one small, risk-free `auto` requirement in a repository of at most 30
tracked files, else `standard` (`deep` when forced). On `express` the router
plans without workflows: one `vbw apply` with one phase, plan and check.
`detail.small` is `true` for one or two `auto` requirements that name no risk
category, in a repository of any size; the router plans those the same way
(docs/rigor.md).

## Decision order (first match wins)

| # | Condition | action | gate |
|---|---|---|---|
| 0 | a run lease is open | `run` (wait for its workflow if it is running in this session; otherwise `vbw run end`; a run owned by another session: wait or check `vbw status`, never end it) | no |
| 1 | milestone `shipped` | `milestone` (start the next one: `vbw milestone start TITLE`) | yes |
| 2a | no requirements in the current milestone, and a VBW 1 plan (`.vbw-planning/`) not converted yet | `convert` (`/vbw:convert`, or start fresh; docs/convert.md) | yes |
| 2 | no requirements in the current milestone | `spec` (write its requirements in `.vbw/spec.md`) | yes |
| 3 | the current milestone has no phases, an `auto` requirement has no check, or a current `auto` requirement is in no plan | `plan` (`detail.tier`: the early tier; plan workflow: phases, plans, contract checks, or direct `vbw apply` when express) | no |
| 4 | contract not approved (never approved, or its structure changed since: requirements, checks, plans) | `approve` (review and approve the contract) | yes |
| 4a | the contract is approved except for edits to the bytes of test files (a check's `files`), and a phase is built but not proved | `approve` with `detail.files`: the one approval of those test files, before they are proved (docs/proof.md) | yes |
| 5 | plans ready to build: not `done`, not `blocked`, every `after` plan `done` | `build` (one wave: the ready plans in order, skipping any that shares a file with one already in the wave). When a plan is `blocked`, the instruction names it with its reason and `detail.blocked` lists `{id, note}`; plans that depend on it wait, unrelated plans still run | no |
| 6 | no plan is ready and a plan is `blocked` | `unblock` (a Dev reported a blocker; `detail.plans` and `detail.blocked` name every blocked plan and its reason) | yes |
| 7 | a fix is `escalated` | `escalate` (the fix cap was reached) | yes |
| 8 | current evidence has scope violations | `scope` (commits changed files outside their plans) | yes |
| 9 | a fix is `open` | `fix` (`detail.fixes`, and `detail.groups`: fixes whose files overlap, one Dev each; a project command's fix may touch any file) | no |
| 10 | an `auto` requirement is not `proven`, or the evidence is stale (another contract, or the project files changed since; docs/proof.md) | `prove` | no |
| 10a | a phase of the current milestone is built and QA must check it again (never passed, failed, its own files, tests, goal or plan changed since it passed, or a phase it builds on was checked again; docs/proof.md). An express phase is skipped when every requirement is `auto` and it has no escalations; a `human` requirement or an escalation brings QA back | `qa` (`detail.phases`: only the phases to check again, not the whole project, and `detail.tier`: the highest QA tier of those phases in the profile's table) | no |
| 11 | a `human` requirement is `open` | `accept` (one scenario at a time) | yes |
| 12 | otherwise | `ship` (`vbw ship`, which refuses while the proven work is not committed: the proof reads files on disk, a shipped milestone must be in git history) | yes |

While a Dev builds, edits to test files do not stop the build: only a change to
the contract's structure does (row 4). Row 4a is the one approval for all of
those edits, asked just before proof.

Every result also carries a `qa` key: `{recheck, standing, problems}`. `recheck`
maps each built phase QA must check again to its reasons in plain words
(`{"P2": ["builds on P1, which changed"]}`); `standing` lists the built phases
whose pass stands; `problems` lists plan links that point nowhere or loop.

At the `qa` step the result also carries `round.suite`: the proof's one run of
the project's test command, `{command, status, exit, seconds, tail}`, or `null`
when the project has no test command. `status` is the proof's (`pass`, `fail`,
`timeout`, `skipped`), or `not run` when the proof did not include the command.
The router gives `round` to the QA workflow, which hands it to every QA agent so
none runs the suite again (docs/workflows.md).

Rejecting a `human` requirement (`vbw req reject R2 "why"`) opens a fix item at
once, so it is worked by row 9; when the fix is done the requirement returns to
row 11 for acceptance.

Fix items and their attempt cap are defined in docs/proof.md.
