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
  `vbw show contract` shows the folders and how they changed.
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
and fails.

### Checks run in parallel

```text
vbw config set check_jobs 8     # up to 8 checks at the same time
vbw config set check_jobs 1     # one after another
vbw config set check_jobs default
```

`vbw prove`, `vbw check` and the checks of `vbw fix done` run at most
`check_jobs` checks at a time: 1 to 64, default 4. The setting belongs to this
clone and is shared by its worktrees; it is not in the record or the contract,
so changing it needs no approval. `vbw config` shows it. A missing or damaged
setting means 4.

The results are the same as running the checks one after another: the
evidence lists them in the checks' own order, whatever order they finish in.
Checks marked `alone` (below) still run by themselves. A proof of many checks
takes about as long as its slowest checks, not the sum of all of them. Checks
that share a resource and are not marked `alone` (a database, a fixed port) can
disturb each other: mark them `alone`, or set `check_jobs` to 1.

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

## The contract and approval

The contract is the requirements (id, text, proof, and rules when listed), the checks, the plans
(everything but their status) and the contents of every check's `files`. Its
hash is SHA-256 over a canonical rendering of all of it.

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
  `vbw show contract --changes`, then approve once.
- `vbw prove` refuses and names the files: `check files changed since it was
  approved are waiting for approval: tests/pay.sh: review them, then /vbw:approve`.
  Nothing is proved.

