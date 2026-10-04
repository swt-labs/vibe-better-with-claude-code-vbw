# The plan of record: `.vbw/record.json`

The single machine-readable answer to "what are we building, what is proven,
what is next". Only the kernel (`vbw`) writes it. Humans edit `.vbw/spec.md`;
agents act through `vbw` subcommands. Git holds the history: every VBW commit
carries `VBW-Plan:`/`VBW-Req:` trailers, so the record stays small.

## Guarantees

- **One writer, atomic:** every mutation takes the project lock, writes a
  temporary file in `.vbw/runtime/`, validates it, and renames it into place.
  A reader never sees a partial or invalid record.
- **Validated on every read and write:** `plugin/lib/record.jq` is the
  definition. A record that fails validation is reported as corrupt with the
  first violation; the kernel never "repairs" it silently.
- **Stable ids:** ids are assigned once and never reused or renumbered.
- **Versioned:** `schema` is an integer. A newer kernel migrates older records
  forward in one tested step; an older kernel refuses a newer record (see
  Versioning).

## Shape (schema 1)

```json
{
  "schema": 1,
  "project": { "name": "Shop" },
  "milestone": { "id": "M1", "title": "Checkout", "status": "active" },
  "shipped": [],
  "requirements": [
    { "id": "R1", "text": "A customer can pay by card", "proof": "auto", "status": "failing", "milestone": "M1" }
  ],
  "checks": [
    { "id": "C1", "req": "R1", "run": ["npm", "test", "--", "tests/pay.test.ts"],
      "files": ["tests/pay.test.ts"] }
  ],
  "phases": [
    { "id": "P1", "title": "Payments", "reqs": ["R1"], "milestone": "M1" }
  ],
  "plans": [
    { "id": "P1.1", "phase": "P1", "title": "Card form", "reqs": ["R1"],
      "files": ["src/pay.ts"], "after": [], "status": "done" }
  ],
  "fixes": [
    { "id": "F1", "req": "R1", "attempts": 1, "status": "open", "note": "C1 exit 1" }
  ],
  "todos": [ { "id": "T1", "text": "Dark mode", "status": "open" } ],
  "decisions": [ { "id": "D1", "text": "Stripe, not PayPal", "at": "2026-10-01T09:00:00Z" } ],
  "commands": { "test": ["npm", "test"] },
  "settings": { "profile": "balanced", "autonomy_cap": 25 },
  "evidence": null,
  "lease": null
}
```

