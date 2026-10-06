# Workflows and agents

VBW's engine is seven Claude Code workflows (`plugin/workflows/*.js`) and
VBW 1's team of seven agents (`plugin/agents/*.md`): Architect, Lead, Dev, QA,
Scout, Debugger and Docs, with their VBW 1 mandates. The workflows hold the
procedure: who runs, in what order, in parallel or not. The agents hold the
standard: what good output is. Every write to the plan of record goes through
`vbw`.

| Workflow | Started when | Agents | Ends with |
|---|---|---|---|
| `vbw:planning` | `vbw next` says `plan` | Architect (decide) → Architect (scope) → Lead | `needs_decisions` (up to 4 questions for the user, each with options, trade-offs and a recommendation; the router asks them, records the answers with `vbw decide`, and runs the workflow again with `decided: true`), or phases with goals and criteria, plans with tasks and checks in the record, test files written and failing, the Lead's own `choices` and the Architect's scope `notes` |
| `vbw:building` | `build` (one wave: the ready plans, no two sharing a file) | a Dev per plan, Docs for documentation plans, in parallel | each plan `done` (one commit per task, its checks green) or `blocked` with a reason |
| `vbw:fixing` | `fix` (`detail.groups`: open fixes that share files, grouped) | a Dev per group, groups in parallel | each fix `fixed` (verified, committed) or its plan `blocked` |
| `vbw:verifying` | `qa` (built phases not yet verified on the proven code) | a QA agent per phase, in parallel | each phase's verdict recorded (`vbw qa record`), its findings as fixes (`vbw qa finding`) |
| `vbw:mapping` | `spec` or `plan` on existing code without `.vbw/map.md` | Scouts, one per angle, then one merge | the map, written to `.vbw/map.md` |
| `vbw:researching` | the user runs `/vbw:research` | four Scouts (sources, practice, current state, this project), then one answer | a sourced answer with a recommendation |
| `vbw:investigating` | the user runs `/vbw:debug` | three Debuggers (reproduce, trace, history), then one diagnosis; with the diagnosis given, one Debugger fixes it | the root cause with evidence and rejected hypotheses; or the fix, its regression test and commit |

After `build` and `fix`, the router runs `vbw prove` (deterministic, no agent);
after a passing proof, QA verifies what the checks cannot (docs/proof.md). Then
`vbw next` decides again. Approval, acceptance and shipping are human gates.

Every stop ends with one plain line, **What I need from you:** followed by the
one thing you must do now, or "nothing" when VBW needs nothing.

## The run lease

The router opens a lease before it starts a workflow and closes it after:

```
vbw run start build P1.1 P1.2     # or: fix F1 F2 | plan | qa | map
vbw run end
```

`record.lease` is `{run, kind, started_at, session, files}`. `session` is the
Claude Code session that opened the run (skills pass it as `VBW_SESSION_ID=${CLAUDE_SESSION_ID}`).
In any other session `vbw next` answers that the run belongs to another session
and to wait or check status; it never says to end it. `vbw run end` from a
non-owner session is refused. Two exceptions: the user states the owning session
is closed (`vbw run end --owner-closed`), or the run is older than 24 hours
(`VBW_LEASE_HOURS`).

`files` holds the paths the
run's agents may write: the plans' files for `build`; for `fix`, the files of
every plan that serves a fixed requirement; `null` for `plan` (the Lead writes
test files that no plan owns yet); `[]` for `qa` and `map` (their agents
only read; the lease also tells the autonomy gate a workflow is still running). While a lease is active, any **subagent**
(the hook input carries `agent_type`) is held to it:

