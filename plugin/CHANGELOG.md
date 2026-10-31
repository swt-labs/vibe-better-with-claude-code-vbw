# Changelog

## [2.1.22] - 2026-10-31

A fourth community release. The guard fix is
[@halindrome](https://github.com/halindrome)'s, and the rest makes VBW's own
checks steady on every machine. Thank you.

### Fixed

- **The guard judges the files shell commands write.** An agent inside a run
  could change a file outside its plan with `cp`, `rsync`, `install`, `ln`,
  `mv`, `tee`, `sed -i` or `rm`, because the guard read only redirections and
  the file tools. It now reads the targets of those commands too, including a
  folder or a glob that reaches a protected check file, and refuses with the
  usual next step. (#727, fixed by [@halindrome](https://github.com/halindrome)
  in #730)
- **The status line no longer loses its answer when the reader stops early.**
  On bash 5.2 (Linux), a reader that took only the first line could cut the
  status line off with a broken-pipe signal, so the first line came back
  empty. The status line now ignores that signal and exits 0. It also keeps
  jq's error text of its last render in `.vbw/runtime/statusline.err`, so a
  status line that cannot render says why.
- **The hook benchmark compares like with like on Linux.** The guard cases
  leave out the shell's and jq's start-up time, but the reference kept it,
  and start-up costs about 7 ms on a Mac against 2 ms on Linux, so Linux
  runners read the guard as too slow. The reference is now measured the same
  way, with a program the guard's size, and the nominal figure was measured
  again. `VBW_BENCH_STEPS=1` prints the guard's cost step by step, and
  `tools/test-linux.sh` can pick the Ubuntu image and run only the benchmark.
- **Steadier tests.** The three waits for a lock without an owner count their
  five seconds on one clock a test can set, the timed waiting test measures
  again before failing and reports a busy machine as busy, and the real-user
  scenarios read a spec section without its HTML comments.

### Added

- **A real-user scenario for projects with a git submodule** (`submodule`):
  a plan whose file sits inside a submodule, judged in git and the record.
  Its first run, on pull request #737, did not pass yet; #737 lands when it
  does.

Sizes, for information: kernel 760 KB (`plugin/bin/vbw` and `plugin/lib`), mods 342 KB (hooks, panel and status line), workflows 73 KB, prompts 109 KB (agents and skills).

## [2.1.21] - 2026-10-31

A third community release. The first four items come from field reports by
[@halindrome](https://github.com/halindrome) on a real project, who also
contributed the map fix; the last two close gaps VBW's own CI runs showed.
Thank you.

### Added

- **The router chooses the project commands from the map's verified ones.** The
  map marks every test and lint command it tried as `ran as of <commit>, <date>`
  or `Not run`. At the spec step the router prefers a command the map ran; a
  whole suite marked `Not run` never enters `## Commands` silently: VBW runs
  it once before planning (its own step) or offers it to you marked unverified,
  and a suite that is red today is named before planning with the narrower
  command as the recommendation. The outcome is recorded as a dated decision.
  A real-user scenario, `mapnotrun`, drives a project with a green test and a
  red end-to-end suite. (#733; two Angular suites the map had not run went
  into a contract and one was red)
- **Suggestions come when a yes is free, and a late yes shows its price.**
  VBW offers its suggestions right after triage adds requirements to the
  milestone, before the first planning run. A suggestion at plan approval that
  would add a requirement states what a yes costs, as the kernel's own estimate
  of a new planning run (`detail.replan` in `vbw next --json`), and offers
  "add to the backlog" (recommended) or "add to this milestone (replan)".
  (#734; 26 of 52 planning minutes in one session were replans after
  approval-time yeses)
- **One mutation run per plan.** `vbw mutate PLAN --run` refuses to start while
  another run of the same plan is still going, with a Next line naming the
  running one, through a per-plan marker in `.vbw/runtime` that a dead process
  does not hold. The Dev's instructions say how to wait for a long run: start
  it in the background and read its result. (#738, the part about two runs of
  one plan; the clean-copy reuse it also asks for is designed on the issue for
  2.1.22)

### Fixed

- **A new map is committed with its own run.** The map run used to end, and
  make its record commit, before `.vbw/map.md` was written, so the map landed
  in the next VBW commit. `vbw run end --map` now takes the map on standard
  input, writes `.vbw/map.md` and then makes the run's record commit, so the
  commit holds the map; it refuses an empty map, a run of another kind and
  another session's run, and then writes nothing. (#731, fixed by
  [@halindrome](https://github.com/halindrome) in #736)
- **The benchmark's reference workload has the shape of a hook call.** It is
  now one jq call over a program and a document of fixed size, written by the
  bench itself, in place of a compute-bound counting loop. The nominal figure
  was measured again for the new shape on the Mac and on GitHub's macOS
  runner, and the larger is pinned. On GitHub's Linux runners the guard still
  costs about one and a half times what the reference predicts, so a slow
  Linux runner can read over budget; the cause is being traced for the next
  release. Nothing changes on macOS. (the 2.1.20 pull request's Ubuntu shard)
- **The mutation-timing test no longer waits on a real second.** The clock the
  timer reads can be injected (`VBW_PROOFTIME_CLOCK`, a test-only file), the
  R207 case asserts figures from injected readings, and no test file outside
  the timed ones asserts elapsed time. (the case failed on Linux runners in
  three CI runs)

Sizes, for information: kernel 759 KB (`plugin/bin/vbw` and `plugin/lib`), mods 336 KB (hooks, panel and status line), workflows 73 KB, prompts 109 KB (agents and skills).

## [2.1.20] - 2026-10-30

A second community release. Every item below comes from a field report by
[@halindrome](https://github.com/halindrome) on a real project; one was
found by VBW's own real-user scenarios. Thank you.

### Added

- **jq 1.7 is the floor, and VBW says so.** Every `vbw` command refuses a jq
  older than 1.7 before doing anything, naming the installed version and how
  to get a current one (the jq releases page; on Debian 12 the
  `bookworm-backports` package); `vbw doctor` reports it the same way and
  still runs its full report, and the hooks and the status line never ask jq
  its version. A maintainer scan refuses jq builtins that differ between 1.7
  and 1.8, and each CI shard prints its jq version. On jq 1.6 the record's
  argv rule rejected every check and one program did not compile; support of
  1.6 was declined. (#709)
- **`vbw init` and `vbw doctor` name the branch VBW commits to.** `vbw init`
  states once that VBW commits its record and the checks it plans to the
  branch checked out, naming it (or the commit, on a detached HEAD), and
  `vbw doctor` shows the branch the next VBW commit lands on. Nothing refuses,
  prompts or adds a setting. (#693; a refusal, a prompt and a branch-guard
  option were declined)
- **The status line hands back outside a VBW project.** With no `.vbw` folder
  at or above the folder Claude Code reports, VBW's status line script prints
  nothing and exits 3, so the setting runs the status line you had before
  `vbw statusline on` and shows its output unchanged; with none saved,
  nothing shows. Inside a VBW project the line renders as before. The
  benchmark measures this hand-back as `status line (no project)` against the
  same 10 ms budget as the turned-off path. (#692; a per-project option was
  declined)

### Fixed

- **The proof's scope check judges a commit against the right record
  version.** The base version is now the last record commit the judged commit
  descends from, found by git ancestry, never by commit time; a record commit
  that shares a second with a plan commit can no longer make the later version
  the base and report a false violation. A regression test pins two commits in
  the same second. (#715; the flaky `scope-of-its-time` case in CI)
- **The benchmarks judge a slow runner as slow, not failed.** The hook and
  status line benchmarks first measure a fixed reference workload on the same
  machine and print it with the ratio to a nominal figure; a case over its
  budget but within budget times ratio is reported slow and the bench exits 0,
  while a case over the scaled budget still fails. The absolute budgets (20 ms
  per hook call, 60 ms status line, 10 ms hand-back) stay the documented
  meaning on a nominal machine; the busy report is unchanged. (#716; the 2.1.18
  and 2.1.19 CI runs failed Linux shards on runner speed with the guard
  unchanged)
- **A check whose test runs a script by path no longer reruns for every new
  root file.** Executing a fresh script (`./greet.sh`) moved the project
  root's listing onto the check's read list through the shell's own start-up,
  so a commit adding an unrelated file at the root reran the check. The
  executed script's folder is left off the unit's own listings; a listing the
  test asks for itself (`ls`, a glob) stays a read. The cause and the limit
  are in docs/proof.md. (found by the `ignoredplanning` real-user scenario)
- **The Now panel's empty state says what it knows.** It reads "VBW is not
  waiting on you" instead of claiming that nothing is needed, and every
  action of `vbw next` that waits on you yields a need in the panel, a generic
  one made from the action's instruction when no case names it. (#708, the
  wording point; the milestone-gate symptom awaits the reporter's data)

Sizes, for information: kernel 755 KB (`plugin/bin/vbw` and `plugin/lib`), mods 335 KB (hooks, panel and status line), workflows 75 KB, prompts 105 KB (agents and skills).

## [2.1.19] - 2026-10-29

A community release: thirteen pull requests by two contributors,
[@halindrome](https://github.com/halindrome) and
[@shacharbard](https://github.com/shacharbard), each from a field report on a
real project. Thank you both.

### Added

- **A decision recorded after the approval reaches the Dev who builds the
  plan.** Each approval now records which plans it changed, and a Dev or Docs
  agent is given every decision since the last approval that changed its own
  plan, so a `vbw decide` made after the contract was approved is applied by
  the build instead of being lost behind a later re-approval. The record
  schema rises to 6 at the first approval after this update; an older VBW
  refuses the record and says it needs a newer VBW. (#714 by @halindrome,
  fixes #705)
- **Planning hands its findings from stage to stage.** The Architect's
  decide and scope steps return what they verified in the code, and the Scope
  and the Lead start from those findings instead of reading the same files
  again; the router passes them back when the user has answered the
  decisions. (#723 by @halindrome, fixes #720)
- **A fix round reproves before it starts.** When the code moved past the last
  proof and a fix of an automatic check or project command is still open,
  `vbw next` asks for a proof before another fix round, so the Dev reads the
  failures of the code as it is now, never a stale list. QA, restore and
  rejection fixes are unchanged. (#712 by @halindrome, fixes #706)
- **Triage checks the code before planning a bug.** A bug the code already
  fixes is reported as fixed at triage, and if it reaches the Architect or the
  Lead anyway, they return it as an already-met requirement for the user to
  drop or reword instead of planning checks that pass today. (#718 by
  @halindrome, fixes #717)
- **The map records the command that runs one test file.** The mapping Scout
  finds, per test framework, the command that runs one file and what a new
  test file needs, runs it once and writes it verbatim, so the Lead reads it
  instead of working it out while planning; a test or lint result in the map
  is dated with its commit and no advice in the map rests on it. The Lead
  proves each check red with that check's own command, once, never by
  rerunning a whole suite while iterating. (#724, #713 and #725 by
  @halindrome, fix #721, #707 and #722)

### Fixed

- **A proof on a large project no longer loads the whole run store for every
  time estimate.** Estimates read a small file of each run's seconds, written
  beside the store; a run that read the project through git keeps no read
  list, which the reuse rule never consulted; and the step lock stays with its
  owner while it works. On a 1,000-test Python project the store had reached
  669 MB and the estimates alone ran the machine out of memory. (#698 by
  @shacharbard, fixes #697)
- **Read lists no longer spread through build output.** Build output a unit
  writes (`__pycache__`, `.pytest_cache`, `bin`, `dist`, `target` and the
  like) is removed before the next unit runs in the same copy, so no unit
  inherits another's read list through it; and git run elsewhere in the
  repository while a unit runs (`git worktree list`, `git branch`, `git gc`,
  another proof making its copy) no longer marks the unit as reading the
  project through git. (#701 by @shacharbard, fixes #699 and #700)
- **On a copy-on-write file system VBW reuses nothing, and says why.** On
  btrfs and XFS with reflinks a copy (`cp`, `cat a > b`, Python's
  `shutil.copyfile`) leaves no trace of reading its source, so a unit that
  copied a tracked file could keep a stale pass. The start-of-proof probe
  now tries such a copy and, where it is not seen, the proof runs every unit
  and names the cause. (#703 by @shacharbard, fixes #702)
- **`vbw prove` works when `.gitignore` ignores `.vbw-planning/` or
  `.vbw/`.** The fingerprint of the project files no longer dies on an
  ignored exclude. (#710 by @halindrome, fixes #695)
- **Panel Timeline rows stay on one line.** The time column has a fixed
  width, long names are cut first, and the bar shrinks, so a label like
  `2 min 12 s` no longer wraps and misaligns the next row. (#711 by
  @halindrome, fixes #696)
- **A test of the mutation timing no longer depends on the wall clock.**
  (#719 by @halindrome)

Sizes, for information: kernel 750 KB (`plugin/bin/vbw` and `plugin/lib`), mods 335 KB (hooks, panel and status line), workflows 75 KB, prompts 105 KB (agents and skills).

## [2.1.18] - 2026-10-27

### Added

- **Four new voices.** The panel's "needs you" sound can now be Eric, Homer,
  Peter or Stephen as well as Arnold, Charlize or Darth: `vbw config set sound
  homer` picks one, `default` plays a random clip of any voice, `off` plays
  none. A wrong name is refused with the list of the voices shipped.
- **The Bash guard stops a program that writes a file it cannot name.** During a
  build or fix (and every other run), an inline program a Dev types (`python3
  -c`, `node -e`, `perl -e`, `ruby -e`, `php -r`, `lua -e`, `deno eval`, `bun -e`,
  or the same fed through a heredoc) whose file-writing call gives its target
  through a variable, an expression or another call is refused, with the call
  quoted and the fix named: write the literal path in the program, or use the
  Edit tool (Write for a new file). A literal path is judged exactly as before,
  and a program that only reads or prints passes. Until now such a program
  could write a protected test file unseen (it happened twice in one build:
  `p = 'tests/x.bats'; open(p, 'w')`). The guard still costs about 13 ms per
  call against its 20 ms budget.
- **`vbw apply` refuses a test check whose case filter names no case.** A check
  that runs `bats --filter PATTERN FILE` is refused when the pattern matches no
  `@test` name in the file as it stands, in every mode, naming the check and the
  file and ending with the next step: write the cases first, see them fail, then
  send the plan again. The Lead's brief now says the failing cases of a filtered
  check are written at planning. Until now such a check was "red" only because
  the runner found nothing, and the Devs had to write the cases during the build
  into files the guard protects.
- **`vbw apply` refuses a check two open plans own, in any order.** The 2.1.17
  refusal covered plans that build one after the other; it now also covers two
  plans that build beside each other in one wave (the first Dev's mutation step
  would run the check before the other Dev committed, a race that fails only
  sometimes). The message says which case it is, and every `vbw apply` refusal
  ends with a Next line of its own, pinned word for word, so none can fall back
  to the generic advice.

### Fixed

- **`vbw mutate` names pending and strengthened files from one definition.** The
  files a break reports as "caught by the pending one" or as strengthened are
  now the files the plan may strengthen (those of its own rules' checks), never
  the files of whatever checks the break happened to run; a check file of another
  requirement that waits for approval no longer appears in either list. The
  queued-break path passed a leftover list of check files that the kernel
  ignored; it is gone. `docs/proof.md` and `docs/record.md` say the same.
- **The loop-writes standard sees a function that writes.** The maintainers'
  check for the macOS bash 3.2 interrupted-write fault now finds the functions
  that print in their own shell, across the repository, and refuses a call to
  one inside a loop fed by a process substitution as it refuses a direct
  `printf`, naming the writer and the line where it prints.

Sizes, for information: kernel 740 KB (`plugin/bin/vbw` and `plugin/lib`), mods 334 KB (hooks, panel and status line), workflows 72 KB, prompts 102 KB (agents and skills).

## [2.1.17] - 2026-10-27

### Added

- **A Dev can strengthen a check that other requirements share.** When the
  mutation step finds a test that cannot fail (a survivor), the Dev strengthens
  the test file. Until now `vbw commit` refused that file when another
  requirement's check also used it, and the Dev blocked. After `vbw mutate`
  records a survivor, the check files that a check of the plan's own rules
  names open for the plan, shared with other requirements or not; a check file
  none of the plan's own rules' checks name is still refused by name. One
  definition of these files (`strengthen_files` in the kernel) is read by
  `vbw commit`, the build lease, the file guard and the proof's scope check, so
  they cannot disagree. The edit waits for the user's one approval before the
  proof, as every check edit does.
- **The whole diff at approval.** `vbw show contract --changes` prints, under
  each changed test file, the whole diff between the approved content and the
  file as it is now, committed or not, every hunk included; when the approved
  content is not in the project's git history it says so in one line. The
  `/vbw:vibe` approval step shows that diff before asking.
- **`vbw apply` refuses two plan layouts that cannot be built.** A check whose
  rules two plans of one milestone own, when those plans build one after the
  other (an `after` link, a chain, or a shared file): the earlier plan's
  mutation step would find the check red on unbroken code (seen twice in M43).
  And a requirement whose rules name an owning plan on only some of them: every
  rule names a plan, or none does, so each rule's owner is defined for `vbw show
  plan` and for the task break. Both refusals name the check or the requirement
  and both plans, and say what to change. The Lead's brief states the two rules.
  A project in the middle of a milestone whose record already holds a mixed
  requirement is refused at its next `vbw apply` until the rules are patched
  (`vbw apply --patch` with `{"rule": "R5.2", "plan": "P1.1"}` on each rule, or
  the plan taken off every rule).
- **A blocked plan keeps its reason.** A full `vbw apply` of a later phase kept
  a started plan's status and recorded breaks but dropped its note (the reason
  it blocked). The note is kept too, and `vbw show roadmap` prints a blocked
  plan's note under the plan.

### Fixed

- **The Clean copy documentation is exact.** `docs/proof.md` quotes `vbw spec
  check`'s missing-path sentence as the kernel prints it and says a listed path
  is one word per line (a path with a space cannot be listed, as for a `Test
  results` folder). The clean copy reads the leave-out list once per copy, not
  once per ignored entry.
- **The Docs agent's survivor rule matched the kernel.** Its prompt still said
  to strengthen only the check file of the rule's own requirement, so a Docs
  plan would have blocked where the kernel now lets it strengthen a shared file.

Sizes, for information: kernel 736 KB (`plugin/bin/vbw` and `plugin/lib`), mods 328 KB (hooks, panel and status line), workflows 73 KB, prompts 102 KB (agents and skills).

## [2.1.16] - 2026-10-26

This release exists because of Shahar, a VBW user from the Discord community,
who wrote a detailed field report of VBW on a real project: the 18 GB ignored
folder copied into every check, the plan hidden by a `*.json` rule, and the
time a mutation run takes. Each point below that cites the field report is his.
Thank you, Shahar.

### Added

- **Leave big git-ignored folders out of the clean copy.** Every proof, fix
  check and mutation check runs on a clean copy of the project with the
  git-ignored files copied in, so the checks find their environment. A project
  with an 18 GB ignored data folder copied it for every check (Shahar's field
  report, 2026-10-26). The spec's new `## Clean copy` section names the
  git-ignored paths to leave out, one per line (`- data/`). `vbw spec sync`
  keeps them in the record, `vbw show contract` lists them (`clean copy leaves
  out: data/`), and every clean copy skips them while every other ignored path
  is still copied in. A listed path inside a folder git ignores as a whole
  (`data/raw/` under an ignored `data/`) is left out too: the folder is copied
  around it, never whole. A path that git does not ignore is refused by name; a
  listed path with nothing at it is accepted, since there is nothing to leave
  out.
- **A line when a plain copy is big.** On a file system without copy-on-write
  clones (ext4 and NTFS under WSL copy byte by byte; APFS and btrfs clone
  instantly), a clean copy that copies more than 500 MB of ignored data prints
  one line naming the largest ignored folders copied, their sizes and how to
  leave them out.
- **`vbw mutate` says where its time went** (Shahar's field report asked where
  the minutes of a mutation run go on a real project). Every mutation run ends
  with the two lines the proof prints: `VBW's own work: X of Y min` and `steps
  of W s: copies A, unbroken B, break R1.1 C, waits D, saving E`, measured,
  summing to the wall. The breakdown never changes a verdict; a refusal,
  `--queue` and `--none` print none.

### Fixed

- **VBW's own plan files are never hidden by a project's ignore rule.** A
  project-wide `*.json` rule in `.gitignore` hid `.vbw/record.json`: VBW's
  commits silently left the plan out and a fresh clone got none (Shahar's
  field report, 2026-10-26). `vbw init` now writes un-hide lines (`!record.json`,
  `!spec.md`, `!map.md`, `!.gitignore`) into VBW's own `.vbw/.gitignore` and
  says so in one line; an existing project gets them at VBW's next commit. A
  rule that hides the whole `.vbw` folder, which no line inside it can undo,
  is named with its source line and the fix by `vbw init`, fails `vbw doctor`,
  and makes `vbw approve` refuse instead of committing nothing. A commit of
  VBW's own files never silently skips one.
- **A Dev no longer blocks on a sibling plan's red check.** When one
  requirement is split across plans, `vbw show plan` listed every rule and
  check of the requirement with no owner, and a Dev read another plan's red
  check as "this plan cannot work" (seen twice in the taskbreak real-user
  run). A rule that names another plan is now marked `[P1.2's, built after
  this plan]` (or `built before this plan`, `built beside this plan`, `done`,
  `blocked`), a check that serves only other plans' rules is marked `[P1.2's:
  red until it is built, not this plan's to pass]`, and the Dev's red-first
  and green steps use only the plan's own checks. The mutation step and the
  listing share one definition of a plan's own rules, so they cannot disagree.
  `vbw show plan --json` gains `plan`, `own` and `order` on each rule and
  `own` and `plans` on each check; nothing is removed or renamed.
- **`vbw doctor` prints its hidden-file lines with no child process alive**
  (the macOS bash 3.2 rule against interrupted writes).

### Changed

- **The README shows the panel at work.** Its screenshot is now the Now tab
  beside a running build; the Plan, Timeline and Settings tabs follow it, and
  [docs/panel.md](docs/panel.md) shows the same.

Sizes, for information: kernel 732 KB (`plugin/bin/vbw` and `plugin/lib`), mods 328 KB (hooks, panel and status line), workflows 73 KB, prompts 102 KB (agents and skills).

## [2.1.15] - 2026-10-25

### Fixed

- **Renaming a test file no longer blocks a milestone for good.** VBW checks
  that each step of the plan changed only the files it was allowed to. It
  judged earlier steps by today's plan, so renaming a check's test file (for
  example to `*.test.tsx`, so the project's tools see it) made an earlier,
  correct step look out of bounds, and nothing could clear it. Each step is
  now judged by what its plan allowed when it was made.
- **You can accept a step that went outside its plan.** When VBW reports
  `abc123456789 (P1.1) changed src/other.txt, which is not in the plan` and
  the change is fine, a decision naming that commit and file accepts it
  (`/vbw:vibe` asks you); before, only rewriting history could clear it.

### Changed

- **Setup tells you how to get VBW updates.** VBW never goes online to check
  for a new version, and Claude Code's auto-update is off by default for
  VBW's marketplace. The install steps and `/vbw:init` now say how to turn it
  on: `/plugin`, Marketplaces tab, `vbw-marketplace`, Enable auto-update.

## [2.1.14] - 2026-10-25

### Added

- **You decide about files changed outside VBW, before any review.** When a
  file VBW built is changed or deleted outside VBW, VBW now asks you first:
  keep the change, or restore it. Keeping records your decision; restoring
  sends the file back through a fix. A fix round never undoes your own edits
  unless you chose that.
- **The Timeline shows a running proof.** While VBW proves your work, the
  panel's Timeline says so, with the checks done so far, and points to the
  Proof tab.

### Fixed

- **Mapping an existing project saves its map.** `/vbw:map` could stop
  before saving the map when Claude Code kept the result in a file; VBW now
  reads it from there.
- **`vbw fix done` with a fix that does not exist** says so and ends cleanly,
  instead of an internal error on newer versions of bash.

## [2.1.13] - 2026-10-25

### Added

- **Choose how hard each helper thinks.** Settings has a new Effort heading
  with one row per helper: `low`, `medium`, `high`, `xhigh`, `max`, or
  `default` to keep the profile's choice. For example, the architect at
  `max` while the docs helper stays light, without changing the whole
  profile. From the command line: `vbw config set effort.dev high`.

### Changed

- **A project with a chosen effort needs VBW 2.1.13 or newer for everyone
  on it.** The choice is shared through git like the model choices. A
  teammate on an older VBW is asked to update VBW instead of being told the
  project is damaged. Projects without one are not affected.

### Fixed

- **A setting's name keeps its gap in Settings** when its choices are wide
  ("your level" no longer runs into its first choice).
- **Proofs reuse earlier results correctly on the night the clocks go back.**
  During the hour that happens twice, a proof could lose track of which files
  each check read, and ran every check again; on some Linux systems it could
  not record them at all.

## [2.1.12] - 2026-10-24

### Added

- **Change how VBW talks to you from Mission Control.** The Settings tab now
  holds your interview answers, with one click each: your level, the wording
  and who makes the decisions, plus whether they stay private to you or are
  shared with your team through git. The first interview still asks them;
  Settings lets you change your mind later.
- **Turn the autonomous run on or off for this chat** from Settings. While it
  runs, the row says which step of how many.
- **See at a glance whether Dynamic workflows are on.** VBW plans and builds
  with them. Settings shows them on in green, or in amber with a `turn on`
  button when Claude Code is left to decide. When they were turned off on
  purpose, Settings says so and leaves that choice to you.

## [2.1.11] - 2026-10-24

### Added

- **Mission Control has six tabs: Now, Plan, Proof, Timeline, Sessions and
  Settings.** Everything is colour coded: each helper by its role, each state
  by its colour. Plan shows the phases with their progress and the decisions
  made. Proof shows every check, passed, failing or running. Timeline shows
  each run with its cost. Each What's next item is one button.
- **Change any VBW setting with a click.** The Settings tab lists every setting
  under four headings: Models, How VBW works, Checks, and Look and sound. The
  current choice is lit; click another and it is saved at once, with
  `✓ saved`. Numbers have `−` and `+`. Each helper's model can be Fable, Opus,
  Sonnet or Haiku (QA never Haiku).
- **Choose the "needs you" sound, or turn it off.** Pick a voice or `off` in
  Settings, or with `vbw config set sound`. The choice is your own copy of the
  project's, never shared through git.
- **A notification when VBW starts waiting for you,** so you can work elsewhere.
- **Something new is marked until you have seen it:** a changed setting, a
  finished run, a new refusal.
- **The status line shows one coloured state:** `● working`, `⚑ needs you` with
  since when, or `✓ idle`.
- **A guide to running several chats on one project:** `docs/parallel-sessions.md`.

### Fixed

- **VBW works in a chat started in a subfolder of the project.** The panel
  stayed closed and the guards stayed off when Claude Code was started inside
  a folder of the project rather than at its top. The panel, the guards, the
  approval hooks and the helpers now find the project from any of its folders.
- **Every time the panel shows names its day** when it is not today.
- **Refusals in the panel are one short line;** a click shows the whole text.

## [2.1.10] - 2026-10-24

### Fixed

- **A loop item's time counts only while the loop works on it.** The time
  budget used the clock since the item opened, so a night with the loop
  stopped, a session that dropped or a turn that ended on an API error could
  stop a healthy item. That time is now left out. Two pauses Claude Code does
  not report still count: a turn you interrupt with Esc, and a computer asleep
  during a step; stop the loop with `/vbw:loop stop` before you leave.
- **`/vbw:loop THE_ITEM` resumes a stopped item.** It was refused because the
  item's milestone was not shipped. It now picks the item up where the loop
  left it, with its budget and its time so far. An item stopped because it
  spent its whole budget is not resumed: finish it with `/vbw:vibe`.
- **A run that lost the shared slot store no longer leaves a slot held** for
  other runs once the store works again.
- **Checks start a little sooner after each other.** Handing over the proof's
  gate costs two processes instead of seven.

## [2.1.9] - 2026-10-24

### Fixed

- **A damaged record is reported as what it is.** A record that was valid
  JSON but had a field of the wrong type (a number where a name belongs) was
  reported as unparseable JSON. VBW now says a field has the wrong type, with
  jq's own description of it.

### Changed

- **Four more features are now checked in real Claude Code sessions, driven
  as a user**: two chats on one project (the holder's name shown and never
  written to the record or git), a task break judged by the plan's own rules,
  a fix that commits its own check files with one approval, and a failing
  check's full output kept and named by `vbw show fix`.
- The guards' documented cost per call is brought up to date: VBW's own CPU
  is about 4 to 5 ms for a file edit and 10 to 13 ms for a Bash command.

## [2.1.8] - 2026-10-24

### Changed

- **Mission Control's Now box tells you the whole step**: what VBW is doing,
  when it started and when it should end. When VBW needs you, it shows the one
  sentence that says what for, the command to type and since when, and the
  Now tab says each fact once.
- **The status line is faster in projects where VBW is off.** Handing back to
  your earlier status line now costs one shell and one `jq` instead of two of
  each, and `vbw statusline on` keeps that line's padding and refresh interval.

### Fixed

- **Mission Control no longer stops working after a failed start.** It tries
  again on your next prompt, question or run. The docs and `/vbw:panel` now
  say when Claude Code opens the pane by itself: in a window at least 144
  columns wide, or 110 once you have opened it yourself.
- **A failing panel hook can no longer leave "VBW has a question for you" on
  screen.** Every hook that waits on the panel now lets the event through
  when it fails.

## [2.1.7] - 2026-10-24

### Added

- **Approved rules can be reworded or retired.** When later work changes what
  an earlier requirement said, the Lead can now name the old rule by its
  address (`R1.2`, as `vbw show req R1` numbers them) and give it new words or
  retire it with a reason, in any milestone, a shipped one included. Before,
  new wording only added a second rule beside the stale one. The change goes
  through your approval like any other contract change, and a retired rule
  stays visible with its reason.
- **You see every refusal, not only Claude.** When a guard blocks a call, you
  get a one-line message from Claude Code beside the reason Claude reads. When
  VBW refuses something inside a workflow, the agent reports it word for word,
  and Comms and Mission Control show it in amber with its time and next step.

### Fixed

- **QA no longer calls interleaved phases a cycle.** Phases whose plans build
  on each other in both directions are legitimate; QA now notes them, and
  still reports a real cycle between plans as a problem.
- **A setting you state in words at the start of a new project is kept.**
  Saying "work guided" before the project existed could be lost, because the
  setting was written before `vbw init` and refused. VBW now records it right
  after the project is set up.

## [2.1.6] - 2026-10-24

### Changed

- **Heavy test commands share the computer's cores.** When several checks run
  side by side, each check's command now gets its share of the cores through
  the settings build tools read (`CARGO_BUILD_JOBS`, `GOMAXPROCS`,
  `MAKEFLAGS=-jN`); a check that runs alone gets every core. A project whose
  checks each started a full parallel build no longer runs many such builds
  at once. Values you already set are kept.

### Fixed

- **Two runs no longer write the proof's step times at the same moment.** The
  lock around that note could be taken from a run still writing it, after a
  few seconds' wait; it is now taken over only from a run that has died.

## [2.1.5] - 2026-10-24

### Changed

- **A long proof says why before you wait for it.** The proof's first line
  counts the checks that run again and names the main reasons, and VBW's
  sentence for the proof step ends with the top one, so you know at once
  whether a proof will take a minute or an hour.
- **A loop item's time budget follows its planned work.** The budget was set
  from the size label guessed before planning. Once the road is planned, the
  budget is twice the time spent so far plus the planned road, at least 30
  minutes, and the loop's report names what it was based on.
- **Unit times are measured to a tenth of a second**, so quick checks no
  longer all read "0 s" or "1 s".
- **`vbw mutate --none` names what it cannot see**: a check that only tests
  whether a plan's file exists is not caught by it.

### Fixed

- **Time estimates no longer absorb a run left open overnight.** A step that
  sat idle for hours counted as work and could ruin the build and proof
  estimates for days. A step far longer than its kind usually takes is now left
  out of the estimates.
- **Runs that share the computer hand slots and locks over faster and more
  safely.** A lock left by a run that died is taken over by exactly one run, a
  folder that refuses new files is reported at once instead of after 30
  seconds, and a freed slot still goes to the waiting run that holds the
  fewest.

## [2.1.4] - 2026-10-23

### Fixed

- **Commits from an earlier roadmap no longer block the proof.** A project that
  started a new VBW record (after VBW 1, or after removing `.vbw/`) has older
  commits whose trailers name plan ids the new record uses again. The proof
  judged them against today's plans, reported them as out of scope and listed
  their files as delivered work changed by hand, and nothing short of rewriting
  history cleared it. VBW now reads only the record's own history: the commits
  made since `.vbw/record.json` was first committed. The same rule applies to
  `vbw plan done` (an old commit no longer counts as a plan's commit), to the
  commits `vbw show` lists for a requirement and to the loop's report. Nothing
  to do: the next proof judges only your record's commits.

## [2.1.3] - 2026-10-23

### Fixed

- **A new or deleted file no longer re-runs every check.** When a file was
  added or deleted that no recorded check run had read or listed the folder
  of, the proof ran everything, "because a check could now see a different set
  of files". No check could: a check sees a file by listing its folder (VBW
  records the listing), by reading it, or through git (always re-run). Two
  images added to a README cost a full check run of every unit. Such a file
  now re-runs only the units that could see it, as every other change does,
  and the checks of the requirement whose plans list it: a check may test
  whether a path exists without opening it, and the contract knows what each
  requirement's plans deliver. A path outside those plans that a check only
  tests for is the documented limit it always was.
- **A proof cut short no longer re-runs every check next time.** An
  interrupted proof saves nothing, or complete per-unit results, so the next
  proof reuses what the read lists allow, as if the interrupted one had not
  run. The unfinished-proof marker file is gone.
- **Proof time estimates no longer inherit a busy day.** The estimate summed
  each unit's last recorded seconds, taken under whatever load the machine had,
  and multiplied by the median wall-to-unit ratio, which one 3-unit proof could
  pull to 22. It promised 200 minutes for a proof that takes about 45. Each
  unit now counts the fastest it ran in the latest 10 proofs or in its last
  run, and the ratio is those proofs' total wall time over their total unit
  time; a proof that runs late still moves its end as it goes.

## [2.1.2] - 2026-10-23

### Fixed

- **What's next is never out of date.** A recommendation stayed until a new
  one replaced it, so after milestones shipped without one, Mission Control
  could show a pick from weeks ago. Shipping now retires it: What's next offers
  Suggest next until VBW recommends again.
- **"Waiting since" shows when VBW really stopped for you.** It restarted from
  every Claude Code restart, so a wait of days could read as minutes. VBW now
  keeps the time it first reached the stop, in every session.
- **A changed plan is called a changed plan.** When a plan you had approved
  changed (a requirement reworded, a test file edited), VBW said "the plan is
  ready: review it, then approve it to build", even with the work already
  built. It now says the plan changed since you approved it and shows just the
  changes.

## [2.1.1] - 2026-10-23

### Changed

- **The plan tells you why a plan waits.** When you approve, VBW already said
  how many rounds the build takes and the most plans built at the same time.
  It now also says, for each plan that has to wait, what holds it back: it is
  planned after another plan, or both would change the same file, for example
  `P1.4 waits for P1.2 (both change src/x.js)`. If you would like more built
  at once, answer "Not yet" and ask for the split. Thanks to a community
  developer for the idea.

### Fixed

- **Large projects no longer lose an hour per plan in break testing.** Before
  and after each deliberate break, VBW finds the newest file in its clean copy
  of the project, so build tools notice the change. It used to check every
  file one at a time, dependencies included: about 10 minutes per pass on a
  project with 111,529 files. It now reads them all in one pass, about a
  second for 100,000 files. Thanks to the community developer who measured
  it and found the cause.

## [2.1.0] - 2026-10-21

The first VBW 2 release for the community. VBW gives Claude Code an executable
definition of done: you approve what to build, VBW writes the checks that prove
it, builds in parallel, proves every check mechanically, and asks you only what
checks cannot judge. How it works is in the [README](../README.md); coming from
VBW 1, `/vbw:convert` brings a `.vbw-planning/` project over through a short Q&A
([docs/convert.md](../docs/convert.md)). What is known to be missing or planned
is in [docs/known-issues.md](../docs/known-issues.md), and ideas open for
contributions are in [docs/ideas.md](../docs/ideas.md); see
[CONTRIBUTING.md](../CONTRIBUTING.md) to take one on.

### Changed

- **Comms says when a message began.** The step line and the weekly-limit
  line start with the time their message began, for example
  `[14:32] building P1.1 · about 12 min, until around 14:44`; on a narrow
  window the text is cut, never the time.

### Fixed

- **The tools offer is always asked.** VBW asks once whether it may look for
  tools, even when you chose "decide and tell me": it is your consent to a
  search and to installs, so VBW never answers it for you.
- **A file that changed outside VBW is left to QA.** When a proof finds a
  delivered file changed or missing, VBW tells you in one line and lets QA and a
  fix round restore it (or records your decision), instead of repairing it
  itself.

## [2.0.44] - 2026-10-21

### Added

- **QA checks that delivered files are still there.** Every proof now notes
  any file a plan of the current milestone delivered that changed or went
  missing outside VBW (a hand edit, a delete, a revert, a merge). Its phase goes
  to QA at every rigor tier, QA is told which file, and `vbw qa record` will not
  record a pass while it stands. A change you want kept is recorded once as
  your decision; `/vbw:fix` and `/vbw:debug` record it for the files they
  change.

### Changed

- **Faster proofs.** A proof prepares all its units in one pass, collects their
  results in one pass, and starts the next unit as soon as a slot frees. On a
  200-unit project a proof took 40 s instead of 48 s, with about half the
  helper processes.

### Fixed

- **A killed test run could take an earlier check's result** and keep its slot
  in the computer-wide limit. Each run now keeps its results apart.
- **Step history order:** steps that end in the same second keep their order,
  so the time estimates read them correctly.

## [2.0.43] - 2026-10-21

### Changed

- **A lighter panel.** A refresh of Comms and Mission Control does less work:
  the config folder is found once per session, a transcript's start time is read
  from its first timed line, the tab strip is laid out once per width, and the
  view is no longer built twice. Drawing is unchanged (pinned by a test of what
  the panel draws).

### Fixed

- **Two proofs at once are no slower than one.** A freed slot of the
  computer-wide limit now goes straight to the next waiting unit, and waiting
  units no longer hold the slot store's lock while they wait. On a 200-unit
  project two proofs together took 77 s against 79 s for one (they took four to
  six times one before).
- **No lost output on macOS.** macOS `/bin/bash` 3.2 does not retry a write
  that a finished child interrupts, so `vbw check` and other commands could stop
  mid-output with "Interrupted system call" when their output went to a pipe.
  Every such write now runs where no child can interrupt it, and a check keeps
  the pattern out.

## [2.0.42] - 2026-10-21

### Added

- **VBW tells you when it was updated.** The first session after an update
  says so once and offers `/vbw:whats-new`. VBW still makes no network call;
  `/vbw:doctor` says whether Claude Code's auto-update is on for VBW's
  marketplace and how to turn it on ([docs/update.md](../docs/update.md)).
- **Every proof names its slowest tests.** `vbw prove` and `vbw fix done`
  print the three slowest units and their share of the time; `vbw show
  evidence` lists the ten slowest and every unit over the new `check_budget`
  setting (seconds per unit, default 120). It reports and never fails a
  proof. `vbw ship` says how the milestone changed the total test time.
- **Rule breaks can run side by side.** `vbw mutate PLAN Rn.k --queue` sets a
  break aside and `vbw mutate PLAN --run` runs the queued breaks at once, each
  in its own clean copy, under the computer-wide limit.

### Changed

- **Lean tests by default.** The Lead writes one test file per requirement
  area, builds expensive fixtures once per file, avoids sleeps and timing
  assertions, and replaces the cases a new requirement supersedes instead of
  stacking new ones. A fix's regression test goes into the existing file. QA
  notes a slow test, never fails a phase for it.
- **The mutation check asks one break per rule** at standard and deep, plus a
  task break only where no rule's check covers the task.
- **Build estimates time a wave by its slowest plan**, counting the breaks,
  so the "until around" times run late far less often.
- **`vbw fix done` runs nothing while test files wait for your approval**: it
  names them and says the approval comes first, instead of starting a long
  run that could not count. It needs an approved contract only when
  something will run.
- **Costs are measured in dollars only.** Claude Code's token fields describe
  the last request, not a running total, so a run could show an unknown cost
  and a compaction could over-count spending; both are fixed.
- **A small change keeps its quick QA check**, and a small documentation plan
  is built by the Docs agent, when VBW plans the request itself.
- **Faster status line** on the paths that go through Claude Code's setting
  (about 10–15 ms less per refresh). The status line setting is rewritten once
  at the next session start.
- **Proof bookkeeping**: VBW's own work in the report counts every step; the
  causes of a re-run are bounded (a 3,000-file drop is one line); the run store
  forgets units that no longer exist; the cached unit list follows the git index;
  the scope check reads long histories in seconds.

### Fixed

- **macOS with jq 1.8.2 (Homebrew):** every VBW guard crashed, which blocked
  every tool call during a run.
- **jq 1.8:** the hint to name a chat never showed.
- **Linux with non-atomic `mkdir` (Ubuntu 26.04):** two processes could take the
  same lock, and a run could wait for itself.
- **Very large projects:** `vbw prove` and `vbw fix done` could stop with
  "Argument list too long".

## [2.0.41] - 2026-10-20

### Added

- **Every proof says where its time went.** `vbw prove` and `vbw fix done`
  print two lines: how much of the run was VBW's own work (planning, clean
  copies, read tracking, saving, the record), and how many units ran again
  with the top three reasons. `vbw show evidence` gives the full split and,
  per unit, why it ran or which proof it reused.
- **A rule with no code to break can pass the mutation check.** When a rule's
  check judges only what the record holds (a measurement kept as a decision),
  `vbw mutate PLAN Rn.k --none REASON` is accepted, but only after the kernel
  confirms from the check's recorded read list that no file of any plan of the
  requirement could change its outcome.

### Changed

- **Proofs on large projects cost seconds, not minutes.** Read tracking runs
  in a fixed number of processes however many folders a test lists, resets
  only the files the last run read, and walks each copy once; the written-file
  store keeps each read list once. Reuse planning and saving run in batches.
  On a generated 5,000-file, 200-unit project on a Mac, VBW's own work in a
  full proof fell from 142 s to 56 s and read tracking from 122 s to 48 s.
- **`vbw next` answers in seconds on a large project.** It keeps the proof's
  unit list in `.vbw/runtime/proof-units.json` and works it out again only when
  the commit, the record or the run store changes (31 s to 3 s on the same
  project).
- **VBW's own work counts in the computer-wide limit.** A test's slot covers
  its read tracking, and the proof's planning, copies and saving take slots
  (`vbw:plan`, `vbw:copies`, `vbw:save`). `vbw next` never waits for one.
- **The scope check skips work that was exactly undone.** A commit that a
  later commit exactly reverses (checked by git, file by file, whoever made
  it) is no longer blamed on a plan; a partial or edited undo still is. The
  proof lists what it skipped, and the check reads the history in one pass.
- **`vbw fix done` needs an approved contract** even when nothing has to run
  again.

## [2.0.40] - 2026-10-19

### Added

- **Every long step says when it should end.** Planning, builds, proofs, QA
  and fix rounds name what they are doing and a clock time for their end, in
  the status line, the panel and VBW's messages. The time comes from how long
  the same work took before in this project, per unit of work at its rigor
  tier, times the work's size.
- **The whole milestone has an end time too.** VBW adds up the build, the
  proofs, QA and the fix rounds usual in this project, and shows when the
  milestone should end in Mission Control and its messages.
- **You see who holds the run, by name.** The run remembers the session that
  started it by its Claude Code session name. The status line, Comms and
  `vbw next` say who leads, and the new Sessions tab lists every chat working
  on the project, marks the one holding the run and gives its resume line.
  `/vbw:vibe` may suggest a `/rename` once; it never renames for you.
- **Failing output is kept.** After `vbw prove`, `vbw fix done` and
  `vbw check`, a failing check or project command keeps its full output under
  `.vbw/runtime/output/`. `vbw show fix` names that file and the failing tests
  (bats, pytest, cargo, go, jest, vitest, mocha), so nobody reruns the suite to
  see what failed.

### Changed

- **A task break judges a plan by its own tests.** Without `--check`, a task
  break runs the checks of the rules the plan owns, so an early plan whose
  requirement a later plan completes can still break its tasks.
- **A fix can commit its own requirement's test files.** `vbw commit --fix`
  takes the protected check files of the fix's own requirement, with trailers
  naming the fix and the requirement. They still wait for your one approval
  before the proof, and every other protected file stays closed.
- **The mutation check rebuilds what it breaks.** The broken file and its
  restore get a modification time newer than any build output, so cargo or
  make rebuild them and a break is never reported as surviving because of a
  stale build. When only a test file waiting for approval catches a break,
  `vbw mutate` says so.
- **Comms and the panel show only what is true now.** A message disappears as
  soon as it stops being true, the sound plays once per question when the
  question is on screen, and Mission Control's Now tab shows what is running
  and what is new.

### Fixed

- **No lost record updates under heavy load.** The record lock now names the
  process holding it. A waiting command takes the lock over only when that
  process has ended, or after 10 minutes, and never from a holder that is
  still writing, so many VBW commands at once no longer overwrite each
  other's changes.
- **The pane's tabs fit at every width.** With eight tabs, the tab names no
  longer split across lines or spill down the pane's right edge: the tabs sit
  in whole rows, full names where they fit, and the portrait gives way before
  a name does.
- **Comms keeps its helper line in a short window.** With one row, Comms shows
  the helpers at work and the step's end time on that row.
- **Say the autonomy you want.** "Use guided autonomy" (or balanced, or
  hands-off) in your words to `/vbw:vibe` is recorded before the first step.
- **Session start is quick again.** The session-start hook asks the kernel
  once for where the project stands, instead of twice, so a new session no
  longer waits about half a second longer than it needs to.

## [2.0.39] - 2026-10-15

### Changed

- **The mutation check is cheap on slow test suites.** A break with several
  checks runs them one at a time, fastest first by their last recorded time,
  and stops at the first that catches the break. Each check runs on the
  unbroken code only when an earlier break at the same commit has not already
  done so. A project whose tests take minutes now pays for the checks a break
  needs, not for every check on every break.
- **Each plan breaks its own rules.** When several plans serve a requirement,
  the Lead names the plan that builds each rule's code, and that plan cannot
  finish until its rules have a break the tests caught. A later plan no longer
  inherits rules it cannot break.

## [2.0.38] - 2026-10-15

### Changed

- **No shortcuts in plans.** The Architect and the Lead choose the best
  long-term design, never the merely safe or simple one, and name any cost or
  debt they accept. QA fails a phase that pays a recurring cost (time, tokens,
  re-runs) instead of the better design, or leaves a cost unnamed.
- **Builders see your later decisions.** A decision recorded after you
  approved the plan reaches every Dev and Docs agent of a build or fix round
  (`vbw show decisions --since-approval`) and wins over the plan.
- **A wait behind another VBW command is told.** When another `vbw` command of
  the same project holds the checks, `vbw check`, `vbw prove` and `vbw mutate`
  end with the same "waited N s" line as a wait for the computer-wide limit.

### Fixed

- **Read tracking on fast machines.** The check that the file system records
  reads could pass when it should not on a fast Linux machine; it now asks
  whether the set-back times took, by their age.

## [2.0.37] - 2026-10-15

### Added

- **Tests are checked for real.** At standard and deep rigor, the builder of
  each plan breaks its own code on purpose, once per rule (and at deep, per
  task, error and edge case), with the new `vbw mutate`; VBW runs the plan's
  checks on a private copy and records whether they noticed. `vbw plan done`
  waits until every rule has a break the tests caught. A test that let a break
  through is strengthened in place and waits for one approval before the proof
  (under `/vbw:loop`, the loop approves it for you and records it). `vbw show
  plan` lists the rules and every break. Nothing changes at express rigor.
- **A loop item has a time budget.** Twice the usual time of past items of its
  size, or 2, 4 or 8 hours for small, medium and large when there is no
  history. Past it, the loop stops before the item's next step, keeps the work
  and tells you where it stands. `vbw loop status` shows each item's time.

### Changed

- **Only behaviour blocks a phase.** QA fails a phase for wrong or missing
  behaviour, a test that cannot fail, a deviation from the plan, or a document
  that states a false fact. Wording, style and naming are notes in its summary
  and never start a fix round.
- **QA re-checks only what changed.** A phase that failed QA is checked again
  on its fixes, the files they changed and its goal, not swept whole again. A
  phase is re-checked because of a phase it builds on only when that phase's
  tests changed.

### Fixed

- **A loop survives a resumed session.** The step that drives a loop is now
  the plugin's own, so it keeps working after `claude --resume`, and it runs
  once per turn: a loop no longer opens an item twice. For a loop started
  before this version, run `/vbw:loop` again in its session.
- **Giving up on an item never leaves the project unreadable.** When the loop
  sets an item aside, it updates its record before it undoes the item's work.
- **Changing a plan keeps its recorded breaks.**
- **Ctrl-C stops a proof at once on Linux.** Before, it waited for the running
  checks to end.

## [2.0.36] - 2026-10-14

### Added

- **Runs take turns on your computer.** Every VBW run on one computer, in any
  project or session, shares one limit: about three quarters of the processor
  cores, at least 1 and at most 64. Each check, project command and test file
  takes one slot while it runs; a run that finds none free waits its turn, and
  a freed slot goes to the run holding the fewest. A run that waited ends with
  `waited N s for other VBW runs on this computer (limit L of C cores)`, and
  `vbw config` shows the limit. `check_jobs` stays a per-run cap below it. The
  shared count lives in `<Claude config folder>/vbw/slots.json` and is removed
  when nothing runs; if it cannot be written, a run goes on under `check_jobs`
  and says so once. Results never change because of waiting. See
  docs/proof.md, "The computer-wide limit".
- **`vbw --version`**, and `vbw doctor` now shows which `vbw` your session runs
  and whether it is the loaded plugin's, with the fix when it is not.

### Changed

- **A fix round checks its work once.** The Devs of a fix round commit and
  check their own fixes; one `vbw fix done` for every finished fix runs after
  they all return, so no check runs twice in a round. On a three-group test
  project a round went from 0.72 to 0.40 minutes and from 18 checks to 6.
- **Closing a run uses the smallest model.** The step that ends each workflow
  run (confirm, end, and a fix round's `vbw fix done`) runs on Haiku in every
  profile, whatever model the Lead uses.
- **A project where you turned VBW off shows no VBW.** The status line there
  shows your own earlier status line, or nothing if you had none; an older
  VBW status line setting updates itself at the next session start.
- **Your working copy runs its own kernel.** With `claude --plugin-dir`, the
  loaded copy's `vbw` comes first for the session and its agents, the status
  line shows its version, and the session's first line names the kernel. See
  CONTRIBUTING.md, "Local development".
- **Leftover proof copies are cleaned up.** A proof or `vbw fix done` removes
  copies left by a run that was killed, and leaves running ones alone.
- `/vbw:config` says the computer-wide limit caps `check_jobs`.

## [2.0.35] - 2026-10-13

### Added

- **The loop: a night shift that works through your backlog.** `/vbw:loop T4
  T7 --ceiling 20` (or `--ceiling 20 --finish-item`, or `--no-ceiling`) takes
  the named todo items in order and, for each, opens a milestone, plans,
  approves the contract on your behalf only when it is exactly the item you
  named (recorded as the loop's own decision and commit, the project commands
  and the test-file form included), builds, proves, fixes, verifies and ships.
  A `[human]` requirement is skipped for you to judge and stays listed until
  you do. The loop stops at the ceiling, at the end of its list, on
  `vbw loop stop` from any session, or when a step needs you; a contract not
  ready yet (a check file not written) is handed back to the session once.
  `vbw loop status` shows the items, the spend and the ceiling from any
  session. A ceiling needs cost figures, which the VBW status line provides
  (`vbw statusline on`); without any figure the loop stops before its first
  step, unless you chose `--no-ceiling`. See docs/loop.md.
- **Retry once, then park.** A fix escalated or a plan blocked a second time
  parks the item: its commits since the item began are reverted with revert
  commits (one touching a file you staged or edited, one that changes code and
  a `.vbw/` file together, or one that does not revert cleanly is left in place
  and named), its requirement, plans and checks leave the record and the spec,
  the milestone is marked `parked` with its cost frozen, the backlog entry
  stays open, and the loop goes on to the next item. `vbw loop park` does the
  same by hand.
- **Nothing leaves the project while a loop is on.** The Bash guard denies
  `git push`, releases, publishes and deploys (gh, npm, cargo, docker, heroku
  and the like, in any spelling, with a redirect glued to the word too) for
  every caller, the main session included, with a pinned text. Outside a loop
  a plain `git push` by you stays allowed.
- **The loop report.** `.vbw/loop-report.md` is written at each item's end
  and at the loop's end: what shipped with its commits, what was parked and
  why, what waits for you, and what each item cost. `vbw show costs` prices a
  parked milestone by its frozen total, or unknown when no figure was seen.

### Changed

- **A QA finding belongs to the phase whose QA found it** (`vbw qa finding
  PHASE REQ TEXT`; a finding given without the phase is adopted by that
  phase's fail verdict). A verdict changes only its own phase's findings, so
  phases that share a requirement can be verified in parallel without closing
  each other's findings.
- **A project command or test-file form changed after the contract's
  approval is approved on its own**, with its decision (`Project commands
  approved: ...`) and its commit, by you or by the loop. A consent is never
  granted without its decision.
- **A parked milestone is left behind like a shipped one:** `vbw next` asks
  for the next milestone, the parked one keeps its name, and `vbw status`
  lists it.
- The Bash guard reads a redirect glued to a word (`cmd>out.log`) as the shell
  does, so every rule that reads a command's words or its redirect targets
  sees them.
- For contributors: the plugin size cap test is gone (VBW grows as it needs
  to); the loop's state (`loop`, `parked`, a fix's `phase`) is documented in
  docs/record.md.

## [2.0.34] - 2026-10-12

### Added

- **What a run and a milestone cost.** With the VBW status line on, each
  session's spend (dollars, tokens in and out, from the figures Claude Code
  gives the status line) is noted in `.vbw/runtime/cost.<session>.json`. Every
  `vbw run end` records the run's cost in the record; a run VBW saw no figures
  for, or whose figures went down, is recorded as unknown, never as zero or a
  negative number. `vbw milestone start` notes where each session stood and
  `vbw ship` freezes the milestone's total, so a dollar counts in one
  milestone only. `vbw show costs` prints every milestone and every run's
  share in plain words, `--json` returns one object and `--ceiling USD` judges
  the active milestone's known spend (exit 0 under, 1 reached or cannot tell,
  2 for a bad number). See docs/costs.md.
- **One scratch folder for agents.** During a run, VBW's agents write only
  inside the project: a write to `/tmp` or to any path outside it, by a file
  tool, a shell redirect or an inline program, is refused and the refusal names
  where the run may write. A path the guard cannot resolve (one starting with
  `~` or holding a shell expansion such as `$HOME`) counts as outside.
  Debugging scripts and logs go in `.vbw/runtime/scratch/`, which plan,
  build and fix runs may write and git ignores; a read-only run (QA, mapping)
  writes nothing.

### Changed

- **"Nothing was committed since the last passing proof" means nothing at
  all.** That cause of a full proof fires only when the code, the contract
  and the record are exactly as the last passing proof left them: a recorded
  decision, a verdict or a backlog item is a change, and the next proof then
  reuses what the read lists allow. It never reads a commit message.
- **`vbw fix done` says what it ran and what it reused**, one line per check
  and per test file with the reason it ran, then the same two count lines a
  proof prints. The test files it ran are saved in your clone, so the proof
  after it reuses them.
- **Approval compares every section of the spec with the record**, the Test
  results list included: an edited list that was not synced cannot be approved
  as the record's list.
- A run's id is its kind and its start second (`qa-20260101T120000Z`); a second
  run started in that same second gets a numbered suffix, so no two runs share
  an id.
- For contributors: every check and project command of a proof runs without
  the proving session's `VBW_SESSION_ID`; the release benchmark feeds the status
  line cost figures, so the side-file write is measured.

## [2.0.33] - 2026-10-11

### Fixed

- **No approval question for a contract that approval would refuse.** While a
  check file is still missing or the spec and the record differ, `vbw next`
  says the contract is not ready, names each problem and the step that fixes
  it, instead of asking you to approve. The question comes once approval would
  succeed.
- For contributors: the test helper leaves the repository before its git
  calls and turns off background git work; no test runs bats on a bats file it
  wrote (that lost a test on Linux CI).

## [2.0.32] - 2026-10-11

### Changed

- **Proofs run only what a change can reach.** Every `vbw prove`, the full
  proof before QA and shipping included, re-runs a check only when a file it
  read or a folder it listed has changed since its last pass, and reuses every
  other passing result, naming the proof it came from. VBW learns what each
  check reads by running it in a clean copy of the committed code and keeps
  those read lists in your clone (`.git/vbw/runs.json`), never in the record.
  When VBW cannot know what a change reaches, it runs everything and says why
  (a new file no recorded run read, a proof that was cut short, a file system
  that does not record reads, ...). Every summary prints how many checks and
  test files ran and how many were reused.
- **One test file at a time.** When your test runner can run a single file,
  declare it in `.vbw/spec.md` under `## Test files` (`- run: bats {file}` and
  `- files: tests/*.bats`); the Lead proposes it when planning and you approve
  it with the contract. Your test command then runs as one unit per test file,
  so a change re-runs only the files it reaches.
- **Fix rounds add their own regression tests.** After a QA finding, the fix
  may create new test files and register them as checks of the finding's
  requirement (`vbw fix check FIX`); edits to an approved check file wait for
  one approval from you before the proof.
- **Judge it later.** A `[human]` requirement you are not ready to judge can be
  skipped ("Skip for now" in the acceptance menu, `vbw req skip ID`); when
  skipped requirements are all that holds up shipping, they move to the next
  milestone with their id, checks and history.
- **Plans change without surprises.** A milestone can re-plan a requirement it
  reopened from a shipped milestone; a new phase can sit beside a started phase
  for more work on the same requirement; an unstarted phase can change its goal
  and criteria; a re-plan never raises the tier of a phase that has started;
  and every refusal while a plan changes ends with what to do instead.
- **`--help` on every command.** `vbw CMD --help` (or `-h`) prints that
  command's usage and changes nothing.
- **Guards fail closed.** During a VBW run, a guard that crashes, cannot start
  or times out blocks the action it guards instead of letting it through.
  Outside VBW projects nothing changes.

### Fixed

- A test-file form with nothing left to run (every file it matches already
  runs as an approved check) no longer records a nameless unit: the proof
  counts the test command as covered by those checks and says so; a form that
  matches no committed file fails the test command and names the pathspecs.
- `vbw fix done` right after a passing proof reuses that proof instead of
  re-running every check: "nothing committed since the last passing proof"
  makes only a second `vbw prove` run everything.
- `vbw apply --add` refuses a phase id that already exists in any milestone,
  and a requirement that an unstarted phase of this milestone already covers
  (change that phase with a full apply instead).
- `vbw req skip` is listed in `vbw --help` and `vbw req --help`, and the panel
  names it.
- `vbw next` no longer prints "ignored null byte in input" under bash 5 while
  a check a fix added waits for approval.
- The ship row of the `vbw next` decision table in docs/next.md renders.

### What you need to know

- **The first proof after this update runs everything once** (your clone has
  no recorded runs yet). From then on, proofs reuse what a change does not
  reach. A clone on a file system that does not record file reads runs
  everything every time, and the summary says so.
- For contributors: `bash tools/test.sh --lint` runs the shellcheck stage
  alone; the release run (`--release`) adds only the timed speed checks and
  the benchmarks when a passing proof already covers the same code, results
  it reused included.

## [2.0.31] - 2026-10-10

### Changed

- **Lighter fix rounds.** When a fix after QA changes only documentation, the
  next full proof reuses the earlier passing run of your test command instead
  of running it again, and says so. Any change to code, tests or a check's
  files still runs it.
- **VBW sizes itself to your machine.** By default it runs about three
  quarters of your processor cores' worth of checks at once (at least one),
  instead of 4 everywhere, and Devs or fix groups working at the same time
  share that one limit. Fix groups share one run of your test command.
  `vbw config set check_jobs N` still overrides it.
- **More time for your test command.** `vbw prove` now gives your project's
  commands 60 minutes (was 15), so a busy machine no longer stops a long test
  run. Set your own with `vbw config set command_timeout SECONDS` (1 to
  86400; `default` resets it). When a limit stops a command, the proof names
  the limit and how to raise it.
- **A phase that was raised stays raised.** A phase escalated after a blocked
  plan, a failed fix or a failed QA is verified at its raised QA depth; the
  small-change shortcut applies only to phases that never escalated.
- **Backlog commands leave your project clean.** `vbw todo add`, `sort`,
  `done` and `drop` commit the record, never taking your own staged files.

### Fixed

- **Long-lived projects keep working.** Every `vbw` command works on a record
  over 1 MB (the operating system's command-line limit), and VBW's guards stay
  fast however long the record grows.
- **`vbw config rigor` works with macOS's built-in bash.** Setting a rigor
  mode no longer fails with "record update failed" under `/bin/bash` 3.2.

### What you need to know

- **Record format 4.** The first VBW 2.0.31 command in a project saves its
  record in format 4. Older VBW versions cannot read it, so update VBW on every
  machine that works on the project. Nothing else to do.
- For contributors: VBW's speed checks fail only on a real slowdown (a hook
  above 20 ms per call, the status line above 60 ms) and report a busy machine
  instead of failing. They run once per release (`bash tools/test.sh --release`,
  in CI and before a push), never in `vbw prove`.

## [2.0.30] - 2026-10-09

### Fixed

- **No "jq: command not found" at session start.** Without `jq`, starting
  Claude Code in a VBW project no longer shows an error: the session-start hook
  ends quietly, like VBW's other hooks. `/vbw:doctor` still tells you `jq` is
  missing.

### Changed

- The README is rewritten: the team, the loop and the engineering practices
  behind each step, how the kernel differs from Claude Code on its own (with an
  architecture diagram), and a features table.
- For contributors: CI runs the macOS tests on four machines at once
  (`bash tools/test.sh --shard K/N` runs one share locally), and a push that
  changes no code, tools or docs runs only the test files it changed, or no
  tests when only the VBW record or saved test results changed
  (`tools/ci-scope.sh`; see CONTRIBUTING.md).

## [2.0.29] - 2026-10-09

### Added

- **Sort an item already in the backlog.** `vbw todo sort T3 next small` sets
  (or changes) an open item's sort and size, so items you planned earlier show
  up in triage and in the what's-next suggestion. An unknown or closed item, or
  another value, is refused and nothing changes.

### Changed

- **Every hook answer is pinned by a test.** Each answer VBW's hooks give
  Claude Code (block, ask, added context, a message for you, no answer) has a
  test that fixes its meaning, and a standards rule fails the build if any
  hook could ever answer "allow" in your place. `docs/guards.md` explains each
  answer.
- **A VBW update alone no longer sends passed phases back to QA.** The QA
  fingerprint now carries a version; after an update that changes how it is
  computed, a passed phase is compared as it was when it passed, and only a
  real change to its files, tests or plan lists it again.

### Fixed

- QA was always told "the project's test command (undefined)"; it is now told
  the real command and how its run ended, in plain words, and a missing piece
  is named instead of printed as "undefined".
- `vbw plan block` refuses a plan that is already done, and the full
  `vbw apply` refuses a requirement another milestone owns or already covers
  (as `vbw apply --add` does); in both cases nothing changes.
- After a ship, the what's-next suggestion is committed with the record, so
  the project is no longer left with an uncommitted `.vbw/record.json`.
- A what's-next pick can no longer carry an empty source, which could make
  VBW refuse the whole suggestion.
- The workflow guide lists all nine workflows, the proof guide says a test
  results folder name cannot contain spaces, and the router's triage line
  reads correctly whatever you type after `/vbw:vibe`.

## [2.0.28] - 2026-10-09

### Added

- **VBW sorts every new idea first.** When you bring a new feature, change or
  fix to `/vbw:vibe`, VBW sorts it as now, next or later, with a one-line
  reason and a size (small, medium or large), in one menu before anything is
  planned or changed. `now` joins the active milestone; `next` and `later` go
  into the backlog (`/vbw:todo`), listed in that order. If you overrule VBW's
  sort, it asks your reason once and records it as a decision. See
  `docs/triage.md`.
- **What's next.** After you ship a milestone, and whenever you ask
  `/vbw:vibe what's next`, the Architect reads your backlog and recommends the
  best next item and two runners-up, each with its size and why. `vbw status`
  shows it, and the panel's Now tab has a new What's next section with a
  "Suggest next" button and a short colour animation when a new suggestion
  arrives. See `docs/whats-next.md`.

### Changed

- CI uses the Node 24 versions of the GitHub actions and also runs on
  Ubuntu 26.04.

### Fixed

- **No lost writes on Ubuntu 25.10 and 26.04.** Those systems ship a new
  `mkdir` that does not refuse a folder that already exists, and VBW's locks
  relied on that refusal: two VBW commands running at the same moment (two
  worktrees, or parallel agents) could both write, and one change was lost.
  VBW now takes its locks with bash itself, on every system.

### Note for updating

- A project that stores a sorted backlog item or a recommendation uses record
  format 3. An older VBW opened on such a project says it needs a newer VBW
  instead of misreading it; update every machine that works on the project.

## [2.0.27] - 2026-10-08

### Changed

- **Small changes take the short path on their own.** When you ask for
  something that names one or two files and touches no risky area, VBW adds one
  phase with one plan and its check to your current milestone and asks you to
  approve once, without the planning workflow. Earlier phases, plans, checks
  and rules stay as they were. The phase gets the tier `vbw next` names:
  express when the change allows it, standard for example in a project without
  a test command. A larger or riskier request still goes to planning.
- **QA stops re-checking for doc edits and saved test results.** A phase that
  passed QA is not checked again when the only files changed since are
  documentation (`.md`, `.markdown`, `.rst`), or saved test results in folders
  your spec lists under a new `## Test results` section (that list is approved
  like the rest of the contract). A change to code, tests, a file a check uses,
  the goal or the plans still sends the phase back to QA, and so does a change
  to the documents of a documentation-only phase.
- **The Lead plans on Opus in the balanced profile**, like the Architect. Dev,
  QA, Scout, Debugger and Docs stay on Sonnet. QA is never set below Sonnet.
- **A failure's full output is kept.** When a check or project command fails or
  times out, `vbw prove` keeps its whole output in `.vbw/runtime/output/` (one
  file per check or command, git-ignored, removed when it passes), and
  `vbw show fix` names that file, so a Dev can read the failing test without
  running everything again.

### Fixed

- `vbw apply --add` refuses a requirement another milestone already covers or
  owns, a plan or check id already in use, and a check or rule for an earlier
  requirement. It no longer re-judges the tier of finished phases.
- `vbw show fix` no longer lists a project command that was skipped because it
  is not approved as a failure.
- **The approval menu is shown again when Claude rewords it.** In 2.0.26, VBW's
  fix for a reworded approval question told Claude Code the hook had answered
  it, so the menu never appeared and Claude said you had not answered (typing
  `/vbw:approve` still worked; nothing was approved without you). The menu now
  appears with `Approve contract <code>?` in front, and your choice is recorded.

### Note for updating

- After updating, a phase in your current milestone that passed QA and whose
  files include documentation or saved results is checked by QA once more:
  2.0.27 fingerprints a phase's files without its docs, so the old fingerprint
  no longer matches. This happens once.

## [2.0.26] - 2026-10-08

### Fixed

- **Approve always approves the contract you were shown.** When Claude words
  the approval question in its own way and leaves out the contract's code, VBW
  now puts `Approve contract <code>?` in front of it before you see it, so your
  Approve is recorded. Before, a reworded question approved nothing.
- **Editing the spec no longer sends a phase back to QA.** VBW's own files
  under `.vbw/` (the spec and the record) never make QA check a passed phase
  again, even when a plan lists them.
- The QA refusal for changed code, `vbw help` and the docs now say
  `vbw prove --full` wherever a QA verdict needs a full proof.
- The interview skill says it runs before any spec or convert work, as the
  router does.

## [2.0.25] - 2026-10-08

### Changed

- **A proof re-runs only what a change touches.** Each check's pass now carries
  a fingerprint of the committed content of the files it serves (its own files
  and the files of the plans behind its requirement). `vbw prove` runs a check
  again only when those files or its approved definition changed, when its last
  result was not a pass, or when it declares no files; every other check reuses
  its pass. The summary says `checks: N ran, M reused`.
- **A quick test command for build and fix rounds.** A project can name a
  `quick` command next to `test` in its spec's Commands. A plain `vbw prove`
  runs it in place of the full test command.
- **QA and shipping still need everything.** `vbw prove --full` runs every check
  and the full project commands and reuses nothing. `vbw qa record` and
  `vbw ship` refuse a partial proof and say to run `vbw prove --full`; `vbw next`
  asks for it before QA and shipping. The summary says `proof: full` or
  `proof: partial`.
- **vbw init** now points to the approval menu instead of `/vbw:approve` when it
  lists the project commands it found.

## [2.0.24] - 2026-10-07

### Changed

- **Proofs reuse what is already proven.** When the committed code has not
  changed since the last passing proof (only VBW's own record or spec did),
  `vbw prove` reuses every result whose approved check or command is unchanged
  and runs only the rest; each reused line says so (`C1 pass 2s reused (proof of
  ...)`). A proof that failed or was interrupted is never reused, and proving
  again with nothing committed since still runs everything fresh.
- **Fewer QA rounds.** A phase that passed QA is not checked again when the
  only change is a decision, a finding closed without code, or a requirement
  that only you judge. A changed `[auto]` requirement is checked again and named
  as the reason.
- **Lighter tiers in mature projects.** Proven requirements that an approved
  check guards no longer push a phase to the deep tier (the proof re-runs those
  checks anyway). The tier's reasons list them as `guarded: R1 (C1)`.
- **Each agent works at the effort its step needs.** A new effort table per
  profile, role and step (low for closing a run, higher for planning and QA) is
  passed to every workflow agent; `vbw config effort` shows it.
- **Phases are numbered right the first time.** The Architect is told the next
  free phase number.

### Note

- After updating, each phase that already passed QA is checked once more, one
  time, because a plan's fingerprint no longer includes its requirement list.

## [2.0.23] - 2026-10-07

### Fixed

- **VBW's agents record their own results again.** Claude Code now marks the
  task text a workflow gives its agents as not coming from you, and some agents
  then skipped recording a plan's state or QA's verdict. Every agent now carries
  that duty in its own instructions, and the run is closed by the Lead instead
  of the read-only Scout, which sometimes refused. When something still is not
  recorded, VBW says so and names the exact command to run by hand.
- **Approve works however the question is written.** Choosing Approve in the
  approval menu approves the contract it names even when an explanation follows
  on a new line. A malformed contract code approves nothing and says why.
- **No more "type /vbw:approve".** After any plan change VBW asks only with the
  approval menu. Typing `/vbw:approve` yourself still works.
- **Autonomous runs stop asking twice.** While this session's proof runs in the
  background, the stop hook waits instead of asking for the proof again and
  spending autonomous steps.
- **A fix can commit what it changed.** A fix for a failing project command can
  commit the files it changed, even ones no plan lists
  (`vbw commit --fix F1 "fix(x): ..." FILE...`); the commit names the fix.

### Changed

- **The Architect runs on Opus in the Standard profile** (balanced); every
  other role stays on Sonnet, and QA is never below Sonnet in any profile.
- **Plans are split for parallel builds.** The Lead splits each phase into
  plans on separate files wherever the work allows, and the approval shows the
  build waves: `build waves: 3 (the widest runs 7 plans at once)`.

## [2.0.22] - 2026-10-07

### Fixed

- **`vbw prove` no longer breaks pnpm 11 projects or your installed packages.**
  The clean copy a proof runs in used to link your git-ignored folders
  (`node_modules`, `.env` files) from the working folder. pnpm 11 refuses a
  linked `node_modules`, and a reinstall through the link could rewrite your
  real packages to point into the copy. The copy now holds real copies, cloned
  copy-on-write where the disk allows (APFS, and reflink file systems on Linux),
  so nothing a proof does reaches your working folder. A folder that cannot be
  read stops the proof before any check runs, and says which one.
- **Damage from earlier versions is found.** After every proof, VBW looks for
  links in your project that still point into an old proof copy and names each
  one with the repair (in a pnpm project: delete `node_modules`, run
  `pnpm install`). It says nothing when there are none.
- **A long check marked alone no longer aborts the proof.** Checks waiting for
  it keep waiting as long as it runs (the 900-second wait limit and its
  setting are gone). A check that could not run shows as
  `not run` with the reason, and every other result stands. The "not a child of
  this shell" warnings are gone.

### Changed

- **Colour you can read at a glance.** The band, Mission Control and the
  Wrapped card share one palette: each role has one colour everywhere
  (architect magenta, lead blue, dev green, QA yellow, scout cyan, debugger
  red, docs pink) and each state one colour and mark (● running amber,
  ✓ done green, ✗ failed red, … quiet grey). Mission Control's cards are framed
  in their agent's role colour. The band draws each agent's label and spinner
  in its role colour, dims time and tokens, and shows the run's cost in purple.
  With colour off, the marks and words still tell every state apart.
- **Plain actions instead of raw commands.** An agent's activity reads
  `editing app-topbar.tsx`, `running tests`, `recording P6.7 done` or
  `running fix_topbar.py`; a command VBW does not know reads
  `running a command`. Command lines, flags and secrets are never shown.
- **A change to `.vbw/record.json` is one line** in the conversation
  (`VBW · build run started`); expand the row (ctrl+o) for the full diff.
- **Mission Control's tabs stay at the top** while its content scrolls, and the
  key value of each sentence is coloured (progress green, estimate amber, cost
  purple, anything VBW needs from you yellow).
- **A new agent's row flashes** in its role colour for about a second, at full
  motion only (`vbw config set motion full`).

## [2.0.21] - 2026-10-07

### Added

- **See VBW work.** While VBW's agents work, the band above the prompt shows
  the crew: one row per agent with its role, what it is doing right now (the
  file it reads, the command it runs, or the last words it wrote), its time and
  its tokens. An agent that has said nothing for 45 seconds is marked quiet, so
  a hang is told apart from slow work.
- **VBW needs you, one key away.** At every human step (approve, check, ship,
  unblock and the rest) the band shows a card with numbered buttons. Buttons
  only fill the prompt (`/vbw:approve`, `/vbw:verify`, ...); you press Enter.
  Before a long run it warns when your weekly limit is past 80% and offers
  `/compact` first when the context is past 85%.
- **Mission Control.** `/vbw-panel` opens a pane with tabs: Now (the agents of
  the run as cards; press one for its detail), Plan, Proof (one coloured cell
  per check), Timeline, Decisions, Team and Costs.
- **VBW in Claude Code's own lines:** the spinner says what VBW is doing, the
  hint line under the prompt says what comes next, the footer shows the profile
  or the autonomous run, a workflow's row and its finish notice read as VBW
  steps (`✓ VBW planning finished · 3 phases · 9 plans · 14m`).
- **Instant commands** that work even while VBW runs: `/vbw-status`, `/vbw-why`
  (who holds the run and what blocks the next step) and `/vbw-todo` (park an
  idea, or the selected text).
- **Motion:** `vbw config set motion full|calm|off`. Full shows the crew as
  small animated figures, confetti when a phase passes QA and a green sweep when
  every check passes; calm uses dots and spinners; off is still text. The
  default follows your interview answers. When a milestone ships, the pane shows
  a VBW Wrapped card: requirements proven, checks, agents, fix rounds, time and
  cost.

### Changed

- **The status line refreshes every 5 seconds,** so a run's time and agents no
  longer look frozen while a workflow works. An existing VBW status line gets
  the refresh on its own the next time you start a session in a VBW project.
- **On Claude Code 2.1.287 and newer the status line is one line shorter:** the
  agents and team line moved to the band and Mission Control. Older Claude Code
  keeps it.

### Fixed

- **The panel counts requirements, like the status line** ("1 of 15
  requirements done"), not phases.
- **The panel comes on in your first session.** When `/vbw:vibe` sets up a
  new project, the panel starts at its first question; no restart needed.
- **Every step that waits for you is shown as one.** The panel said "nothing is
  needed" at the unblock, scope, milestone and convert steps; it now says what
  to do and plays the "needs you" sound.

### What you need to do

- Nothing. The pane, the one-line notes and the commands need Claude Code
  2.1.287 or newer; the band above the prompt needs 2.1.290 or newer
  (`claude update`). On older versions VBW works as before.

## [2.0.20] - 2026-10-07

### Changed

- **Small changes stay small.** A request of one or two simple requirements
  now goes from your words to done through `/vbw:vibe` without the planning
  workflow: VBW plans it itself, you approve once, it is built, checked and
  closed. How deeply QA checks a phase follows the size and risk of its change:
  a change of one or two files with no risk gets a quick check, never a deep
  one. A change to documentation only (Markdown or reStructuredText) needs no
  new test. Plain `.txt` files are treated as data and keep their checks.
- **Faster proof.** `vbw prove` runs your checks in parallel, four at a time by
  default (`vbw config set check_jobs N`, 1 to 64, for this clone). Checks
  marked "alone" still run by themselves, and the results are the same as
  running them one after another. A QA round runs your test command once and
  shares the result with every QA agent.
- **Approve with Enter, every time.** VBW always asks for approval with the
  approval menu; it never asks you to type `/vbw:approve` (typing it still
  works).
- **One approval per phase.** Test files edited while a phase is built are
  approved together once, just before the phase is proved, instead of one
  approval for each edit.
- **Change one plan without starting over.** `vbw apply --patch` changes one
  plan, check or rule and leaves the rest of the milestone as it is; a fix round
  can no longer add or rename phases nobody asked for.
- **The panel opens at a quarter of the terminal** (never narrower than 40
  columns) instead of nearly half. A width you set by dragging always wins.

### Fixed

- **The proof never reuses build output.** The clean copy VBW proves in no
  longer links build folders (`target`, `dist`, `build`, `__pycache__` and
  similar) from your working folder, so compiled files never point into another
  copy. Dependency folders such as `node_modules` and `.venv` are still shared.
- **Plans no longer get stuck.** A plan whose work was already committed (for
  example by the approval commit) can be closed once its checks pass, and a
  blocked plan no longer stops unrelated plans from being built.
- **Planning no longer blocks your other sessions.** While VBW plans, its
  agents may write only VBW's own files and test files.
- **Guards:** a Python, Node, Perl or Ruby command that writes a file outside a
  build's plan is refused like a shell write; reading the plan of record or
  naming the approval command in text is no longer refused.
- **Nothing is lost silently.** Build, fix and QA workflows confirm that every
  agent recorded its result, say plainly which did not, and end their own run.
  An approval whose commit fails now stops and says why.
- **The old-folder review works on Linux** (folders not tracked by git used to
  fail there).

### Compatibility

- The `check_jobs` setting lives in this clone's git directory, not in the
  project record. Records written by this version are read by 2.0.17 to 2.0.19.

## [2.0.19] - 2026-10-06

### Added

- **A live VBW panel.** On Claude Code 2.1.287 or newer, a panel beside the
  conversation shows, in plain words, the milestone and its progress, what VBW
  is doing right now, whether it needs you and for what, what this session has
  cost so far, and roughly how long the current step and the milestone have
  left (or that there is no basis for an estimate yet). It updates by itself.
  It opens by itself in a wide window; `/vbw-panel` opens it at any width.
  Close it and it stays closed until you open it again. On older Claude Code,
  or outside a VBW project, nothing changes. See `docs/panel.md`.
- **A sound when VBW needs you.** A short sound, picked at random from the
  ones shipped with VBW, plays once when VBW needs an approval, an answer or a
  result checked. One click in the panel or `/vbw-sound` turns it off or on;
  the choice is kept in your own settings, never in the project.
- **Approve with Enter.** VBW now asks for approval as a choice: Approve
  (first, so Enter approves), Not yet (VBW asks what to change), or your own
  words. VBW's own code records the approval from your answer, for exactly the
  contract shown, so Claude can never approve by itself. `/vbw:approve` still
  works.
- **The best tools for your project, with your permission.** Once the
  interview knows what you are building, VBW asks whether to look for tools
  that fit it: community skills, code-safety scanners, linters and formatters,
  and test frameworks. On yes, Scouts research current options from trusted
  sources and VBW proposes a short list, explained at your level; nothing is
  installed until you approve it. It is asked once per project; `/vbw:skills`
  runs it again any time. See `docs/tools.md`.
- **Convert or start fresh, with a recommendation.** When a project still has a
  VBW 1 folder, the interview first reviews it: how much was finished, when it
  was last used, whether its plans still match the code, and any work left half
  done. It then recommends converting or starting fresh, with its reasons, and
  you choose. Start fresh leaves the old folder untouched. Run the review again
  with `vbw legacy review`. See `docs/convert.md`.

### Changed

- **A friendlier first question.** The interview now opens with "Hello, Human!
  Welcome to VBW. Let me interview you real quick to better adapt to you. What
  is your level of proficiency?", with the same four options.
- **Every stop says what VBW needs from you.** Each time VBW stops, its message
  ends with one plain line saying what it needs from you now, or that it needs
  nothing.

### Fixed

- **QA keeps its verdicts when the plan changes.** Adding or changing a phase
  in the middle of a milestone used to clear every phase's QA pass, so QA
  checked the whole milestone again. Now each phase keeps its pass; QA checks
  only new phases and phases whose own files, tests, goal or plan changed.
- **The interview comes first in a project with a VBW 1 folder.** VBW now
  always opens with the greeting and the level question, then reviews the old
  folder and asks whether to convert or start fresh.

### Compatibility

- The panel and the sound need Claude Code 2.1.287 or newer (`claude update`).
  Everything else works on older versions as before.
- The project record gains two optional answers (whether to look for tools,
  and the convert-or-fresh choice). VBW 2.0.17 and 2.0.18 read records that
  carry them.

## [2.0.18] - 2026-10-05

### Changed

- **QA checks again only what needs it.** After a round of fixes, QA used to
  check every phase of the milestone again whenever anything in the project
  changed. Now it checks again only the phases that did not pass, the phases
  whose own files, tests, goal or plan changed, and the phases that build on a
  phase checked again for that reason. Every other phase keeps its pass. The
  full proof (`vbw prove`) still runs every test.
- **QA says why.** When QA runs, VBW names each phase it checks again and the
  reason in plain words ("failed last time", "its files changed", "builds on
  P1, which changed"), and lists the phases that keep their pass. See it any
  time with `vbw show qa`; `/vbw:qa` explains it at your level.
- **Planning asks only about what is being planned.** Before planning, VBW asks
  you only about decisions for the milestone being planned, never about work
  that already shipped.

### Compatibility

- No change to the project record: VBW 2.0.16 and 2.0.17 still read it. They
  check every phase again after fixes, as before. Phases that passed QA before
  this version are checked once more after the update, then this rule applies.

## [2.0.17] - 2026-10-05

### Added

- **VBW asks who you are, once per project.** On a project's first spec step
  (after mapping, for existing code) VBW asks three fixed questions: how much
  software you have built, how it should explain things, and how involved you
  want to be in technical decisions. Then what you are building and for whom,
  and up to three follow-up questions written for your level when your answer
  leaves out what the thing does. Last, where to keep your answers: private on
  this machine (the default), or saved in the project for everyone who clones
  it. VBW never asks again in that project; `/vbw:profile` changes any answer.
- **Every message, question and agent speaks at your level.** Planning,
  building, QA, mapping, research and debugging all receive your answers, so a
  newcomer gets plain words and VBW's recommendation, and a senior engineer
  gets brief technical wording and every decision.
- **Suggestions at natural pauses.** When VBW proposes a spec or a plan for
  approval, it may add a few short yes/no suggestions worded for your level.
  Declined suggestions are remembered and not offered again
  (`vbw suggest list`).
- **Close several fixes in one command:** `vbw fix done F8 F9 F5` runs the
  checks they share once. A failing check blocks only the fixes it covers; the
  others close.
- **Checks that must run alone.** A check marked `alone` in the contract (for
  example one that starts containers) never runs at the same time as another
  VBW check in the project. The Lead marks such checks when it plans.

### Changed

- **Closing a fix skips checks that cannot have changed.** `vbw fix done` no
  longer reruns a check that already passed on the same committed files under
  the same approved contract; it prints `C46 unchanged since its pass (time)`.
  `vbw prove` still runs every check. Passes are kept privately in your clone,
  so closing a fix leaves no record change to commit.

### Compatibility

- A project whose contract has an `alone` check is written as record schema 2.
  VBW 2.0.16 and older then say "this project needs a newer VBW, update with
  /vbw:update"; everyone on the project should update. Projects without an
  `alone` check stay readable by 2.0.16.

## [2.0.16] - 2026-10-04

### Changed

- **QA never runs on Haiku.** QA is what catches the mistakes VBW's own
  checks miss, so it now runs on Sonnet or a stronger model in every profile
  and rigor tier; the `budget` profile used Haiku for QA before. Other agents
  keep their models (in `budget`, the Scout and express Devs still use Haiku).
  `vbw config set model.qa haiku` is refused with the reason; `sonnet`, `opus`,
  `default` and other non-Haiku models are accepted. A Haiku QA setting saved
  earlier is treated as Sonnet, and `vbw config` and the status line show it so.

## [2.0.15] - 2026-10-04

### Changed

- **Every rule a requirement states gets its own check, and you see them
  before you approve.** The approval screen lists each requirement's rules
  (its conditions, edge cases and error cases) with the check that tests each
  one, for example `rule: two names print "Hello, Ana Maria!" -> C3`.
  `vbw apply` refuses a rule that no check tests and names it. Requirements you
  approved before this version keep their approval and show
  "rules not listed".
- **A proof checks exactly what is committed.** `vbw prove` runs the checks and
  project commands on a clean copy of the committed code, with the project's
  git-ignored files (installed packages, build output, local config) linked in.
  Leftover or uncommitted files in your working folder no longer change a
  proof, and committing code that was never proved asks for a new proof.
  `vbw check` still runs on your working folder while you build.
  Commit your work before proving.

### Fixed

- **An older VBW opening a project made by a newer VBW** now says "this
  project needs a newer VBW, update with /vbw:update" (also when a session
  starts), instead of calling the record corrupt. Every VBW still reads
  projects made by older versions.

## [2.0.14] - 2026-10-03

### Added

- **VBW sizes its process to the work, on its own (adaptive rigor).** Every
  phase gets a tier, `express`, `standard` or `deep`, computed from measured
  signals: how many requirements, how many files and how large, risky areas
  (sign-in, payments, migrations, secrets, deletion, CI), proven work it could
  break, and whether the project has its own tests. The approval screen shows
  each phase's tier and why, on one line.
  - **Express** (a small, safe request in a small repository): VBW writes the
    requirement, its check and a one-plan contract itself, asks once for
    approval, one Dev builds it and the kernel proves it. No mapping, no
    planning agents, and QA only when a requirement needs a person's judgement.
  - **Deep** (risky or large work): a Scout researches first, and QA goes
    deeper, with an adversarial pass.
  - **When work goes badly** (a Dev blocked, a second fix round, a QA finding
    in an express phase, a risky or oversized commit, proven work failing), VBW
    raises the tier and records why. It never lowers a tier once work began.
  - `vbw config rigor auto|express|standard|deep`: automatic by default;
    any other value forces a tier. `vbw show rigor` reports how often VBW's
    predicted tier held. `vbw tier raise PHASE TIER REASON` raises one by hand.
  - See `docs/rigor.md`, and `docs/m4-report.md` for the measurements.
- **`vbw commit PLAN MESSAGE FILE...`** commits only the named files of a plan,
  so each task gets its own commit.
- **A benchmark against plain Claude Code** (`docs/benchmark.md`): seven
  single-task cases, three multi-requirement projects, both models. It states
  plainly where VBW costs more and where it lost.

### Fixed

- **An agent can write inside a directory its plan lists** (a plan entry
  ending in `/` covers its files); before, every file there was refused.
- **Check files stay approved after a formatter run.** The Lead runs the
  project's formatter and linter on new check files before approval, and Devs
  run formatters on their own files only (a field report: `cargo fmt --all`
  rewrote protected Rust tests and voided the approval three times in a day).
- **`vbw init` detects an executable `test.sh`, `tests.sh` or `run_tests.sh`**
  at the root as the project's test command.
- **VBW changes no project file before you approve the contract,** even for a
  one-line request.

## [2.0.12] - 2026-10-02

### Changed

- **Several Claude Code sessions on one project are safe.** A build, fix,
  QA, planning or mapping run now belongs to the session that started it:
  - another session is told the run belongs elsewhere (wait, or
    `/vbw:status`) and is never asked to end it;
  - `vbw run end` from another session is refused, unless you say the other
    session is closed (`vbw run end --owner-closed`) or the run is more than
    24 hours old;
  - another session, and its agents, cannot edit or overwrite with a shell
    command the files a live run is writing (during a planning run, any
    project file).
  - after Claude Code restarts in the middle of a run, the new session asks
    you once whether the old session is still open, and ends its run only
    when you say it is closed.
- **Autonomous mode is per session:** turning it on or off in one session
  leaves the others as they were, and the status line shows the session it is
  drawn for.

### Fixed

- **The hook speed check no longer fails on a busy machine.** Its budget is
  now relative to the platform's own shell and jq startup (for maintainers:
  `tools/bench-hooks.sh`).

## [2.0.11] - 2026-10-02

### Fixed

- **You can now change the project's commands.** The test, lint and build
  commands every proof runs live in `.vbw/spec.md`, under `## Commands`, one
  per line (`- test: cargo test --manifest-path app/Cargo.toml`, or a JSON
  array when an argument contains spaces). Edit a line to change a command,
  delete it to stop running it, then `vbw spec sync`. `vbw init` writes the
  commands it detects there as a suggestion; in a repository with several
  sub-projects it sees only the root, so check them. A changed command needs
  your approval before any proof runs it.

### What you need to do

- **An existing project keeps its commands** until you add a `## Commands`
  section to `.vbw/spec.md`. To change or remove a detected command, add the
  section with the commands you want (an empty section removes them all), run
  `vbw spec sync`, then `/vbw:approve`.

## [2.0.10] - 2026-10-02

### Fixed

- **QA respects your decisions.** QA now reads the decisions you recorded and
  treats them as part of what was agreed: work that follows one of your
  decisions is no longer failed as a deviation from the plan.
- **Shipping needs the work committed.** VBW proves the files on disk, so a
  milestone could be marked shipped while its work was only staged or
  untracked. `vbw ship` now names the uncommitted files and asks you to commit
  them first.
- **`vbw rtk` reports RTK's hook the way RTK itself does:** a hook given by a
  quoted path to `rtk` is now seen as on, and a command that merely mentions
  `rtk hook claude` is not.

## [2.0.9] - 2026-10-02

### Fixed

- **Your approval stays when a plan is blocked or reset.** A builder that
  stopped on a blocker used to withdraw your approval of an unchanged plan,
  so VBW asked you to approve again for nothing.
- **QA's findings are no longer dropped.** Accepting something you judged
  yourself closed every open fix on it, including fixes QA had raised; now it
  closes only the fixes from your own rejections.
- **QA judges the current code.** A QA verdict on a proof older than the code
  is refused (QA runs the proof again first), and a phase QA failed is checked
  again before VBW offers to ship.
- **Approving commands from two worktrees at once** no longer loses one of
  the approvals.
- **Interrupting a VBW command** (Ctrl-C) no longer leaves temporary files or
  a lock behind.
- **`vbw report`** prints "none" for empty counts and reports a damaged plan
  of record without printing its contents. New page: `docs/diagnostics.md`
  (`vbw report` and `vbw rtk`).

## [2.0.8] - 2026-10-02

### Fixed

- **Autonomous mode no longer wastes steps while QA or mapping runs** (the
  repeated "Stop hook error ... step N of 25"). QA and mapping now run as
  steps VBW knows about, and their agents can read but never write.

## [2.0.7] - 2026-10-02

### Changed

- **VBW 1's team is back, with its mandates:** Architect (the decisions and
  the phases with success criteria), Lead (plans with tasks and tests),
  Dev (one commit per task, deviation rules), QA, Scout, Debugger and Docs.
  Each has its VBW 1 model in every profile, and `/vbw:config` sets any of
  them (`model.dev`, `model.qa`, ...). A model you set for an earlier role name
  carries over.
- **QA verifies finished work again:** after the tests pass, QA checks each
  phase against its goal, criteria and plan; what it finds is fixed and
  checked again.
- **`/vbw:debug`** uses Debuggers (and one fixes the bug with a regression
  test); **`/vbw:research`** uses up to four Scouts in parallel;
  documentation plans go to the Docs agent.
- **The status line** shows the seven agents in their own colours, and the
  team grouped by model.

## [2.0.6] - 2026-10-01

### New

- **A richer status line.** A progress bar for the milestone; a line showing
  each working agent in its role's colour with its task and model (or, when
  idle, your team: the model of each role, the profile and how much VBW does on
  its own); and the tokens and prompt-cache hit rate of the last request.

## [2.0.5] - 2026-10-01

### New

- **See VBW's agents at work in the status line:** while a step runs it shows
  how long it has run and how many agents are working right now, for example
  `▶ build: P1.2 4m10s · 3 agents working`.

## [2.0.4] - 2026-10-01

### Fixed

- **Simultaneous updates to a project's plan could be lost** when many VBW steps
  wrote at the same moment (for example several builders finishing together).
  Every update is now kept.

## [2.0.3] - 2026-10-01

### Fixed

- **`/vbw:map` and `/vbw:debug`** turn on Dynamic workflows themselves, like
  `/vbw:vibe`, instead of sending you to `/config`.
- **Accepting a requirement** closes a fix still open from an earlier rejection.

## [2.0.2] - 2026-10-01

### Fixed

- **The status line** shows your project when Claude Code starts in one of its
  subfolders, points a VBW 1 project to `/vbw:vibe` to bring it in, and
  shortens very long milestone names.
- **`/vbw:doctor`** checks that git knows your name and email (VBW commits as
  you).
- **A kept VBW 1 folder** no longer makes VBW think the code changed.

## [2.0.1] - 2026-10-01

### Fixed

- **Planning could not start where Dynamic workflows are off by default** (e.g.
  the Pro plan). VBW now turns them on itself, like its status line, and says
  so; if you turned them off on purpose, it tells you instead (`vbw workflows`).

## [2.0.0] - 2026-10-01

VBW 2 is a rebuild for today's Claude Code. Same idea and the same commands,
new engine: VBW helps you decide what to build, then proves it is done.

### What's new

- **Better questions, better decisions.** Before planning, VBW asks you the
  decisions that matter (cost, where data lives, security, what is hard to
  change later), one at a time, with plain trade-offs and a recommendation, and
  records what you chose and why. `/vbw:discuss` thinks anything through with
  you; `/vbw:research` brings a sourced answer.
- **One command, `/vbw:vibe`.** It sets VBW up the first time, always knows the
  next step (agree, decide, plan, approve, build, prove, fix, check, ship),
  does it, and keeps going until it needs you. `/vbw:profile` sets how much it
  does on its own: Careful, Standard or Fast.
- **Proof, not claims.** Every requirement a check can prove gets a test that
  fails before the work and passes after it. VBW runs those tests itself; a
  builder cannot mark work done until they pass, and a fix cannot break work
  already proven. You approve the plan and its tests once (`/vbw:approve`), and
  nothing VBW runs is unapproved.
- **Parallel building with Claude Code workflows.** Independent parts of the
  plan are built at the same time, each committing only its own files, with the
  plan and requirement in every commit.
- **Safety guards** stop destructive commands (force-push, `rm -rf` of the
  project, `git reset --hard` ...), secret files, and builders writing outside
  their part of the plan or disturbing each other's work.
- **The status line** shows the project, its progress and what happens next.
- **Every VBW 1 command is still here**, plus `/vbw:approve` and
  `/vbw:convert`. `/vbw:help` lists them by what you want to do.

### What you need

- Claude Code 2.1.286 or later. VBW turns on **Dynamic workflows** itself (they
  are off by default on some plans).
- A Sonnet, Opus or Fable session model.
- `jq` and `git`.

### Coming from VBW 1

- Update as usual. On the first start, VBW 2 removes VBW 1's old command
  copies; type `/reload-skills` (or restart) when it says so.
- Your projects are safe: VBW 1's `.vbw-planning/` folder is never changed.
  `/vbw:vibe` (or `/vbw:convert`) brings a project into VBW 2 through a few
  questions (goals, what to do next, ideas and decisions to keep), then asks
  whether to keep or delete the old folder. Keeping it is the default.


## [1.37.1] - 2026-05-11

### Fixed

- **`hooks`** -- guarded the pre-push hook's `--verify` invocation with a plugin-name check, mirroring `validate-commit.sh`'s existing guard. Without this, third-party repos shipping their own `scripts/bump-version.sh` (e.g., SWT v2.3.5's in-tree version bumper) had every `package.json` `version` field silently overwritten with the literal string `"--verify"` on every push. The new guard verifies `.claude-plugin/plugin.json` exists and reports `name == "vbw"` before invoking `--verify`; non-VBW repos now skip the check silently. (Issue #635, PR #636)

## [1.37.0] - 2026-05-11

### Added

- **`debug`** -- added deterministic selected-todo startup, duplicate completed-session repair, and named foreground non-team subagent support for debug/fix routing. (PR #627, PR #633)

### Changed

- **`uat`** -- strengthened remediation and verification lifecycle routing: active current UAT now resumes Verify, archive is blocked by non-terminal UAT, round 08/09 parsing is safe, re-verification transitions finalize through the deterministic owner, and accepted summary deviations can be tracked as VBW todos without reopening remediation loops. (PR #596, PR #600, PR #601, PR #606, PR #608, PR #611, PR #612, PR #615, PR #618, PR #620)
- **`state`** -- preserved ROADMAP phase numbering across prefix gaps and compacted machine-managed TODO insertion for accepted UAT deviations and known-issue promotion. (PR #604, PR #632)
- **`qa`** -- optimized known-issue comparisons for large registries and kept active QA remediation dormant after UAT cutover. (PR #622, PR #624)
- **`docs`** -- clarified contributor PR automation gates plus README debug routing, command coverage, and hook-handler counts. (PR #603, PR #623)

### Fixed

- **`guards`** -- scoped active-agent guard state by session and allowed foreground non-team agent `name` labels without treating them as team membership. (PR #594, PR #633)
- **`debug`** -- honored accepted exception remediation requests, enforced inline UAT AskUserQuestion boundaries, and kept active UAT prompts self-contained. (PR #618, PR #622, PR #631)
- **`uat`** -- made issue capture synthesize durable remediation descriptions, kept product checkpoint modals self-contained, and made status parsing robust under parallel test load. (PR #611, PR #618, PR #625)

## [1.36.2] - 2026-05-06

### Added

- **`gitnexus`** -- added comprehensive GitNexus skills for CLI operations, debugging, code exploration, impact analysis, and refactoring. (PR #591)
- **`agents`** -- exposed local VBW development agents for GitHub Copilot and added the `fix-planner-vbw` agent to support plan-audit workflows.

### Changed

- **`qa`** -- hardened QA remediation plan validation, UAT remediation orchestration, process-exception evidence gates, known-issue comparisons, and pending-QA explanations. (PR #566, PR #568, PR #574, PR #582, PR #583)
- **`state`** -- fixed linked ROADMAP checklist drift and archive state consistency during UAT/archive reconciliation. (PR #573)
- **`dev`** -- hardened Dev subagent spawns against worktree isolation failures. (PR #579)
- **`release`** -- refreshed GitNexus index metadata and added Serena onboarding memories.

### Fixed

- **`hooks`** -- scoped agent-spawn-guard named-agent blocking to active VBW workflows and stripped unsupported isolation/cwd fields from hallucinated subagent spawn parameters instead of blocking. (PR #585, PR #590)
- **`scout`** -- allowed read-only Bash live validation for Scout workflows. (PR #588)
- **`hooks`** -- guarded non-PDF Read pages and reverted the sanitizer after runtime evidence showed validation happens before hook execution. (PR #562, PR #563)

## [1.36.1] - 2026-05-02

### Fixed

- **`guards`** -- resolved Claude Code internal sidechains at `.claude/worktrees/agent-*` to host repository root for hook state, blocking accidental writes into unmanaged sidechain copies. (PR #558)
- **`state`** -- added deterministic shell-side `STATE.md` reconciliation for UAT/remediation artifacts, fixing drift caused by Bash scripts mutating authoritative files outside PostToolUse hooks; also suppressed invalid SubagentStart/SubagentStop `hookSpecificOutput` JSON. (PR #560)
- **`hooks`** -- reverted non-PDF `Read.pages` sanitizer addition after runtime evidence showed Claude Code validates `Read.pages: ""` before firing `PreToolUse:Read`, making the hook-seam fix insufficient for the observed validation-before-hook path. (PR #562, PR #563)

## [1.36.0] - 2026-05-01

### Added

- **`rtk`** -- added explicit opt-in RTK management for install, setup, verification, update, uninstall, and runtime smoke proof capture. (PR #540)
- **`research`** -- added `/vbw:research N` so numbered todo snapshots can launch context-only Scout research without removing the todo. (PR #543)
- **`skills`** -- nudged agents to read skill-referenced follow-up material after `Skill()` activation when relevant to the active task. (PR #534)

### Changed

- **`config`** -- replaced the typed pseudo-menu with bounded structured prompts for top-level and core settings choices. (PR #528)
- **`debug`** -- split competing-hypothesis investigation from implementation ownership so report-only investigators tear down before a fresh implementation debugger is spawned. (PR #530)
- **`init`** -- aligned init and discussion prompts with the shared AskUserQuestion interaction contract. (PR #541)
- **`testing`** -- expanded interactive prompt contract coverage to keep structured prompts and freeform handoffs on the intended paths. (PR #539)

### Fixed

- **`debug`** -- improved sparse `/vbw:debug` skill selection by enriching sparse todo context and logging runtime skill decisions. (PR #526)
- **`execute`** -- routed true teams only when dependency graphs have real parallel delegate width, preserving serial execution for linear work. (PR #555)
- **`rtk`** -- made install complete setup, added runtime smoke proof recording, and hardened verification when history tails stall or mismatch. (PR #545, PR #547, PR #549, PR #551)
- **`skills`** -- restricted follow-up file resolution to Claude skill roots so lookalike directories are ignored. (PR #538)
- **`testing`** -- hardened verifier pipelines and archive contract matching to avoid pipefail and broken-pipe false failures. (PR #532, PR #537, PR #552)

All notable changes to VBW will be documented in this file.

## [1.35.1] - 2026-04-25

### Changed

- **`fix-issue`** -- Reduce agent verbosity by ~22% through inline bash extraction and pattern consolidation. (PR #523)
- **`workflow`** -- Support user-authored plan reuse and in-place audits in agent and planner. (PR #497)
- **`docs`** -- Revise smoke test guidelines for consumer repos. (ffc7f50c)
- **`agents`** -- Revise plan audit process and add loop procedure for fix-planner. (932e04c9)

### Fixed

- **`debug`** -- Improve sparse todo skill selection with bounded enrichment and orchestrator/runtime logging. (PR #526)
- **`debug-session`** -- Normalize completed no-verification results to `skipped_no_fix_required`. (PR #522)
- **`debug`** -- Preserve completed explicit session state instead of silently reopening. (PR #520)
- **`skills`** -- Clarify high-cardinality selection behavior for bounded vs. freeform prompts. (PR #519)
- **`todo`** -- Stabilize list-with-snapshot flake with deterministic age metadata. (PR #518)
- **`planning`** -- Sync transient planning ignores in all tracking modes. (PR #517)
- **`debug`** -- Commit debug completion artifacts at planning-artifact boundary. (PR #516)
- **`readme`** -- Sync config defaults reference for caveman and discussion_mode settings. (PR #515)
- **`debug-session`** -- Rename metadata export to `session_status` and add stranded session recovery. (PR #514)
- **`debug`** -- Clean up already-fixed outcome state. (PR #509)
- **`skills`** -- Make spawned-agent skill activation additive. (PR #505)
- **`todo-debug`** -- Harden todo-to-debug pickup with deterministic normalization. (PR #504)
- **`todo`** -- Honor planning git boundary for backlog writes. (PR #503)
- **`todo`** -- Restore canonical detail storage. (PR #500)
- **`todo`** -- Make pickup immediate and snapshot-safe across commands. (PR #498)
- **`compact`** -- Harden unauthenticated context cache handling. (PR #495)
- **`debug`** -- Normalize debug session lifecycle spacing. (PR #493)

## [1.35.0] - 2026-04-19

### Added

- **`lifecycle`** -- Add post-archive lifecycle hook for cleanup after plan archival. (PR #481)
- **`caveman`** -- Integrate caveman token compression language for reduced context usage. (PR #456)
- **`run-all`** -- Add execution contract verification script. (PR #454)
- **`fix`** -- Add fix-commit marker and context for inline QA/UAT. (PR #446)
- **`commands`** -- Deprecate standalone /qa and /verify commands in favor of integrated flow. (PR #439)
- **`state-consistency`** -- Add cross-file state consistency checks at lifecycle boundaries. (PR #420)
- **`debug`** -- Make /debug self-contained by absorbing QA and UAT inline. (PR #415)
- **`summary`** -- Add ac_results frontmatter for acceptance criteria reconciliation. (PR #403)
- **`research`** -- Backfill all frontmatter fields during migration. (PR #401)
- **`research`** -- Add standalone research storage with staleness tracking. (PR #397)
- **`vibe`** -- Add skill evaluation at remediation recovery spawn sites. (PR #393)
- **`testing`** -- Add AskUserQuestion maxItems contract test. (PR #389)
- **`debug`** -- Separate active and completed debug sessions into subdirectories. (PR #387)
- **`debug`** -- Add standalone debug session lifecycle with integrated QA/UAT flow. (PR #385)
- **`skills`** -- Add visible skill evaluation reporting in agent output. (PR #384)
- **`scripts`** -- Add todo detail registry for rich context preservation. (PR #375)
- **`vibe`** -- Auto-continue UAT remediation when re-verification finds issues. (PR #366)
- **`map`** -- Add advisory MCP tool guidance for Scout agents. (PR #355)
- **`lifecycle`** -- Auto-promote known issues to STATE.md Todos at lifecycle boundaries. (PR #354)
- **`report`** -- Add LLM-based classification and template matching for issue filing. (PR #345)
- **`report`** -- Add /vbw:report command for self-diagnosis and bug reporting. (PR #336)
- **`discussion-engine`** -- Add codebase-first assumptions mode. (PR #333)
- **`discussion-engine`** -- Add recommendation-led questions. (PR #331)

### Changed

- **`ghcp`** -- Add custom agentic development flow for GitHub Copilot users. (PR #476)
- **`testing`** -- Sanitize README path example and add docs contract checks. (PR #473)
- **`known-issues`** -- Fail closed on degraded known-issues status probes. (PR #465)
- **`skills`** -- Add Step 5b global path contract test. (PR #463)
- **`testing`** -- Auto-throttle local run-all suites across worktrees. (PR #449)
- **`gitignore`** -- Update .gitignore entries. (PR #442)
- **`report`** -- Add contract test for temp-file diagnostic handoff. (PR #417)
- **`cleanup`** -- Remove accidentally committed fix-issue agent file. (PR #408)
- **`report`** -- Add contract test for template alignment and classification. (PR #399)
- **`copilot`** -- Add Copilot cloud-agent onboarding instructions for VBW. (PR #377)
- **`docs`** -- Clarify UAT remediation round-cap semantics. (PR #372)
- **`ghcp`** -- Expose local VBW development agents for GitHub Copilot. (e1a878b)
- **`gitignore`** -- Add presentation source doc to .gitignore. (2718d3b)

### Fixed

- **`list-todos`** -- Replace AskUserQuestion with display-and-stop pattern. (PR #490)
- **`vibe`** -- Extract AskUserQuestion contract into shared reference. (PR #489)
- **`agents`** -- Prevent stop-hook recovery ambient context and cross-thread contamination. (PR #479)
- **`context`** -- Stabilize cache-context target resolution. (PR #477)
- **`testing`** -- Stabilize run-all overlap auto-tune test. (PR #475)
- **`commands`** -- Consolidate agent settings resolution. (PR #474)
- **`debug-target`** -- Add configurable debug target and root CLAUDE symlink. (PR #472)
- **`tests`** -- Stabilize hook-wrapper cache env isolation. (PR #471)
- **`commands`** -- Eliminate embedded inline plugin-root spans. (PR #468)
- **`run-all`** -- Harden command contracts against local drift. (PR #464)
- **`phase-detect`** -- Harden flaky QA routing under parallel load. (PR #462)
- **`testing`** -- Eliminate statusline SIGPIPE flake. (PR #461)
- **`report`** -- Consolidate diagnostic helpers into /vbw:report. (PR #460)
- **`state-updater`** -- Harden temp file operations against parallel BATS flakiness. (PR #457)
- **`init`** -- Align CLAUDE_CONFIG_DIR prose with resolve-claude-dir.sh semantics. (PR #455)
- **`skills`** -- Unify global skills path resolution around CLAUDE_DIR cascade. (PR #445)
- **`phase-detect`** -- Harden QA pending detection under parallel BATS. (PR #441)
- **`tests`** -- Stabilize live PID fixtures. (PR #440)
- **`session-start`** -- Replace inline sed parser with shared extract_summary_status(). (PR #438)
- **`skills`** -- Correct global install path display to ~/.claude/skills/. (PR #437)
- **`scripts`** -- Remove extract_summary_status() override in recover-state.sh. (PR #432)
- **`tests`** -- Replace hardcoded dead PIDs with get_dead_pid helper. (PR #430)
- **`scripts`** -- Stabilize phase-detect QA pending status under parallel BATS. (PR #429)
- **`vibe`** -- Self-heal retryable phase-detect cache with sentinel and blank handling. (PR #427)
- **`qa-gate`** -- Skip change-evidence checks for plan-amendment-only remediation rounds. (PR #425)
- **`hooks`** -- Bypass task-verify for non-commit tasks. (PR #423)
- **`tests`** -- Harden run_phase_detect retry with exponential backoff. (PR #419)
- **`suggest-next`** -- Add debug-session awareness to fix case. (PR #416)
- **`security-filter`** -- Anchor directory patterns as path components. (PR #412)
- **`tests`** -- Use _ORIG_HOME for real HOME capture after setup_temp_dir. (PR #410)
- **`tests`** -- Fix flaky phase-detect.bats under parallel execution. (PR #409)
- **`report`** -- Persist diagnostics to temp file for reliable issue filing. (PR #400)
- **`qa-result-gate`** -- Support gitignored planning directory evidence in corroboration. (PR #395)
- **`track-known-issues`** -- Aggregate accepted-process-exception outcomes across remediation rounds. (PR #394)
- **`config`** -- Sync config.md settings table with defaults.json. (PR #392)
- **`debug`** -- Handle legacy migration failures in find_latest_unresolved and list. (PR #391)
- **`commands`** -- Address AskUserQuestion maxItems:4 violations. (PR #383)
- **`scripts`** -- Route to needs_uat_remediation when round UAT shows issues_found. (PR #370)
- **`commands`** -- Disambiguate step 4 task list from TaskCreate delegation. (PR #368)
- **`skills`** -- Require explicit skill outcome blocks for subagent spawns. (PR #364)
- **`qa-remediation`** -- Remove hardcoded MAX_ROUNDS=3 cap on remediation loop. (PR #362)
- **`hooks`** -- Fix CC 2.1.94 hook breakage (zsh nomatch, BSD awk locale, test isolation). (PR #359)
- **`qa-remediation`** -- Stop false remediation loops from docs-only rounds and carried known issues. (PR #358)
- **`known-issues`** -- Persist phase known-issues lifecycle through QA remediation. (PR #352)
- **`execute`** -- Enforce real team semantics in /vbw:vibe. (PR #351)
- **`research`** -- Use phase-wide RESEARCH.md naming for Plan mode. (PR #350)
- **`report`** -- Always auto-file issues; remove --file-issue flag. (PR #346)
- **`report`** -- Add scope guardrails to prevent unauthorized side effects. (PR #343)
- **`vibe`** -- Clarify routing prohibition to require AskUserQuestion tool call. (PR #342)
- **`testing`** -- Ungate verify-vibe.sh and add to CI. (PR #334)

## [1.34.1] - 2026-04-03

### Added

- **`hooks`** -- Prefer native `agent_id`/`agent_type` fields for subagent detection across start, stop, health, and compaction hooks, with backward-compatible fallback for legacy payload shapes. (PR #321)
- **`ci`** -- Add Discord release notification workflow that posts rich embeds with release notes when a GitHub release is published. (PR #314)

### Changed

- **`config`** -- Canonicalize `prefer_teams` aliases by removing `when_parallel` as a distinct mode, normalizing legacy values to `always|auto|never` via a shared helper, and adding contract test coverage. (PR #320)
- **`ci`** -- Add `.github/references` to `.gitignore`.

### Fixed

- **`vibe`** -- Fold Milestone UAT Recovery's two sequential AskUserQuestion calls into a single three-option question, eliminating the redundant yes/no entry gate. (PR #327)
- **`vibe`** -- Add explicit `AskUserQuestion` tool-call directives at all confirmation gates in the routing table, co-locating tool instructions with routing decisions. (PR #326)
- **`commands`** -- Add missing tools (AskUserQuestion, Agent, team management) to `allowed-tools` frontmatter across 14 command files, and add contract test for consistency. (PR #323)
- **`archive`** -- Use the Write tool instead of Bash for SHIPPED.md creation so PostToolUse hooks fire for artifact tracking. (PR #319)
- **`verify`** -- Keep execute-time UAT generation human-only by explicitly excluding programmatic and UI-automation checks from UAT in `execute-protocol.md`. (PR #318)
- **`verify`** -- Add `--remediation-kind` filter to `compile-verify-context.sh` so UAT remediation re-verification scans only the UAT directory when both QA and UAT remediation exist. (PR #317)

## [1.34.0] - 2026-04-01

### Added

- **`qa`** -- Add QA gate enforcement that blocks UAT until QA passes, treats deviations as defects, and auto-loops dev agents through a remediation state machine before UAT can start. (PR #296)
- **`qa`** -- Write per-round `R{RR}-VERIFICATION.md` into round directories, making each QA remediation round a self-contained artifact set while preserving phase-level verification as frozen QA history. (PR #299)
- **`scope`** -- Persist milestone-level scope decisions in a new `CONTEXT.md` artifact capturing decomposition rationale, requirement mapping, key decisions, and deferred ideas. Route project-level decisions into STATE.md. (PR #292)
- **`testing`** -- Reduce full test-suite latency from ~4m to ~1m via parallelized BATS execution, CI matrix sharding, auto-sized worker counts, and workspace-scoped cache/temp isolation. (PR #303)

### Fixed

- **`vibe`** -- Route active UAT via metadata-only routing from `phase-detect.sh` and direct file read, eliminating the fragile precomputed extraction payload that caused intermittent zero-issue counts during template expansion. (PR #311)
- **`statusline`** -- Use `-ge` instead of `-gt` for cache mtime comparison so lifecycle artifacts written in the same second correctly invalidate stale statusline values. (PR #309)
- **`uat`** -- Add consistency guard to `extract-uat-issues.sh` that detects when the awk parser produces zero issues but frontmatter declares a non-zero count, outputting `uat_extract_error=true` instead of misleading zeros. (PR #307)
- **`qa`** -- Prevent deviation laundering through metadata-only remediation rounds by hardening classification rules, original FAIL carry-forward, and deterministic gate evidence requirements. Also fix first-UAT scope selection, fail-closed UAT finalization, and statusline lifecycle labeling. (PR #301)
- **`debugger`** -- Enable MCP tool access for Debugger and QA agents by switching from `tools:` allowlists to `disallowedTools:` denylists, and add skill pre-evaluation at spawn points. (PR #289)
- **`plan`** -- Remove team creation from Plan mode so Scout and Lead are always spawned as plain sequential subagents, fixing incorrect concurrent execution that broke Scout-before-Lead dependency. (PR #287)
- **`statusline`** -- Anchor root resolution to script location instead of agent CWD, fixing monorepo scenarios where agents navigate to sub-packages. (PR #267)

## [1.33.2] - 2026-03-24

### Added

- **`scripts`** -- Add `resolve-artifact-path.sh` for deterministic artifact filename resolution, replacing inline LLM-computed filenames across plan, summary, research, context, UAT, and verification artifacts. (PR #277)
- **`agents`** -- Enable MCP tool access for VBW subagents by switching Scout from a restrictive `tools:` allowlist to a `disallowedTools:` denylist pattern, and adding MCP evaluation guidance to orchestrator commands. (PR #280)

### Fixed

- **`hooks`** -- Exempt remediation round summaries (`R{RR}-SUMMARY.md`) from the file-guard terminal-status check that blocks SUMMARY writes with non-terminal status values. (PR #255)
- **`state`** -- Restore canonical `## Current Phase` section in STATE.md after milestone archive, introduce shared phase-state helpers, and harden brownfield/archive recovery for consistent phase status across all downstream readers. (PR #256)
- **`statusline`** -- Resolve `.vbw-planning/config.json` by walking up from CWD instead of using bare relative paths, fixing monorepo subdirectory hook execution. (PR #259)
- **`vibe`** -- Re-route after milestone UAT "Start fresh" instead of dead-ending, by re-running phase-detect after marking milestones as remediated. (PR #269)
- **`phase-detect`** -- Add `needs_verification` as a first-class state to eliminate ambiguous `auto_uat` routing, and prohibit UAT delegation to subagents. (PR #271)
- **`uat`** -- Fix `advance` from `verify` stage to start a new remediation round instead of dead-ending as a no-op. (PR #282)
- **`uat`** -- Normalize LLM-generated UAT status synonyms (`all_pass`, `passed`, `verified`, etc.) to canonical forms so phase-detect recognizes them as terminal statuses. (PR #284)

## [1.33.1] - 2026-03-17

### Added

- **`statusline`** -- Normalize context percentages and X/Y totals to Claude Code's usable autocompact window, including override-aware calculations for larger context windows. (PR #250)

### Changed

- **`docs`** -- Clarify the v1.33.0 release wording across the changelog, Discord draft, and published GitHub release notes. (PR #245)
- **`docs`** -- Remove the temporary v1.33.0 Discord draft file from the repository. (PR #247)

### Fixed

- **`statusline`** -- Treat HTTP 429 usage responses as stale OAuth tokens, back off retries to 5 minutes, and skip usage fetches when nonessential traffic is disabled. (PR #251)

## [1.33.0] - 2026-03-14

### Added

- **`remediation`** -- Store UAT remediation artifacts in dedicated `remediation/round-XX/` directories with `RXX-*` filenames, while keeping legacy flat layouts readable via fallback logic. (PR #236)
- **`remediation`** -- Add dedicated remediation research, plan, and summary templates so remediation rounds use their own structured artifacts instead of overloading phase-level files. (PR #236)
- **`statusline`** -- Add four display controls to hide the limits line, hide it only for API-key sessions, suppress the build/agent line in tmux, or collapse the statusline to a single line in tmux. (PR #118)
- **`statusline`** -- Color the `[VBW]` badge dynamically based on whether VBW context is active in the current session. (PR #213)
- **`dx`** -- Add `scripts/dev-setup.sh` plus an optional `claude-vbw` launcher to automate local VBW setup, teardown, status checks, and launching Claude Code against a local clone. (PR #212)
- **`ci`** -- Require pull requests to link an issue, recognizing closing keywords, bare issue refs, full issue URLs, and sidebar-linked issues. (PR #194)

### Changed

- **`qa`** -- QA now persists `VERIFICATION.md` through `write-verification.sh` directly instead of relying on a heredoc escape hatch or parent-command passthrough. (PR #231)
- **`skills`** -- Fix forced skill evaluation for spawned agents by moving skill injection to `SubagentStart`, so team and subagent workflows reliably receive the skills they need; also stop accidental YAML turn ceilings from capping agents that should be unlimited. (PR #197)
- **`session-start`** -- Warn when GSD is co-installed to reduce cross-wired `/gsd:*` versus `/vbw:*` workflows in VBW sessions. (PR #197)
- **`remediation`** -- Make remediation planning and execution self-contained and sequential so remediation no longer inherits normal execute-mode wave/team behavior or creates unnecessary worktrees. (PR #236)
- **`todo`** -- Make `/vbw:todo` and `/vbw:list-todos` fail cleanly in restricted permission modes with actionable guidance. (PR #227)
- **`release`** -- Make release-audit changelog insertion non-interactive: generated entries are written immediately and completed before the separate README prompt. (PR #243)
- **`prompts`** -- Add and clarify AskUserQuestion spacing guidance so dialogs do not obscure surrounding output. (PR #241)
- **`config`** -- Change the default `prefer_teams` setting from `always` to `auto` so VBW only spins up teams when parallelism is useful. (PR #236)

### Fixed

- **`verify`** -- Limit post-remediation re-verification to the latest remediation round, carry prior UAT issues forward into targeted tests, and write remediation UAT files into the round directory instead of the phase root. (PR #236)
- **`compact`** -- Clear stale `.context-usage` data at session boundaries and stamp it with session IDs so new sessions do not inherit false high-context warnings from old sessions. (PR #239)
- **`statusline`** -- Fix stale completion counts after reset/undo, count only valid completed summaries, and render remediation/UAT lifecycle states more accurately. (PRs #197, #236)
- **`statusline`** -- Fix first-render reliability by seeding caches on session start and avoiding blocking stdin reads. (PR #236)
- **`agents`** -- Add explicit mechanical `shutdown_response` tool-call instructions so shutdown requests are acknowledged through the team protocol. (PR #226)
- **`teams`** -- Clean stale or orphaned VBW team directories before `TeamCreate` and after `TeamDelete` to prevent ghost agent labels in Claude Code's status bar. (PR #230)
- **`worktree`** -- Fully remove residual `.vbw-worktrees/` directories and stale git worktree metadata during cleanup, including locked worktrees. (PR #229)
- **`watchdog`** -- Kill tmux panes that get stuck indefinitely during compaction. (PR #190)
- **`agents`** -- Prune dead PIDs from `.agent-pids` on session start. (PR #228)
- **`ci`** -- Harden linked-issue enforcement with `synchronize` coverage, tighter matching rules, clearer failure messages, explicit permissions, and updated docs/templates. (PR #196)

## [1.32.2] - 2026-02-26

### Fixed

- **`release`** -- Finalize Step 4 now checks remote branch existence before attempting deletion, preventing spurious error output when the branch was already removed by PR merge. (PR #184)

## [1.32.1] - 2026-02-26

### Fixed

- **`release`** -- Finalize now auto-merges the release PR (marks ready, waits for checks, merges, pulls) instead of requiring manual GitHub merge. Prepare returns to main after pushing release branch. Changelog extraction uses awk instead of sed for macOS compatibility. (PR #181)

## [1.32.0] - 2026-02-26

### Added

- **`release`** -- Version bump now accounts for pending release branches. Computes bump base as highest of local, remote, and pending semver values with dry-run/no-push safety contracts preserved. (PR #178)
- **`plugin`** -- Exclude release command from marketplace installs via `.claude-plugin/exclude` patterns. (PR #161)

### Changed

- **`gitignore`** -- Ignore `.claude` directory to keep user-local Claude Code state out of version control. (PR #158)

### Fixed

- **`release`** -- Correct git date format placeholders (`%cd --date=short` instead of `%Y-%m-%d`) and clarify tag existence checks to test stdout content rather than exit code. (PR #175)
- **`release`** -- Robust grep pattern eliminates false positives from `[Unreleased]` section indirection; changelog entries now target versioned headers directly. (PR #173)
- **`release`** -- Auto-create versioned changelog section and populate from merged PRs and commits when section is missing. (PR #170)
- **`release`** -- Two-phase prepare/finalize workflow respects branch protection rules by using draft PRs instead of direct pushes to main. (PR #163)
- **`commands`** -- Add symlink fallback and robust grep pattern for plugin root resolution when `CLAUDE_PLUGIN_ROOT` is unset. (PR #168)
- **`commands`** -- Add phase-detect fallback to prevent template-block race condition when phase-detect.sh runs concurrently. (PR #165)
- **`commands`** -- Revert session-key from SHA1 to deterministic value and inject `session_id` from hook stdin for reliable session tracking. (PR #154)
- **`planning`** -- Enforce deterministic plan filename convention (`PLAN.md`) to prevent naming drift across phases. (PR #164)
- **`auto-uat`** -- Trigger verification mid-milestone before continuing execution, ensuring UAT gates are not bypassed. (PR #149)

## [1.31.0] - 2026-02-23

### Added

- **`auto-uat`** -- Auto UAT detection and routing for unverified phases. New `auto_uat` config flag runs `/vbw:verify` inline after QA instead of only suggesting it. Config controls whether UAT runs inline or is merely suggested. (PR #135)
- **`require-phase-discussion`** -- New `require_phase_discussion` config flag gates plan execution behind a mandatory discussion step per phase. Undiscussed phases route to `needs_discussion` instead of jumping to `needs_plan_and_execute`. (PR #123)
- **`deterministic-verification`** -- Deterministic VERIFICATION.md generation via `write-verification.sh`. Per-category 6-col verification tables derived from §4–§7 semantics. Replaces ad-hoc QA agent output with structured, reproducible verification artifacts. (PR #138)
- **`remediation`** -- Seeding of ROADMAP.md and STATE.md for remediation phases. Pre-seed CONTEXT.md with UAT report for in-phase remediation. Pre-seeded discussion annotations in Next Up hints. Skip discuss step for in-phase UAT remediation.
- **`config`** -- Multi-location `CLAUDE_CONFIG_DIR` fallback across all scripts and commands. Removes hardcoded `$HOME/.claude` assumptions. (PR #116 by @halindrome)
- **`context`** -- Pre-flight context guard to prevent mid-workflow compaction from disrupting agent execution.
- **`brand`** -- Horizontal bars format for LLM-generated output, replacing box-drawing characters.
- **`suggest-next`** -- Annotate pre-seeded discussion in Next Up hints for remediation phases.

### Changed

- **`docs`** -- Source-validated GSD comparison document added. Consolidated 6 config sections into unified Configuration section in README. Execution Model section added. Contributing guide rewritten with QA review process and local dev setup. Default settings reference and runtime feature flags details added. (PRs #133, #125, #119)
- **`verify`** -- Added "Skip" option for checkpoint testing. CHECKPOINT loop now blocking with explicit wait-for-input via AskUserQuestion. Clarified UAT test requirements and banned automated checks. Updated code blocks to specify language for formatting clarity.
- **`suggest-compact`** -- Replaced `eval jq` with safe direct assignment. Dynamic token cost calculated from actual file sizes instead of hardcoded estimates.
- **`suggest-next`** -- Removed misleading `--resume` from verify `issues_found` output.
- **`execute-protocol`** -- Enhanced user interaction for first test results with CHECKPOINT and AskUserQuestion.
- **`commands`** -- Replaced shared temp file with deterministic symlink path. Updated inline script execution syntax for clarity. Used fenced code blocks for template processor execution. Removed dead `CLAUDE_PLUGIN_ROOT` fallback in `!` expressions.
- **`codeowners`** -- Added dpearson2699 as code owner.
- **`ci`** -- Improved ShellCheck and shell syntax check steps. Removed branch restriction for pull requests.

### Fixed

- **`phase-detect`** -- Prioritize earlier incomplete phases over later UAT issues (fixes #145). Add `require_phase_discussion` gate to earlier-incomplete scan. Collect all phases with UAT issues. Exclude SOURCE-UAT from UAT globs and cross-reference remediation phases. Implement `latest_non_source_uat` function for UAT file retrieval. Replace `ls`-pipe patterns with glob for-loops. Use `find` for file counting instead of `ls|wc -l`. Exclude SOURCE-UAT.md from UAT scanning globs. (PRs #146, #142)
- **`archive`** -- Detect unresolved UAT in shipped milestones, block archive on UAT issues. Deterministic milestone slug derivation via script. (PR #121)
- **`plugin-root`** -- Replace model-executed `CLAUDE_PLUGIN_ROOT` with inline load-time resolution. Content validation and process-tree fallback for `--plugin-dir`. Hardened resolver policy and runtime callsites. Replace `ls` glob with `find` for zsh compatibility. Use temp file for deterministic plugin root resolution. Added preamble for plugin root resolution in skills. (PR #137)
- **`symlink`** -- Canonicalize symlink target via `pwd -P` to survive cache deletion. Spin-wait guard for symlink race condition. (PR #144)
- **`hooks`** -- Add quad-resolution fallback for local dev mode (`--plugin-dir`).
- **`uat`** -- Flow discovered issues into remediation pipeline. Enhanced UAT issue detection and remediation suggestions. Make CHECKPOINT loop blocking with explicit wait-for-input. Multiple QA rounds: pad normalization, orphan guard, mid-execution guard, numeric sort, `sort -V` portability. (PR #142)
- **`vibe`** -- Read phase-detect live to avoid stale routing state. Fallback to preamble phase-detect on transient live-read failures. Avoid shared default session key collisions. Standardize deterministic session-key fallback. Run phase-detect.sh atomically in preamble.
- **`resume`** -- Use phase-detect.sh for deterministic state detection instead of inline logic.
- **`recovery`** -- Automatic state recovery wired into session-start via `recover-state.sh`. 5 rounds of QA hardening.
- **`remediation`** -- Pre-seed CONTEXT.md with UAT report for in-phase remediation. Skip discuss step for in-phase UAT remediation. Update sed commands to create backup files during ROADMAP.md and STATE.md edits. Seed ROADMAP.md and STATE.md for remediation phases.
- **`guards`** -- Narrow milestone path guards to prevent false positives. Harden milestone path guards in bash scripts.
- **`routing`** -- Harden milestone path guards in bash scripts to prevent cross-milestone pollution.
- **`cache`** -- Handle empty plugin cache globs under pipefail. Bridge local dev plugin root into marketplace cache. 5 rounds of QA hardening on cache operations.
- **`cache-nuke`** -- Handle empty plugin cache globs under `pipefail`.
- **`config`** -- Remove dir-existence check from `resolve-claude-dir.sh`. Fix bare `HOME/.claude` references in scripts. Auto-UAT runs UAT inline, not just suggests.
- **`session-start`** -- Bridge local dev plugin root into marketplace cache. Remove unused `PHASES_DIR` assignment.
- **`verify`** -- Add trailing newline to CHECKPOINT expected line. Use bash builtins for cross-platform portability. Enhance user interaction by adding AskUserQuestion for checkpoint responses.
- **`lint`** -- Resolve SC2034 warnings in `extract-verified-items.sh`.
- **`tests`** -- Hardened for BATS 1.10 compatibility — avoid backtick escaping incompatible with bats 1.10. Harden stale cache test against SIGINT from bats runner. Plugin root resolver safety and callsite checks. 6 rounds of QA on test suite. Regression tests for deterministic path pattern.
- **`docs`** -- Update defaults for lease locks and event recovery settings. Fix all markdown lint errors in README. Remove `.markdownlint.json` configuration file. Update plugin root resolution documentation.

## [1.30.1] - 2026-02-20

### Added

- **`session-start`** -- Shipped milestones detection and QA verification script for post-ship validation.
- **`context`** -- Pre-flight context guard to prevent mid-workflow compaction from disrupting agent execution.

### Changed

- **`milestone`** -- Removed ACTIVE-file milestone indirection. Slug derivation and decision/todo extraction enhanced in milestone scripts.
- **`flags`** -- Partially reverted flag graduation — restored 9 flags as configurable. Legacy key fallback added to all consumer scripts. Runtime defaults aligned with legacy fallback behavior.
- **`suggest-compact`** -- Replaced eval jq with safe direct assignment. Dynamic token cost from actual file sizes.
- **`worktree`** -- Defaults to off. Fixed merge args, normalized boundary paths, added branch-exists fallback.

### Fixed

- **`crash-recovery`** -- Avoid false fallback and preserve last words when SUMMARY.md missing.
- **`uat`** -- 4 rounds of QA fixes: pad normalization, orphan guard, mid-execution guard, numeric sort, sort -V portability, false remediation fallback.
- **`vibe`** -- Hardened UAT remediation routing and chain enforcement. Auto-route UAT remediation from /vbw:vibe.
- **`milestone`** -- Fixed rename-default-milestone slug derivation, post-ship state, collision guard, phases/ guard, generic tag strip, contract scope.
- **`scripts`** -- Null-safe jq patterns for false-default booleans. Tightened artifact globs. Removed unused variables (SC2034). Removed unreachable exit in validate-contract.sh.
- **`config`** -- Graduated v2_token_budgets. Stripped graduated V2/V3 flags from brownfield configs. Synced EXPECTED_FLAG_COUNT after worktree_isolation addition.
- **`tests`** -- Updated 90+ tests for graduated flags and portable paths. Fixed BATS_TEST_TMPDIR usage. Updated rollout-stage counts.

## [1.30.0] - 2026-02-19

### Added

- **`crash-recovery`** -- Agent crash recovery via `last_assistant_message` from CC 2.1.47 SubagentStop hook. `agent-stop.sh` captures agent final output to `.agent-last-words/` when SUMMARY.md missing. `validate-summary.sh` uses crash recovery files as fallback (60s freshness window). `session-start.sh` auto-cleans stale files (7-day TTL). Event log tracks `agent_shutdown` events with `last_message_length` metric.
- **`bash-classifier-tests`** -- 55 new BATS tests validating all 26 VBW hook bash patterns against CC 2.1.47 stricter permission classifier. Tests cover hook-wrapper.sh resolution, individual script invocations, bash-guard.sh pattern matching, and end-to-end integration. All patterns confirmed classifier-safe with zero changes needed to hooks.json.
- **`agent-memory`** -- Native `memory` frontmatter added to all 7 agents. Core agents (lead, dev, qa, debugger, architect) use `memory: project` for cross-session learning. Ephemeral agents (scout, docs) use `memory: local`.
- **`agent-restrictions`** -- Native `Task(agent_type)` spawn restrictions added to all 7 agents. Lead can only spawn Dev. Debugger can only spawn Debugger (competing hypotheses). Dev, architect, docs cannot spawn agents. Scout and QA already lacked Task capability.
- **`cc-version-table`** -- Claude Code version requirements table added to README with minimum versions for key features (hooks, teams, classifier, memory).
- **`token-analysis`** -- v1.30.0 token analysis document covering CC Alignment + Worktree Isolation impact: 85 scripts, 57 test files, 825 BATS tests. Per-request +12% (enforcement content), 73% reduction vs stock teams.
- **`worktree-isolation`** — Git worktree-per-plan isolation for Dev agents
  (6 scripts, enabled by default via `worktree_isolation` config, set `"off"` to disable).

### Changed

- **`feature-flags`** -- Graduated 20 always-true feature flags (6 v2_*, 14 v3_*). Removed dead else-branches from 18+ scripts. Consolidated duplicate flags (`v3_lock_lite` → `v3_lease_locks`, `v3_contract_lite` → `v2_hard_contracts`). Graduated v3 observability flags (metrics, schema_validation, smart_routing, monorepo_routing, validation_gates, delta_context).
- **`config`** -- `v2_token_budgets` now defaults to `false` in config/defaults.json. CC manages context natively.
- **`compaction`** -- Plan mode compaction workaround removed (CC 2.1.47 handles natively). Instructions updated to clarify CC-native vs VBW-specific behavior.
- **`update`** -- `/vbw:update` no longer displays restart requirement. Changes active immediately (CC 2.1.45+).
- **`token-budgets`** -- Added inline documentation to config/token-budgets.json explaining budget sizing rationale (1-4% of agent context windows) and per-task complexity scaling (0.6x-1.6x multipliers).

### Deprecated

- **`file-guard`** -- `scripts/file-guard.sh` marked as worktree-deprecation candidate with header comment.

### Removed

- **`lock-lite`** — Deprecated script removed (replaced by lease-lock.sh).

## [1.21.31] - 2026-02-19

### Added

- **`skills`** -- Installation scope selection step (project vs global) when installing skills. (PR #91 by @Aperrix)
- **`discovered-issues`** -- Pre-existing test failures surfaced as "Discovered Issues" across `/vbw:fix`, `/vbw:debug`, `/vbw:qa`, and `/vbw:verify` instead of being silently dropped. New DEVN-05 deviation code for dev agent. (PR #99 by @dpearson2699)
- **`debugger-report`** -- New `debugger_report` schema type replacing incorrectly-shaped `blocker_report` usage by the Debugger agent. Role Authorization Matrix updated. (PR #99 by @dpearson2699)
- **`state-persistence`** -- Root STATE.md content (todos, key decisions, project-level notes) now persists across milestone shipping. New `migrate-orphaned-state.sh` and `persist-state-after-ship.sh` scripts. (PR #103 by @dpearson2699)

### Changed

- **`bootstrap`** -- Codebase mapping bootstrap across all agents now uses META.md gating and "whichever exist" qualification to avoid wasted tool calls. Compaction re-reads codebase files. (PR #99 by @dpearson2699)
- **`bootstrap`** -- Key Decisions section removed from CLAUDE.md template. Existing decision rows migrated to STATE.md. Deprecated section handling added. (PR #93 by @dpearson2699)
- **`requirements`** -- Added minimum Claude Code version table to README documenting CC 2.1.47+ requirement for agent teams model routing and plan mode native support.

### Fixed

- **`help`** -- CLAUDE_CONFIG_DIR fallback added to backtick expansion in help.md for non-standard config paths. (PR #101 by @halindrome)
- **`hooks`** -- Circuit breaker added to `task-verify.sh` preventing infinite loop when failed verification re-triggers itself. Expanded stop words in session-stop.sh. (PR #95 by @dpearson2699)

### Compatibility

- **Agent Teams Model Routing** -- Requires Claude Code >= 2.1.47. Earlier versions had silently broken model routing for team teammates, causing all agents to use the default model instead of role-specific model profiles. If you experience agents using incorrect models (e.g., all agents using Sonnet when configured for Opus/Haiku), upgrade to Claude Code 2.1.47 or later.

## [1.21.30] - 2026-02-17

### Added

- **`rolling-summary`** -- New `scripts/compile-rolling-summary.sh` compiles prior SUMMARY.md files into a condensed `ROLLING-CONTEXT.md` (<200 lines). Integrated into `compile-context.sh` and `cache-context.sh` hash. Feature-flagged via `v3_rolling_summary` config. Archive and execute modes call it automatically.
- **`correlation-id`** -- `scripts/log-event.sh` auto-resolves `correlation_id` from `VBW_CORRELATION_ID` env var or `.execution-state.json`. Execute protocol generates UUID at phase start. Zero caller changes required — all shell callers get correlation threading for free.

### Changed

- **`readme`** -- Updated token efficiency section with v1.21.30 analysis (17% per-request reduction). Consolidated comparison table. Linked all 5 analysis reports. Fixed agent count (6→7). Trimmed Manifesto section.
- **`statusline`** -- Halved progress bar widths for compact display.
- **`agent-start`** -- Added tmux pane detection for PID→pane_id tracking.
- **`agent-stop`** -- Added tmux pane auto-close on agent stop.
- **`session-stop`** -- Added `.agent-panes` to cleanup list.

## [1.21.29] - 2026-02-17

### Added

- **`shutdown-protocol`** -- Agent shutdown request/response schema and handlers for all agents. Message types `shutdown_request`/`shutdown_response` added to `message-schemas.json`. Agents gracefully terminate on orchestrator request. 4 rounds of QA hardening. (PR #90 by @dpearson2699)
- **`codebase-mapping`** -- Bootstrap codebase mapping for dev, qa, lead, and architect agents. Agents now reference PATTERNS.md, DEPENDENCIES.md, ARCHITECTURE.md, and CONCERNS.md from `.vbw-planning/codebase/` when available. (#78, #79, #80, #81 by @dpearson2699)
- **`list-todos`** -- New `/vbw:list-todos` command to browse and act on pending todos with milestone context resolution.
- **`config`** -- Effort-aware agent `maxTurns` resolution. Unlimited turns via `0`/`false`. Documented in README.

### Changed

- **`todos`** -- Migrated from `### Pending Todos` to flat `## Todos` structure. Todo extraction delegated to `list-todos.sh` for token efficiency.
- **`vibe`** -- Scout returns findings to orchestrator instead of writing files directly. Add/Insert Phase modes now load codebase mapping. Strengthened Lead shutdown HARD GATE with compaction-resilient verification and pre-chain checks.
- **`execute`** -- Post-summary improvisation blocked with STOP + Discovered Issues pattern. Post-shutdown verification gate added for Pure-Vibe loop safety.
- **`readme`** -- Updated hook diagram for SubagentStart/Stop hardening, added Agent Turn Limits section.

### Fixed

- **`hooks`** -- Isolation marker lifecycle causing false blocks. Compaction and session-stop marker races. CLAUDE_PLUGIN_ROOT fallback for `--plugin-dir` installs. Role alias normalization and concurrency hardening for agent-start/stop. YAML frontmatter context required for expanded VBW command detection. Security-filter path-based root resolution with stale TTL. Commit keyword matching skipped for role-only task subjects. Docs role added to lifecycle hook matchers and token budgets. 14 regression tests added.
- **`hooks`** -- Missing `hookEventName` in session-start.sh and blocker-notify.sh. Skip commit gate for `[analysis-only]` tasks.
- **`agents`** -- Lead shutdown gates strengthened to prevent tmux pane accumulation. PR review diff-vs-repo rule added to CLAUDE.md.
- **`commands`** -- CLAUDE_PLUGIN_ROOT resolution in model-executed contexts. Slug validation and milestone resolution alignment in pause.md.

## [1.21.28] - 2026-02-16

### Added

- **`debugger`** -- Codebase mapping bootstrap now references PATTERNS.md and DEPENDENCIES.md in addition to ARCHITECTURE.md and CONCERNS.md. Compiled context includes dynamic "Codebase Map Available" hint section for debugger role. Cache invalidation when mapping files change. (PR #77 by @dpearson2699)
- **`debug`** -- Codebase bootstrap instruction added to both Path A (team) and Path B (single) debugger task prompts. (PR #77 by @dpearson2699)

### Fixed

- **`statusline`** -- Replace `tr` with `sed` for UTF-8 progress bar characters on Linux. GNU `tr` corrupts multi-byte characters (█ ░ ▓) by processing byte-by-byte.

## [1.21.26] - 2026-02-16

### Added

- **`discussion-engine`** -- Unified discussion engine replacing three competing subsystems (bootstrap discovery, phase discovery, phase discussion). One engine, three entry points (`/vbw:vibe`, `/vbw:vibe --discuss N`, `/vbw:discuss N`). Auto-calibrates between Builder and Architect modes from conversation signals. Generates phase-specific gray areas instead of keyword-matched templates. ~1095 lines removed, ~180 lines added.
- **`discuss`** -- New `/vbw:discuss [N]` standalone command for explicit phase discussions.
- **`agent-health`** -- New agent health monitoring system with start/stop/idle/cleanup/orphan-recovery subcommands, lifecycle hooks (SubagentStart, SubagentStop, TeammateIdle, Stop), and integration tests.
- **`circuit-breaker`** -- Circuit breaker protocol added to all agent definitions for resilient failure handling.
- **`compaction`** -- Enhanced compaction recovery with TaskGet reminder for better context restoration.
- **`debugger`** -- Bootstrap investigation from codebase mapping when available.

### Changed

- **`vibe`** -- Bootstrap B2 now delegates to the discussion engine instead of 6-round rigid questioning. Plan mode no longer auto-asks 1-3 questions; users run `/vbw:discuss` explicitly if they want context. Discuss mode replaced with a 5-line engine delegation.
- **`bootstrap-requirements`** -- Removed tier-based annotation (table_stakes/differentiators/anti_features) and research cross-referencing. Reads simplified `discovery.json` schema directly.
- **`readme`** -- Updated all counts (31k lines, 81 scripts, 23 commands, 7 agents, 461 tests). Added `/vbw:discuss` command, Docs agent, agent health monitoring, discussion engine references.

### Removed

- **`discovery-protocol`** -- Deleted 800-line `references/discovery-protocol.md`. Replaced by `references/discussion-engine.md` (~150 lines).

### Fixed

- **`teams`** -- Remove stale tmux forced in-process workaround, restore split-pane mode.
- **`token-budget`** -- Switch from line-based to character-based budgets, default to head truncation, remove cross-task escalation.
- **`ci`** -- Add executable bit to `agent-health.sh`. Remove unused variables in `token-baseline.sh` (SC2034). Use `CLAUDE_CONFIG_DIR` fallback in `agent-health.sh`.

## [1.21.18] - 2026-02-16

### Fixed

- **`hooks`** -- Skip commit gate for `[analysis-only]` tasks. Debugger agents in team mode no longer get blocked by the TaskCompleted hook when investigating hypotheses without applying fixes. Contributed by [@dpearson2699](https://github.com/dpearson2699) (#71, fixes #70).
- **`hooks`** -- Add missing `hookEventName` to session-start.sh (3 outputs) and blocker-notify.sh (1 output). Without this field, Claude Code's schema validator silently dropped all VBW context injection on session start. Also hardens compaction marker handling for clock skew and corrupted markers. Contributed by [@dpearson2699](https://github.com/dpearson2699) (#73, fixes #72).

## [1.21.17] - 2026-02-15

### Fixed

- **`planning-git`** -- Add 24 missing transient runtime artifacts to `ensure_transient_ignore()` — session tracking, metrics, caching, events, snapshots, logging, watchdog, and codebase mapping files are now excluded from `planning_tracking=commit` commits. Contributed by [@dpearson2699](https://github.com/dpearson2699) (#69, fixes #66).

## [1.21.16] - 2026-02-15

### Added

- **`max-turns`** -- Agent turn-budget resolver with effort-based scaling (thorough=1.5x, balanced=1x, fast=0.8x, turbo=0.6x), per-agent defaults, and config override support. Contributed by [@dpearson2699](https://github.com/dpearson2699) (#64).

### Fixed

- **`hooks`** -- Prevent false isolation blocks by tightening SubagentStart/Stop/TeammateIdle/TaskCompleted matchers from 6 to 24 patterns for correct VBW agent detection. Contributed by [@dpearson2699](https://github.com/dpearson2699) (#64).
- **`compact`** -- Role-matched snapshot restore prefers snapshots from the same agent role after compaction, with fallback to latest. Task-level resume hints from event log provide in-progress task and resume candidate context. Contributed by [@Solvely-Colin](https://github.com/Solvely-Colin) (#65).
- **`agents`** -- Add docs agent to max-turns resolver and fix missing EOF newline in resolve-agent-max-turns.sh.

## [1.21.15] - 2026-02-15

### Added

- **`agents`** -- New docs agent (vbw-docs) for documentation tasks with Sonnet as default model across all profiles, plus `qa_skip_agents` config to auto-skip QA for documentation work.

## [1.21.14] - 2026-02-15

### Fixed

- **`prompt-preflight`** -- Stop deleting `.vbw-session` marker on non-`/vbw:` prompts. The marker was being removed mid-workflow when users sent follow-up messages (plan approvals, answers), causing `security-filter.sh` to block Write/Edit calls to `.vbw-planning/`. Cleanup now only happens at session end via `session-stop.sh`.
- **`hook-wrapper`** -- Add `CLAUDE_CONFIG_DIR` fallback in SIGHUP handler. Previously used bare `$HOME/.claude` without respecting custom config directory.
- **`shellcheck`** -- Fix SC2155 warnings (declare and assign separately) in `tmux-watchdog.sh`, `session-start.sh`, `clean-stale-teams.sh`, `doctor-cleanup.sh`. Fix SC2034 unused variable in `doctor-cleanup.sh`.
- **`security-filter`** -- Remove `.vbw-planning/` self-blocking. The marker-based isolation (`.gsd-isolation` + `.active-agent` + `.vbw-session`) caused false blocks in too many scenarios: orchestrator after team deletion, agents before markers set, Read calls before prompt-preflight runs. GSD isolation is enforced by CLAUDE.md instructions + `.planning/` block (VBW→GSD direction).

## [1.21.11] - 2026-02-15

### Added

- **`help`** -- Dynamic help output from command frontmatter. Added `category:` field to all 22 commands and `scripts/help-output.sh` that reads frontmatter to generate grouped, formatted help. Zero tokens, zero drift.
- **`tmux`** -- PID tracking utility for agent process registration and cleanup on SubagentStop.
- **`tmux`** -- Watchdog script for tmux detach detection, launched on session start.
- **`tmux`** -- SIGHUP trap fallback in hook-wrapper for tmux disconnect resilience.
- **`tmux`** -- Forced in-process mode auto-patch when tmux is detected.
- **`session`** -- Orphan claude process cleanup on SessionStart.
- **`session`** -- Stale team cleanup script with paired tasks directory cleanup, integrated into SessionStart.
- **`compaction`** -- Pre-compact agent state snapshots with agent metadata, restore in post-compact hook.
- **`doctor`** -- Runtime health checks: cleanup preview, --cleanup flag, cleanup logging with summary counts.

### Fixed

- **`doctor`** -- Remove `local` keyword from top-level case block (bash compatibility).

### Documentation

- **`gitignore`** -- Runtime files (snapshots, watchdog, doctor logs) documented in .gitignore.

---

## [1.21.10] - 2026-02-15

### Fixed

- **`commands`** -- Plugin root preamble dual-fallback. When `CLAUDE_PLUGIN_ROOT` is empty (observed in some marketplace installs), the backtick preamble now resolves via the plugin cache using the same `sort -V | tail -1` pattern established by PR #54 for hooks. Zero regression when `CLAUDE_PLUGIN_ROOT` is set — the fallback never fires. 15 command preambles + 4 backtick bash calls updated. Extends PR #50's preamble architecture with PR #54's dual-fallback philosophy.
- **`testing`** -- `verify-plugin-root-resolution.sh` updated to recognize both simple and dual-fallback preamble forms.

---

## [1.21.9] - 2026-02-15

### Added

- **`security`** -- Database safety guard. PreToolUse hook (`bash-guard.sh`) intercepts every Bash command and blocks 40+ destructive patterns across Laravel, Rails, Django, Prisma, Knex, Sequelize, TypeORM, Drizzle, Diesel, SQLx, Ecto, raw SQL clients, Redis, MongoDB, and Docker volumes. Fires on all agents with Bash access (Dev, QA, Lead, Debugger). Override with `VBW_ALLOW_DESTRUCTIVE=1` or `bash_guard=false` config.
- **`security`** -- `config/destructive-commands.txt` blocklist file, extensible per-project via `.vbw-planning/destructive-commands.local.txt`.
- **`agents`** -- `## Database Safety` prompt sections added to vbw-qa, vbw-dev, vbw-debugger, and vbw-lead agents.
- **`contracts`** -- `forbidden_commands` gate type in `hard-gate.sh` for per-plan command restrictions.
- **`templates`** -- `forbidden_commands: []` field added to PLAN.md template.
- **`docs`** -- `docs/database-safety-guard.md` — full design document with flowchart, pattern table, override guide, and architecture decisions.
- **`readme`** -- Database safety guard in Features section, Settings Reference (`bash_guard`), Security hook diagram updated.

---

## [1.21.8] - 2026-02-15

### Added

- **`readme`** -- Feature Flags Reference documenting all 20 v2/v3 flags with descriptions, dependencies, and toggle instructions. Settings Reference for all config keys. Planning & Git section for `planning_tracking` and `auto_push`. (PR #62, @dpearson2699)
- **`readme`** -- Contributors section now uses [contrib.rocks](https://contrib.rocks/) auto-updating image.

### Changed

- **`config`** -- `/vbw:config` feature flags display uses human-friendly labels instead of raw `v2_`/`v3_` prefixed keys. (PR #62, @dpearson2699)

---

## [1.21.7] - 2026-02-15

### Added

- **`planning_tracking` + `auto_push` config** — Control how VBW planning artifacts are tracked in git. Three modes: `manual` (default), `ignore` (auto-gitignore `.vbw-planning/`), `commit` (auto-commit at lifecycle boundaries: bootstrap, plan, execute, archive). Push behavior: `never`/`after_phase`/`always`. New `scripts/planning-git.sh` with sync-ignore, commit-boundary, and push-after-phase subcommands. `/vbw:init` asks preference during setup. (PR #59, @dpearson2699)
- **Contributors section in README** — Added [@dpearson2699](https://github.com/dpearson2699), [@halindrome](https://github.com/halindrome), and [@navin-moorthy](https://github.com/navin-moorthy).

---

## [1.21.6] - 2026-02-15

### Fixed

- **`scripts/migrate-config.sh`** — Brownfield config migration extracted into shared script. SessionStart hook and `/vbw:config` both run migration, ensuring missing v2/v3 flags are backfilled even when hooks didn't fire. Legacy `agent_teams` key renamed to `prefer_teams` and cleaned up. (PR #57, @dpearson2699)

### Added

- **`scripts/migrate-config.sh --print-added`** — Generic defaults merge from `config/defaults.json`. Future config keys auto-backfill without code changes. `/vbw:config` now shows a notice when settings were added. (PR #58, @dpearson2699)

---

## [1.21.5] - 2026-02-15

### Fixed

- **`hooks.json` + `hook-wrapper.sh`** — Hooks now resolve `CLAUDE_PLUGIN_ROOT` via dual fallback: cache path first, then `--plugin-dir` path. Previously, `--plugin-dir` installs had no `CLAUDE_PLUGIN_ROOT` set, causing all hook scripts to silently fail. New `resolve-claude-dir.bats` and `sessionstart-compact-hooks.bats` tests added. (PR #54, @dpearson2699)

---

## [1.21.4] - 2026-02-15

### Fixed

- **`statusline-cache-isolation.bats`** — CI runners now have git identity configured in test setup(), fixing "Author identity unknown" failures on GitHub Actions. Default branch detection is now dynamic instead of hardcoding "main". Statusline also renders repo label on detached HEAD. (PR #46, @dpearson2699)
- **`commands/*.md`** — 15 commands now include `Plugin root: !` backtick preamble so `${CLAUDE_PLUGIN_ROOT}` resolves correctly in model-executed Bash blocks. Previously the variable expanded to empty string, silently breaking all path references. Regression test added. (PR #50, @dpearson2699)
- **`research-persistence.bats`** — Tests now use tracked `templates/RESEARCH.md` as fixture instead of gitignored `.vbw-planning/` runtime state. CI no longer depends on local development artifacts existing at repo root. (PR #56, @dpearson2699)

### Added

- **`.github/CODEOWNERS`** — `* @yidakee` ensures all PRs auto-request code owner review.
- **Branch protection** — main branch now requires passing CI and PR review before merge.

---

## [1.21.3] - 2026-02-14

### Fixed

- **`session-start.sh`** — Config migration now backfills `prefer_teams` for users who initialized before v1.20.8, defaulting to `"always"`. Previously these users had the old boolean `agent_teams` but no `prefer_teams` enum, causing silent config drift.
- **`session-start.sh`** — jq migration failures now log a warning to stderr instead of failing silently. Users see a clear message when config migration encounters malformed JSON.

### Testing

- **16 new tests** across 2 new test files:
  - `tests/config-migration.bats` (9 tests) — empty config, partial config, full config no-op, idempotent migration, malformed JSON handling, EXPECTED_FLAG_COUNT sync validation, prefer_teams migration, prefer_teams preservation, count=23 validation
  - `tests/research-persistence.bats` (7 tests) — Phase 1 RESEARCH.md section format, research-warn.sh JSON schema (4 cases), compile-context RESEARCH.md inclusion, flag-disabled path verification
- Test suite: 383 → 397 total tests (zero regressions)

### Documentation

- **`research-persistence`** — Documented Scout write path, test coverage, and known hook isolation limitation for RESEARCH.md creation

---

## [1.21.2] - 2026-02-14

### Fixed

- **`/vbw:config`** — Feature flags (`v3_*`, `v2_*`) now displayed in config output. Previously these flags existed in `config.json` but were invisible to users — the only way to discover or toggle them was manual JSON editing. Now shown as a dedicated "Feature Flags" section with descriptions and toggle hint. (Reported by @dpearson2699)

---

## [1.21.1] - 2026-02-14

### Fixed

- **`vbw-debugger`** — Increased maxTurns from 40 to 80. The scientific method protocol (reproduce + hypothesize + evidence + diagnose + fix + verify) legitimately needs more turns for complex bugs in large codebases. (Reported by @dpearson2699, #43)

### Added

- **`vbw-debugger`** — Turn budget awareness: debugger now proactively checkpoints its state (hypotheses, evidence, files examined, next steps) when running long, preventing context loss on turn exhaustion. (Proposed by @dpearson2699, #44)

---

## [1.21.0] - 2026-02-14

### Community Contributions

- **PR #41** (@halindrome) — Statusline cache isolation: per-repo cache key with cross-platform hash
- **PR #36** (@dpearson2699) — CI consolidation, contributor workflow improvements, ShellCheck fixes

### Fixed

- **`vbw-statusline.sh`** — Statusline cache key now includes a hash of `git rev-parse --show-toplevel`, preventing cross-repo cache leakage when running Claude Code in multiple repos. Cross-platform hash: `md5sum` (Linux) -> `md5` (macOS) -> `cksum` (fallback). Local-only repos (no remote) display directory name instead of leaking another repo's data. (Thanks @halindrome)
- **`pre-push-hook.sh`** — Relaxed to consistency-only checks: verifies 4 version files match but no longer requires VERSION to change on every push. Removes ~30 lines of false-positive-prone enforcement. (Thanks @dpearson2699)
- **`resolve-claude-dir.sh`** — Added `export` to `CLAUDE_DIR` assignment so sourcing scripts can access it. (Thanks @dpearson2699)
- **`bootstrap-project.sh`** — Removed unused `CREATED` variable (ShellCheck SC2034). (Thanks @dpearson2699)
- **`bootstrap-requirements.sh`** — Removed unused `COMPETITORS` and `ANSWERED_COUNT` variables (ShellCheck SC2034). (Thanks @dpearson2699)

### Changed

- **CI workflows** — Consolidated `.github/workflows/verification.yml` into `ci.yml`: shell syntax check + 4 contract verification steps now run as part of the test job. One workflow instead of two overlapping ones. (Thanks @dpearson2699)
- **`CLAUDE.md`** — Removed version bump instruction (contributor concern, not end-user relevant); push guard retained. (Thanks @dpearson2699)
- **`CONTRIBUTING.md`** — Rewritten Version Management section: describes manual merge-time bumping, no release-please references. (Thanks @dpearson2699)

### Testing

- **10 new tests** in `tests/statusline-cache-isolation.bats` for cache key isolation, cross-repo leakage prevention, no-remote directory name display, stale cleanup, and non-git directory handling. (Thanks @halindrome)

---

## [1.20.9] - 2026-02-14

### Community Contributions

- **PR #35** (@dpearson2699) — Security filter bypass fix: `hook-wrapper.sh` exit code 2 passthrough
- **PR #32** (@dpearson2699) — Progress dashboard fix: `state-updater.sh` milestone-aware path resolution

### Fixed

- **`hook-wrapper.sh`** — exit code 2 (Claude Code's "block tool call" signal) was silently converted to exit 0, disabling the security filter for `.env`, `.pem`, `.key` files. Now passes exit 2 through correctly. (Thanks @dpearson2699)
- **`session-start.sh`** — compaction-marker check prevents error output during compaction cycles. (Thanks @dpearson2699)
- **`map-staleness.sh`** — compaction-marker skip and `_diag()` stderr helper for hook mode. (Thanks @dpearson2699)
- **`post-compact.sh`** — `.compaction-marker` added to cleanup. (Thanks @dpearson2699)
- **`state-updater.sh`** — three bugs fixed: missing `.execution-state.json` no longer skips STATE.md/ROADMAP.md updates; reads `.plans[]` (current schema) instead of only `.phases{}` (old schema); `planning_root_from_phase_dir()` resolves milestone-aware paths instead of hardcoded `.vbw-planning/`. (Thanks @dpearson2699)

### Testing

- **14 new tests** in `tests/sessionstart-compact-hooks.bats` for compaction marker, hook wrapper exit codes, and session start behavior. (Thanks @dpearson2699)
- **4 new tests** in `tests/state-updater.bats` for milestone-aware path resolution and schema support. (Thanks @dpearson2699)

---

## [1.20.8] - 2026-02-14

### Added

- **`config`** -- New `prefer_teams` config option (`always`|`when_parallel`|`auto`) replaces boolean `agent_teams`. Default `always` creates Agent Teams for all operations, maximizing color-coded UI visibility
- **`vibe.md`** -- Plan mode respects `prefer_teams` — creates team even for Lead-only when set to `always`
- **`debug.md`** -- Debug mode respects `prefer_teams` — uses team path for all bugs when set to `always`

### Fixed

- **`init.md`** -- Config scaffold creates `prefer_teams` instead of deprecated `agent_teams`
- **`session-start.sh`** -- Reads `prefer_teams` config instead of `agent_teams`
- **`phase-detect.sh`** -- Reads `prefer_teams` config instead of `agent_teams`

### Changed

- **`config.md`** -- Settings reference table updated for `prefer_teams` enum
- **`test_helper.bash`** -- Test fixtures updated for `prefer_teams` config

---

## [1.20.7] - 2026-02-14

### Fixed

- **`vbw-statusline.sh`** -- OAuth token lookup now detects keychain access denial vs API key usage. Users with OAuth (Pro/Max) whose keychain blocks terminal access now see an actionable diagnostic message instead of misleading "N/A (using API key)". Added `VBW_OAUTH_TOKEN` env var as escape hatch. Uses `claude auth status` to distinguish auth methods when credential store fails.

---

## [1.20.6] - 2026-02-14

### Community Contributions

- **PR #38** (@navin-moorthy) -- Human UAT verification gate with CHECKPOINT UX

### Added

- **`commands/verify.md`** -- New `/vbw:verify` command for human acceptance testing with per-test CHECKPOINT loop, resume support, and severity inference
- **`templates/UAT.md`** -- UAT result template with YAML frontmatter for structured pass/fail/partial tracking
- **`execute-protocol`** -- Step 4.5 UAT gate after QA pass (autonomy-gated: cautious + standard only)
- **`vibe.md`** -- `--verify` flag, Verify Mode section, and NL keyword detection (verify, uat, acceptance test, etc.)
- **`execute-protocol`** -- TeamCreate for multi-agent execution (2+ plans get colored labels, status bar entries, peer messaging)
- **`vibe.md`** -- TeamCreate for Plan mode when Scout + Lead co-spawn (research + planning as coordinated team)

### Changed

- **`suggest-next.sh`** -- UAT suggestions surfaced after QA passes (cautious + standard autonomy)
- **`execute-protocol`** -- Step 5 shutdown now conditional on team existence (skip for single plan/turbo)

---

## [1.20.5] - 2026-02-13

### Community Contributions

- **PR #27** (@halindrome) -- CLAUDE_CONFIG_DIR support across all hooks and scripts
- **PR #29** (@dpearson2699) -- Fix 6 command names missing `vbw:` prefix for discovery

### Added

- **`resolve-claude-dir.sh`** -- Central helper for Claude config directory resolution

### Fixed

- **`hooks`** -- All 21 hook commands now respect `CLAUDE_CONFIG_DIR` environment variable
- **`commands`** -- 6 commands missing `vbw:` prefix now discoverable under `/vbw:*`
- **`doctor`** -- Plugin cache check respects custom config directory
- **`verify-vibe`** -- Removed unused `GLOBAL_MIRROR` variable

### Changed

- **`scripts`** -- 8 scripts source central resolver instead of inline fallback pattern

### Testing

- **`resolve-claude-dir`** -- 19 new bats tests for CLAUDE_CONFIG_DIR resolution

---

## [1.20.4] - 2026-02-13

### Fixed

- **`shellcheck`** -- resolved all shellcheck warnings across scripts. Removed unused variables, quoted command substitutions, added targeted disables for intentional patterns (ls|grep for zsh compat, git `@{u}` syntax, read-consumed vars).
- **`ci`** -- bats tests now pass on GitHub Actions Ubuntu runner. Added git user config for phase-detect tests, fixed cross-platform `stat` flag order (GNU first, BSD fallback) in resolve-agent-model.
- **`scripts`** -- added executable bit to 6 scripts missing chmod +x: generate-incidents.sh, lease-lock.sh, recover-state.sh, research-warn.sh, route-monorepo.sh, smart-route.sh.
- **`testing`** -- corrected command name expectation in verify-commands-contract.sh. Test now accepts both bare names (`map`) and prefixed names (`vbw:map`) since the plugin system auto-prefixes.

---

## [1.20.3] - 2026-02-13

### Changed

- **`discovery-protocol`** -- complete rewrite of `references/discovery-protocol.md` for coherence and completeness. B2 bootstrap and Discuss mode logic fully specified with gap fixes from research. Removed brittle line number references from Integration Points.
- **`vibe`** -- updated Discuss mode and Bootstrap B2 to align with rewritten discovery protocol.

---

## [1.20.2] - 2026-02-13

### Community Contributions

Merges 10 pull requests from **[@dpearson2699](https://github.com/dpearson2699)** (Derek Pearson). These contributions identified bugs, proposed fixes, and directly influenced the v1.20.0 architecture. Previously closed without proper merge credit — now properly merged and attributed.

### Merged

- **#10** -- `fix(update)`: identified `CLAUDE_PLUGIN_ROOT` breakage when commands copied to user directory.
- **#11** -- `fix(compile-context)`: fixed unpadded phase number resolution in `compile-context.sh`.
- **#12** -- `fix(stack)`: identified nested manifest scanning gap in `detect-stack.sh`, added iOS/Swift mappings.
- **#13** -- `fix(map)`: identified zsh `nomatch` glob crash, triggering a repo-wide zsh compatibility audit.
- **#14** -- `fix(todo)`: fixed STATE.md/todo.md heading mismatch causing unreliable insertion after `/vbw:init`.
- **#15** -- `test(verification)`: built repo-wide verification harness (228+ tests, GitHub Actions CI, command frontmatter validation).
- **#17** -- `fix(bootstrap)`: hardened CLAUDE.md bootstrap with centralized isolation, brownfield stripping, input guardrails.
- **#19** -- `refactor(isolation)`: designed the two-layer defense model and auto-migration that ships as the canonical isolation architecture.
- **#22** -- `fix(vibe)`: identified and fixed scope mode writing lifecycle actions into Todos section.
- **#24** -- `fix(hooks)`: systematic audit of `hookEventName` compliance across 8 hook scripts.

### Added (from Derek's PRs, beyond v1.20.1)

- **`ci`** -- GitHub Actions CI workflow (`.github/workflows/verification.yml`) for automated PR and push checks.
- **`testing`** -- repo-wide test harness: `testing/run-all.sh`, `verify-bash-scripts-contract.sh`, `verify-commands-contract.sh`.
- **`bootstrap`** -- `scripts/verify-claude-bootstrap.sh` with 27 contract tests.
- **`hooks`** -- `hookEventName` compliance added to 7 additional hook scripts (`post-compact`, `map-staleness`, `prompt-preflight`, `validate-commit`, `validate-frontmatter`, `validate-summary`).
- **`stack`** -- expanded `config/stack-mappings.json` with iOS/Swift and recursive detection entries.

---

## [1.20.1] - 2026-02-13

### Fixed

- **`update`** -- prefix all `claude plugin` commands with `unset CLAUDECODE &&` to prevent "cannot be launched inside another Claude Code session" error when running `/vbw:update` from within an active session.
- **`statusline`** -- remove misleading agent count that counted all system-wide `claude` processes instead of VBW-managed agents.

## [1.20.0] - 2026-02-13

### Added

- **`doctor`** -- `/vbw:doctor` health check command with 10 diagnostic checks: jq installed, VERSION file, version sync, plugin cache, hooks.json validity, agent files, config validation, script permissions, gh CLI, sort -V support. `disable-model-invocation: true`.
- **`templates`** -- CONTEXT.md and RESEARCH.md templates for agent context compilation and research output structure.
- **`blocker-notify`** -- TaskCompleted hook auto-notifies blocked agents when their blockers resolve, preventing teammate deadlocks.
- **`control-plane`** -- lightweight Control Plane dispatcher (`scripts/control-plane.sh`, 328 lines) that sequences all enforcement scripts into a unified flow. Four actions: pre-task (contract → lease → gate), post-task (gate → release), compile (context compilation), full (all-in-one). Fail-open on script errors, JSON result output, lease conflict retry with 2s wait. 15 unit tests + 3 integration tests.
- **`rollout-stage`** -- 3-stage progressive flag rollout automation (`scripts/rollout-stage.sh`). Stages: observability (threshold 0), optimization (threshold 2), full (threshold 5). Actions: check prerequisites, advance flags atomically, status report with all 14 v3_ flags. Stage definitions in `config/rollout-stages.json`. Supports `--dry-run`. 10 tests.
- **`token-baseline`** -- per-phase token usage measurement and comparison (`scripts/token-baseline.sh`). Actions: measure (aggregate from event log), compare (delta with direction indicators), report (markdown with budget utilization by role). Baselines saved to `.baselines/token-baseline.json`. 10 tests.
- **`token-intelligence`** -- per-task token budgets computed from contract metadata. Complexity scoring (must_haves weight 1, files weight 2, dependencies weight 3) maps to 4 tier multipliers. Fallback chain: per-task → per-role → config defaults. Token cap escalation emits `token_cap_escalated` event and reduces remaining budget for subsequent tasks. 12 tests.
- **`context-index`** -- `context-index.json` manifest generated in `.cache/` with key-to-path mapping per role/phase. Atomic writes via mktemp+mv. Updated on every cache miss, timestamps refreshed on cache hits. 6 tests.
- **`execute-protocol`** -- Control Plane orchestration block in Step 3, context compilation and token budget guards in Steps 3-4, cleanup in Step 5. Individual scripts (generate-contract.sh, hard-gate.sh, compile-context.sh, lock-lite.sh) preserved as independent fallbacks.

### Changed

- **`isolation`** -- consolidated to single root CLAUDE.md with context isolation rules for both VBW and GSD plugins.
- **`agents`** -- removed dead `memory: project` from all 6 agent frontmatters. Clarified standalone vs teammate session scope in debugger.
- **`references`** -- fixed internal references in verification-protocol.md (S5→§5/VRFY-06). Added per-model cost basis to model-profiles.md methodology note.
- **`README`** -- token efficiency section updated with v1.20.0 numbers (8,807 lines bash, 63 scripts, 21 commands, 11 references). Command/hook counts updated to 21. Typo and incomplete sentence fixes.
- **`compile-context`** -- ROADMAP metadata parser fixed (`### Phase` → `## Phase` to match actual format). Scout, Debugger, and Architect roles extended with conventions, research, and delta files. Code slices added to Debugger and Dev contexts.
- **`token-budget`** -- extended argument parsing for contract path and task number. Per-task budget computation with complexity scoring. Escalation config added to `config/token-budgets.json`.
- **`detect-stack`** -- expanded coverage for Python, Rust, Go, Elixir, Java, .NET, Rails, Laravel, Spring. 4 new manifest file detections.
- **`control-plane`** -- `context_compiler` default harmonized from `false` to `true` to match phase-detect.sh and defaults.json.
- **`config`** -- all 20 V2/V3 feature flags available in project config (default: off, enable via `/vbw:config`). 15 flags added to migration: lock_lite, validation_gates, smart_routing, event_log, schema_validation, snapshot_resume, lease_locks, event_recovery, monorepo_routing, hard_contracts, hard_gates, typed_protocol, role_isolation, two_phase_completion, token_budgets.

### Fixed

- **`task-verify`** -- bash 3.2 compatibility: replaced `case...esac` inside piped command substitution with `grep -Ev` stop word filter. macOS bash 3.2.57 parsing bug.
- **`bump-version`** -- added `--offline` flag to skip remote GitHub fetch for CI/air-gapped environments.
- **`phase-detect`** -- compaction threshold now configurable via `compaction_threshold` in config.json (default: 130000).
- **`scope`** -- prevent lifecycle actions from polluting Todos.
- **`init`** -- remove `*.sln` glob that crashes zsh on macOS.
- **`teams`** -- auto-notify blocked agents when blockers clear.
- **`defaults`** -- harmonize model_profile fallback to quality across all scripts.
- **`migration`** -- comprehensive flag migration and jq boolean bug fix.
- **`release`** -- resolve 8 findings from 6-agent pre-release verification.
- **`validate-commit`** -- heredoc commit messages no longer overwritten by `-m` flag extraction. macOS sed compatibility fix.
- **`session-start`** -- zsh glob compatibility across session-start, snapshot-resume, lock-lite, and file-guard scripts.
- **`security-filter`** -- stale marker detection (24h threshold) prevents false positive blocks on old markers.

### Documentation

- **`tokens`** -- v1.20.0 Full Spec Token Analysis (664 lines): 258 commits, 6 milestones, per-request -7.3%, ~85% coordination overhead reduction maintained despite 33% codebase growth.

### Tests

- **86 new tests** across 5 new test files: hooks-isolation-lifecycle.bats (10), phase0-bugfix-verify.bats (16), token-budgets.bats (12), context-index.bats (6), control-plane.bats (18), rollout-stage.bats (10), token-baseline.bats (10). Plus 4 context metadata tests. Test suite: 237 → 323 (zero regressions).

---

## [1.10.18] - 2026-02-12

### Added

- **`isolation`** -- context isolation to prevent GSD insight leakage into VBW sessions. New `### Context Isolation` subsection in Plugin Isolation instructs Claude to ignore `<codebase-intelligence>` tags and use VBW's own codebase mapping. bootstrap-claude.sh now strips 8 known GSD section headers when regenerating CLAUDE.md from existing files.

---

## [1.10.17] - 2026-02-12

### Added

- **`config`** -- interactive granular model configuration. Second menu in `/vbw:config` Model Profile flow offers "Use preset profile" or "Configure each agent individually". Individual path presents 6 agent questions across 2 rounds (4+2 split), writes model_overrides to config.json, and displays before/after cost estimate. Status display marks overridden agents with asterisk (*). Feature implemented in commits 1ac752b through 91da54f (Phase 1, Plan 01-01).
- **`init`** -- GSD project detection and import. Step 0.5 detects existing `.planning/` directory before scaffold, prompts for import consent, copies to `.vbw-planning/gsd-archive/` (preserves original), generates INDEX.json with phase metadata and quick paths. Enables seamless migration from GSD to VBW with zero-risk import.
- **`scripts`** -- generate-gsd-index.sh for lightweight JSON index generation (<5s performance). Creates INDEX.json with imported_at, gsd_version, phases_total, phases_complete, milestones, quick_paths, and phases array for fast agent reference without full archive scan.
- **`help`** -- GSD Import section documenting detection flow during /vbw:init, archive structure (.planning/ → gsd-archive/), INDEX.json generation, and isolation options.
- **`docs`** -- migration-gsd-to-vbw.md comprehensive migration guide (273 lines, 9 sections) covering import process, archive structure, version control best practices, INDEX.json format, usage patterns, GSD isolation, migration strategies (full/incremental/archive-only), troubleshooting scenarios, and FAQ.
- **`bootstrap`** -- 5 reusable bootstrap scripts in scripts/bootstrap/ (project, requirements, roadmap, state, claude). Each accepts arguments only, outputs to specified path, uses set -euo pipefail. Enables shared file generation between /vbw:init and /vbw:vibe.
- **`inference`** -- brownfield intelligence engine. infer-project-context.sh (247 lines) reads codebase mapping to extract project name, tech stack, architecture, purpose, and features with source attribution. infer-gsd-summary.sh (163 lines) reads GSD archives for latest milestone, recent phases, key decisions, and current work.
- **`init`** -- auto-bootstrap flow (Steps 5-8). After infrastructure setup, init detects scenario (greenfield/brownfield/GSD migration/hybrid), runs inference engine, presents always-show confirmation UX with 3 options (accept/adjust/define from scratch), field-level correction, then calls bootstrap scripts to generate all project files. Seamless flow with no pause between mapping and project definition.

### Changed

- **`vibe`** -- Bootstrap mode (B1-B6) refactored to call extracted bootstrap scripts via ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/. Discovery logic stays inline, file generation delegated to shared scripts. Verified standalone mode, config compliance, and zero regression across all 11 modes.

---

## [1.10.15] - 2026-02-11

### Added

- **`statusline`** -- model profile display on L1 after Effort field. Shows current active profile (quality/balanced/budget) dynamically from config.json.

### Changed

- **`defaults`, `init`, `session-start`, `suggest-next`, `statusline`** -- default model profile changed from "balanced" to "quality". New VBW installations and auto-migrations now use Opus for Lead/Dev/Architect/Debugger by default for better output quality.

### Fixed

- **`pre-push-hook`** -- hook now skips enforcement in non-VBW repos. Added early exit guard that checks for VERSION and scripts/bump-version.sh files. If both absent, hook exits cleanly without blocking pushes. Fixes issue where installing VBW plugin blocked git pushes in existing brownfield repositories.

---

## [1.10.14] - 2026-02-11

### Added

- **`model-profiles`** -- cost control via model profile configuration. Three preset profiles (quality/balanced/budget) with per-agent model assignments, plus per-agent override support for advanced users.
- **`config`** -- model profile selection in `/vbw:config` interactive menu with quality/balanced/budget options. Settings table displays current profile and all 6 agent model assignments.
- **`config`** -- CLI arguments `/vbw:config model_profile <profile>` for direct profile switching and `/vbw:config model_override <agent> <model>` for per-agent overrides.
- **`vibe`** -- Phase Banner displays active model profile during Plan and Execute modes.
- **`execute-protocol`** -- agent spawn messages include model name in parentheses format: "◆ Spawning {agent} ({model})...".
- **`model-routing`** -- agent model resolution helper script (`scripts/resolve-agent-model.sh`) with hybrid architecture pattern: commands read config, helper handles merge/override logic.
- **`init`** -- new projects seeded with `model_profile: "quality"` in config.json.
- **`session-start`, `suggest-next`, `statusline`** -- auto-migration adds `model_profile: "quality"` to existing projects without the field.

### Changed

- **`vibe`, `execute-protocol`, `debug`, `research`, `qa`** -- all agent-spawning commands now pass explicit `model` parameter to Task tool based on active profile and overrides.
- **`references`** -- new `model-profiles.md` with complete preset definitions, cost comparison table, and override syntax documentation.
- **`effort-profiles`** -- all 4 effort profile files updated to clarify effort controls planning depth while model profile controls cost.
- **`help`** -- Model Profiles section added with command examples and cost estimates.
- **`README`** -- Cost Optimization section added with 3-profile comparison table and usage guidance.

---

## [1.10.13] - 2026-02-11

### Fixed

- **`statusline`** -- distinguish auth expired from network failure in usage limits. Previously, both a stale OAuth token (401/403) and a network timeout showed the same "fetch failed" message. Now shows "auth expired (run /login)" for auth failures, keeping "fetch failed (retry in 60s)" for actual network issues.

---

## [1.10.12] - 2026-02-11

### Fixed

- **`init`** -- preserve existing `CLAUDE.md` in brownfield projects. `/vbw:init` Step 3.5 was blindly overwriting the user's root `CLAUDE.md`. Now reads first — if it exists, appends VBW sections to the end instead of clobbering. Same brownfield-awareness added to `/vbw:vibe` Bootstrap B6 and Archive Step 8.

---

## [1.10.11] - 2026-02-11

### Fixed

- **`config`** -- respect `CLAUDE_CONFIG_DIR` env var across all scripts and commands. Users who set `CLAUDE_CONFIG_DIR` to relocate their Claude config directory were hitting hardcoded `~/.claude/` paths. All 9 affected files now resolve via `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` fallback pattern — zero breakage for existing users.

---

## [1.10.10] - 2026-02-11

### Fixed

- **`refs`** -- purge all stale `/vbw:implement` and standalone command references from shipped code
- **`meta`** -- correct stale counts in README (9→10 reference files, 11→15 disable-model-invocation commands) and agent memory (27→20 commands, 18→20 hooks, 8→11 event types)

---

## [1.10.9] - 2026-02-11

### Fixed

- **`hooks`** -- `qa-gate.sh` tiered SUMMARY.md gate: commit format match now only grants a 1-plan grace period; 2+ missing summaries block regardless. Replaces `||` logic where format match bypassed missing summaries entirely.
- **`references`** -- `execute-protocol.md` Step 3b hardened to mandatory 4-step verification gate. No plan marked complete without verified SUMMARY.md.
- **`docs`** -- README TeammateIdle hook description updated to reflect tiered gate. CHANGELOG execute.md references corrected to execute-protocol.md. qa-gate.sh comments fixed (GSD → conventional).

---

## [1.10.8] - 2026-02-11

### Added

- **`/vbw:vibe`** -- single intelligent lifecycle command replacing 10 absorbed commands (implement, plan, execute, discuss, assumptions, add-phase, insert-phase, remove-phase, archive, audit). 293 lines, 11 modes, 3 input paths (state detection, NL intent parsing, flags), mandatory confirmation gates. 76/76 automated verification checks PASS.
- **`references/execute-protocol.md`** -- execution orchestration logic (Steps 2-5) extracted from execute.md for on-demand loading by vibe.md Execute mode. Zero per-request cost.
- **`scripts/verify-vibe.sh`** -- 241-line automated verification script validating all 25 vibe command requirements across 6 groups.
- **Context compiler milestone** -- 3-phase optimization reducing agent context loading by 25-35% across all project sizes. 14 feat/refactor commits, 65/65 QA checks (3 phases, all PASS). Agents now receive deterministic, role-specific context instead of loading full project state.
- **`scripts/compile-context.sh`** -- new script producing `.context-lead.md` (filtered requirements + decisions), `.context-dev.md` (phase goal + conventions + bundled skills), `.context-qa.md` (verification targets). Config-gated with `context_compiler` toggle.
- **`config`** -- `context_compiler` toggle (default: `true`) in `config/defaults.json`. Setting to `false` reverts all compilation to direct file reads.
- **`compiler`** -- skill bundling reads `skills_used` from PLAN.md frontmatter, resolves from `~/.claude/skills/`, bundles into Dev context. No-op when no skills referenced.
- **`hooks`** -- compaction marker system: `compaction-instructions.sh` writes `.compaction-marker` with timestamp on PreCompact. `session-start.sh` cleans marker at session start for fresh-session guarantee.

### Changed

- **`commands`** -- all 6 commands (execute, plan, qa, discuss, assumptions, implement) now use pre-computed `phase-detect.sh` output instead of loading 89-line `phase-detection.md` reference doc.
- **`commands`** -- plan.md, execute.md, implement.md call `compile-context.sh` before agent spawn with config-gated fallback to direct file reads.
- **`agents/vbw-dev.md`** -- removed STATE.md from Stage 1 (never used). Added marker-based conditional re-read with "when in doubt, re-read" conservative default.
- **`agents/vbw-qa.md`** -- replaced `verification-protocol.md` runtime reference with inline 12-line format spec. Tier provided in task description instead of loaded from full protocol.

### Fixed

- **`hooks`** -- `pre-push-hook.sh` restored to actual validation logic (was replaced by delegator wrapper causing infinite recursion).
- **`hooks`** -- `qa-gate.sh` tightened to tiered SUMMARY.md gate. Commit format match now only grants a 1-plan grace period; 2+ missing summaries block regardless. Replaces previous `||` logic where format match could bypass missing summaries entirely.
- **`references`** -- `execute-protocol.md` Step 3b hardened: SUMMARY.md verification gate is now a mandatory 4-step checkpoint after Dev completion. No plan marked complete without verified SUMMARY.md.

### Removed

- **`commands`** -- 29 commands consolidated to 20. Ten lifecycle commands hard-deleted: `implement`, `plan`, `execute`, `discuss`, `assumptions`, `add-phase`, `insert-phase`, `remove-phase`, `archive`, `audit`. All absorbed into `/vbw:vibe` (single intelligent router with 11 modes). Global commands mirror cleaned. No aliases, no deprecation shims.

---

## [1.10.6] - 2026-02-10

### Fixed

- **`hooks`** -- `state-updater.sh` now updates ROADMAP.md progress table and phase checkboxes when PLAN.md or SUMMARY.md files are written. Previously only STATE.md was updated, leaving ROADMAP.md permanently stale after bootstrap.
- **`hooks`** -- `pre-push-hook.sh` restored to actual validation logic. Commit `da97928` accidentally replaced it with the `.git/hooks/pre-push` delegator wrapper, causing infinite recursion that hung every `git push`.

---

## [1.10.5] - 2026-02-10

### Added

- **`discovery`** -- intelligent questioning system for `/vbw:implement`. Discovery protocol reference (`references/discovery-protocol.md`) with profile-gated depth (yolo=skip, prototype=1-2, default=3-5, production=thorough), scenario-then-checklist format, and example questions.
- **`config`** -- `discovery_questions` toggle (default: `true`) in `config/defaults.json`. Disabling skips all discovery prompts.
- **`implement`** -- bootstrap discovery (State 1) rewrites static B2 questions with intelligent scenario+checklist flow, feeding answers into REQUIREMENTS.md.
- **`implement`** -- phase-level discovery (States 3-4) asks 1-3 lightweight questions scoped to the phase goal before planning. Checks `discovery.json` to avoid re-asking.
- **`discuss`** -- answers now written to `discovery.json` for cross-command memory, so `/vbw:discuss` and implement share the same question history.

### Changed

- **`hooks`** -- `state-updater.sh` auto-advances STATE.md to the next incomplete phase when all plans in a phase have summaries. Sets status to "active" on plan writes.
- **`hooks`** -- `pre-push-hook.sh` simplified to a thin delegator routing to the latest cached plugin script via `sort -V | tail -1`.
- **`profile`** -- added Discovery depth column to built-in effort profiles table.
- **`config`** -- added `discovery_questions` to settings reference table.

---

## [1.10.4] - 2026-02-10

### Changed

- **`statusline`** -- removed Cost field from Line 4. Moved Prompt Cache from usage line (L3) back to context line (L2) after Tokens field.
- **`README`** -- promoted "What You Get Versus Raw Claude Code" comparison table from subsection to top-level section, moved above Project Structure for better visibility.

---

## [1.10.3] - 2026-02-10

### Changed

- **`statusline`** -- removed Cost field from Line 4. Status line now shows Model, Time, Agents, and VBW/CC versions only.

---

## [1.0.99] - 2026-02-10

### Fixed

- **`security-filter.sh`** -- `.planning/` block now conditional on VBW markers, so GSD can write to its own directory when VBW is not the active caller. Previously blocked GSD unconditionally in every project.
- **`/vbw:init`** -- creates `.vbw-session` marker after enabling GSD isolation, so the security filter allows VBW writes during the remainder of the init flow (codebase mapping).

### Changed

- **Autonomy level rename** -- `dangerously-vibe` renamed to `pure-vibe` across all commands, references, README, and changelog. Tone adjusted to be informative without scare language.
- **Statusline economy line** -- renamed "Cache" to "Prompt Cache" for clarity.

---

## [1.0.98] - 2026-02-10

### Added

- **Token economy engine** -- per-agent cost attribution in the statusline. Each render cycle computes cost delta and attributes it to the active agent (Dev, Lead, QA, Scout, Debugger, Architect, or Other). Accumulated in `.vbw-planning/.cost-ledger.json`. Displays `Cost: $X.XX` on Line 4 and a full economy breakdown on Line 5 (per-agent costs sorted descending, percentages, cache hit rate, $/line metric). Economy line suppressed when total cost is $0.00.
- **Agent lifecycle hooks** -- `SubagentStart` hook writes active agent type to `.vbw-planning/.active-agent` via `scripts/agent-start.sh`. `SubagentStop` hook clears the marker via `scripts/agent-stop.sh`. Enables cost attribution to know which agent incurred each cost delta.
- **`/vbw:status` economy section** -- status command reads `.cost-ledger.json` and displays per-agent cost breakdown when cost data is available. Guarded on file existence and non-zero total.
- **GSD isolation** -- two-layer defense preventing GSD from accessing `.vbw-planning/`. Layer 1: root `CLAUDE.md` Plugin Isolation section (advisory). Layer 2: `security-filter.sh` PreToolUse hard block (exit 2) when `.gsd-isolation` flag exists and no VBW markers present. Two marker files (`.active-agent` for subagents, `.vbw-session` for commands) prevent false positives. Opt-in during `/vbw:init` with automatic GSD detection.

### Changed

- **Statusline cache consolidation** -- 6 cache files (`-ctx`, `-api`, `-git`, `-agents`, `-branch`, `-model`) reduced to 3 (`-fast`, `-slow`, `-cost`). Grouped by update frequency to reduce file I/O.
- **Pure shell formatting** -- `awk` replaced with shell functions (`fmt_tok`, `fmt_cost`, `fmt_dur`) for token, cost, and duration formatting. Eliminates 3 subprocesses per render cycle.
- **`session-stop.sh` cost persistence** -- session stop hook now reads `.cost-ledger.json` and appends a cost summary line to `.session-log.jsonl` before cleanup.
- **`post-compact.sh` cost cleanup** -- compaction hook resets cost-tracking temp files (`.active-agent`, stale cache entries) to prevent attribution drift after context compaction.
- **README statusline documentation** -- updated hook counts (18/10 to 20/11), added SubagentStart to hook diagram, documented economy line in statusline description.
- **`/vbw:init` GSD detection** -- Step 1.7 checks `~/.claude/commands/gsd/` and `.planning/` to detect GSD. Prompts for isolation consent only when GSD is present; silent skip otherwise.

---

## [1.0.97] - 2026-02-09

### Added

- **`suggest-next.sh`** -- context-aware Next Up suggestions (ADP-03). New script reads project state (phases, QA results, map existence, milestone context) and returns ranked suggestions. 12 commands updated to call it instead of hardcoded static blocks. After QA fail, suggests `/vbw:fix` instead of `/vbw:archive`; when codebase map is missing, injects `/vbw:map` hint.

### Changed

- **`templates/SUMMARY.md`** -- slimmed frontmatter to consumed fields only (TAU-05). Removed `duration`, `subsystem`, `tags`, `dependency_graph`, `tech_stack`, `key_files` (never read by any command). Added `tasks_completed`, `tasks_total`, `commit_hashes` (actually consumed by status and QA). Saves ~80-120 output tokens per SUMMARY write.
- **`references/shared-patterns.md`** -- added Command Context Budget tiers (TAU-02 formalization). Documents Minimal/Standard/Full context injection convention so future commands don't cargo-cult STATE.md injections.

### Removed

- **`/vbw:status --metrics`** -- removed broken flag that referenced `tokens_consumed` and `compaction_count` fields which never existed in the SUMMARY template.

---

## [1.0.96] - 2026-02-09

### Fixed

- **`/vbw:update`** -- version display now uses the actual cached version after install, not the GitHub CDN estimate. Fixes misleading "Updating to vX.Y.Z" and false version mismatch warnings when CDN lags behind the marketplace.

---

## [1.0.95] - 2026-02-09

### Fixed

- **`hooks`** -- all 18 hook commands now exit 0 when the plugin cache is missing, preventing "PostToolUse:Bash hook error" spam during `/vbw:update`. Previously, `cache-nuke.sh` deleted the cache but hooks kept firing and failing until the cache was re-populated.

---

## [1.0.94] - 2026-02-09

### Changed

- **`config`** -- default autonomy level changed from `pure-vibe` to `standard`. New installations now require plan approval and stop after each phase for review, giving users guardrails by default.

---

## [1.0.93] - 2026-02-09

### Changed

- **`commands`** -- lazy reference loading (TAU-01). Cross-command `@`-references in `implement.md` and `init.md` replaced with deferred `Read` instructions so `plan.md`, `execute.md`, and `map.md` are only loaded when the model reaches the state that needs them. Removed unused STATE.md injections from `fix`, `todo`, and `debug` commands. Saves 200-500 tokens per invocation for states that don't use the deferred files.

---

## [1.0.92] - 2026-02-09

### Changed

- **`/vbw:update`** -- always runs full cache refresh even when already on latest version. Fixes corrupted caches or stale hook schemas without requiring a version bump.

---

## [1.0.91] - 2026-02-09

### Added

- **`statusline`** -- hourly update check with visual indicator. When a newer VBW version is available, Line 4 turns yellow bold showing `VBW {current} → {latest} /vbw:update`. Cached 1 hour, single curl, zero overhead otherwise.

---

## [1.0.90] - 2026-02-09

### Fixed

- **`hooks.json` invalid event types** -- `PostCompact` (not a valid Claude Code event) replaced with `SessionStart` matcher `"compact"`. `NotificationReceived` renamed to `Notification`. Fixes fresh install validation error on newer Claude Code versions.
- **`notification-log.sh` field mismatch** -- script was reading `.sender`/`.summary` (non-existent fields). Now reads `.notification_type`, `.message`, and `.title` per the `Notification` event schema.
- **README event type count** -- corrected "11 event types" to "10 event types" after PostCompact was merged into SessionStart.

### Added

- **`README Quick Start`** -- prominent warning against using `/clear`, explaining Opus 4.6 auto-compaction and directing users to `/vbw:resume` for context recovery.

---

## [1.0.87] - 2026-02-09

### Fixed

- **`install-hooks.sh` resolves .git from project root** -- scripts used `dirname "$0"` to find `.git`, which resolves to the plugin cache directory (`~/.claude/plugins/cache/...`) for marketplace users instead of the user's project. Now uses `git rev-parse --show-toplevel`. Also replaces symlink-based hook install with a standalone wrapper script that delegates to the latest cached plugin version via `sort -V | tail -1`.
- **`pre-push-hook.sh` uses git for repo root** -- replaced `dirname "$0"` + relative path navigation (`../../`) with `git rev-parse --show-toplevel`. Works regardless of invocation method (symlink, direct call, or delegated from hook wrapper).
- **`session-start.sh` hook install guard** -- auto-install check now uses `git rev-parse --show-toplevel` to find the project's `.git/hooks/` instead of checking relative to `$PWD`.

---

## [1.0.86] - 2026-02-09

### Fixed

- **`/vbw:release` GitHub auth** — `gh release create` now extracts `GH_TOKEN` from the git remote URL when `gh auth` is not configured, instead of failing silently.
- **Statusline layout** — moved Diff (`+N -M`) from Line 4 to Line 1 after repo:branch. Added `Files:` and `Commits:` labels to the staged/modified and ahead-of-upstream indicators.

---

## [1.0.84] - 2026-02-09

### Changed

- **Context Diet: `disable-model-invocation` on 13 commands** — manual-only commands (add-phase, assumptions, audit, discuss, insert-phase, map, pause, qa, release, resume, skills, todo, whats-new) no longer load descriptions into always-on context. ~7,500+ tokens/session savings.
- **Context Diet: brand reference consolidation** — `vbw-brand-essentials.md` made self-contained (~50 lines), removing 329-line `vbw-brand.md` injection from 27 command references.
- **Context Diet: effort profile lazy-loading** — monolithic `effort-profiles.md` split into index + 4 individual profile files. Commands load only the active profile (~270 tokens/execution savings).
- **Context Diet: initialization guard consolidation** — `plan.md` guard deduplicated to shared-patterns reference.
- **Script Offloading: `phase-detect.sh`** — new script pre-computes 22 key=value pairs for project state, replacing 7 inline bash substitutions in `implement.md` (~800 tokens/invocation savings).
- **Script Offloading: SessionStart rich state injection** — `session-start.sh` now injects milestone, phase position, config values, and next-action hint via `additionalContext` (~100-200 tokens/command savings).
- **Script Offloading: compaction instructions** — CLAUDE.md Compact Instructions section + enhanced `compaction-instructions.sh` with main session detection guide context preservation during auto-compact.
- **Script Offloading: inline substitution cleanup** — 10 inline `config.json` cats removed from 6 commands (plan, execute, status, qa, fix, implement). Config pre-injected by SessionStart.
- **Agent Cost Controls: model routing** — Scout→haiku, QA→sonnet (40-60% cost reduction). Lead/Dev/Debugger/Architect inherit session model.
- **Agent Cost Controls: `maxTurns` caps** — all 6 agents capped (Scout: 15, QA: 25, Lead: 50, Dev: 50, Debugger: 75, Architect: 30). Prevents runaway spending.
- **Agent Cost Controls: reference deduplication** — 3 redundant `@` references removed from agent files (~1,600 tokens/agent spawn savings).
- **Agent Cost Controls: `state-updater.sh` enhancement** — auto-updates STATE.md plan counts when PLAN.md or SUMMARY.md files are written (PostToolUse hook, no LLM involvement).
- **Agent Cost Controls: effort-profiles and model-cost docs** — updated for consistency with new Scout/QA frontmatter model fields.

---

## [1.0.83] - 2026-02-09

### Added

- **`/vbw:release` pre-release audit** — new audit section runs after guards but before mutations. Finds commits since last release, checks changelog coverage against them, detects stale README counts (command count, hook count), presents branded findings with `✓`/`⚠` symbols, and offers to generate missing changelog entries or fix README numbers. Skippable with `--skip-audit`. Respects `--dry-run`.
- **`/vbw:release` git tagging** — creates annotated git tag `v{version}` on the release commit.
- **`/vbw:release` GitHub release** — creates a GitHub release via `gh release create` with changelog notes extracted from the versioned section. Gracefully warns if `gh` is unavailable. Skipped when `--no-push`.
- **Statusline local commit count** — `↑N` indicator (cyan) on Line 1 shows commits ahead of upstream.

### Changed

- **Statusline Line 1 consolidates all git/GitHub info** — clickable `repo:branch` link moved from Line 4 to Line 1, replacing the duplicate `Branch: X` field. Staged, modified, and ahead-of-upstream indicators all on Line 1.
- **Statusline Line 4 cleaned up** — removed duplicate GitHub link (now on Line 1).
- **Statusline progress bars fixed and unified** — all usage bars (Session, Weekly, Sonnet, Extra) now width 20, matching the Context bar. Previously Sonnet was width 10 and Extra was width 5, causing bars to render empty at low percentages (e.g., 7% × 10 = 0 filled blocks). Added minimum-1-block guarantee for any non-zero percentage.

---

