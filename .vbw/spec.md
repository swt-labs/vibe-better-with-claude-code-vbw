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
- R57 [auto] VBW plays a short sound when it needs the user (an approval, a question, a result to check), picked at random from the sounds shipped with VBW in plugin/assets/audio/<character>/; one click in the panel or one command turns it off or on, and the choice is remembered
- R58 [auto] The panel shows an estimated time left for the current step and for the milestone, based on how long earlier steps took in this project, and says plainly when it has no basis for an estimate yet
- R59 [auto] The interview opens with: "Hello, Human! Welcome to VBW. Let me interview you real quick to better adapt to you. What is your level of proficiency?", with the same four options as before
- R60 [auto] At every stop, VBW ends its message with one plain line saying what it needs from the user now, or that it needs nothing
- R61 [auto] Approval is offered as a choice: VBW asks with the options Approve (first, so Enter approves), Not yet (VBW asks what to change) and the user's own words; picking Approve approves exactly the contract shown, recorded by VBW's own code from the user's answer so Claude can never approve by itself; typing /vbw:approve still works
- R62 [auto] Once the interview knows what is being built, VBW asks the user's permission to look for the best tools for this project (community skills, automated code-safety scanners, code-quality tools such as linters and formatters, unit-test and other test frameworks); on yes, Scouts research current best-in-class options for the project's stack, with sources, and VBW proposes a short list; nothing is installed until the user approves that list; on no, nothing is searched or installed; it is asked once per project, and /vbw:skills runs it again any time
- R63 [human] The recommended tools fit the project and are explained at the user's level
- R64 [auto] VBW's own real-app test sessions never play the sound aloud and never read or change the user's own panel and sound choices
- R65 [auto] When a project has a VBW 1 folder, VBW first reviews it (how much was finished, how recently it was used, whether its plans still match the current code, any work half done) and recommends converting or starting fresh with its reasons in plain words, the recommended option first; the user still chooses
- R66 [auto] Changing the plan mid-milestone (adding or changing phases) keeps each phase's QA pass; QA then checks again only new phases and phases whose own inputs changed
- R67 [auto] When a project has a VBW 1 folder and the user has not been interviewed yet, VBW opens with the interview greeting and level question, and asks convert or start fresh right after the level answer
- R68 [auto] The review of an old VBW 1 folder works on Linux as on macOS, including folders not tracked by git
- R69 [auto] vbw prove runs the approved checks in parallel, except checks marked alone, which still run by themselves; the results are the same as running them one after another, and a proof of many checks finishes in a fraction of the time
- R70 [auto] A QA round runs the project's test command once and gives its result to every QA agent of that round, instead of each agent running the whole suite again
- R71 [auto] How deeply QA checks a phase follows the size and risk of its change: a small, low-risk change gets a quick check and never a deep one, and a change to wording or documentation alone needs no new check
- R72 [auto] A small change (one or two files, low risk) goes from the user's request to done through /vbw:vibe without a planning workflow: VBW plans it itself as one plan with its check, the user approves once, it is built, checked and closed
- R73 [auto] A project's proof never reuses build output from the working folder: the clean copy has its own build folders (for any language), so artifacts never point into another copy
- R74 [auto] A plan whose files were already committed (for example by the approval commit) and whose checks pass can be marked done; a blocked or stuck plan never stops unrelated plans from being scheduled
- R75 [auto] While VBW plans, its agents may write only VBW's own files and the test files the plan declares, so a planning run never blocks another session's folders
- R76 [auto] A Dev's command that writes a file outside its plan through a program (Python, Node, Perl or similar) is refused like a shell write outside its plan
- R77 [auto] Reading the plan of record (copying or printing it) or naming the approval command in plain text is never refused as a write or as an approval
- R78 [auto] After each agent of a build, fix or QA workflow returns, VBW confirms that its plan state or verdict was recorded, and says plainly which ones were not
- R79 [auto] The test-file edits made while building a phase are approved together once, before the phase is proved, instead of one approval for each edit
- R80 [auto] One plan, check or rule can be changed without resubmitting the whole milestone, and a fix round cannot add phases or rename phases nobody asked for
- R81 [auto] A project setting limits how many checks run at the same time; an approval whose commit fails stops and says why instead of only warning; a workflow ends its own run when it finishes
- R82 [auto] The VBW panel opens at about a quarter of the terminal width (never narrower than 40 columns); a width the user sets by hand always wins
- R83 [auto] VBW always asks for approval with the approval menu, where Enter approves; it never asks the user to type /vbw:approve, which still works when the user types it
- R84 [auto] Every part of the VBW panel (the band, Mission Control, Wrapped) takes its colours from one shared palette: each agent role has one colour everywhere (architect magenta, lead blue, dev green, qa yellow, scout cyan, debugger red, docs pink), and each state has one colour (running amber, done green, failed red, quiet or cut off grey)
- R85 [auto] In Mission Control's Now tab, each agent card is framed in its role's colour and shows its state as a coloured mark and word (running, done, failed, quiet), so two agents of different roles never look the same
- R86 [auto] In the band, each agent row shows its plan label and spinner in the role's colour, its time and tokens dimmed, and the run's cost in an accent colour in the header
- R87 [auto] An agent's activity is shown as a plain intention (for example editing app-topbar.tsx, running tests, recording P6.7 done) instead of the raw command; a script run through Python, Node or another interpreter is named by what it touches; the verb is coloured and the object dimmed
- R88 [auto] When Claude Code shows a change to .vbw/record.json in the conversation, VBW shows one line saying what happened (for example VBW · build run started) instead of the full diff; the full diff still shows when the user expands the row
- R89 [auto] Mission Control's tabs stay visible at the top of the pane however long its content is, and each sentence of the pane shows its key value in colour (progress green, estimate amber, cost in the accent colour, a need of the user yellow)
- R91 [auto] When an agent starts, its new row in the band flashes briefly in its role's colour (about a second), only when the motion setting is full
- R92 [auto] The proof copy shares no writable folder with the working folder: git-ignored files and folders (dependencies, env files) are copied in, as a copy-on-write clone where the file system offers one, never linked; so a tool that refuses linked folders or writes into its dependency folders (for example pnpm 11 recursive runs and its dependency check) behaves in the proof as in the working folder, and nothing a proof does changes the working folder
- R93 [auto] After a proof, VBW checks the working folder for links that point into its proof copies and names each one with how to repair it, so damage left by an earlier VBW is found; with none, it says nothing
- R94 [auto] In one proof, a check waiting for an alone check keeps waiting as long as that check is still running; a proof never aborts because a check waited: a check that cannot run is reported as not run with the reason, every other result stands, and the proof prints no shell job warnings
- R95 [auto] Every agent of a VBW workflow (build, fix, QA, planning) records its own result through VBW (a plan's state, a fix's state, a phase's verdict) even though Claude Code marks a workflow's task text as not coming from the user; in the real Claude Code app a workflow ends with every result recorded and nothing recorded by hand, and the project's test command is named in what QA is told
- R96 [auto] A workflow's closing step (confirm what its agents recorded, then end the run) is done by an agent whose own instructions allow it; it never refuses, and when it cannot finish it says which command to run by hand
- R97 [auto] Choosing Approve in the approval menu approves the contract it names whatever text, spaces or line breaks follow the fingerprint in the question
- R98 [auto] In an autonomous run, while this session's proof or workflow is still running in the background, the stop hook does not ask for that step again and spends no autonomous step on it
- R99 [auto] A fix for a failing project command can commit the files it changed to make that command pass, even when no plan lists them, and the commit names the fix
- R100 [auto] After the plan changes (a new plan, a changed plan or a re-plan), VBW asks for approval only with the approval menu; it never tells the user to type /vbw:approve
- R101 [auto] In the balanced profile the Architect runs on Opus and every other role on Sonnet; QA is never below Sonnet in any profile
- R102 [auto] Planning splits each phase into plans that touch separate files wherever the work allows, so as many plans as possible build at the same time; the approval shows the number of build waves and how many plans the widest wave runs at once
- R103 [auto] When the committed project files are identical to those of the last passing proof (only VBW's own record or spec changed), vbw prove reuses that proof's results for every check and command whose approved definition is unchanged, says so, and runs only the rest
- R104 [auto] A phase is not checked by QA again when the only change since its pass is a recorded decision, a closed finding with no code change, or a removed requirement that only a person judges; a phase whose code, tests, goal or remaining requirements changed is still checked again
- R105 [auto] A phase's rigor tier is not raised by proven requirements it could affect when each of them is guarded by an approved check the proof re-runs; only proven requirements no check guards raise it, and the tier's reasons still list what the phase could affect
- R106 [auto] The Architect is given the next free phase number and proposes phases numbered from it, so planning never needs a renumbering round
- R107 [auto] Each workflow agent runs at the effort its step needs, set per role and step by the profile (lower for closing a run and for documentation, higher for planning and QA), through Claude Code's per-agent effort setting; on a Claude Code without that setting, agents run as before
- R108 [human] The panel's colours make it easy to tell at a glance which agent is which and what state each is in
- R109 [auto] vbw init's notice about detected commands names the approval menu, never the typed /vbw:approve command
- R110 [auto] vbw prove re-runs only the approved checks whose served files (the check's own files and the files of the plans serving its requirement) changed since their last pass, every check that declares no files, and every check whose definition changed; it reuses every other result and says so
- R111 [auto] A project may name a fast variant of its test command for build and fix rounds; vbw prove --full runs every check and the full project commands, and vbw qa record and vbw ship refuse a proof that ran only part of them, saying to run vbw prove --full
- R112 [auto] The interview skill says it runs before any spec or convert work, as the router does

<!-- One requirement per line: an id, how it is proved, and a user-observable
     statement. [auto] = a check can prove it; [human] = only a person can judge it.
- R1 [auto] A visitor can sign up with an email address
- R2 [human] The landing page feels trustworthy
-->

## Commands

- test: bash tools/test.sh
- quick: bash tools/test.sh --quick