| Field | Rules |
|---|---|
| `schema` | `1` |
| `project.name` | non-empty string |
| `project.interview` | optional: the interview's answers kept in the project, `{ "level", "depth", "involvement", "at" }`: all three answers from the allowed values (`plugin/lib/interview.json`) and an ISO-8601 UTC time `at`; no other keys. Absent when the answers are kept private or not given yet. `vbw interview keep project` writes it (docs/interview.md). Added within schema 1: a record without it stays valid, so the schema stays 1 |
| `project.declined` | optional: the suggestions the user declined, `[{ "text", "at" }]`, each a non-empty `text` and an ISO-8601 UTC time `at`; no other keys. `vbw suggest decline TEXT` appends one (a text equal to an existing one, ignoring case and spacing, is not added again); `vbw suggest list` prints them and `vbw next --json` returns the texts as `declined`. They are never offered again in the project (docs/interview.md). Absent until something is declined. Added within schema 1: a record without it stays valid, so the schema stays 1 |
| `milestone` | the current milestone: `id` `M<n>`, non-empty `title`, `status` `active` or `shipped`. `vbw milestone start TITLE` opens the next one after shipping; `vbw milestone rename TITLE` names the current one until it ships |
| `shipped` | the shipped milestones, in order: `{ "id", "title", "at" }`. The current milestone is in this list exactly when its status is `shipped`. Shipped requirements, plans and checks stay in the record, and their checks keep running in every proof as regression guards |
| `requirements[]` | `id` `R<n>` unique; non-empty `text`; `milestone` the milestone it belongs to (the current or a shipped one); `proof` `auto` or `human`; `status` `open`, `failing`, `proven`, `accepted` or `rejected`. A `human` requirement is never `proven`/`failing`; an `auto` requirement is never `accepted`/`rejected`. Requirements mirror `.vbw/spec.md` (`vbw spec sync`). Optional `rules[]` on an `auto` requirement: the conditions, edge and error cases its text states, each `{ "text", "check" }` with non-empty `text` and `check` the id of one of that requirement's own checks; no other keys, and a `human` requirement cannot carry rules. `rules: []` means pending: listed rules are required but not yet given. `vbw apply` writes them; `vbw spec sync` resets them to `[]` when a requirement's text or proof changes (docs/proof.md, Rules) |
| `checks[]` | `id` `C<n>` unique; `req` an existing `auto` requirement; `run` argv; optional `files[]` (relative, no `..`), `exit` (0–255), `output` (a regular expression), `timeout` (1–3600 s), `alone` (boolean: the check never runs beside another VBW check, docs/proof.md). A requirement's checks are the checks whose `req` names it. Full semantics in docs/proof.md |
| `phases[]` | `id` `P<n>` unique; non-empty `title`; `milestone` as for requirements; `reqs[]` non-empty, existing requirements. Optional `goal` and `criteria[]` (the Architect's outcome and goal-backward success criteria) and `qa` (`{result, tier, tree, at, note?, rounds?}`: QA's verdict on the code with that tree, `vbw qa record`). Optional rigor fields (docs/rigor.md): `tier` (`express`, `standard` or `deep`), `proposed` (the Architect's tier), `reasons[]` (why the tier), `predicted` (the tier the phase began at), `escalations[]` (`{at, from, to, reason}`, one per raise) and `outcome` (`{tier, predicted, held, fix_rounds, qa_findings, escalations}`, written once when the phase finishes). A phase has no stored status: it is derived from its plans (`planned`, `building`, `built` when every plan is done) |
| `plans[]` | `id` `P<n>.<m>` unique, prefix equals `phase`; `phase` an existing phase; optional `tasks[]` (the Lead's, one commit each) and `role` (`dev`, or `docs` for a documentation plan); non-empty `title`; `reqs[]` non-empty, existing requirements; `files[]` non-empty, relative project paths (no `..`, no duplicates; a path ending in `/` is a directory and covers every file under it, for the guards, the proof's scope check and wave scheduling); `after[]` existing plan ids, no cycles; `status` `planned`, `building`, `done` or `blocked`; optional `note` (why it is blocked). A plan's commits are not stored: they are the commits whose `VBW-Plan:` trailer names it (`git log`) |
| `fixes[]` | `id` `F<n>` unique; exactly one of `req` (an existing requirement) or `command` (a name in `commands`); optional `source` `qa` (a QA finding: only QA closes it); `attempts` integer ≥ 0; `status` `open`, `fixed`, `closed` or `escalated` (lifecycle in docs/proof.md); `note` string |
| `todos[]` | `id` `T<n>` unique; non-empty `text`; `status` `open`, `in_progress`, `done` or `dropped` |
| `decisions[]` | `id` `D<n>` unique; non-empty `text`; optional `why` (non-empty: the reason the user gave); `at` an ISO-8601 UTC timestamp. `vbw decide TEXT [WHY]` records one |
| `commands` | object of name → argv (a non-empty array of non-empty strings): the project's own test, lint and build commands, kept in line with the `## Commands` section of `.vbw/spec.md` by `vbw spec sync` (`vbw init` writes the detected ones there; docs/proof.md). Recording a command never runs it; `vbw prove` runs only commands whose argv hash has consent (see Consent) |
| `settings` | `profile` `quality`, `balanced` (default) or `budget`: the models VBW 1's team runs on (`vbw config`, `lib/profiles.json`); optional `rigor` `auto` (the default when unset), `express`, `standard` or `deep`: computes each phase's tier or forces it (`vbw config rigor`, docs/rigor.md); optional `autonomy` `guided`, `balanced` (the default when unset) or `hands-off`: how much `/vbw:vibe` does on its own (`/vbw:profile`); `autonomy_cap` steps per autonomous run (1–500, default 25); optional `models` overrides per agent (`architect`, `lead`, `dev`, `qa`, `scout`, `debugger`, `docs`; the earlier names `planner`, `critic`, `builder` are renamed to `lead`, `qa`, `dev` on first use) |
| `evidence` | `null` or the last `vbw prove` result: `at`, `contract` (the hash proved), `tree` (the git tree id of the working folder's project files), `head` (the tree of the committed code the checks ran on; both decide freshness, docs/proof.md), `passed`, `checks` and `commands` (name → `{status, exit, seconds, tail}`), `scope[]` violations (docs/proof.md) |
| `converted` | optional: `{ "from": ".vbw-planning", "at" }`, set by `vbw legacy done` once a VBW 1 plan was brought in (docs/convert.md) |
| `lease` | `null` or `{ "run", "kind", "started_at", "files" }`: the active run (`kind` `plan`, `build`, `fix`, `qa` or `map`; `files` the paths its agents may write: `null` for any, `[]` for none) that the guards hold subagents to (docs/workflows.md) |

Unknown keys are rejected, at the top level and inside every item: an unknown
key is a typo, a stale field or a newer schema, and all three must be loud.

## Versioning

A VBW reads every schema up to its own (`VBW_SCHEMA_MAX`, currently 2).
The kernel writes the schema that the fields in use need: a record with a check
that has `alone: true` is schema 2, every other record is schema 1. A VBW that
reads only schema 1 therefore asks for an update on a record that uses `alone`
instead of calling it corrupt.

The last pass of each check is not in the record. It is a cache in the clone
(`passes.json` in the git directory, see docs/proof.md), so a record never
carries it.

For example, an older VBW that reads up to schema 1 says this on a schema 2 record:

```text
this project needs a newer VBW: its record was written with schema 2, this VBW reads up to schema 1; update VBW with /vbw:update
```

The refusal comes before any validation, so the record is never called
corrupt, and it covers reads and writes: the file is never modified.
`vbw doctor` reports the same condition with the same advice.

Exit codes of a command that opens the record:

| Code | Meaning |
|---|---|
| 3 | the record is damaged: invalid JSON, a non-numeric `schema`, or a validation failure |
| 4 | the record was written by a newer VBW: update VBW |

Every earlier schema keeps loading. The fixtures in `tests/fixtures/records`
(`v1.json`, and `future.json` for the refusal) are protected by check C29
(`tests/record-newer.bats`), so a change that stops an old record from loading
fails the proof.

## Consent

Commands and contract checks from the repository run only with the user's
consent, recorded by content hash in the clone's git directory:
`$(git rev-parse --git-common-dir)/vbw/consent.json`. A repository cannot ship
that file (clones never carry `.git` contents), it is writable under the Claude
Code sandbox, and linked worktrees share it. Granting consent is a user action
(`/vbw:approve`), never something an agent can do on its own.

Approval of the contract is therefore not a field of the record: the record
travels with the repository, so a field saying "approved" could be shipped by
anyone. The contract is approved when its current hash has consent
(docs/proof.md).
