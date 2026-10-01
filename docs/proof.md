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
  Notes for the planner may follow on indented lines.
- R2 [human] The landing page feels trustworthy
```

- `R<n>`: a stable id, never reused. `vbw spec add` appends the next free one.
- `[auto]`: a check can prove it. `[human]`: only a person can judge it.
- Indented lines under a bullet are notes for the planner; the kernel ignores
  them. HTML comments are ignored.
- Any other bullet in the section is an error, reported with its line number.

`vbw spec check` validates the file. `vbw spec sync` validates it and brings
the record in line: new ids are added as `open`, changed text or proof resets
the requirement to `open`, and ids removed from the spec are removed from the
record, which is refused while anything (a check, phase, plan or fix) still
references them. The kernel never rewrites the spec; `vbw spec add auto|human
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

Checks run from the project root with stdin closed. A run that reaches its
timeout is stopped (by `timeout` where available, otherwise by `perl`'s alarm)
and fails.

## The contract and approval

The contract is the requirements (id, text, proof), the checks, the plans
(everything but their status) and the contents of every check's `files`. Its
hash is SHA-256 over a canonical rendering of all of it.

`vbw approve` (the user's `/vbw:approve`, never an agent) refuses an incomplete
contract (no requirements, an `auto` requirement without a check, a missing
check file), then records consent for the contract hash and for every project
command in `record.commands`, in the clone's git directory (see
docs/record.md, Consent), and logs a decision. A repository cannot ship
approval: a fresh clone must approve before anything runs.

Any change to the contract (a check edited, a test file touched, a plan's files
widened) changes the hash, and the contract is unapproved again until the user
re-approves it. `vbw show contract` renders what is being approved.

## `vbw prove`

1. Refuses unless the current contract hash is approved.
2. Runs every check, and every project command whose argv is approved; an
   unapproved command is skipped and reported, never run.
3. Scope: every commit with a `VBW-Plan:` trailer naming a plan in the record
   must change only that plan's files.
4. Writes the evidence and updates requirements and fixes in one atomic record
   update, then prints a one-screen summary. Exit 0 only when everything passed.

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
| no fix item | nothing | new fix, `open`, `attempts` 0 |
| `open` (no work yet) | `closed` | stays `open` |
| `fixed` (work committed) | `closed` | `attempts` + 1, back to `open`; `escalated` at the cap (3) |

An escalated fix is a human gate (`vbw next`).

### Freshness

`tree` fingerprints the project files the proof ran on (tracked and new files,
committed or not, `.vbw/` and ignored files excluded), taken after the checks
ran. `vbw next` treats evidence as stale, and asks for `prove` again, when the
contract changed or the files differ from that fingerprint. Committing proved
work, or the record, changes nothing.

### `vbw check [--expect-red] [CHECK...]`

Runs the given approved checks (all when none are given), reports, and writes
nothing: the builder's tool. Exit 0 when all pass. With `--expect-red`, red-first:
before a plan is built its checks must fail, and a check that already passes
proves nothing, so exit 0 only when every check fails.
