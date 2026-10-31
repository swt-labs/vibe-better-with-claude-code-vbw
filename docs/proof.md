# Contract and proof

VBW does not ask anyone to trust that work is done: it proves it. The user
states requirements in `.vbw/spec.md`; the plan workflow proposes checks; the
user approves the contract; `vbw prove` runs exactly what was approved and
records the evidence.

## The spec: `.vbw/spec.md`

The user owns this file. Free prose everywhere, except the `## Requirements`
section, where every bullet is a requirement:

```markdown
## Requirements

- R1 [auto] A visitor can sign up with an email address
  Notes for the Architect and Lead may follow on indented lines.
- R2 [human] The landing page feels trustworthy
```

- `R<n>`: a stable id, never reused. `vbw spec add` appends the next free one.
- `[auto]`: a check can prove it. `[human]`: only a person can judge it.
- Indented lines under a bullet are notes for the Architect and Lead; the kernel ignores
  them. HTML comments are ignored.
- Any other bullet in the section is an error, reported with its line number.

`vbw spec check` validates the file. `vbw spec sync` validates it and brings
the record in line: new ids are added as `open` to the current milestone,
changed text or proof resets the requirement to `open` (in the current
milestone), and an id removed from the spec is removed from the record with its
checks, its fix items, and the unstarted plans that served only it. Removing a
requirement whose only plans have already started is refused: built work is
never discarded without the user deciding.

The spec keeps every milestone's requirements. After a milestone ships, its
requirements stay (their checks keep running in every proof, guarding the
shipped work), and `vbw milestone start TITLE` opens the next milestone for new
requirements. The kernel never rewrites the spec; `vbw spec add auto|human
TEXT` only appends a line.

### Saved test results: `## Test results`

Some projects commit the output of their test runs (reports, recordings,
snapshots). List the folders that hold them under `## Test results`, one
folder per line. A folder name cannot contain spaces: `vbw spec sync`
refuses such a line and prints its line number.

```markdown
## Test results

- results/
- reports/benchmarks/
```

- Each line is `- <folder>/`: a path relative to the project root, with no `.`
  or `..` parts, outside `.vbw/`. A missing trailing `/` is added. A folder
  named twice, or any other bullet in the section, is an error with its line
  number. Text that is not a bullet is ignored, as in `## Requirements`.
