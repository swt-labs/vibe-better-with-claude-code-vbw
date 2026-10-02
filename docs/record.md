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
  forward in one tested step; an older kernel refuses a newer record.

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
| `milestone` | the current milestone: `id` `M<n>`, non-empty `title`, `status` `active` or `shipped`. `vbw milestone start TITLE` opens the next one after shipping; `vbw milestone rename TITLE` names the current one until it ships |
| `shipped` | the shipped milestones, in order: `{ "id", "title", "at" }`. The current milestone is in this list exactly when its status is `shipped`. Shipped requirements, plans and checks stay in the record, and their checks keep running in every proof as regression guards |
| `requirements[]` | `id` `R<n>` unique; non-empty `text`; `milestone` the milestone it belongs to (the current or a shipped one); `proof` `auto` or `human`; `status` `open`, `failing`, `proven`, `accepted` or `rejected`. A `human` requirement is never `proven`/`failing`; an `auto` requirement is never `accepted`/`rejected`. Requirements mirror `.vbw/spec.md` (`vbw spec sync`) |
| `checks[]` | `id` `C<n>` unique; `req` an existing `auto` requirement; `run` argv; optional `files[]` (relative, no `..`), `exit` (0–255), `output` (a regular expression), `timeout` (1–3600 s). A requirement's checks are the checks whose `req` names it. Full semantics in docs/proof.md |
| `phases[]` | `id` `P<n>` unique; non-empty `title`; `milestone` as for requirements; `reqs[]` non-empty, existing requirements. Optional `goal` and `criteria[]` (the Architect's outcome and goal-backward success criteria) and `qa` (`{result, tier, tree, at, note?, rounds?}`: QA's verdict on the code with that tree, `vbw qa record`). A phase has no stored status: it is derived from its plans (`planned`, `building`, `built` when every plan is done) |
| `plans[]` | `id` `P<n>.<m>` unique, prefix equals `phase`; `phase` an existing phase; optional `tasks[]` (the Lead's, one commit each) and `role` (`dev`, or `docs` for a documentation plan); non-empty `title`; `reqs[]` non-empty, existing requirements; `files[]` non-empty, relative project paths (no `..`, no duplicates); `after[]` existing plan ids, no cycles; `status` `planned`, `building`, `done` or `blocked`; optional `note` (why it is blocked). A plan's commits are not stored: they are the commits whose `VBW-Plan:` trailer names it (`git log`) |
| `fixes[]` | `id` `F<n>` unique; exactly one of `req` (an existing requirement) or `command` (a name in `commands`); optional `source` `qa` (a QA finding: only QA closes it); `attempts` integer ≥ 0; `status` `open`, `fixed`, `closed` or `escalated` (lifecycle in docs/proof.md); `note` string |
| `todos[]` | `id` `T<n>` unique; non-empty `text`; `status` `open`, `in_progress`, `done` or `dropped` |
| `decisions[]` | `id` `D<n>` unique; non-empty `text`; optional `why` (non-empty: the reason the user gave); `at` an ISO-8601 UTC timestamp. `vbw decide TEXT [WHY]` records one |
| `commands` | object of name → argv (a non-empty array of non-empty strings): the project's own test, lint and build commands detected by `vbw init`. Recording a command never runs it; `vbw prove` runs only commands whose argv hash has consent (see Consent) |
| `settings` | `profile` `quality`, `balanced` (default) or `budget`: the models VBW 1's team runs on (`vbw config`, `lib/profiles.json`); optional `autonomy` `guided`, `balanced` (the default when unset) or `hands-off`: how much `/vbw:vibe` does on its own (`/vbw:profile`); `autonomy_cap` steps per autonomous run (1–500, default 25); optional `models` overrides per agent (`architect`, `lead`, `dev`, `qa`, `scout`, `debugger`, `docs`; the earlier names `planner`, `critic`, `builder` are renamed to `lead`, `qa`, `dev` on first use) |
| `evidence` | `null` or the last `vbw prove` result: `at`, `contract` (the hash proved), `tree` (the git tree id of the project files proved), `passed`, `checks` and `commands` (name → `{status, exit, seconds, tail}`), `scope[]` violations (docs/proof.md) |
| `converted` | optional: `{ "from": ".vbw-planning", "at" }`, set by `vbw legacy done` once a VBW 1 plan was brought in (docs/convert.md) |
| `lease` | `null` or `{ "run", "kind", "started_at", "files" }`: the active run (`kind` `plan`, `build`, `fix`, `qa` or `map`; `files` the paths its agents may write: `null` for any, `[]` for none) that the guards hold subagents to (docs/workflows.md) |

Unknown keys are rejected, at the top level and inside every item: an unknown
key is a typo, a stale field or a newer schema, and all three must be loud.

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