- it writes only files in `lease.files` (when not null);
- it never writes a protected check file (any check's `files`) during `build` or `fix`;
- it never runs `git commit`, `push`, `rebase`, `merge`, `pull`, `cherry-pick`, `revert` or `am`: commits go through `vbw commit`;
- it never moves HEAD or other agents' changes in the shared working tree: no `git stash` (except `list`/`show`), `switch`, `reset`, or `checkout` of a branch, and `git checkout -- PATH`/`git restore PATH` only for paths in `lease.files`.

The main session is never held to a lease, so the user can always step in. A
lease older than 24 hours is ignored (a crashed run must not lock a project).

## Kernel commands agents use

| Command | Who | What |
|---|---|---|
| `vbw show plan P1.2 [--json]` | Dev | the plan, its requirements, its checks, its files |
| `vbw show fix F1 [--json]` | Dev | the fix, its requirement, failing checks and output, the files it may touch |
| `vbw check [--expect-red] [C1 ...]` | Dev | run approved checks, report, write nothing. `--expect-red`: every check must fail (red-first) |
| `vbw commit P1.2 "feat(x): ..."` | Dev | commit the plan's changed files with provenance trailers |
| `vbw plan done P1.2` / `vbw plan block P1.2 "reason"` | Dev | the plan's outcome. `done` is verified: none of the plan's files has uncommitted changes, and the checks of the requirements it completes pass. The plan also needs a commit with its `VBW-Plan` trailer (`vbw commit`); without one, every file must be committed in `HEAD` (for example by the approval commit) and a check of its requirements must pass, or `done` is refused and names the failing check. A blocked plan stops only the plans that depend on it (docs/next.md) |
| `vbw fix done F1` or `vbw fix done F8 F9` | Dev | verified (several fixes in one command run the checks they serve once; one that cannot close is named, the others still close, and the exit code is non-zero): no uncommitted changes in the files it may touch, and the checks of every finished requirement those files serve pass; then awaiting proof |
| `vbw apply < plan.json` | Lead | replace phases, plans and checks, and set each `auto` requirement's rules, in one validated write (refused while a build or fix run is open; a plan that has started must come back unchanged) |

## `vbw apply` and rules

The Lead's one write is a JSON document on stdin. The optional `rules` key
lists what each `auto` requirement states, with the check that tests it:

```json
{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"]}],
 "plans":  [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.sh"], "after": []}],
 "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]},
            {"id": "C2", "req": "R1", "run": ["sh", "tests/twice.sh"], "files": ["tests/twice.sh"]}],
 "rules":  [{"req": "R1", "text": "A payment succeeds", "check": "C1"},
            {"req": "R1", "text": "Paying twice is refused", "check": "C2"}]}
```

When the key is present, `vbw apply` refuses, writes nothing, and names the
problem when:

- a rule's `check` is not a check of that rule's requirement in this plan
  ("the rule ... names C9, which is not a check of R1 in this plan");
- a rule is for a `human` requirement;
- an `auto` requirement of the plan's phases lists no rules (`R1 lists no
  rules`), counting rules the record already holds.

An accepted document stores each requirement's rules in the record
(docs/record.md). Re-planning without the key keeps the stored rules. Without
the key on a first plan, nothing changes (see docs/proof.md for the approval
consequence).

## Agents

Agents are specifications of good output, not procedures (design §4). Each
returns a structured result through the workflow's `schema`, so Claude Code
validates it and retries on a mismatch. A completion gate of our own is not
needed.

- **Architect**: requirements to roadmap. First the decisions only the user
  should make (cost, data, security, user experience, hard to undo); then the
  phases, each with a goal and goal-backward success criteria, must-haves
  separated from nice-to-haves. Planning only; it writes nothing.
- **Lead**: research, then each phase decomposed into plans of 3 to 5 tasks
  (no shared files in a wave; documentation plans marked `docs`), checks that
  fail today, a self-review, and `vbw apply`.
- **Dev**: executes a plan's tasks (or a group of fixes) within its files, one
  commit per task, checks red first and then green; deviations classified
  DEVN-01 to DEVN-05; database safety.
- **QA**: goal-backward verification of a built phase at the profile's tier
  (quick, standard, deep): the goal and criteria met, test gaps, and every
  deviation from the plan as a failure. It changes nothing but its record.
- **Scout**: research from one angle (codebase, web, documentation), verified
  and sourced, read-only.
- **Debugger**: the scientific method: reproduce, hypothesize, evidence,
  diagnose; in fix mode a minimal root-cause fix with a regression test.
- **Docs**: documentation plans (README, changelog, guides, API and inline
  docs), concise and example-first; documentation files only.

## The user's level

The router passes `args.profile` (the `profile` key of `vbw next --json`,
docs/next.md) to every workflow: `{level, depth, involvement, ...}`
(docs/interview.md). Each workflow turns it into one sentence and appends it to
the task of every agent it starts:

```
The user's level: professionally. Explanation depth: plain with technical terms
explained. Involvement: I make the calls. Write whatever the user will read at
that level and depth.
```

Without `args.profile`, or for a missing value, the workflow uses the middle
choices (`small scripts or no-code`, `plain with technical terms explained`,
`options with a recommendation`). All seven workflows do this.

Each agent file has a section on the user's words: what reaches the user is the
agent's summary, notes and questions, and those follow the level and depth.
Where a choice is the user's, the agent follows involvement: Architect returns
a decision instead of options for `decide and tell me`, and lists every
decision, obvious ones included, for `I make the calls`. The `schema` fields
stay as the schema defines them at every level.

## Planning scope

The router passes `args.requirements` (the `requirements` key of `vbw next
--json`, docs/next.md) to `vbw:planning`: only the active milestone's
requirements, as `{id, text, proof}`. The workflow lists exactly those in the
task of both Architect jobs (decide and scope) under "Requirements of this
milestone (the only ones to consider)", so the Architect never asks about
requirements of shipped milestones. When every listed requirement is an
internal technical change, it returns no decision.

Without `args.requirements`, or with an empty list, the workflow starts no
agent and returns `status: "blocked"` with the summary "planning needs the
requirements of this milestone ... and got none".

## Rigor

The router passes `args.rigor` (the `rigor` key of `vbw next --json`, docs/next.md)
to the building, verifying and fixing workflows. It maps each phase id to
`{tier, agents, qa, models}` (docs/rigor.md).

- `vbw:building`: each Dev runs on `rigor[phase].models.dev`, falling back to `args.models.dev`; a documentation plan's Docs agent runs on `args.models.docs`.
- `vbw:verifying`: each phase is verified at `rigor[phase].qa` (`quick`, `standard` or `deep`), falling back to `args.tier`, on `rigor[phase].models.qa`.
- `vbw:fixing`: a fix has no phase of its own, so every Dev runs on the Dev model of the highest-tier phase in `args.rigor`.

Without `args.rigor`, each workflow uses `args.models` and `args.tier` as before.

## Models

A workflow agent inherits the session model unless `args.models` names one for
its role (`{architect, lead, dev, qa, scout, debugger, docs}`), which the router fills from the
project's model profile. The session itself must run an auto-mode-capable model
(Sonnet, Opus or Fable; probe G4).

## Why agents share one folder (decided 2026-10-01)

Devs in one wave share the working tree. The kernel never puts two plans
that share a file in one wave (`vbw next`, and `vbw run start build` refuses
such a wave), fixes that share files go to one Dev, and the guards stop a
Dev from stashing, switching or resetting the tree, so commits never
conflict. A Dev can still see another's half-written file while it runs
its checks; its own checks decide its result, and `vbw prove` after the wave is
the authority.

Per-agent git worktrees (`isolation: 'worktree'`) would isolate Devs
fully, but a worktree holds only tracked files: ignored dependencies
(`node_modules`, a virtualenv) and build outputs are missing. Devs would
reinstall per copy, fail checks for unrelated reasons, or, sharing the main
checkout's dependencies (an editable install), prove the main checkout's code
instead of their own. A false proof is the one failure VBW must not have, so
worktrees may come later only as an opt-in setting with a per-copy install
step.
