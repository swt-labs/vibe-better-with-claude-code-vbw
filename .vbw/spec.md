# v2

## Goals

VBW is a Claude Code plugin that makes it build software properly: the user agrees on what to build, VBW writes tests that must pass, builds the work in parallel, proves it works, and asks the user only about what tests cannot judge. It is for anyone who builds with Claude Code, from people who have never written code to senior engineers, and it adapts how it talks to each.

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
- R31 [auto] Before approval, every [auto] requirement lists the rules its text states (each condition, edge and error case), each with the check that tests it; vbw apply refuses a listed rule that no check tests, naming it, and the approval screen shows the rules with their checks
- R32 [auto] vbw prove runs the checks and project commands on a clean copy of the committed code, so uncommitted changes and untracked files in the working folder change no proof result; vbw check keeps running on the working folder for the Dev's red and green steps
- R33 [auto] A VBW that opens a project record written by a newer VBW says the project needs a newer VBW and how to update, instead of calling the record corrupt, and every VBW still reads the records of older versions
- R34 [auto] A real-user scenario in tools/l3-suite.sh shows both in the real Claude Code app: a request that states an edge case gets a check for that edge before approval, and a leftover untracked file in the working folder does not change the proof
- R35 [auto] In every profile and rigor tier, QA agents run on Sonnet or a stronger model, never Haiku; other roles keep the models their profile gives them
- R36 [auto] vbw config set model.qa refuses a model weaker than Sonnet (haiku) and says QA needs Sonnet or stronger; sonnet, opus and default are still accepted
- R37 [auto] At the start of a project (after mapping, for existing code), VBW asks three fixed questions: how much software the user has built (never, small scripts or no-code, professionally, senior engineer), how VBW should explain things (plain words, plain with technical terms explained, technical and brief), and how involved they want to be in technical decisions (decide and tell me, options with a recommendation, I make the calls); then what they are building and for whom; then up to three follow-up questions VBW writes for that user and project
- R38 [auto] The interview's answers are kept in the project, shown by vbw status, asked only once per project (a project started before this version is asked once, at its next milestone), and can be changed later with /vbw:profile
- R39 [auto] Every VBW step that talks to the user, and every agent whose words reach the user, receives the user's level, explanation depth and involvement, and writes at that level
- R40 [auto] When VBW proposes requirements and when it presents a plan for approval, it offers at most three suggestions matched to the user's level, each one a yes or no the user may decline; an accepted one becomes a requirement or a recorded decision, and a declined one is not offered again in that project
- R41 [human] A vibe coder and a senior engineer each find VBW's wording right for their level: never too simple, never too technical
- R42 [auto] Real-user scenarios answer the interview as a newcomer and as a senior engineer; both record their answers, are not asked again, and reach the ship step
- R43 [auto] Closing a fix does not rerun a check that already passed on the same project files under the same approved contract: it says the check is unchanged since its pass, and when that pass was; vbw prove still runs every check
- R44 [auto] Several fixes close in one command (vbw fix done F8 F9 F5), running the checks their files serve once; each fix ends as it would if closed alone; a fix that cannot close is named, and the others still close
- R45 [auto] A check the contract marks to run alone (for example one that starts containers) never runs at the same time as another VBW check in the same project, even when several fixes or builds run checks in parallel
- R46 [auto] A record written by this VBW is either read by VBW 2.0.16 or makes it say the project needs a newer VBW; it is never reported as corrupt
- R47 [auto] After a round of fixes, QA checks again only the phases that did not pass and the phases whose own inputs changed since they passed (their files, their tests, or their goal and plan); an untouched phase keeps its pass
- R48 [auto] When QA runs, VBW says for each phase why it is checked again (failed last time, or which of its inputs changed) and lists the phases whose pass still stands
- R49 [auto] A phase is also checked again when a phase it builds on was checked again because its inputs changed, even if its own inputs did not
- R50 [auto] Before planning, VBW asks the user only about decisions for the milestone being planned, never about requirements of shipped milestones
- R51 [auto] A VBW panel in Claude Code shows, in plain words, the milestone and its progress, what VBW is doing right now (planning, building which parts, checking), and whether it needs the user and for what; it updates by itself within a few seconds when that changes
- R52 [auto] The panel opens by itself in a wide window, and at any width with a command; the user can close it, and it stays closed until they open it again
- R53 [auto] On Claude Code versions without mods (older than 2.1.287), or outside a VBW project, nothing breaks: no panel and no error, and the status line works as before
- R54 [human] The panel is easy to read at a glance at the user's level
- R55 [auto] The panel stays light: it uses no network, and its updates do not slow Claude Code down
- R56 [auto] The panel shows how much the current session has cost so far
- R57 [auto] VBW plays a short sound when it needs the user (an approval, a question, a result to check); one click in the panel or one command turns it off or on, and the choice is remembered
- R58 [auto] The panel shows an estimated time left for the current step and for the milestone, based on how long earlier steps took in this project, and says plainly when it has no basis for an estimate yet

<!-- One requirement per line: an id, how it is proved, and a user-observable
     statement. [auto] = a check can prove it; [human] = only a person can judge it.
- R1 [auto] A visitor can sign up with an email address
- R2 [human] The landing page feels trustworthy
-->

## Commands

- test: bash tools/test.sh
