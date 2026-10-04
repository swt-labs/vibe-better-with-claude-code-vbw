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

A check that cannot start waits at most 900 seconds, then fails with a message
naming the check that holds it. Set `VBW_CHECK_WAIT_SECONDS` to change the
limit. The wait is not part of the check's `timeout`, which counts only the run.

## The contract and approval

The contract is the requirements (id, text, proof, and rules when listed), the checks, the plans
(everything but their status) and the contents of every check's `files`. Its
hash is SHA-256 over a canonical rendering of all of it.

`vbw approve` (the user's `/vbw:approve`, never an agent) refuses an incomplete
contract (no requirements, an `auto` requirement without a check, a missing
check file), then records consent for the contract hash and for every project
command in `record.commands`, in the clone's git directory (see
docs/record.md, Consent), and logs a decision. A repository cannot ship
approval: a fresh clone must approve before anything runs.

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

Any change to the contract (a check edited, a test file touched, a plan's files
widened) changes the hash, and the contract is unapproved again until the user
re-approves it. `vbw show contract` renders what is being approved, and
`vbw show contract --changes` only what changed since the last approval in this
clone (`vbw approve` keeps a copy of what it approved in `.vbw/runtime/`).

## `vbw prove`

1. Refuses unless the current contract hash is approved.
2. Makes a clean copy of the committed code (`HEAD`) inside the project, under
   `.vbw/runtime/`.
3. Runs every check, and every project command whose argv is approved, from the
   root of that copy; an unapproved command is skipped and reported, never run.
   Then it removes the copy, also when interrupted.
4. Scope: every commit with a `VBW-Plan:` trailer naming a plan in the record
   must change only that plan's files.
5. Writes the evidence and updates requirements and fixes in one atomic record
   update, then prints a one-screen summary. Exit 0 only when everything passed.

Because the copy holds only committed files, uncommitted edits and untracked
files in the working folder change no result. A check file that is not
committed as approved is refused: commit it, then `/vbw:approve`.

Git-ignored files (`node_modules/`, `.env.local`, build caches) are the
project's environment, not its code, so the copy links them in from the working
folder. Untracked files that are not ignored never enter the copy (D54): to
make one count, commit it or ignore it. Removing the copy never touches the
files behind the links.

Evidence (`record.evidence`):

```json
{ "at": "2026-10-01T09:00:00Z", "contract": "<sha256>", "tree": "<git tree id>", "passed": false,
  "checks": { "C1": { "status": "fail", "exit": 1, "seconds": 3, "tail": "…" } },
  "commands": { "test": { "status": "pass", "exit": 0, "seconds": 9, "tail": "" },
                "lint": { "status": "skipped", "exit": null, "seconds": 0, "tail": "not approved" } },
  "scope": [] }
```

Statuses: `pass`, `fail`, `timeout`, `skipped`.

An `auto` requirement is `proven` when all its checks pass and `failing`
otherwise. Human requirements are untouched.

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
evidence's tree. A pass closes the phase's QA fixes; code that changes
afterwards needs QA again; three failed rounds in a row escalate.

`vbw qa record` refuses a verdict when no proof exists yet, or when the project
files differ from the proof's `tree` (the code changed since the last proof). The
error asks for `vbw prove` first; the verdict is recorded only against a proof of
the current code. The QA agent handles the refusal itself: it runs `vbw prove`
and retries the record once.

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