A change to the structure (a new check, a changed `run`, a plan's files) is not
waiting: the contract needs approval first, as before.

### An approval whose commit fails

`vbw approve` commits the approval record. When that commit fails (a project
hook refuses it, or git has no identity), VBW stops and prints git's own reason
and `the approval commit failed (reason above); the contract is not approved`.
It exits non-zero and leaves no approval: the decision is not in the record and
no consent is kept. `vbw show contract` still says `NOT APPROVED` and `vbw next`
asks again. Fix the cause (for example, make the hook pass) and approve again.
Other VBW commits still only warn, with git's reason.

## Rules

A rule is one condition, edge or error case that an `auto` requirement's text
states, paired with the check that tests it. The Lead lists them with
`vbw apply` (docs/workflows.md), so an approved contract shows what each check
is meant to cover, not only that checks exist.

`vbw show contract` is the approval screen. Each `auto` requirement shows its
rules with their checks:

```text
R1 [auto] A customer can pay once
  rule: A payment succeeds -> C1
  rule: Paying twice is refused -> C2
```

- `vbw approve` refuses an `auto` requirement whose rules are pending
  (`rules: []`): `R1 has no rules listed (vbw apply with rules)`.
- Rules are part of the contract hash: adding, removing or re-pointing a rule
  needs re-approval, and `vbw show contract --changes` lists it as
  `added rule`, `removed rule` or `changed rule`.
- When a requirement's text or proof changes, `vbw spec sync` resets its rules
  to pending, so the Lead restates them.
- A requirement approved before rules existed (no requirement has a `rules`
  field) keeps its approval. Its screen shows `rules not listed`, and nothing
  forces rules until the Lead applies a plan that lists them (D53). Once any
  requirement has rules, new and changed `auto` requirements need them too.

## Project commands

The project's own test, lint and build commands live in `.vbw/spec.md`, under
`## Commands`, one per line: a name, then the command as words, or as a JSON
array when an argument contains spaces:

```markdown
## Commands

- test: cargo test --locked --workspace --manifest-path market_recorder/Cargo.toml
- pytest: conda run -n portfolium python -m pytest -q market_recorder/
- e2e: ["sh", "run tests.sh", "--fast"]
```

`vbw init` writes the commands it detects there as a suggestion (in a
repository with several sub-projects it sees only the root, so check them).
Edit a line to change a command, delete it to stop running it, then
`vbw spec sync`: the record's commands become exactly that section. A spec
without the section keeps the commands it has. A command whose exact argv the
user has not approved makes `vbw next` ask for approval again, and
`vbw prove` runs only approved commands.

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
command runs instead. `vbw prove --full` never runs the quick command.

Any change to the contract (a check edited, a test file touched, a plan's files
widened) changes the hash, and the contract is unapproved again until the user
re-approves it. `vbw show contract` renders what is being approved, and
`vbw show contract --changes` only what changed since the last approval in this
clone (`vbw approve` keeps a copy of what it approved in `.vbw/runtime/`).

## `vbw prove`

1. Refuses unless the current contract hash is approved.
2. Makes a clean copy of the committed code (`HEAD`) inside the project, under
   `.vbw/runtime/`.
3. Runs every check (up to `check_jobs` at a time, `alone` checks by themselves),
   and every project command whose argv is approved, from the
   root of that copy; an unapproved command is skipped and reported, never run.
   A check whose served files, definition and last result are unchanged since
   its last pass is reused, not run again
   ([Reusing results in `vbw prove`](#reusing-results-in-vbw-prove)).
   Then it removes the copy, also when interrupted.
4. Scope: every commit with a `VBW-Plan:` trailer naming a plan in the record
   must change only that plan's files.
5. Writes the evidence and updates requirements and fixes in one atomic record
   update, then prints a one-screen summary. Exit 0 only when everything passed.

### Full and partial proofs: `vbw prove --full`

```text
usage: vbw prove [--full]
```

`vbw prove --full` reuses nothing. It runs every check, the test command and
every other approved command, and never the quick command. Any other argument
is refused with the usage line, and nothing runs.

A proof is full only when all of these hold; otherwise it is partial:

- it reused no result ([Reusing results](#reusing-results-in-vbw-prove)),
- it ran the test command, not the quick command, and
- every project command ran (none was skipped as not approved).

The summary ends with `proof: full` or `proof: partial`, and the evidence
records the same in its `full` field (docs/record.md).

A full proof is needed at two points, QA and shipping. Both refuse a partial
proof and change nothing:

- `vbw qa record` prints:
  `the last proof was partial: run vbw prove --full, then record the verdict again`
- `vbw next` returns the `prove` step before QA or shipping, with an
  instruction that starts `Run vbw prove --full: ...`; `vbw ship` refuses with
  the same advice.

Build and fix rounds use the plain, faster `vbw prove`. The test result QA
agents receive always comes from the full proof.

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
VBW makes a copy-on-write clone where the file system offers one (APFS on macOS,
btrfs or XFS on Linux), which is instant and takes no extra space. Where it does
not, VBW makes a plain copy, which is slower for a large folder.
Links that sit inside a copied folder stay links. When one is an absolute link
into the working folder, VBW prints a `vbw:` line naming it and still copies it
as it is. If an ignored file or folder cannot be read, the proof stops with an
error naming the path, instead of running on an incomplete copy.

Build output is not environment: the copy never brings in a folder named `target`,
`dist`, `build`, `bin`, `out`, `__pycache__`, `.pytest_cache`, `.mypy_cache`,
`.ruff_cache`, `.tox`, `.next`, `.nuxt`, `.gradle` or `coverage`, at any depth.
The copy builds its own, so a proof never reads stale output from the working
folder, and nothing it builds lands in the working folder or in another copy.
Untracked files that are not ignored never enter the copy (D54): to make one
count, commit it or ignore it.

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
  "scope": [] }
```

Statuses: `pass`, `fail`, `timeout`, `skipped`.

`tail` holds only the end of the output. When a check or project command fails
or times out, `vbw prove` keeps its full output in a file, so you can read the
whole failure without running everything again:

```text
.vbw/runtime/output/C1.log            check C1
.vbw/runtime/output/command-test.log  project command test
```

- There is one file per check or command, holding its latest failure; a newer
  failure replaces it.
- A pass removes the file.
- A reused result, or a check that was skipped, leaves the file as it is.
- `.vbw/runtime/` is git-ignored, so these files are never committed.

An `auto` requirement is `proven` when all its checks pass and `failing`
otherwise. Human requirements are untouched.

### Reusing results in `vbw prove`

Most commits after a passing proof touch only part of the code. Running every
check again would prove nothing new for the checks whose files did not change.
`vbw prove` runs again only the checks that can have changed, and reuses the
rest.

```text
C1 pass 2s reused (proof of 2026-10-07T20:49:55Z)
C2 pass 3s
lint pass 9s reused (proof of 2026-10-07T20:49:55Z)
checks: 1 ran, 1 reused
```

Each line shows the seconds the result took when it ran and the time it
really ran. A reused result keeps the time and fingerprint of the run it came
from, so reuse can chain across proofs without losing the original time. In the
evidence, reused results carry `"reused": true`. The last line counts the
checks: `checks: N ran, M reused`.

A check runs again when any of these holds:

- Its served files changed since its last pass. Served files are the check's
  own `files` plus the files of every plan that serves its requirement.
- Its approved definition changed (its command, expected exit and output,
  timeout, `alone`, `files` or requirement).
- Its last result was fail, timeout or lost (never recorded).
- It is new since the last proof.

Every other check is reused. A check removed from the contract is left out of
the new proof.

A check that declares no files always runs: VBW cannot know what it depends
on, so it cannot know that nothing it depends on changed. A check with a
served path that is missing from the committed code always runs too.

Some things to know:

- A change in the working folder that is not committed
  does not make a check run again, and is never counted as proven: the proof reads only the committed
  code. Commit the work, then run `vbw prove`.
- An interrupted proof reuses nothing: it recorded no evidence, so the next
  proof runs every check.
- A second `vbw prove` with no commit since a passing proof runs everything
  fresh. It is a deliberate re-run, for when something outside the committed
  code changed, such as installed dependencies.
- Project commands keep their own rule: a command's result is reused only when
  the committed code is identical to the last passing proof's (only
  `.vbw/record.json` or `.vbw/spec.md` differ), the working folder has no
  uncommitted or untracked project files, and its approved argv is unchanged.

A proof that reuses results records the current contract and code. `passed` is
set from every result, reused or new, and requirements become `proven` as
usual. It is a partial proof: `vbw qa record` and `vbw ship` need a full one
([`vbw prove --full`](#full-and-partial-proofs-vbw-prove---full)).

### Fix items

A failure becomes a fix item: `req` for a failing requirement, `command` for a
failing project command. Lifecycle:

| Before prove | Target passes | Target fails |
|---|---|---|
| no fix item | nothing | new fix, `open`, `attempts` 0, once the work is built (below) |
| `open` (no work yet) | `closed` | stays `open` |
| `fixed` (work committed and verified by `vbw fix done`) | `closed` | `attempts` + 1, back to `open`; `escalated` at the cap (3) |

A failure opens a fix only once the work is built: every plan serving the
requirement (for a project command: every plan) is `done`. Before that, a
failing check is work in progress, not a defect, and opens nothing.

`vbw fix done` is verified, not claimed: none of the files the fix may touch has
uncommitted changes, and the checks of every finished requirement (all its plans
`done`) that those files serve pass now. A fix cannot quietly break other work.
A project command's fix is left to `vbw prove`, which runs the command.

`vbw show fix F1` names each failing check's or project command's kept full output
file (`full output: .vbw/runtime/output/C1.log`), listed under it. When no file is
kept, for example after it was removed, it says
`full output not kept: run vbw prove again`. With `--json`, each failing check
and command has a `kept` field: the file's path, or `null`.

### Closing several fixes

```text
vbw fix done F8 F9 F5
```

One command closes several fixes. The checks that their files serve run once
(the union, not once per fix), and a check that passed earlier is reused as
below. Each fix ends as it would if closed alone: `fixed` and awaiting
`vbw prove`, or, for a `[human]` requirement, `closed` with the requirement
back to the user for acceptance. Naming an id twice closes it once.

A fix that cannot close is named, and the others still close. The cases:

- an unknown id, or a fix that is not `open`;
- uncommitted changes in a file the fix may touch;
- a failing check: only the fixes whose requirement that check serves fail
  (`F2 broke finished work`, with the check), the rest close.

The exit code is 0 when every fix closed and non-zero when any could not. A fix
that could not close keeps its status and `attempts`; fix the cause and run
`vbw fix done` again for it.

### Reusing an unchanged pass

`vbw fix done` does not rerun a check that already passed on the same project
files under the same approved contract. It prints one line per skipped check
and runs the rest:

```text
C1 unchanged since its pass (2026-10-04T20:30:00Z)
```

The time is when that check passed. A check is skipped only when all of these hold:

- A recorded pass exists in the clone's cache, `vbw/passes.json` in the git
  directory (`git rev-parse --git-common-dir`). It is never in the record. `vbw prove`
  and `vbw fix done` record one for every check that passes. A lost or damaged
  file only makes the checks run again.
- The contract hash of that pass is the current, approved contract hash.
- The committed content of the check's served files is the same as at the pass.
  Served files are the check's own `files` plus the `files` of every plan that
  serves its requirement.
- None of those files has uncommitted changes.

A check with no `files`, or with a served path that is not committed, always
runs and is never recorded. A check that fails loses its recorded pass.
`vbw prove` does not use this cache; it has its own reuse, described in
[Reusing results in `vbw prove`](#reusing-results-in-vbw-prove).

An escalated fix is a human gate (`vbw next`).

Accepting a `[human]` requirement (`vbw req accept ID`) closes only the fixes
that the user's own rejections opened (`vbw req reject ID NOTE`). A fix that QA
opened (`source: "qa"`) stays open after acceptance and closes only on a passing
QA verdict (below).

### QA verification

Passing checks prove each requirement's behavior; they cannot see whether the
work matches the plan that was agreed. After a passing proof, VBW 1's QA agent
verifies each built phase goal-backward, at the profile's tier, against its goal
and criteria (the Architect's) and its plans' tasks (the Lead's): test gaps and
every deviation from the plan are failures. Each failure is recorded with
`vbw qa finding REQ TEXT`, a fix item with `source: "qa"` that a proof never
closes; the verdict with `vbw qa record PHASE pass|fail TIER`, against the
phase's inputs (see "Which phases QA checks again"). A pass closes the phase's
QA fixes; three failed rounds in a row escalate.

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
- a phase it builds on is checked again because that phase's inputs changed,
  even if its own inputs did not. A phase builds on another when one of its
  plans comes after a plan of the other, directly or through other phases.

- one of its `[auto]` requirements was added, reworded or removed.

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
  Until approval, a file in the new folder counts like any other file.

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
P2 is checked again: builds on P1, which changed
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
| `builds on P1, which changed` | a phase it builds on has changed inputs |
| `its files, tests or plan changed` | something changed, but the cache that says what is missing |

`vbw next` sends only these phases to QA, gives the reasons in its `qa` key
(docs/next.md) and states them in its instruction line. The QA skill tells the
user the same. `vbw qa record PHASE pass` stores a digest of the phase's inputs
and those of the phases it builds on in the phase's `qa.tree` (docs/record.md).

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
uncommitted and untracked files included, reports, and writes nothing: the
Dev's tool for the red and green steps. Exit 0 when all pass. With `--expect-red`, red-first:
before a plan is built its checks must fail, and a check that already passes
proves nothing, so exit 0 only when every check fails.
