# v2

## Goals

## Non-goals

## Constraints

## Requirements

- R1 [auto] Two consent grants made at the same time from different worktrees of one clone are both kept
- R2 [auto] A vbw command interrupted mid-commit leaves no stray index files in .vbw/runtime and keeps the caller's own exit cleanup
- R3 [auto] vbw report and vbw rtk do what their help says
- R4 [auto] In a real session, a documentation requirement is built by the Docs agent and proved
- R5 [auto] In a real session, QA fails a phase whose build deviates from its plan, and the fix loop closes it
- R8 [auto] In balanced autonomy, a background QA run causes no Stop-hook errors and the session reaches the accept stop
- R10 [auto] Blocking or resetting a plan (its note or status) never withdraws the user's approval of an unchanged contract
- R11 [auto] Accepting a [human] requirement closes only the fixes opened by the user's own rejections; a fix QA opened stays open until QA passes the phase again
- R12 [auto] QA cannot record a verdict on a proof older than the current code: vbw qa record refuses and asks for vbw prove first
- R13 [auto] While one session's VBW run is open, vbw next in another session says the run belongs to another session and to wait or check status; it never tells that session to end the run
- R14 [auto] vbw run end from a session that does not own the open run is refused, unless the user states that the owning session is closed or the run is older than 24 hours
- R15 [auto] While a run is open, another session, neither its main conversation nor its agents, can edit the files that run is writing
- R16 [auto] Turning on autonomous mode in one session leaves it on in every other session where it was on
- R17 [auto] tools/baseline holds the plan's seven benchmark cases (fix-oneshot, failing-check fix, brownfield feature, safety-destructive, safety-secret, hostile-repo, markdown deliverable), each with a deterministic pass/fail check that fails on the untouched starting project and passes on a correct solution
- R18 [auto] The benchmark has run every case 3 times with plain Claude Code and 3 times with VBW 2, on Sonnet 5.5 and on Opus 5.5, and its committed results record each run's pass or fail, tokens and cost
- R19 [human] docs/benchmark.md compares VBW 2 with plain Claude Code case by case, shows VBW 1 from its recorded runs and behaviour ledger, and states plainly what was not measured
- R20 [human] README.md presents VBW 2 to someone new: what it does and why, how to install it, a first project, the commands, with images
- R21 [auto] CONTRIBUTING.md and the repository's other contributor files describe VBW 2 only: every command, path and tool they name exists
- R22 [auto] Before planning finishes, every phase has a rigor tier (express, standard or deep) with its reasons, computed from measured signals (requirement count, planned files and size, risk paths, proven requirements it could break, test coverage), and the approval shows each phase's tier and reasons in one line
- R23 [auto] A phase whose signals call for a higher tier (a risk path such as sign-in, payments, data migrations, secrets, deletion or CI, or many requirements) is never planned below that tier: the Architect may only raise a tier, never lower it
- R24 [auto] An express phase is approved in one step (its requirement, check and plan together), built by one Dev and proved, and runs QA only when a requirement needs a person's judgement or the phase escalated
- R25 [auto] While a phase runs, VBW raises its tier on its own and records and shows why when a Dev blocks, a fix needs a second round, QA finds a problem in an express phase, the change touches a risk path or grows well beyond its plan, or a proven requirement fails; it never lowers a tier during a run
- R26 [auto] Which agents run, how many, the QA tier and the models follow each phase's tier through the profile
- R27 [auto] The tier is chosen automatically by default; the user can force it with vbw config rigor auto, express, standard or deep
- R28 [auto] Each finished phase records its predicted tier and the outcome (fix rounds, QA findings, escalations), and vbw show reports how often the prediction held; cost is measured per session by the benchmark
- R29 [auto] On the seven single-task benchmark cases, VBW 2 with automatic rigor passes every case and costs at most twice what plain Claude Code costs, on Sonnet 5.5 and Opus 5.5
- R30 [human] The benchmark adds at least three multi-requirement projects (a feature on an existing codebase with earlier requirements to protect, a data migration, and a third non-UI project of several requirements), each graded by a deterministic check, run with plain Claude Code and VBW 2, and docs/benchmark.md reports them plainly

<!-- One requirement per line: an id, how it is proved, and a user-observable
     statement. [auto] = a check can prove it; [human] = only a person can judge it.
- R1 [auto] A visitor can sign up with an email address
- R2 [human] The landing page feels trustworthy
-->

## Commands

- test: bash tools/test.sh