- `vbw spec sync` copies the list into the record (`project.results`,
  docs/record.md) and prints the new list. It is part of the contract: adding,
  changing or removing the list needs approval like any other spec change, and
  `vbw show contract` shows the folders and how they changed. The list is
  compared with the record at approval like the other spec sections (see
  [The contract and approval](#the-contract-and-approval)).
- A file committed inside one of these folders is a saved test result. It does
  not make QA check a passed phase again
  ([Which phases QA checks again](#which-phases-qa-checks-again)).
- No section, no exemption: when the spec names no folder, a saved result is a
  file like any other.

## Checks

A check proves one `auto` requirement. It lives in the record:

```json
{ "id": "C1", "req": "R1", "run": ["npm", "test", "--", "tests/signup.test.js"],
  "files": ["tests/signup.test.js"], "exit": 0, "output": "1 passed", "timeout": 120 }
```

| Field | Rules |
|---|---|
| `run` | argv, a non-empty array of non-empty strings. Executed directly, never through a shell |
| `files` | optional: the test files the check depends on (relative paths, no `..`). Their contents are part of the contract, so editing them after approval is tampering |
| `exit` | optional expected exit status, default `0` |
| `output` | optional extended regular expression that stdout+stderr must match |
| `timeout` | optional seconds, 1 to 3600, default 300 |
| `alone` | optional boolean, default `false`. `true` marks a check that must not run beside any other VBW check (for example one that starts containers or binds a fixed port) |

`vbw prove` runs checks from the root of a clean copy of the committed code,
`vbw check` from the project root; both close stdin. A run that reaches its
timeout is stopped (by `timeout` where available, otherwise by `perl`'s alarm)
and fails. Every check and project command runs without `VBW_SESSION_ID`, the
session that is proving: a project's tests give one result whoever proves them,
and the figures a test records under a session id are its own, never the
prover's (docs/costs.md).

A case filter (`bats --filter`) must match a case in the file when `vbw apply`
runs, so the Lead writes the failing cases at planning; otherwise `vbw apply`
refuses, because a new check is red because its cases fail, never because none
exist.

### Checks run in parallel

```text
vbw config set check_jobs 8     # up to 8 checks at the same time
vbw config set check_jobs 1     # one after another
vbw config set check_jobs default
```

`vbw prove`, `vbw check` and the checks of `vbw fix done` run at most
`check_jobs` checks at a time: 1 to 64. Without a setting, `check_jobs` is
three quarters of the processor cores, rounded down, at least 1 and at most 64
(a machine with 8 cores runs 6). It is 1 when the core count cannot be read.
`vbw config` shows the value and whether it is the machine default or set;
`vbw config set check_jobs default` returns to the default. The setting
belongs to this clone and is shared by its worktrees; it is not in the record
or the contract, so changing it needs no approval.

The limit is shared. Several VBW commands can run checks at the same time in
one project folder (parallel Devs each running `vbw check`, the round's one `vbw fix done`
beside `vbw prove`). Together they never run more checks than the limit. A
check that finds no free slot waits for one instead of failing, and its
timeout counts from its real start. A slot held by a VBW process that died is
freed. Checks that run alone are unchanged.

The results are the same as running the checks one after another: the
evidence lists them in the checks' own order, whatever order they finish in.
Checks marked `alone` (below) still run by themselves. A proof of many checks
takes about as long as its slowest checks, not the sum of all of them. The next
check starts as soon as a running one gives its slot back, while that one
still writes its result. Reading what the checks need to start and gathering
their results take VBW one step each, however many checks there are. Checks
that share a resource and are not marked `alone` (a database, a fixed port) can
disturb each other: mark them `alone`, or set `check_jobs` to 1.

#### Cores per unit

Build-and-test commands such as `cargo test`, `make` and `go test` each use
every core unless told otherwise, so several of them side by side overload the
machine. VBW tells each unit its share: the processor cores divided by the
units this run puts side by side (`check_jobs`, under the computer-wide limit
below), at least 1; a check marked `alone` gets every core. The share reaches
the unit's command through `CARGO_BUILD_JOBS`, `GOMAXPROCS` and `MAKEFLAGS`
(`-jN`). A variable your environment already sets is passed on unchanged, so
`MAKEFLAGS=-j2 claude` keeps your own choice. When the core count cannot be
read, nothing is set.

### The computer-wide limit

VBW as a whole never runs more than the machine limit at once: three quarters
of the processor cores, rounded down, at least 1 and at most 64.
Every VBW project on this computer shares it, however many projects, sessions and runs
prove at the same time. It is not a setting. `check_jobs` stays as a per-run
cap below it; a run never goes above either number. `vbw config` prints a
`machine limit:` line with the number and says when it applies instead of
`check_jobs`.

Each check, each project command and each test file takes one slot while it
runs. The slots live in `<claude-config-dir>/vbw/slots.json`, where
`<claude-config-dir>` is `CLAUDE_CONFIG_DIR` if set, else `~/.config/claude-code`
if that folder exists, else `~/.claude`. The file exists only while runs use it.

VBW's own bookkeeping takes slots too, so it counts in the limit. A unit's slot
also covers its read tracking: it is taken before the access times are reset
and given back after the read list is collected. Writing the unit's result
comes after that, outside the slot, and the run starts its next unit at once.
The proof-wide steps hold one
slot each, listed in the store as `vbw:plan` (reuse planning), `vbw:copies`
(making the clean copies) and `vbw:save` (saving the run store).

`vbw next` never waits for a slot: it answers at once, even while every slot is held. A
nested run (a proof started from inside a proof) takes no slot of its own.

Runs take equal turns: when slots free up, the waiting run holding the fewest
goes first; between equals, the one that waited longest. The step that frees a
slot hands it to that run at once. A waiting unit only reads the store until
its turn has come, without taking the store's lock, so waiting runs never slow
down the runs giving slots back. A run that waits
prints `waited ... for other VBW runs on this computer`. Waiting changes
nothing else: the same result as without it, and a timeout counts from when its command really starts.

Every change of the store is one short step under a lock file next to it
(`slots.lock`), and a step spends little: one `jq` run, one rename and the
lock's removal, with no pause unless another run holds the lock. A run that
finds the lock held retries after 10 ms and waits a little longer each time,
up to a tenth of a second, so slots do not sit idle between one unit and the
next.

If a run is killed, the next run takes over its slots. Ctrl-C gives them back
at once. A lock left by a dead process is taken over too, by renaming its owner
file: when two runs find the same dead owner, one of them gets the lock and the
other waits for it, and neither ever removes a lock another run has just taken.

If the store cannot be written (a read-only folder, a full disk, the Claude
Code sandbox) or is damaged, the run goes on under `check_jobs` alone and
prints `the computer-wide limit was not in force` with the reason (at the
start, or once at the end when the store failed in the middle of the run, also
when it failed in the last step that saves the proof). A unit that loses the
store while it waits or holds a slot leaves no slot behind: as soon as the
store can be written again, the run's next change of it removes that unit's
place, so no other run is handed a slot nobody uses. A folder that reports
itself writable but refuses a new file is recognised at once, not after a long
wait. A store lock held by a live process is waited for, however long.

### Checks that run alone

```json
{ "id": "C2", "req": "R1", "run": ["docker", "compose", "run", "--rm", "e2e"], "alone": true }
```

A check with `"alone": true` never runs at the same time as another VBW check
in the same project, even when several fixes or builds run checks in parallel.
Other checks keep running in parallel with each other.

Every running check registers in `.vbw/runtime/gate`. An alone check starts
when nothing else is running. A shared check starts when no alone check is
running or waiting, so a waiting alone check is not starved. The registration
is released when the check ends, times out or is interrupted, and a
registration left by a dead process is taken over.

A check that cannot start waits as long as the check holding the gate is alive,
and takes over when that check's process is gone. There is no wait limit
(`VBW_CHECK_WAIT_SECONDS` no longer exists), and the wait is not part of the
check's `timeout`, which counts only the run. A check whose runner ends without
leaving a result is recorded as `skipped` (its tail starts `not run:` with the
reason) and counts as not passed; every other result stands.

### Clean copy: `## Clean copy`

A clean copy brings in the project's git-ignored files. When one ignored folder
is big and no check needs it (a data folder of many gigabytes), list it under
`## Clean copy`, one git-ignored path per line, relative to the project root.

```markdown
## Clean copy

- data/
```

- A path is relative to the project root, with no `.` or `..` parts, outside `.vbw/` and `.git/`. An absolute path, `..`, `.vbw/` or `.git/` is refused like a bad Test results folder, with its line number. A path named twice is refused with the second line.
- A listed path is one word per line: a path with a space in it cannot be listed. A line like `- my data/` is refused, like a Test results folder with a space, with its line number and the words `expected "- <path>" (a git-ignored path relative to the project root, ...)`.
- `vbw spec check` and `vbw spec sync` refuse a path git does not ignore (it is tracked, or untracked and not ignored), naming the spec line and the path: `is not git-ignored: only ignored paths are copied in, so only they can be left out`. The record stays unchanged.
- A path with nothing at it (it does not exist yet, or not on this computer) is accepted, since there is nothing to leave out. `vbw spec check` says so, so a mistyped path is noticed: `spec.md line N: PATH is not here now, so nothing is left out for it yet`. A folder whose files alone are ignored is accepted.
- `vbw spec sync` copies the list into the record (`project.leave_out`, docs/record.md), prints `clean copy leaves out: data/, cache/`, and removes the field when the section is gone.
- The list is part of the contract: adding a path changes the contract, so it reads NOT APPROVED and the approval question is asked again. `vbw show contract` prints the line `clean copy leaves out: data/, cache/`, and `vbw show contract --changes` names the new list and the old one (`clean copy leaves out: data/, cache/ (was data/)`, `none` for an empty side).
- Every clean copy (`vbw prove`, `vbw fix done`, `vbw mutate`) skips the listed paths and everything under them, including ignored files inside a listed folder. The other ignored paths are still copied in. A listed path that no longer exists changes nothing, and the next `vbw spec sync` still accepts it.
- Leaving a path out changes no result: the next proof reuses what it can, as before. No section, no change: every ignored path is copied in.

## The contract and approval

The contract is the requirements (id, text, proof, and rules when listed), the checks, the plans
(everything but their status) and the contents of every check's `files`. Its
hash is SHA-256 over a canonical rendering of all of it.

`vbw approve`, and `vbw next` before it offers the approval question, first
compares every section of `.vbw/spec.md` with the record:
Requirements, Commands, Test files, Test results and Clean copy. A spec that was edited and
not synced cannot be approved; the refusal reads
`spec.md and the record differ (vbw spec sync)`.
Run `vbw spec sync`, then approve.

### Approving by choice

When the contract is ready, VBW shows it and asks a question in Claude Code's
own question box. `vbw show contract` prints the question and its options:

```text
approval question: Approve contract 4cfe6f0859c9?
approval options: Approve, Not yet
```

- **Approve** comes first, so pressing Enter approves the contract shown.
- **Not yet** approves nothing; VBW asks what to change.
- **Your own words** (the box's own-answer slot) approve nothing either. VBW
  takes them as what to change, or as a question.

The 12 characters in the question are the contract's fingerprint (the start of
its hash). Approval covers exactly that contract. The question may carry more
text after the fingerprint (a sentence, spaces or line breaks that Claude adds
to explain what you approve). Choosing **Approve** still approves the contract
the fingerprint names; the extra text changes nothing. The fingerprint must
stay at the start of the question: a question that does not begin with
`Approve contract <12 characters>?` is not the approval question, and nothing
is approved. So that a reworded question still works, VBW adds the start
itself: when Claude asks a question with the options Approve and Not yet without
the fingerprint while a contract waits for approval, VBW puts
`Approve contract <12 characters>?` in front of it before you see it (the
`PreToolUse` hook `hooks/approve-ask.jq` and `hooks/approve-ask.sh`), so
Approve approves exactly the contract shown.

If the fingerprint is not the current contract's, nothing is approved. This
happens when the contract changed after the question was asked (a plan or check
was edited meanwhile), or when the fingerprint is wrong. VBW says
`the contract changed since you were asked (now ...): review it again`. Review
it with `vbw show contract` and answer the new question.

After any change to the plan (a new plan, a changed plan or a re-plan), VBW
asks for approval only with this menu. It never tells you to type
`/vbw:approve`. Typing `/vbw:approve` still works and approves the current
contract, without the question.

`vbw approve` (the user's answer or `/vbw:approve`, never the model) refuses an incomplete
contract (no requirements, an `auto` requirement without a check, a missing
check file), then records consent for the contract hash and for every project
command in `record.commands`, in the clone's git directory (see
docs/record.md, Consent), and logs a decision. A repository cannot ship
approval: a fresh clone must approve before anything runs. The kernel accepts
`vbw approve --hash FINGERPRINT` only when the fingerprint is the current
contract's.

### Test files edited while building

Devs often adjust a test file while building a phase. VBW asks about those
edits once, before the phase is proved, not once per edit.

Each approval remembers the contract's structure (requirements, rules, checks,
plans) next to the full hash. While only the bytes of check files differ from
what was approved:

- `vbw next` keeps building. `vbw check` runs, and prints
  `vbw: waiting for approval (changed since approved): tests/pay.sh` on stderr.
- When a phase is built and not yet proved, `vbw next` returns `approve` with
  `detail.files`: every edited test file, sorted. Review them with
  `vbw show contract --changes`, which prints the whole diff of each edited
  file (every hunk, committed or not), then approve once.
- `vbw prove` refuses and names the files: `check files changed since it was
  approved are waiting for approval: tests/pay.sh: review them, then /vbw:approve`.
  Nothing is proved.

A change to the structure (a new check, a changed `run`, a plan's files) is not
waiting: the contract needs approval first, as before.

### A regression test added by a QA fix

When QA finds a problem, the fix can add a test that would have caught it. The
Dev writes the test file, then registers it:

```
echo '{"run": ["sh", "tests/pay-zero.sh"], "files": ["tests/pay-zero.sh"]}' | vbw fix check F3
```

The document takes the same fields as a check in `vbw apply` (`run` and `files`
are required). The new check belongs to the finding's requirement, and
`vbw show req R1` names the fix it came from. Only a fix that QA opened can do
this; a fix for a failed proof is fixed in the code its check already tests.

The test is new, so nothing runs it until you approve it. The fix closes with
the checks already approved. When the fix is done, `vbw next` returns `approve`
once, naming every new or changed check file of the fix (`detail.files`):

```
approval question: Approve contract 4cfe6f0859c9?
approval options: Approve, Not yet
```

- **Approve** lets `vbw prove` run the new test with the others.
- **Not yet** approves nothing. `vbw prove` runs none of the waiting files,
  names them and says to approve; the fix stays open until you do.

The approval is by content: if the test changes again, it waits for a new
approval. See docs/guards.md for what the fix run may write.

### An approval whose commit fails

`vbw approve` commits the approval record. When that commit fails (a project
hook refuses it, or git has no identity), VBW stops and prints git's own reason
and `the approval commit failed (reason above); the contract is not approved`.
It exits non-zero and leaves no approval: the decision is not in the record and
no consent is kept. `vbw show contract` still says `NOT APPROVED` and `vbw next`
asks again. Fix the cause (for example, make the hook pass) and approve again.
Other VBW commits still only warn, with git's reason.

A project command or the test-file form changed after the contract was
approved is approved on its own, the same way: `vbw approve` records the
decision `Project commands approved: name (argv); ...` and its commit
`chore(vbw): approve commands` before it grants the consent, so the record and
git say what was approved and when. When that commit fails, the decision is
taken back, no consent is kept and the message ends `the commands are not
approved`. A loop records the same decision with its own words (docs/loop.md).

## Rules

A rule is one condition, edge or error case that an `auto` requirement's text
states, paired with the check that tests it. The Lead lists them with
`vbw apply` (docs/workflows.md), so an approved contract shows what each check
is meant to cover, not only that checks exist.

`vbw show contract` is the approval screen. Each `auto` requirement shows its
rules, each by its address `Rn.k` (its place among the requirement's rules),
with their checks:

```text
R1 [auto] A customer can pay once
  rule R1.1: A payment succeeds -> C1
  rule R1.2 retired: Paying twice is refused (R4 lets a customer pay twice)
  rule R1.3: A refused card is named -> C2
```

- `vbw approve` refuses an `auto` requirement whose rules are pending
  (`rules: []`, or every rule retired): `R1 has no rules listed (vbw apply with rules)`.
- A rule is reworded or retired by its address with `vbw apply --patch`
  (docs/workflows.md), in any milestone, a shipped one included. A retired
  rule stays in the record, in its place, with its reason: no other rule's
  address moves, the mutation check owes it no break, `vbw show plan` leaves it
  out of the plan's rules and `vbw mutate` refuses its address. Retire a rule
  whose behaviour a newer requirement replaced, so the old rule no longer
  contradicts the new one.
- Rules are part of the contract hash, retired ones and their reasons
  included: adding, removing, rewording, retiring, moving or re-pointing a rule
  needs re-approval, and `vbw show contract --changes` lists it by its
  address as `added rule`, `removed rule`, `reworded rule`, `retired rule`,
  `moved rule` or `changed rule`, for example
  `retired rule R1.2: Paying twice is refused (R4 lets a customer pay twice)`.
- `vbw apply` refuses a check whose rules are owned by two plans not yet
  built, order or not. When they build one after the other (one in the other's
  `after`, sharing a file, or in an earlier wave), the earlier plan's mutation
  step would find the check red on unbroken code, because the later plan has
  not built its part yet. When they share a wave, they build beside each
  other: the first Dev's mutation step would run the check before the other
  Dev committed, a race that fails only sometimes. Give each plan's rules a
  check of their own.
- When a requirement's text or proof changes, `vbw spec sync` resets its rules
  to pending, so the Lead restates them.
- A requirement approved before rules existed (no requirement has a `rules`
  field) keeps its approval. Its screen shows `rules not listed`, and nothing
  forces rules until the Lead applies a plan that lists them (D53). Once any
  requirement has rules, new and changed `auto` requirements need them too.

## Project commands

The project's own test, lint and build commands live in `.vbw/spec.md`, under
`## Commands`, one per line: a name, then the command as words, or as a JSON
array when an argument contains spaces. The router chooses them from the Tests
section of the map, and asks before planning about a suite marked `Not run`,
offering to run it now or add it unverified (details below the example):

```markdown
## Commands

- test: cargo test --locked --workspace --manifest-path engine/Cargo.toml
- pytest: conda run -n analysis python -m pytest -q engine/
- e2e: ["sh", "run tests.sh", "--fast"]
```

`vbw init` writes the commands it detects there as a suggestion (in a
repository with several sub-projects it sees only the root, so check them).
Edit a line to change a command, delete it to stop running it, then
`vbw spec sync`: the record's commands become exactly that section. A spec
without the section keeps the commands it has. A command whose exact argv the
user has not approved makes `vbw next` ask for approval again, and
`vbw prove` runs only approved commands.

The router chooses `## Commands` from the Tests section of `.vbw/map.md`, and
prefers a command the map ran and dated (`ran as of <short commit>, <date>`).
A whole suite the map marked `Not run` is never added silently. Before planning,
the router asks once per such suite, naming it as unverified with its expected
time (or saying the time is unknown), and offers:

- run it now (Recommended): the suite runs once, you hear green or red with the
  names of failing tests, and the dated outcome is recorded as a decision
  (`Commands: <command> ran <date> at <short commit>: green|red (<n> failing)`).
  The map itself is written only by the map run.
- leave it out: only the verified commands are used.
- add it unverified: the line goes into `## Commands` as it is.

Under hands-off the router takes run it now and says so. A suite that is red
today, by the map or by that run, is named with a narrower command recommended
(one test file, or the sub-project's green command). It enters `## Commands`
only if you choose it, and the router then tells you the first proof will be red.

Evidence: the wording is pinned at L1 by bats checks of the skills and these
docs. At L3 only the `mapnotrun` scenario in `tools/l3-suite.sh` covers it, and
only once it has run; nothing beyond that is claimed.

### The time limit of project commands

A project command (the test run above all) runs for up to 3600 seconds
(60 minutes) under `vbw prove`. A project sets its own limit, from 1 to 86400
seconds, and returns to the default:

```
vbw config set command_timeout 7200
vbw config set command_timeout default
```

A command that reaches the limit is stopped and recorded with the status
`timeout`. The summary then names the limit it ran under and how to raise it:

```
  test stopped by its time limit (3600 s); raise it with vbw config set command_timeout SECONDS
```

A check's own `timeout` (1 to 3600 seconds, see [Checks](#checks)) is separate:
it limits that check only, and `command_timeout` does not change it.

### Unit time and the budget per unit

Every check, project command and test file of a proof is a unit, and the
evidence keeps the seconds each one took when it last ran, to a tenth of a
second (the shell's own timer reads the unit's wall time; a record written with
whole seconds reads as before). Reports print tenths under 10 s (`C1 pass 0.4s`)
and whole seconds from 10 s (`tests/import.bats 140 s`). VBW reports that
time so a slow or growing test suite is seen early. It never fails or stops a
proof for it: a busy machine never fails a proof.

`vbw prove` prints one line just before its `VBW's own work` line, and
`vbw fix done` just after its `ran again` line. It names the three slowest
units that ran (a reused result did not run) and their share of the time the
units that ran took:

```text
slowest units: tests/import.bats 140 s, C3 30 s, test 12 s (78% of 233 s unit time); over budget (more than 120 s): tests/import.bats
```

When nothing ran, the line is left out. A unit over the budget is named after
`over budget` (five at most; the rest are counted). The budget is 120 seconds
a unit. A project sets its own, from 1 to 86400 seconds, and returns to the
default:

```
vbw config set check_budget 60
vbw config set check_budget default
```

The budget only names units; the time limits of project commands and checks
are what stop one.

`vbw show evidence` prints the whole picture after its `own work` line: the
total unit time of every current unit, each as it last ran (a reused result
keeps the seconds of the run it reuses), the ten slowest, and every unit over
the budget:

```text
  unit time: 915 s in 14 units, each as it last ran; the slowest:
    C12 120 s
    ...
  over budget (more than 50 s a unit): 9
    C12 120 s
    ...
```

`vbw ship` ends with the total and how the milestone changed it:

```text
unit time: 925 s in 120 units, +140 s since M3 started (785 s in 104 units)
```

`vbw milestone start` keeps the unit time a milestone starts with in this
clone (`vbw/unit-time.json` in the git directory), never in the record. A clone
that did not start the milestone has no figure to compare with, and the line
says so: `this clone kept no figure from the start of M1`. The first milestone
has none either.

Every report counts current units only: the record's checks, the project
commands the proof covers and the test files the form matches now. A test
command whose test files ran in its stead adds nothing of its own (its time is
theirs), and a check waiting for approval or a skipped command took none.

### The quick command

A project whose test command is slow can name a faster variant for build and
fix rounds, with a `quick` entry:

```markdown
## Commands

- test: cargo test --locked --workspace
- quick: cargo test --locked --workspace --lib
```

The quick command needs approval like any other command: it is part of the
contract, and `vbw prove` never runs it before the user approves it. VBW never
detects a quick command and never suggests one (`vbw init` does not write one); only the
user can say which subset of the tests is enough for a build round.

A plain `vbw prove` runs the quick command in place of the test command. When
the quick command is not approved, the summary says so and the full test
command runs instead. `vbw prove --full` never runs the quick command. A proof
where the quick command stood in is partial: QA and shipping accept a proof that
reused results but refuse a partial one until a full proof ran. The refusals read
`the last proof was partial: run vbw prove --full, then record the verdict again`
(`vbw qa record`) and `Run vbw prove --full` (`vbw next`).

Any change to the contract (a check edited, a test file touched, a plan's files
widened) changes the hash, and the contract is unapproved again until the user
re-approves it. `vbw show contract` renders what is being approved, and
`vbw show contract --changes` only what changed since the last approval in this
clone (`vbw approve` keeps a copy of what it approved in `.vbw/runtime/`).

## Test files

A project whose test runner can run one test file at a time can say how, so a
change re-runs only the test files it can affect. The form is a `## Test files`
section in `.vbw/spec.md`, beside `## Commands`:

```markdown
## Test files

- run: bats {file}
- files: tests/*.bats
```

`run` is the command for one test file; it names `{file}` exactly once, and VBW
puts each test file's path there. `files` lists the git pathspecs of the test
files, one or more per line. The Lead proposes the form with the runner's
documented syntax (`vbw apply`, see docs/workflows.md). `vbw init` never writes
one: VBW never guesses a form.

The form is approved like a command. It is part of the contract, and
`vbw prove` never runs an edited form before the user approves it again. Without a
form (no section, or one not approved), the test command runs whole.

With an approved form, `vbw prove` runs each test file on its own, several at a
time, and reuses a test file's result like a check's (see
[Reusing results in `vbw prove`](#reusing-results-in-vbw-prove)). A test file
runs again when it is new or changed, when a file it read changed or was
deleted, when a folder it listed gained a file, or when its last result
failed. The summary counts them, as `test files: N ran, M reused`:

```
  test files: 3 ran, 41 reused
```

A failing test file fails the proof, and the proof names it. `vbw prove --full`
runs every test file on its own and reuses none.

A test file that an approved check runs runs only as that check, not a second
time as a test file. The quick command never stands in for an approved form:
with a form, neither the test command nor the quick command runs.

When that leaves no test file to run (every file the form matches is run by
an approved check), the test command counts as covered by those checks: it
passes with `test files: 0 ran, 0 reused`, and the summary says so. When the
form matches no committed file at all, the test command fails, the summary
names the pathspecs, and a fix opens for it: add the test files, or change the
form in `.vbw/spec.md`.

## `vbw prove`

1. Refuses unless the current contract hash is approved.
2. Makes a clean copy of the committed code (`HEAD`) inside the project, under
   `.vbw/runtime/`. The copy's folder is named after the process that made it
   (its owner, by process id), for example `.vbw/runtime/proof.48213.k3Xa9Q`.
   Each checked-out submodule is in it at the submodule's own `HEAD`, with its
   git-ignored files, since `vbw commit` commits there and leaves the project's
   pointer where it was (docs/workflows.md, "Submodules").
3. Runs every check (up to `check_jobs` at a time, `alone` checks by themselves),
   and every project command whose argv is approved, from the
   root of that copy; an unapproved command is skipped and reported, never run.
   A check whose last pass is still valid for the files it read is reused, not
   run again ([Reusing results in `vbw prove`](#reusing-results-in-vbw-prove)).
   Then it removes the copy, also when interrupted.
4. Scope: every commit of the record's own history
   ([Whose commits VBW judges](#whose-commits-vbw-judges)) with a `VBW-Plan:`
   trailer naming a plan of the current milestone must change only that plan's
   files. Each commit is judged by what its plan allowed when it was made: a
   file the plan listed, or a check file a mutation survivor let it
   strengthen, in the version of the record the commit descends from (the last
   record commit in its git ancestry, whatever the clocks say) or any later
   one in the record's history, as well as today's. A file a later change renamed or dropped
   (a check's test file renamed for the project's test runner) leaves its
   earlier commits in scope. Only a commit that looks out of scope today is
   judged again this way: one git listing of the record's versions, one
   read of those since the oldest base, and one git lookup per flagged commit. A file no version allowed is
   a violation (`abc123456789 (P1.1) changed src/other.txt, which is not in
   the plan`). The user accepts one by a decision recorded after the commit
   that names both the commit (those 12 characters) and the file (`vbw decide
   "Accept abc123456789: src/other.txt holds the receipts"`); it names both
   the commit and the file, so it accepts that violation and no other.
   A shipped milestone's commits
   were judged by its own proofs and are not judged again, nor are the commits
   a park undid (their `git revert` is in the loop's `reverts`): their changes
   are gone, even when git had to merge the revert over a later change.
   A commit that is exactly undone by a later commit is not judged: its change
   is gone too. Git verifies this file by file: the later commit touches the
   same files, and takes each file back from the commit's content and mode to
   what it had before. It is the mirror image of the earlier commit, as git's
   own fingerprints of file content show, whoever made it (a hand `git revert`
   or a plain commit) and whatever its message says.
   The rule: an undo of an undo clears nothing (the original is judged again;
   a re-apply is judged as a fresh commit). Also, the undoing commit is not judged either
   when the commit it undoes carries a `VBW-Plan:` trailer too, since the pair
   leaves every file as it was. An undo that names a plan of this milestone but
   takes back a commit with no trailer is judged as that plan's commit: a plan
   commit that reverts work outside its plan is out of scope.
   A partial or edited revert is still judged (one extra line, one of two
   files restored, an extra file touched).
   The summary names each pair after the scope line:
   `scope: abc123456789 (P163.2) undone by def123456789, not judged`.
   The check reads the history as a plain listing plus a bounded raw walk: a
   fixed 2 git processes plus one per undone pair, however long the history.
   The listing finds the record's oldest commit with a trailer, the walk reads each
   commit's file changes back to it, and each pair found costs one ancestry
   check (does the undo descend from its original?). Each revert a park
   recorded adds one more, to read which commit it undid.
5. Delivered files: every file a plan of the current milestone delivered must
   still be at `HEAD` as VBW's last commit of it left it
   ([Delivered files](#delivered-files)). Each one that is not is listed in the
   evidence's `deviations`, and the summary names it after the scope lines:
   `delivered: NOTES.md (P1.1) deleted outside any plan, by abc123456789: QA judges it`.
   A deviation does not fail the proof, because the checks still pass. It is QA's
   to judge.
6. Writes the evidence and updates requirements and fixes in one atomic record
   update, then prints a one-screen summary. Exit 0 only when everything passed.

### Whose commits VBW judges

VBW's trailers (`VBW-Plan:`, `VBW-Fix:`, `VBW-Req:`) carry bare ids, and ids
start again when a project starts a new record: a roadmap retired with VBW 1,
or a record removed and made again, left commits whose trailers name ids the new
record uses again. Such a commit is not one of today's plans' commits. So every
reader of the trailers (the scope check, delivered files, `vbw plan done`'s
"the plan has a commit", the commits `vbw show` lists for a requirement, the
loop's report) reads only the record's own history: the commits after the
newest commit that added `.vbw/record.json`. The record is in git before any
plan can commit, because `vbw approve` commits it and a build needs an approved
contract. A project whose record was never committed keeps its whole history.
Each of those readers also reads each checked-out submodule's history, where
`vbw commit` commits the plan files inside it, and names a file there by its
path from the project folder. A submodule has no record of its own: its own
history starts after the commit the record's first commit pointed it at, or is
all of it when that commit had no submodule there (docs/workflows.md,
"Submodules"). One limit: an older branch merged in after the record was born is part of its
history, because git has it after the record's first commit.

### Delivered files

A plan delivers the files its own commits added or changed (the commits of the
record's own history whose `VBW-Plan:` trailer names it,
[Whose commits VBW judges](#whose-commits-vbw-judges)). A check can pass while such a file is gone: no
check reads `NOTES.md`, so deleting it by hand after the build breaks nothing a
check sees. So the proof checks each plan of the current milestone with git:

- The file must still be at `HEAD` with the content (and mode) that VBW's last
  commit of it left. VBW's commits are those whose `VBW-Plan:` trailer names a
  plan of the record, or whose `VBW-Fix:` trailer names a fix of the record.
- A later plan's or fix's commit moves the file on. A later plan that changes
  the file delivers the new content, and one that removes it delivers nothing
  for it. The newest plan commit that touched the file owns it. A plan whose task
  deletes a file delivers nothing for that file either. A commit a park undid
  (its `git revert` is in the loop's `reverts`) delivered nothing, because its
  change is gone, even when a later plan took its plan's id.
- Any other difference at `HEAD` is a deviation of the plan that owns the file: a
  hand edit, a hand deletion, a revert by hand, a merge. A hand commit that puts
  back the content VBW left is no deviation, because `HEAD` is what counts. So is a
  fix that brings the file back through its plan (`vbw commit PLAN`).
- These files are not deliverables: files under `.vbw/`, the check files (their
  approval guards them, see "Test files edited while building") and files in the
  approved results folders (`## Test results`).

Each deviation in the evidence is `{file, plan, commit, at, change, by}`: `commit` is
VBW's last commit of the file and `at` its time, `change` is `deleted` or `changed`,
and `by` lists the commits after it that changed the file outside any plan. A
change made by a merge alone lists none.

The check costs a fixed few processes, however long the history and however
many files. git lists the record's own history once to find the oldest commit that names a
plan of the current milestone, walks the file changes back to it once, reads the
park's reverts once (only when there are any), and lists `HEAD` once for the
files found. A proof recorded before this check existed lists no deviations.
The next proof checks.

**The user's decision.** A deviation the user chose is not one. A decision covers
a deviation when it was recorded (`vbw decide TEXT [WHY]`) at or after VBW's last
commit of the file, and its text or reason names the file's path as a word of
its own. A sentence's closing dot or a leading `./` does not hide the name.
`NOTES.md` names neither `NOTES.md.bak` nor `docs/NOTES.md`. A decision recorded
before the file was delivered does not cover it. `/vbw:fix` and `/vbw:debug`
record such a decision for the files they change. They are changes the user asked
for.

**The user settles it first.** Only the user knows whether a change made outside
VBW is wanted, so a deviation that no decision covers goes to the user before QA
or shipping: `vbw next` answers `deviations` (docs/next.md) with each file, its
plan, how it changed and by which commits. Keeping a change records a decision
naming the file (`vbw decide`). Restoring it runs `vbw fix restore FILE...`:

```text
usage: vbw fix restore FILE [FILE...]
```

Each file gets one fix that names it (`restore`), on its plan's first
requirement, and the fix round brings it back to what the plan made. The command
refuses a file that is not an unsettled deviation, or one a restore is already
under way for, and then records nothing. A restore closes when a proof finds the
file as its plan left it, not when the checks pass: no check names such a file.
If its fix round ends and the file still deviates, the restore opens again and
counts an attempt, up to the fix cap.

**What QA gets.** A phase that goes to QA gets its deviations with the decision
that covers each. This holds even for a phase whose pass stood, even when only a
document changed. The reason QA is told is
`NOTES.md, delivered by P1.1, was deleted outside any plan`. `vbw next --json` hands
the QA round each such phase's deviations (`round.deviations`, docs/next.md),
with `decision` (the id of the decision that covers it, or `null`). The QA agent's
prompt names them, and so does `vbw show phase`
(`deviation: NOTES.md (P1.1) deleted outside any plan, by abc123456789`).
`vbw qa record PHASE pass` refuses, at every QA depth, while one that no decision
covers stands. The refusal names each file and the way on: record a finding (`vbw qa
finding PHASE REQ TEXT`) and a failed verdict, so a fix brings the file back
through its plan, or, if the user chose the change, record the user's decision
naming the file, then record the verdict again.

### Timed speed checks are not part of the proof

`vbw prove` does not run VBW's own timed speed checks (the hook, status line
and panel benchmarks, and the test files named `tests/timed-*.bats`), so a busy
machine never fails or delays a proof. They run once per release, in
`bash tools/test.sh --release`, which CI runs on every pull request. `bash tools/test.sh`
without `--release` runs the same lint and tests the proof runs, without them.

### Full and partial proofs: `vbw prove --full`

```text
usage: vbw prove [--full]
```

`vbw prove --full` runs everything fresh: every approved check and every
approved project command, and never the quick command. It reuses nothing. Any
other argument is refused with the usage line, and nothing runs.

A plain `vbw prove` may reuse results
([Reusing results](#reusing-results-in-vbw-prove)). A proof is full only when
all of these hold; otherwise it is partial:

- it reused no check or other command result,
- it ran the test command, and not the quick command, and
- every project command ran (none was skipped as not approved).

The release run of VBW itself (`bash tools/test.sh --release`) reuses a passing
proof whether or not it reused results: a reused result is one the read lists
still vouch for. It does not reuse a proof that skipped a command or let the
quick command stand in.

The summary ends with `proof: full` or `proof: partial`, and the evidence
records the same in its `full` field (docs/record.md).

QA and shipping accept a proof that reused results. `vbw qa record` and
`vbw ship` need a proof that covers the current contract and code and passed.
A reused result is taken only when nothing its check read has changed, so a
proof that reused passing results counts as much as one that ran them. They
refuse a proof that is out of date or failed:

- `vbw qa record` prints the reason and asks for `vbw prove` first;
- `vbw next` returns the `prove` step before QA or shipping when the last
  proof is out of date.

For every check run fresh, use `vbw prove --full` (see
[Limits](#limits-of-reusing-results)).

### Proof in the background during an autonomous run

In an autonomous run (`/vbw:vibe --auto`), a stop hook runs each time Claude
stops. It reads `vbw next` and, until a step needs you, tells Claude to do the
next step. A proof can run in the background while Claude stops. To keep the hook
from asking for the proof again, `vbw prove` writes a mark for its session,
`.vbw/runtime/proving.SESSION_ID`, holding its process id, and removes it
however the proof ends (also on an error or an interrupt).

While that mark names a live process, the hook asks for nothing and spends no
autonomous step (`settings.autonomy_cap`) on the proof. When the proof ends, its
result wakes the session and the run continues. A mark left by a dead process is
stale and ignored. The mark belongs to one session: another session's proof does
not pause this session's run.

Because the copy holds only committed files, uncommitted edits and untracked
files in the working folder change no result. A check file that is not
committed as approved is refused: commit it, then `/vbw:approve`.

Git-ignored files (`node_modules/`, `.venv/`, `.env.local`) are the project's
environment, not its code, so the copy holds them too. They are copied, not linked.
A linked folder would let a proof write into the working folder, and some
tools refuse a linked `node_modules` outright (pnpm 11 does). A copy behaves as
the working folder does, and nothing a proof does changes the working folder.
VBW makes a copy-on-write clone where the file system offers one (APFS on macOS, btrfs or XFS on Linux), which is instant and takes no extra space. Where it does
not, VBW makes a plain copy, which is slower for a large folder. When a plain copy
brings in more than 500 MB of ignored data, the command prints once, on stderr, one
`vbw:` line naming the largest ignored folders it copied with their sizes (MB or
GB, one decimal) and the way out: list them under `## Clean copy` in
`.vbw/spec.md`, then `vbw spec sync` (see [`## Clean copy`](#clean-copy-clean-copy)).
A copy-on-write clone, 500 MB or less, or nothing ignored prints nothing. The
line changes no verdict, result or exit code.
Links that sit inside a copied folder stay links. When one is an absolute link
into the working folder, VBW prints a `vbw:` line naming it and still copies it
as it is. If an ignored file or folder cannot be read, the proof stops with an
error naming the path, instead of running on an incomplete copy.

Build output is not environment: the copy never brings in a folder named `target`,
`dist`, `build`, `bin`, `out`, `__pycache__`, `.pytest_cache`, `.mypy_cache`,
`.ruff_cache`, `.tox`, `.next`, `.nuxt`, `.gradle` or `coverage`, at any depth.
The copy builds its own, so a proof never reads stale output from the working
folder, and nothing it builds lands in the working folder or in another copy.
Each unit builds its own too: before a unit runs in a copy, the files an earlier
unit wrote inside a folder with one of those names are removed (Python's
`__pycache__` and `.pytest_cache` files, for example), so every unit starts as the
first unit of a fresh copy does. A file there that the copy was made with stays:
a tracked file, or one inside an ignored folder copied in whole, such as a virtual
environment.
Untracked files that are not ignored never enter the copy (D54): to make one
count, commit it or ignore it.

To keep a big ignored folder out of the copy, list it under
[`## Clean copy`](#clean-copy-clean-copy).

#### Leftover proof copies

A proof killed outright can leave its copy behind. The next `vbw prove` or
`vbw fix done` removes every leftover copy whose owner (the process named in
the folder) has ended, together with its git worktree entry. It never removes a
copy whose owner still runs. A copy without an owner in its name (made by an
older VBW) goes once it is more than 24 hours old. A copy that cannot be
removed (a locked file) leaves the result unchanged and prints one line:
`vbw: cannot remove the leftover proof copy <path>; remove it by hand`.

#### Links left pointing into a proof copy

An earlier VBW linked git-ignored folders into its proof copies. A link like
that can survive in your working folder and break once the copy is deleted.
After every `vbw prove`, VBW scans the working folder for such links and prints
one line for each:

```text
vbw: node_modules/.bin/tsc -> /home/me/app/.vbw/runtime/proof.k3Xa9/node_modules/typescript/bin/tsc points into a proof copy of an earlier run; re-run the project install command
```

The line names the link, where it points, and the repair. It appears only when
such a link exists; with none, VBW prints nothing. The scan only reads: it
changes no file, never follows a link, skips `.git` and `.vbw`, and never turns
a passing proof into a failing one. It also runs when the proof stops early
with an error.

To repair, rebuild the folder that holds the link:

- **pnpm projects** (a `pnpm-lock.yaml` or `pnpm-workspace.yaml` exists): delete
  `node_modules`, then run `pnpm install`.
- **Other projects:** re-run the project's install command (`npm install`,
  `pip install -r requirements.txt`, `bundle install`, and so on). If a link
  remains, delete the folder it sits in and run the install command again.

The warning stops once no link points into `.vbw/runtime/proof.*`.

Evidence (`record.evidence`):

```json
{ "at": "2026-10-01T09:00:00Z", "contract": "<sha256>", "tree": "<git tree id>", "passed": false,
  "checks": { "C1": { "status": "fail", "exit": 1, "seconds": 3, "tail": "…" } },
  "commands": { "test": { "status": "pass", "exit": 0, "seconds": 9, "tail": "" },
                "lint": { "status": "skipped", "exit": null, "seconds": 0, "tail": "not approved" } },
  "scope": [],
  "undone": [],
  "deviations": [] }
```

Statuses: `pass`, `fail`, `timeout`, `skipped`.

`tail` holds only the end of the output. When a check or project command fails
or times out, `vbw prove`, `vbw fix done` and `vbw check` keep its full output in
a file, so you can read the whole failure without running everything again.
`vbw show fix` names the file and lists the failing test names:

```text
.vbw/runtime/output/C1.log            check C1
.vbw/runtime/output/command-test.log  project command test
```

- There is one file per check or command, holding its latest failure; a newer
  failure replaces it.
- A pass in `vbw prove` or `vbw fix done` removes the file; a pass in `vbw check`
  leaves it as it is.
- A reused result, or a check that was skipped, leaves the file as it is.
- `.vbw/runtime/` is git-ignored, so these files are never committed.
- `vbw check` keeps a failing check's output the same way; `--expect-red` keeps
  nothing. `vbw show fix` reads the file and lists the failing test names.

An `auto` requirement is `proven` when all its checks pass and `failing`
otherwise. Human requirements are untouched.

### Reusing results in `vbw prove`

Most commits after a passing proof touch only part of the code. `vbw prove`
runs again only the checks a change can affect, and reuses the passing result
of every other check.

```text
C1 pass 2s reused (proof of 2026-10-07T20:49:55Z)
C2 pass 3s
lint pass 9s reused (proof of 2026-10-07T20:49:55Z)
checks: 1 ran, 1 reused
```

Each line shows the seconds the result took when it ran and, for a reused
result, the time of the proof that really ran it. A reused result keeps the time
it really ran and the fingerprint of that run, so reuse can chain across proofs.
In the evidence, reused results carry `"reused": true`, and the summary counts
`checks: N ran, M reused` and `test files: N ran, M reused`.

**The read list.** While a check runs, VBW records its read list: the files it
opened and the folders it listed. The list comes from the run itself,
never from file names, and not from the `files` a check declares. A check that
declares no files is judged by what it read, like any other, and a documentation
file a check reads is on its read list like any other file.

**When a result is reused.** A check's last pass is reused when the check has a
read list and nothing on it has changed since that pass.

**When a check runs again.** Every reason:

- Its approved definition changed (its command, expected exit and output,
  timeout, `alone`, `files` or requirement).
- A file on its read list was changed, deleted or renamed.
- A file or a sub-folder was added to or removed from a folder on its read list
  (a sub-folder appears with its first file and vanishes with its last).
- A file of its requirement's plans was added or deleted, whether or not the
  check read it: a check may test whether a path exists without opening it,
  and the contract says what each requirement's plans deliver (a plan's file
  entry is a path, a folder ending in `/`, or `*`).
- Its last result failed (fail, timeout or lost).
- It never passed: it is new, or no earlier proof ran it.
- It has no read list (for example, the earlier run recorded none).

A check removed from the contract is left out of the new proof.

**Where read lists are kept.** In `vbw/runs.json` in the clone's git directory
(`git rev-parse --git-common-dir`), never in the record. A lost or damaged
file only makes the checks run again. The store is protected
(docs/guards.md). It holds current units only: when `vbw prove` saves, the
runs of units that no longer exist leave it (a deleted test file, a test file
an approved check now runs, a check taken out of the record). The clone's
worktrees share the store, so a unit another worktree still has keeps its run:
a check or command its record names, a test file in its folder. A branch
checked out in no worktree is not consulted: switching back to it re-runs the
units only it has, once.

A run that read the project through git keeps no read list: it runs again
whatever changed, so its list could never vouch for it, and git's walk of the
project would put every file on it. A store an older VBW wrote loses such lists
at its next save. Beside the store, `vbw/run-times.json` keeps each run's
seconds alone, written with it. Time estimates read only that file, never the
store, whose read lists can run to hundreds of MB (docs/panel.md).

**Files a unit writes.** Build output a unit writes is removed before the next
unit runs in its copy (see the clean copy, above), so no unit reads
another's. Any other file a unit writes carries that unit's read list. A
later unit that reads the file inherits the list, so it runs again when
anything the writer read changed. A file two units wrote carries both lists,
and inherited lists pass on through a chain of units. The lists live in the
copy's written-file store, `written.json`: each run's read list is kept once,
by run id, and each written name once, so a unit that writes 1,000 files adds
1,000 names and one list.

**What `vbw next` caches.** To size the proof, `vbw next` plans the units the
next proof would run. It keeps that list in `.vbw/runtime/proof-units.json` and
plans again only when the committed tree, the git index, the record or the run store changes
([`docs/next.md`](next.md#the-step)).

**Speed.** Checks still run several at a time (`check_jobs`), each in its own
clean copy of the committed code.

### The two report lines: where the time went

`vbw prove` prints two lines just before its verdict (`proved` or `not proved`).
`vbw fix done` prints the same two lines right after its `test files: N ran, M
reused` line; its closing lines and exit code are unchanged. The line naming
the slowest units that ran comes just before the two lines in `vbw prove` and
just after them in `vbw fix done`
([Unit time and the budget per unit](#unit-time-and-the-budget-per-unit)).

```text
VBW's own work: 0.4 of 6.2 min
ran again: 3 of 52 units; top reasons: src/a.txt changed (2), definition changed (1)
```

**`VBW's own work: X of Y min`.** Y is the command's wall-clock time, up to the
end of its record step; X is the part VBW spent on its own bookkeeping instead
of running a unit's command (both in minutes, one decimal). Own work is five
steps:

- planning: reading the record and the contract, judging the named fixes
  (`vbw fix done`), planning the reuse, the scope check, and the trees of the
  committed code and of the working folder;
- copies: making, checking and removing the clean copies;
- read tracking: resetting access times before a unit and collecting its read
  list after it;
- saving: the run store and the kept output of failures;
- record: building the evidence and writing the record.

The clock inside the proof measures each step; nothing is estimated. Up to the
end of the record step, every second is one of these steps, a unit's command
running, or a wait for a slot ([The computer-wide limit](#the-computer-wide-limit)).
Writing the split itself, the record's commit and the printed summary come after
it. Read tracking is summed over the units, and units run side by side, so with
several running at once own work can exceed the wall time.

**Test hook: `VBW_PROOFTIME_CLOCK`.** A test may set this environment variable
to a file whose first line is the clock reading (seconds with milliseconds);
the proof's timer, and the timer of `vbw mutate`, then read that file instead of
the machine clock, so a test moves the clock by writing the file and waits no
real time. Unset or unreadable, the machine clock is read.

**`ran again: N of M units; top reasons: ...`.** M counts every unit the proof
covers (checks, approved commands, test files); N counts those that really ran.
A reason is the unit's own (the list under "When a check runs again", for
example `src/a.txt changed`) or, when the whole proof decided, that cause (for
example `this clone has no earlier recorded run`). The line names at most three
reasons, most frequent first, with their counts; ties keep the order of the
units in the evidence.

When nothing ran, both lines still print:

```text
ran again: 0 of 52 units; top reasons: none
```

**Before the first unit runs.** `vbw prove` prints the same count in the future
tense as its first line, from the plan (the reuse rule and the whole-proof
causes), so a long proof says why before anyone waits for it:

```text
run again: 52 of 52 units; top reasons: plugin/lib/core.sh changed (41), definition changed (7), never passed (4)
```

It counts and ranks the reasons exactly as the closing line does. `vbw next
--json` carries the top reason as `step.why` and ends the proof's `step.say`
with it ([the step](next.md#the-step)).

The steps stay in the evidence as `evidence.own` and the whole-proof causes as
`evidence.causes` (docs/record.md). `vbw show evidence` prints them.

Other things to know:

- An uncommitted change in the working folder does not make a check run again,
  and is never counted as proven: the proof reads only the committed code.
  Commit the work, then run `vbw prove`.
- A proof cut short (interrupted, or unable to write the record) recorded no
  evidence and saved nothing, or runs as complete as any proof's: the next proof
  reuses what the read lists allow, as if the cut-short one had not run.
- Project commands and test files follow the same rule. `vbw prove` reuses the test command's
  passing result when nothing it read changed; a command runs again only when its
  approved argv or time limit changed, a file it read changed, or its last result
  did not pass. A changed approved command re-runs only that command; a changed
  single-file form re-runs every test file; a changed list of test files runs the
  files it adds. Each unit re-runs by its own definition and its own read list, so
  none of these runs everything.

A proof that reuses results records the current contract and code. `passed` is
set from every result, reused or new, and requirements become `proven` as
usual.

#### When a proof runs everything

When VBW cannot tell what a change affects, it does not guess: every check and
test file runs, and the summary says why. One cause prints on one line; several
print as a list.

```text
  ran everything: this clone has no earlier recorded run
```

```text
  ran everything, because:
    - this clone has no earlier recorded run
    - this file system does not record which files are read
```

The causes, with the text the summary shows:

| What happened | Message |
|---|---|
| The file system cannot record which files are read | `this file system does not record which files are read` |
| A copy of a file is no read on the file system: `cp`, or `cat` into a file, leaves the source's access time as it was (a copy-on-write clone, as btrfs and XFS with reflink make), so a unit that copies a tracked file, as a test copies a fixture, would not have it on its read list | `this file system does not record a copied file as read` |
| The clone has no earlier recorded run | `this clone has no earlier recorded run` |
| `vbw prove --full` | `vbw prove --full` |
| Nothing was committed since the last passing proof (`vbw prove` only; `vbw fix done` reuses that proof): the project's files are the tree the last passing proof recorded (`evidence.tree`), the committed code is the tree it ran on (`evidence.head`), the record is as that proof left it (its fingerprint without the evidence is `evidence.record`: a decision, a verdict or a backlog item recorded since is a change, and the proof reuses by read lists), and the record's last proof passed | `nothing was committed since the last passing proof` |

A change to the project's files is never a cause: each unit's own read list
decides, with the contract's ties for a check. A content change to a file no
recorded run read runs nothing: it affects nothing that was run. An added or
deleted file re-runs the units that listed its folder or read it, and the
checks of the requirement whose plans list it, nothing else: a run that listed
the folder recorded the names inside it, so the changed listing re-runs that
run; a file whose own folder appeared or vanished with it (the first file of a
new sub-folder, the last file of one) is seen through the nearest folder above
it that a run listed; a check may test whether a path exists without opening
it, so the files its requirement's plans deliver re-run it when they appear or
vanish, read or not; a unit that reads the project through git always runs
again. A file added to or deleted from a folder no run listed, that no run read
and no plan of a check's requirement lists, runs nothing: no run could have
seen it, and the contract ties nothing to it. A changed approved
command, single-file form or list of test files is no cause either: each unit
re-runs by its own definition ([Reusing results](#reusing-results-in-vbw-prove)).
A proof cut short (interrupted, or unable to write the record) is no cause: it
saved nothing, or runs as complete as any proof's, so the next proof reuses
what the read lists allow, as if the cut-short one had not run.

Every summary, full or not, prints both counts:

```text
  checks: 1 ran, 1 reused
  test files: 2 ran, 40 reused
```

They read `checks: N ran, M reused` and `test files: N ran, M reused`. After
`vbw prove --full`, the reused counts are 0.

#### Limits of reusing results

- What lies outside the project is not tracked: installed tools, the network
  and the clock. A check that depends on them can pass from reuse after they
  changed.
- On a file system that copies a file by a copy-on-write clone (btrfs, XFS
  with reflink), nothing is reused: a clone shares the data without reading
  it, so a copied file never shows on a read list. Every proof there runs
  everything and says why (the causes above). There is no setting that turns
  clones off; a project on another file system reuses as usual.
- A check that only looks whether a file exists, or at its size, without
  opening it or listing its folder, does not put that file on its read list: a
  change to that file does not run the check again, and neither does its
  addition or deletion unless a plan of the check's requirement lists it.
- A script a unit executes by its path (`./greet.sh`) does not put its folder
  on the read list. The cause is a start-up listing: the first time the system
  executes a new file by its path (macOS does; Linux was measured and does not),
  it notes the folder holding that file as listed, though no test asked for it,
  and an unrelated file added to that folder would then re-run the unit. VBW
  cannot prevent that read, so it leaves out of a unit's own read list the
  folder of its program, whenever the program (the first word of the command,
  given by its path or found on `PATH`) is a file inside the project. Running
  the script through `sh greet.sh` never had the listing. The limit: a test that
  both executes a script of a folder by its path and lists that same folder
  itself loses that listing. A listing the test itself asks for (`ls`, a glob,
  `find`) in any other folder stays a read, and a file added there re-runs the
  unit.
- Reads through git always run again. Any git command whose working directory
  is inside the project counts, even one that reads nothing of the project
  (`git config --global` run from the project folder): git opens the
  repository before it does anything else. Such a run keeps no read list
  (above). A test suite that runs such commands from another folder keeps its
  results reusable. VBW sees it by
  the copy's `.git` file, which every git command run inside the copy reads
  first. Git run elsewhere in your repository while a unit runs does not count
  (`git worktree list`, `git branch`, `git gc`, `git fetch`, another proof making
  its copy), though it reads the copy's `HEAD` in the shared git folder. Two
  commands do count: `git status --ignored` and `git clean -X` (also with `-n`),
  run in the project, open each proof copy's `.git` file to see whether it is a
  repository of its own, exactly as git inside the copy does. A unit running
  meanwhile counts as reading through git and runs again in the next proof.
- A commit in a submodule runs every check and command again: git names only
  the submodule's folder as changed, never the files inside it, so no read list
  can vouch for a run made before. Files read inside a submodule are on the read
  lists by their project paths (`apps/mobile/src/comms.ts`), and git run inside a
  submodule of the copy counts as reading through git.

To run everything fresh, use `vbw prove --full`, or prove again with
nothing committed since a passing proof (a second `vbw prove` is a deliberate re-run).
That last cause is `vbw prove`'s alone: `vbw fix done` right after a passing proof
reuses what the rule allows, because a passing proof of the same code is exactly
what it needs. VBW compares those trees and the record's fingerprint, and
never the subject of the last commit, so a VBW record commit landing after code
commits re-runs nothing it need not. Those are the cause's only conditions: the
contract and the commands live in the record, so its fingerprint covers them.

### Fix items

A failure becomes a fix item: `req` for a failing requirement, `command` for a
failing project command. Lifecycle:

| Before prove | Target passes | Target fails |
|---|---|---|
| no fix item | nothing | new fix, `open`, `attempts` 0, once the work is built (below) |
| `open` (not verified by `vbw fix done`) | `closed` | stays `open`, with this proof's failures |
| `fixed` (work committed and verified by `vbw fix done`) | `closed` | `attempts` + 1, back to `open`; `escalated` at the cap (3) |

A failure opens a fix only once the work is built: every plan serving the
requirement (for a project command: every plan) is `done`. Before that, a
failing check is work in progress, not a defect, and opens nothing.

`vbw fix done` is verified, not claimed: none of the files the fix may touch has
uncommitted changes, and the checks of every finished requirement (all its plans
`done`) that those files serve pass now. A fix cannot quietly break other work.
Those checks run only on an approved contract, and otherwise `vbw fix done` is
refused as `vbw prove` is; a fix with nothing to re-check needs no approval.
A project command's fix is left to `vbw prove`, which runs the command. A fix of
the test command with a single-file form is the exception: it judges every test
file by the reuse rule (the failed file and any changed file run, the rest are
reused and counted), and saves the files it ran for the next proof to reuse.

`vbw show fix F1` names each failing check's or project command's kept full output
file (`full output: .vbw/runtime/output/C1.log`), listed under it. When no file is
kept, for example after it was removed, it says
`full output not kept: run vbw prove again`. Under each failing check, test file
and project command it also lists `failing tests:`, one line per failing test name
it recognises (TAP/bats, cargo test, pytest, go test, jest, vitest, mocha); when
none is recognised it says `failing tests: none recognised in the output; read the
full output file`. A failing single-form test file is listed by its path with its
kept file. With `--json`, each failing unit has `kept`, the file's path or `null`,
and `failing_tests`.

A requirement fix commits the check files of its own requirement with
`vbw commit --fix F1 "<msg>" FILE...`; the commit carries `VBW-Fix` and
`VBW-Req` trailers. These check files wait for one approval before the proof;
`vbw next` asks for it. A check file of another requirement is refused, and code
goes through its plan with `vbw commit PLAN`.

While any check file waits for the user's approval (a fix changed or added it),
nothing can be proven before the user approves, so `vbw fix done` runs no
check: a re-check then could take long and still wait for that approval, which
no agent can give. It still refuses an unknown, not open or uncommitted fix, and
the others end as usual (`fixed`, awaiting the proof):

```text
check files are waiting for approval, so no check runs before it: tests/c1.sh
the user approves them first (vbw next asks); then vbw prove runs every check
checks: 0 ran, 0 reused
test files: 0 ran, 0 reused
VBW's own work: 0.0 of 0.0 min
ran again: 0 of 0 units; top reasons: none
F1 fixed: vbw prove decides
```

`vbw next` then asks for the approval, and the proof after it runs every check
the round would have re-checked.

### Closing several fixes

```text
vbw fix done F8 F9 F5
```

One command closes several fixes. The checks that their files serve run once
(the union, not once per fix), and a check that passed earlier is reused as
below. Each fix ends as it would if closed alone: `fixed` and awaiting
`vbw prove`, or, for a `[human]` requirement, `closed` with the requirement
back to the user for acceptance. Naming an id twice closes it once.

A fix of the test command with a single-file form judges every test file by the
same rule: the failed file and any changed file run, the rest are reused and
counted. The files it runs are saved for the next proof to reuse.

A fix that cannot close is named, and the others still close. The cases:

- an unknown id, or a fix that is not `open`;
- uncommitted changes in a file the fix may touch;
- a failing check: only the fixes whose requirement that check serves fail
  (`F2 broke finished work`, with the check), the rest close.

The exit code is 0 when every fix closed and non-zero when any could not. A fix
that could not close keeps its status and `attempts`; fix the cause and run
`vbw fix done` again for it. A fix of an `[auto]` requirement or a project
command lists the failures of the last proof, so when the code changed since
that proof (a round committed work and its `vbw fix done` was refused),
`vbw next` asks for `vbw prove` before another fix round, and the round works
from the failures of the current code. A fix QA, a restore or a rejection
opened keeps its own note, which no proof rewrites, and is worked at once.

### Reusing an unchanged pass

`vbw fix done` follows the same rule as `vbw prove`
([Reusing results](#reusing-results-in-vbw-prove)): a check whose last pass is
still valid for its read list is not run again. It prints one line per check
and per test file, reused or run, and then both counts:

```text
C1 pass 2s ran: src/pay.txt changed
C2 unchanged since its pass (2026-10-04T20:30:00Z)
tests/t_a.sh pass 3s ran: last result failed
tests/t_b.sh unchanged since its pass (2026-10-04T20:30:00Z)
checks: 1 ran, 1 reused
test files: 1 ran, 1 reused
```

Each check and test file that ran gets a line in the proof summary's wording,
with the reason it ran; a reused one keeps the time of the pass it reuses.
Both count lines print after every per-unit line, every time (`0 ran, 0
reused` when nothing was judged), before the closing outcome lines. A check
runs again for any reason listed there: a changed approved definition, a
changed file on its read list, a last result that failed, no earlier pass or
no read list. When a cause ([Causes](#causes)) makes the rule run every
candidate, the cause line comes first and every unit ran, with no reason of
its own:

```text
every candidate check runs: this clone has no earlier recorded run
C1 pass 2s
C2 pass 1s
tests/t_a.sh pass 3s
checks: 2 ran, 0 reused
test files: 1 ran, 0 reused
```

An escalated fix is a human gate (`vbw next`).

Accepting a `[human]` requirement (`vbw req accept ID`) closes only the fixes
that the user's own rejections opened (`vbw req reject ID NOTE`). A fix that QA
opened (`source: "qa"`) stays open after acceptance and closes only on a passing
QA verdict (below).

### Skip for now: judging a `[human]` requirement later

When you cannot judge a `[human]` requirement yet, answer "Skip for now". The
skill records it with `vbw req skip R2`. The three answers stay: Works
(`vbw req accept`), Something's wrong (`vbw req reject`) and Skip for now.

If every other requirement is done and only skipped `[human]` ones remain,
`vbw next` offers `ship` and names them in `detail.later`. You choose once:
ship now and judge them in the next milestone, or judge them now (`vbw req
accept R2`). Looking at the offer changes nothing in the record.

`vbw ship` then ships the milestone. Its decision counts only the requirements
that were proven or accepted and names the moved ones
(`...; moved to the next milestone to judge: R2`). `vbw milestone start TITLE`
moves each into the new milestone with the same id, text, proof type, rules and
history (fixes, decisions, checks), status `open`. `vbw next` there asks you to
accept it. Its line in `.vbw/spec.md` stays as it was, and `vbw spec sync`
neither resets nor duplicates it.

What never moves: an `[auto]` requirement (`vbw req skip` refuses it; a check
can judge it), and a `[human]` requirement with an open fix from your rejection
(`vbw req skip` refuses it too). Finish the fix with `vbw next`, then judge the
requirement or skip it. `vbw ship` refuses while such a fix is open.

### The mutation check

At standard and deep, the builder breaks the plan's code on purpose (one
statement per rule) with `vbw mutate` and runs the rule's own check. Breaks of
several rules can run side by side: each is queued (`--queue`), then `vbw mutate
PLAN --run` runs them at once, each in its own clean copy. See
docs/workflows.md for the command and docs/rigor.md for the levels.

A task break (`taskK`) without `--check` runs the checks of the plan's own
rules: those of the rules that name the plan and those of the requirements it
completes, each check once. A red check of a rule the plan does not owe does not
refuse the break, so an early plan of a requirement that later plans complete
can still break its tasks. `vbw show plan` marks what is another plan's: a rule
reads `[P1.3's, built after this plan]`, and a check that only other plans' rules
use reads `[P1.3's: red until it is built, not this plan's to pass]`. The order is
`built before this plan`, `built after this plan`, `built beside this plan`,
`done` or `blocked`. The Dev's red-first and green steps use only the plan's own checks (the unmarked ones); another plan's red check is no blocker. A plan that owns no rule runs the checks of its
requirements, and a refusal then says it owns no rule and that the Lead names a
plan on each rule.

A break with several checks (a task break) runs them one at a time, fastest
first by their last recorded time, and stops at the first that goes red; a
survivor runs them all. Each check first runs once on the unbroken code, unless
an earlier break of the same committed code (each submodule at its own `HEAD`)
already ran it. A slow test
suite therefore pays for the checks a break needs, not for every check.

- A check that notices the break is **red**: the rule is covered.
- A test that cannot fail, because every check stays green, is a **survivor**.
  The Dev strengthens it in place, in a check file that a check of the plan's
  own rules names (one shared with other requirements' checks included). It
  must never weaken an assertion. Then it repeats the same break until it is
  red. After two attempts that stay green the Dev blocks the plan.
- `vbw plan done` waits for the breaks: at standard it refuses until each
  approved rule of the requirements the plan completes has a red break, and
  lists the rules missing one. A rule that names its plan (`plan` in the
  Lead's rules: the plan that builds its code) is asked of that plan when it
  finishes, even while another plan of the requirement is open, so each plan
  breaks its own rules. Deep asks the same, one break per rule; a task break
  there is the builder's, for a task whose behaviour no rule's check covers.
  At express it asks for nothing. A survivor alone covers nothing.

- A rule whose check judges only the record (a measurement kept as a decision,
  for example) has no code to break. It is recorded with `vbw mutate PLAN Rn.k
  --none REASON` after the kernel verifies the check's read list against the
  files of the requirement's plans: the list must name none of them. The command
  may run the check once in a clean copy of the committed code, with read
  tracking on, and records that run in the store as a proof would. A check that
  only tests whether a plan file exists, without opening it, never reads that
  file: such a check is not detected, and the accepting line says so. `vbw plan
  done` counts such a rule covered.

The broken file, and its restore, get a fresh modification time, newer than
every file in the proof copy (even one stamped ahead of the clock). Builds that
decide by file times (make, cargo) rebuild the broken code, so a break is never
called a survivor because the old build was tested, and rebuild the clean code
after the restore. A break that deletes a file stamps nothing. The newest time
is read in one pass over the copy, dependencies included: about a second for
100,000 files, so a large `node_modules` does not slow the break down.

When a break stays green on the approved check but a strengthened check file
that waits for approval catches it, `vbw mutate` prints `TARGET survives the
approved check; caught by the pending one: FILE...` and exits 0. Without an
earlier survivor of that target, it says a check file waiting for approval
caught the break and names it. The pending file is one the plan may
strengthen, a file of its own rules' checks, and still needs the one approval
before the proof, as below. The strengthened files are files of its own rules'
checks too, changed since the earlier survivor of that target.

After a survivor, `vbw commit PLAN "<msg>" FILE` commits a check file that a check of the plan's own rules names, shared with other requirements or not, with the plan's trailers; a check file that no check of the plan's own rules names, and any check file before a survivor, is refused by name.

A strengthened check file adds one approval. The build finishes, then `vbw next`
asks you to approve the file before the proof, and `vbw prove` refuses until
you do. Under a loop, the loop gives that approval and records a decision that
names the file. A changed check file that no mutation check strengthened, or
one edited again after its red break, still waits for you.

### QA verification

Passing checks prove each requirement's behavior; they cannot see whether the
work matches the plan that was agreed. After a passing proof, VBW 1's QA agent
verifies each built phase goal-backward, at the profile's tier, against its goal
and criteria (the Architect's) and its plans' tasks (the Lead's): test gaps and
every deviation from the plan are failures. Each failure is recorded with
`vbw qa finding PHASE REQ TEXT` (the phase whose QA found it; a finding given
without the phase is adopted by that phase's fail verdict), a fix item with
`source: "qa"` that a proof never closes; the verdict with `vbw qa record PHASE
pass|fail TIER`, against the phase's inputs (see "Which phases QA checks
again"). A verdict changes only its own phase's findings: a pass closes them,
never another phase's, so phases that share a requirement can be verified in
parallel (D332); three failed rounds in a row escalate. A round after a fail
verifies that round's fixes, not the whole phase again
([Re-check rounds](#re-check-rounds)).

One part of the comparison with the plan is mechanical, at every QA depth: a file
the phase's plans delivered that `HEAD` no longer holds as VBW left it is a
deviation the proof found ([Delivered files](#delivered-files)). QA is told each
one. A pass is refused while one stands that no decision of the user covers, so
even a `quick` QA that only runs the checks cannot pass over a missing
deliverable.

Only behaviour blocks (D400). A finding is code that does something wrong or
misses a promised behaviour, a test gap, a deviation, or a document stating a
false or missing fact the user relies on (a command, setting, number, file or
limit). Wording, tone, style, naming and a test that does not pin a sentence's
exact words are notes: QA lists them in its summary, and they never fail a
phase.

The project's test command is not run again for QA. The proof runs it once
(a project command, above) and `vbw next` hands that one result to the QA round
(`round.suite`, docs/next.md). QA agents use it as evidence and do not run the
suite themselves.

Every QA agent's prompt names the test command, its result (`pass`, `fail`,
`timeout`, `skipped` or `not run`), its exit code, its time and how its output
ended. A piece the round does not carry is named in plain words, for example
"its output was not kept"; the prompt never prints `undefined`. When the
command did not run, the agent is told not to retry it and to say in its
summary that the suite was not run. When the project has no test command, the
agent is told so and says so in its summary.

### Which phases QA checks again

After a round of fixes, QA checks only the phases that need it. An untouched
phase keeps its pass. A built phase is checked again when:

- it never passed, or its last verdict was a fail;
- its own inputs changed since it passed: its files (the files of its plans),
  its tests (its requirements' checks and their files), or its goal and plan;
- the tests of a phase it builds on changed (that phase's requirements' checks
  or their files), even if its own inputs did not. A phase builds on another
  when one of its plans comes after a plan of the other, directly or through
  other phases. A change to that phase's code, documents, saved results, goal
  or plan does not list it: that phase is checked again itself, and what the
  phases built on it rely on is what its checks promise;
- one of its `[auto]` requirements was added, reworded or removed;
- a file its plans delivered changed outside any plan and no decision of the
  user covers it ([Delivered files](#delivered-files)). This holds whatever else
  changed, even when the file is a document.

Files and tests count as committed (`HEAD`), so commit work before QA.

Updating VBW alone never lists a passed phase. Each pass's fingerprint carries
the version of how it was computed. When an update changes that method, the
phase is compared as it was at its pass (at the commit the pass was recorded
at), computed the new way. Only a real change to its files, tests, plan or
requirements lists it, with the usual reason. If that commit is not in this
clone, the phase is checked again as described below.

These changes do not list a passed phase again, because QA has nothing new to
judge:

- a recorded decision (it is not code, a test, a goal or a requirement);
- a finding closed with no code change (the files are the same);
- a removed [human] requirement, or a reworded one (QA never judges what only
  a person can: `[human]` requirements are not among QA's inputs).
- a change to documentation only: files ending in `.md`, `.markdown` or `.rst`.
  A plain `.txt` file counts as data, so changing it lists the phase;
- a change only to saved test results inside the approved `## Test results`
  folders ([Saved test results](#saved-test-results--test-results)).

These exceptions have limits. The phase is still listed when:

- the file is one a check uses: a file in one of its checks' `files`, or named
  in a check's command. That file is a test, even as Markdown or inside a
  results folder;
- every plan of the phase changes only documents (a documentation-only
  phase): its documents are its code;
- the same change also touches code, tests, the goal or the plans;
- a results folder was added or removed but the new list is not approved yet.
  Until approval, a file in the new folder counts like any other file;
- the document is one its plans delivered and it changed outside any plan, with
  no decision of the user that covers it ([Delivered files](#delivered-files)).

Changing the approved folder list checks once more each phase whose plans list
files inside the folders added or removed; the new pass stores the new list.

The rule works on each input separately. A skip-type change that comes together
with a listed change does not protect the phase: a decision plus a changed test,
a closed finding plus a code change, or a removed [human] requirement plus a
changed goal still list the phase, with the reason of the listed change.

Re-planning mid-milestone (`vbw apply` with phases added or changed) keeps each
existing phase's QA verdict. QA then checks again only the new phases and the
phases whose own inputs changed, by the rule above.

```
$ vbw show qa
P1 is checked again: its files changed
P2 is checked again: builds on P1, whose tests changed
P3 keeps its pass
```

`vbw show qa` prints one line per built phase: the phases checked again with
every reason (several reasons are joined with `; `), then the phases that keep
their pass. When no phase needs checking, the first line is
`Nothing needs checking again`. A line starting `problem:` names a plan link that
points nowhere or loops.

The reasons, in plain words:

| Reason | Meaning |
|---|---|
| `not checked yet` | QA has never recorded a verdict for the phase |
| `failed last time` | the last verdict was a fail |
| `its files changed` | a file of one of its plans changed since it passed |
| `its tests changed` | a check of its requirements, or a file of that check, changed |
| `its goal or plan changed` | the goal or the plans changed |
| `an [auto] requirement changed` | an `[auto]` requirement of the phase was added, reworded or removed |
| `builds on P1, whose tests changed` | a check of a phase it builds on, or a file of that check, changed |
| `its files, tests or plan changed` | something changed, but the cache that says what is missing |
| `NOTES.md, delivered by P1.1, was deleted outside any plan` | a file its plans delivered was deleted (or `changed`) by a commit outside any plan, and no decision of the user covers it ([Delivered files](#delivered-files)) |

`vbw next` sends only these phases to QA, gives the reasons in its `qa` key
(docs/next.md) and states them in its instruction line. The QA skill tells the
user the same. `vbw qa record PHASE pass` stores a digest of the phase's inputs
and the tests of the phases it builds on in the phase's `qa.tree` (docs/record.md).

#### Re-check rounds

The whole-phase sweep runs once, at a phase's first QA round. When the last
verdict was a fail and the phase's goal, criteria, plans and `[auto]`
requirements are unchanged since, the next round is a re-check round: `vbw
next` adds the phase to `round.focus` with `since` (the commit the failed
verdict was recorded at), `round` (2 or more) and `fixes` (the QA fixes of the
phase still open or fixed, each with its requirement and note). The QA agent is
told to verify only those fixes, the files changed since that commit and what
they reach, and that the goal still holds; anything else it notices is a note
unless it breaks the goal. A change to the goal, criteria, plans or `[auto]`
requirements since the failed verdict, or a clone without the cache
`qa.json`, brings back the whole-phase sweep.

A record from before this rule holds the proof's tree id in `qa.tree`. It matches
no digest, so each such phase is checked once more, and the new pass stores a
digest. The same happens when the clone's cache `qa.json` is missing or damaged:
the cache only names the reason, never decides, so a phase is checked again with
the reason "its files, tests or plan changed".

`vbw qa record` refuses a verdict when no proof exists yet, or when the project
files differ from the proof's `tree` (the code changed since the last proof). The
error asks for `vbw prove --full` first; the verdict is recorded only against a proof of
the current code. The QA agent handles the refusal itself: it runs
`vbw prove --full` and retries the record once.

### Freshness

Evidence carries two fingerprints. `tree` is a git tree id of the working
folder when the proof finished: tracked and new files, committed or not,
`.vbw/` and ignored files excluded. `head` is the tree of the committed code
the checks ran on, `.vbw/` excluded. `vbw next` treats evidence as stale, and
asks for `prove` again, when the contract changed or either fingerprint no
longer matches: the working files changed, or new code was committed (an edit
proved while uncommitted and committed later was never checked). Committing
VBW's own record changes nothing.

Uncommitted changes are not proved. Commit the work, then run `vbw prove`, so
the evidence covers the code you will keep.

### `vbw check [--expect-red] [CHECK...]`

Runs the given approved checks (all when none are given) on the working folder,
uncommitted and untracked files included, and reports. It writes only the full
output of each failing check to `.vbw/runtime/output/<check>.log` and prints
`  full output: PATH` under that check's line (`--expect-red` keeps nothing): the
Dev's tool for the red and green steps. Exit 0 when all pass. With `--expect-red`, red-first:
before a plan is built its checks must fail, and a check that already passes
proves nothing, so exit 0 only when every check fails.
