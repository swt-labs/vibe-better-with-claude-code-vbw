# Workflows and agents

VBW's engine is three Claude Code workflows (`plugin/workflows/*.js`) and three
agents (`plugin/agents/*.md`). The workflows hold the procedure: who runs, in
what order, in parallel or not. The agents hold the standard: what good output
is. Every write to the plan of record goes through `vbw`.

| Workflow | Started when `vbw next` says | Agents | Ends with |
|---|---|---|---|
| `vbw:plan` | `plan` | planner → critic → planner (one revision when the critic finds issues) | phases, plans and checks in the record; protected test files written and failing |
| `vbw:build` | `build` (one wave: the ready plans) | one builder per plan, in parallel | each plan `done` (committed, its checks green) or `blocked` with a reason |
| `vbw:fix` | `fix` | one builder per fix item, in parallel | each fix `fixed` (committed) or its plan `blocked` |

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
- it never runs `git commit`, `git push`, `git rebase` or `git merge`: commits go through `vbw commit`.

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
| `vbw fix done F1` | builder | work committed, awaiting proof |
| `vbw apply < plan.json` | planner | replace phases, plans and checks in one validated write (refused once any plan has started) |

## Agents

Agents are specifications of good output, not procedures (design §4). Each
returns a structured result through the workflow's `schema`, so Claude Code
validates it and retries on a mismatch. A completion gate of our own is not
needed.

- **planner**: turns the spec into phases, plans with disjoint declared files,
  and checks that fail today and pass only when the requirement is met. It
  writes the check test files and applies the plan with `vbw apply`.
- **critic**: reads the spec and the applied plan and finds what would make it
  fail: an uncovered requirement, a check that cannot fail or tests the wrong
  thing, overlapping files, a wrong order. It writes nothing.
- **builder**: implements one plan or one fix within its declared files, proves
  its checks red first, then green, and commits through `vbw`.

## Models

A workflow agent inherits the session model unless `args.models` names one for
its role (`{planner, critic, builder}`), which the router fills from the
project's model profile. The session itself must run an auto-mode-capable model
(Sonnet, Opus or Fable; probe G4).

## Known trade-off

Builders in one wave share the working tree. Their files are disjoint, so their
commits never conflict, but a builder can see another's half-written file while
it runs its checks. Its own checks still decide its result, and `vbw prove`
after the wave is the authority. Per-agent worktrees would remove the overlap at
the cost of merging; the eval data decides whether that is worth it.
