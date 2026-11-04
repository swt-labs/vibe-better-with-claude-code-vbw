# Ideas open for contribution

Ideas for VBW that nobody is building yet. Each one is written for a contributor: the problem, the idea, the questions still open, a rough size and where in the code it would live. Known defects and planned fixes are on [known-issues.md](known-issues.md).

Every idea here is an idea to evaluate, not an instruction to build. The problem is the part to trust; the proposed solution is a first sketch, and a better one is welcome. Some of these may be reshaped or declined once someone looks closely. That is the process, and the first rule in [CONTRIBUTING.md](../CONTRIBUTING.md).

## How to propose or pick up an idea

- **Pick one up.** Open a GitHub issue in [swt-labs/vibe-better-with-claude-code-vbw](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/issues), or comment on the existing one, and say which idea and how you would approach it. For a medium or large idea, agree the design in the issue before writing code. Then follow "Picking up an item" in [CONTRIBUTING.md](../CONTRIBUTING.md#picking-up-an-item-from-the-roadmap).
- **Propose a new one.** Use the [feature request template](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/issues/new?template=feature_request.md). Describe the problem first: what goes wrong, for whom, how often. An idea that helps only one project will be declined, however well it is built.
- **Size** follows [triage](triage.md#the-three-sorts): *small* is a short change in one place, *medium* is several files or one new behaviour, *large* is a feature that needs its own plan.
- Statements about code below were read from the source at the time of writing. Check them before you rely on them.

## Contents

| Idea | Size |
|---|---|
| [A watch for process cost out of proportion](#a-watch-for-process-cost-out-of-proportion) | Medium |
| [Offer CI for the user's project](#offer-ci-for-the-users-project) | Medium |
| [Coordination between sessions on one repository](#coordination-between-sessions-on-one-repository) | Large |
| [Codebase profiles, Rust first](#codebase-profiles-rust-first) | Large |
| [A model profile for judgment-heavy roles](#a-model-profile-for-judgment-heavy-roles) | Small |
| [Choose the sound](#choose-the-sound) | Small |
| [A screenshot kept with a visual acceptance](#a-screenshot-kept-with-a-visual-acceptance) | Small to medium |
| [A status line note for long work outside a run](#a-status-line-note-for-long-work-outside-a-run) | Medium |
| [Are plans split as finely as they safely can be](#are-plans-split-as-finely-as-they-safely-can-be) | Medium |
| [Guards and Claude Code's hook failure setting](#guards-and-claude-codes-hook-failure-setting) | Small |
| [May a read-only run write scratch files](#may-a-read-only-run-write-scratch-files) | Small |
| [Blast radius before a change](#blast-radius-before-a-change) | Medium |
| [Smaller shared kernel files](#smaller-shared-kernel-files) | Large |
| [A shared build cache for proofs](#a-shared-build-cache-for-proofs) | Large |
| [A guide to several sessions on one project](#a-guide-to-several-sessions-on-one-project) | Small |
| [Small fixes for a first contribution](#small-fixes-for-a-first-contribution) | Small each |

## Behaviour and features

### A watch for process cost out of proportion

**Problem.** Nothing in VBW notices when its own process costs far more than the change is worth. A small change can take hours of planning, building, proofs, QA and fix rounds. `/vbw:suggest` fires only when requirements are proposed and when a plan is shown for approval, and offers changes to the work. The loop has a time budget and a spend ceiling; a plain `/vbw:vibe` has neither.

**Idea.** Compare a milestone's elapsed time, spend and number of QA and fix rounds with its size, and tell the person plainly when it is out of proportion, with a cheaper path (a lower rigor, a smaller scope, stopping).

**Open questions.** What is "size" (requirements, tasks, files)? What history is enough to call something out of proportion? VBW already estimates the road ([panel.md](panel.md#time-left)), so "much later than the estimate" is one signal. How often can it speak before it is noise? Where does it speak (Comms, the status line, the router)?

**Size.** Medium.

**Where.** A read-only calculation in `plugin/lib/` beside `road.jq`; the message in `plugin/hooks/panel-lines.js` and the router `plugin/skills/vibe/SKILL.md`; the rules in [rigor.md](rigor.md).

### Offer CI for the user's project

**Problem.** VBW's approved checks run when someone runs VBW. A change made outside VBW, or a project that is about to be shared or deployed, has no continuous integration unless the user already set one up.

**Idea.** Once, when it matters (the project has a GitHub remote and is about to be shared or deployed, or code changed outside VBW), offer one yes-or-no suggestion with the trade-off in plain words: CI minutes and failure emails against catching outside changes and testing on the deploy OS. Yes sets up CI that runs the same approved checks. No is never asked again. Never during the interview.

**Open questions.** Which CI first? How does CI run approved checks without weakening the consent rule (commands from repository files run only after consent recorded in the clone, [record.md](record.md#consent))? What does a CI file look like for a project whose checks are heavy? How does the offer avoid repeating a declined suggestion (`vbw suggest decline`)?

**Size.** Medium.

**Where.** The router `plugin/skills/vibe/SKILL.md` (after a ship) and `plugin/skills/suggest/SKILL.md`; the declined list in `plugin/lib/cmd-suggest.sh`; the CI template as a new file under `plugin/`.

### Coordination between sessions on one repository

**Problem.** Several Claude Code sessions can work on one project. VBW lets one session hold the run at a time, and the Sessions tab lists the chats ([panel.md](panel.md#sessions)). Beyond that the sessions do not know of each other: a session that plans does not see another session's open run or its files, and nobody is told when another session's run ends or a milestone ships.

**Idea.**

1. Planning awareness: a planning step reads the other sessions' open runs and their files from the record and plans around them.
2. Optional notices through Claude Code's peer-session messaging when a run ends or a milestone ships, silently absent where the feature is not available.

**Open questions.** Research first whether this is a good idea at all, and do not build before that discussion. What can go wrong: sessions acting on each other's messages, noise, races, prompt injection from one session into another, and the availability of the messaging feature across Claude Code versions.

**Size.** Large.

**Where.** `plugin/lib/sessions.sh`, `plugin/workflows/planning.js`, the hooks in `plugin/hooks/`.

### Codebase profiles, Rust first

**Problem.** VBW's competence per language lives in four places: the check forms (how a test is named and run), the planner's rules for a red check (it compiles and fails by assertion, never by a compile error), the mutation step (what a break looks like in that language) and the Dev's and QA's prompts (idioms, lints, lockfiles, build identity). Today these are one generic set, with per-project approvals bolted on. A Rust workspace shows the cost: a planned test that does not compile counts as red, a dependency added to one crate misses a workspace lockfile, a clippy gate fails on a planned check, and every plan rediscovers `--locked`.

**Idea.** A *profile* makes each of the four a first-class, versioned unit, selected by the shape of the code, and shipped to everyone as a pack (`vbw init --pack rust`). One kernel, one record, one contract; the profile is chosen per plan by the files it touches, the way Claude Code rules scope by `paths:`. A repository with Rust workspaces beside Python scripts holds two check forms in one contract today; with profiles, a plan over the Rust tree gets the Rust Dev, the cargo forms and the Rust mutation rules, and a plan over the scripts gets the Python ones. Several Devs in one wave each run under their plan's profile, so "many agents, each under the right profile" needs no second kernel or record.

The first Rust profile would hold: check forms for `cargo test -p <crate> --test <name>` and clippy, always `--locked`; the lockfile rule (a dependency added to a crate goes into every workspace lockfile that builds it, in the same commit); a red check must compile and fail by assertion; evidence names the build's commit and lockfile hash; plans cut one crate per plan, with shared registration points (`lib.rs` module lists, enums, `Cargo.lock`) set up once in an early plan; a mutation step that knows Rust targets (a bin, a test, a lib).

**Open questions.** Keep the profile out of the contract's identity: a profile upgrade must not un-approve every plan (compare the amendment work in R250). How is a profile chosen when a plan's files span two trees? What is in a pack and how is it versioned beside VBW itself? Measure before believing: judge the first Rust profile by what it removes from a real project's failure list (a planned test that does not compile, a missing lockfile entry, a clippy gate that fails on a planned check), not by how it reads. A language-specific fork of VBW was considered and rejected: one kernel, profiles as packs.

**Size.** Large.

**Where.** The check forms in `plugin/lib/spec.jq` and `## Test files`; the planner's red-check rule in `plugin/agents/lead.md` and `plugin/workflows/planning.js`; the mutation step in `plugin/lib/cmd-mutate.sh` and `plugin/lib/mutate-queue.sh`; the Dev and QA prompts in `plugin/agents/`; a pack folder under `plugin/` read by `vbw init`.

### A model profile for judgment-heavy roles

**Problem.** The profiles are `quality`, `balanced` and `budget` (`plugin/lib/profiles.json`). A person who wants the strongest model only where judgment decides the outcome, the Architect and the Lead, has to set each role by hand with `vbw config set model.ROLE`.

**Idea.** A fourth profile that gives the strongest model to the Architect and the Lead, Opus or Sonnet to the Devs, and the rest as in `quality`.

**Open questions.** The exact table, decided from the cost data of several real runs, not from a guess. Whether QA at the deep tier belongs on the strongest model. The profile must be named by `/vbw:profile` and the status line. The session model must stay one of the auto-capable ones ([workflows.md](workflows.md#models)).

**Size.** Small.

**Where.** `plugin/lib/profiles.json`, `plugin/lib/cmd-config.sh`, `plugin/skills/profile/SKILL.md`, and the profile docs.

### Choose the sound

**Problem.** The "VBW needs you" sound picks a clip at random from every character folder shipped in `plugin/assets/audio/`. A person who likes one character cannot keep only that one.

**Idea.** Let the person choose the character, or all of them, like the on/off switch: kept in Claude Code's per-user store on their machine, never in the project, set from `/vbw-sound` or the panel.

**Open questions.** The command's shape (`/vbw-sound character NAME`?). What the panel shows. How a person adds their own clips, if at all.

**Size.** Small.

**Where.** `plugin/hooks/panel-sounds.js` (generated by `tools/sounds.sh` from the audio folders), `plugin/hooks/panel-commands.js` and `plugin/hooks/panel.js` for the switch; see [panel.md](panel.md#the-sound).

### A screenshot kept with a visual acceptance

**Problem.** A `[human]` requirement ("the landing page feels trustworthy") is closed with `vbw req accept ID`. The verdict records that someone accepted it, not what they looked at.

**Idea.** When the person accepts a visual requirement, they can attach a screenshot, kept with the verdict.

**Open questions.** Where it is stored and whether it is committed: repository size, and a screenshot can show secrets. The file formats. How a person attaches a file in a terminal session. How Mission Control shows it, if at all.

**Size.** Small to medium.

**Where.** `plugin/lib/cmd-req.sh`, the record's requirement shape ([record.md](record.md)), the acceptance steps in `plugin/skills/vibe/SKILL.md` and `plugin/skills/verify/SKILL.md`.

### A status line note for long work outside a run

**Problem.** The status line says what a VBW run is doing. Long work that VBW did not start, such as a release or a long test run started by hand in the session, looks like idle time.

**Idea.** A short activity note, set while such work runs and cleared at its end, shown in the status line until done.

**Open questions.** Who writes the note: a command the session calls, or a hook? How does it expire if the session dies? It must keep the status line's limits (60 ms, no network, no git process) and must never write `.vbw/record.json` ([statusline.md](statusline.md#engineering)).

**Size.** Medium.

**Where.** `plugin/scripts/statusline.jq` and `plugin/scripts/vbw-statusline.sh`; a runtime note in `.vbw/runtime/`, like `next.json`, written through a `vbw` command in `plugin/lib/`.

### Are plans split as finely as they safely can be

**Problem.** The Lead splits work into plans, and the kernel puts plans into waves; two plans that share a file never share a wave ([workflows.md](workflows.md)). Finer plans can run side by side and finish sooner, but every parallel agent costs CPU and tokens. Nobody has measured whether the split is right.

**Idea.** Measure on several real projects: wave width against time and cost. Adjust the Lead's guidance if the data supports it.

**Open questions.** It interacts with machine load (the heavy-check item on [known-issues.md](known-issues.md)): more parallel agents on a loaded machine may not be faster.

**Size.** Medium. Mostly measurement.

**Where.** `plugin/agents/lead.md`, `plugin/workflows/planning.js`, the wave logic in `plugin/lib/next.jq`.

### Guards and Claude Code's hook failure setting

**Problem.** A guard that fails to start or times out while a run is open must block. VBW does this inside the guard's own command ([guards.md](guards.md#when-a-guard-fails)). A newer Claude Code hook setting, `onFailure: "block"`, would make Claude Code itself block in that case. Check the exact name and the version that introduced it in Claude Code's hooks documentation.

**Idea.** Evaluate using it on the two guards.

**Open questions.** The guards must stay inert outside VBW projects and outside a run, so a blanket `block` is wrong if it applies there. What happens on a Claude Code that does not know the field? How does it combine with the quiet start when `jq` is missing?

**Size.** Small. Mostly a decision, with a test.

**Where.** `plugin/hooks/hooks.json`; `tests/hook-answers.bats`.

### May a read-only run write scratch files

**Problem.** Plan, build and fix runs may write to `.vbw/runtime/scratch/`. A QA or mapping run may write nothing ([guards.md](guards.md)). A QA agent that wants to run an experiment to confirm a finding has nowhere to put the files.

**Idea.** Decide whether QA, and possibly the Scout, may write to a run-private scratch folder.

**Open questions.** QA's job is to change nothing, and that argues against. Its need to probe argues for. Is a scratch folder ignored by git and never read by a proof enough of a boundary?

**Size.** Small.

**Where.** `plugin/hooks/common.jq` (`scratch_path`) and `plugin/hooks/guard-file.jq`; [guards.md](guards.md).

## Speed and tooling

### Blast radius before a change

**Problem.** Some files are read by most test units: a shared test helper, a project's setup file. A change to one re-runs most of the proof, and nobody sees that cost before making the change. Every VBW user with a shared test setup file has the same cost.

**Idea.** The kernel already knows, from the run store, how many units read each file and how long their last runs took.

1. `vbw show reach FILE...` prints, per file, the units that read it and the minutes their last runs took.
2. The Lead's plan, the Dev's brief and the fix brief name the files of the plan that many units read ("read by most units, about 30 minutes per change: make every change in one commit, reviewed before the proof").
3. The approval menu shows the proof cost of the plan's files.

**Open questions.** What counts as "many". How stale the run store can be before the figure misleads. How to say it to a person who does not read code.

**Size.** Medium.

**Where.** `plugin/lib/cmd-show.sh`, the run store in `plugin/lib/proofreuse.sh` and the read lists in `plugin/lib/reads.sh`; the Lead brief in `plugin/agents/lead.md` and `plugin/workflows/planning.js`; the menu in `plugin/hooks/approve-ask.jq`.

### Smaller shared kernel files

**Problem.** Most of VBW's own test units read the kernel entry point (`plugin/bin/vbw`), the four libraries it loads eagerly (`core.sh`, `record.sh`, `consent.sh`, `contract.sh`) and `tests/helper.bash`. A change to any of them re-runs most of the suite, which takes tens of minutes. Those files change in a small share of commits.

**Idea.** Research first, no code. Which functions does each test really use, taken from the run store? Could the pieces load lazily, as the `cmd-*.sh` files do? What is the per-call startup cost against the 20 ms hook budget, and what is the saving per release?

**Open questions.** The benefit is for people building VBW, not for users' projects. Agree the research question in an issue before spending time.

**Size.** Large.

**Where.** `plugin/bin/vbw`, `plugin/lib/core.sh`, `record.sh`, `consent.sh`, `contract.sh`, `tests/helper.bash`; `tools/bench-hooks.sh` for the startup cost.

### A shared build cache for proofs

**Problem.** A proof runs in a clean copy of the committed code, and the copy never carries build output (`target`, `dist`, `build` and others; [proof.md](proof.md)). On a Rust project, every proof compiles from scratch. The same holds for other compiled projects. How much of a proof's time goes to that, against VBW's own work and the tests themselves, has not been measured on a real codebase.

**Idea.** Measure first. Then try a build cache shared between copies, handed to the tool through its standard variable (`CARGO_TARGET_DIR` for cargo, for example), keeping the guarantee that a proof never reads stale output and never writes into the working folder.

**Open questions.** Stale artifacts hiding a break (the mutation check touches files so that cargo and make rebuild them, for this reason). Lock contention when parallel checks share one cache, which needs measuring. Disk use. Where the cache lives: VBW writes nothing outside the project, so it would sit under `.vbw/runtime/`, ignored by git. One variable per tool.

**Size.** Large. Measurement first, then medium.

**Where.** `plugin/lib/proofcopy.sh`, `plugin/lib/checks.sh`; `tools/measure-proof-speed.sh` for measurements.

## Documentation

### A guide to several sessions on one project

**Problem.** People run more than one Claude Code session on one VBW project. How to do it well is spread over several pages: the run lease and "another session holds the run" ([workflows.md](workflows.md)), the Sessions tab ([panel.md](panel.md#sessions)), the shared check limit ([proof.md](proof.md#the-computer-wide-limit)).

**Idea.** One short page, `docs/parallel-sessions.md`: start each session at the project root; give each a different area; say what to leave alone; what "another session holds the run" means and when to choose wait or closed; worktrees against one folder; the shared check limit. Link it from the README.

**Open questions.** It needs hands-on use of two sessions on a real project. The page should say what was tried.

**Size.** Small.

**Where.** `docs/parallel-sessions.md`, a link from `README.md`.

## Small fixes for a first contribution

Each is small and self-contained. Follow the usual rule: the failing test first.

- **An earlier status line that has no refresh interval of its own re-runs every 5 seconds where VBW is off.** The setting is one object for both lines, and Claude Code does not say whether a run is a timer or an event, so the hand-back cannot skip runs. Throttling it would need the last output stored somewhere; the only places VBW may write outside the project are the slot store and the session records. Where: `plugin/lib/cmd-statusline.sh`.
