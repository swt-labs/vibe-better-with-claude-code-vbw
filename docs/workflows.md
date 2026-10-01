# Workflows and agents

VBW's engine is five Claude Code workflows (`plugin/workflows/*.js`) and four
agents (`plugin/agents/*.md`). The workflows hold the procedure: who runs, in
what order, in parallel or not. The agents hold the standard: what good output
is. Every write to the plan of record goes through `vbw`.

| Workflow | Started when `vbw next` says | Agents | Ends with |
|---|---|---|---|
| `vbw:planning` | `plan` | planner (decide) → planner → critic → planner (one revision when the critic finds issues) | `needs_decisions` (up to 4 questions for the user, each with options, trade-offs and a recommendation; the router asks them, records the answers with `vbw decide`, and runs the workflow again with `decided: true`), or phases, plans and checks in the record, protected test files written and failing, and the planner's own `choices` listed |
| `vbw:building` | `build` (one wave: the ready plans, no two sharing a file) | one builder per plan, in parallel | each plan `done` (committed, its checks green) or `blocked` with a reason |
| `vbw:fixing` | `fix` (`detail.groups`: open fixes that share files, grouped) | one builder per group, groups in parallel | each fix `fixed` (verified, committed) or its plan `blocked` |
| `vbw:mapping` | `spec` or `plan` on existing code without `.vbw/map.md` | scouts, one per angle, then one merge | the map, written to `.vbw/map.md` |
| `vbw:investigating` | the user runs `/vbw:debug` | three scouts (reproduce, trace, history), then a judge | the root cause, its evidence and a proposed fix; nothing changed |

After `build` and `fix`, the router runs `vbw prove` (deterministic, no agent),
and `vbw next` decides again. Approval, acceptance and shipping are human gates.

## The run lease

The router opens a lease before it starts a workflow and closes it after:

```
vbw run start build P1.1 P1.2     # or: vbw run start fix F1 F2 | vbw run start plan
vbw run end
```

`record.lease` is `{run, kind, started_at, files}`. `files` holds the paths the
run's agents may write: the plans' files for `build`; for `fix`, the files of
every plan that serves a fixed requirement; `null` for `plan` (planners write
test files that no plan owns yet). While a lease is active, any **subagent**
(the hook input carries `agent_type`) is held to it:

- it writes only files in `lease.files` (when not null);
- it never writes a protected check file (any check's `files`) during `build` or `fix`;
- it never runs `git commit`, `push`, `rebase`, `merge`, `pull`, `cherry-pick`, `revert` or `am`: commits go through `vbw commit`;
- it never moves HEAD or other builders' changes in the shared working tree: no `git stash` (except `list`/`show`), `switch`, `reset`, or `checkout` of a branch, and `git checkout -- PATH`/`git restore PATH` only for paths in `lease.files`.

The main session is never held to a lease, so the user can always step in. A
lease older than 24 hours is ignored (a crashed run must not lock a project).

## Kernel commands agents use

| Command | Who | What |
|---|---|---|
| `vbw show plan P1.2 [--json]` | builder | the plan, its requirements, its checks, its files |
| `vbw show fix F1 [--json]` | builder | the fix, its requirement, failing checks and output, the files it may touch |
| `vbw check [--expect-red] [C1 ...]` | builder | run approved checks, report, write nothing. `--expect-red`: every check must fail (red-first) |
| `vbw commit P1.2 "feat(x): ..."` | builder | commit the plan's changed files with provenance trailers |
| `vbw plan done P1.2` / `vbw plan block P1.2 "reason"` | builder | the plan's outcome |
| `vbw fix done F1` | builder | verified: no uncommitted changes in the files it may touch, and the checks of every finished requirement those files serve pass; then awaiting proof |
| `vbw apply < plan.json` | planner | replace phases, plans and checks in one validated write (refused once any plan has started) |

## Agents

Agents are specifications of good output, not procedures (design §4). Each
returns a structured result through the workflow's `schema`, so Claude Code
validates it and retries on a mismatch. A completion gate of our own is not
needed.

- **planner**: first finds the decisions only the user should make (cost,
  data, security, user experience, hard to undo), then follows the recorded
  decisions and turns the spec into phases, small plans with declared files,
  and checks that fail today and pass only when the requirement is met. It
  writes the check test files and applies the plan with `vbw apply`.
- **critic**: reads the spec and the applied plan and finds what would make it
  fail: an uncovered requirement, a check that cannot fail or tests the wrong
  thing, a wrong order. It writes nothing.
- **builder**: implements one plan, or a group of fixes, within its declared
  files, proves its checks red first, then green, and commits through `vbw`.
- **scout**: investigates from one assigned angle (mapping, debugging) and
  reports verified findings. It changes nothing.

## Models

A workflow agent inherits the session model unless `args.models` names one for
its role (`{planner, critic, builder}`), which the router fills from the
project's model profile. The session itself must run an auto-mode-capable model
(Sonnet, Opus or Fable; probe G4).

## Why builders share one folder (decided 2026-10-01)

Builders in one wave share the working tree. The kernel never puts two plans
that share a file in one wave (`vbw next`, and `vbw run start build` refuses
such a wave), fixes that share files go to one builder, and the guards stop a
builder from stashing, switching or resetting the tree, so commits never
conflict. A builder can still see another's half-written file while it runs
its checks; its own checks decide its result, and `vbw prove` after the wave is
the authority.

Per-agent git worktrees (`isolation: 'worktree'`) would isolate builders
fully, but a worktree holds only tracked files: ignored dependencies
(`node_modules`, a virtualenv) and build outputs are missing. Builders would
reinstall per copy, fail checks for unrelated reasons, or, sharing the main
checkout's dependencies (an editable install), prove the main checkout's code
instead of their own. A false proof is the one failure VBW must not have, so
worktrees may come later only as an opt-in setting with a per-copy install
step.
