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
  "requirements": [
    { "id": "R1", "text": "A customer can pay by card", "proof": "auto",
      "checks": ["C1"], "status": "failing" }
  ],
  "checks": [
    { "id": "C1", "req": "R1", "kind": "spec", "path": ".vbw/checks/C1.json" }
  ],
  "phases": [
    { "id": "P1", "title": "Payments", "reqs": ["R1"], "status": "building" }
  ],
  "plans": [
    { "id": "P1.1", "phase": "P1", "title": "Card form", "reqs": ["R1"],
      "files": ["src/pay.ts"], "after": [], "status": "done",
      "commits": ["3f2a…"] }
  ],
  "fixes": [
    { "id": "F1", "req": "R1", "attempts": 1, "status": "open", "note": "C1 exit 1" }
  ],
  "todos": [ { "id": "T1", "text": "Dark mode", "status": "open" } ],
  "decisions": [ { "id": "D1", "text": "Stripe, not PayPal", "at": "2026-10-01T09:00:00Z" } ],
  "contract": { "hash": null, "approved_at": null },
  "evidence": null,
  "lease": null
}
```

| Field | Rules |
|---|---|
| `schema` | `1` |
| `project.name` | non-empty string |
| `milestone` | `id` `M<n>`, non-empty `title`, `status` `active` or `shipped` |
| `requirements[]` | `id` `R<n>` unique; non-empty `text`; `proof` `auto` or `human`; `checks[]` ids that exist in `checks`; `status` `open`, `failing`, `proven`, `accepted` or `rejected`. A `human` requirement has no checks and is never `proven`/`failing`; an `auto` requirement is never `accepted`/`rejected` |
| `checks[]` | `id` `C<n>` unique; `req` an existing requirement; `kind` `spec` (a `.vbw/checks/*.json` check spec) or `test` (a test file in the project's own framework); `path` a relative path inside the project, no `..` |
| `phases[]` | `id` `P<n>` unique; non-empty `title`; `reqs[]` existing requirements; `status` `planned`, `building` or `built` |
| `plans[]` | `id` `P<n>.<m>` unique, prefix equals `phase`; `phase` an existing phase; non-empty `title`; `reqs[]` existing requirements; `files[]` relative project paths (no `..`, no duplicates); `after[]` existing plan ids of earlier-or-same phase, no cycles; `status` `planned`, `building`, `done` or `blocked`; `commits[]` full or abbreviated hex SHAs |
| `fixes[]` | `id` `F<n>` unique; `req` an existing requirement; `attempts` integer ≥ 0; `status` `open`, `closed` or `escalated`; `note` string |
| `todos[]` | `id` `T<n>` unique; non-empty `text`; `status` `open`, `in_progress`, `done` or `dropped` |
| `decisions[]` | `id` `D<n>` unique; non-empty `text`; `at` an ISO-8601 UTC timestamp |
| `contract` | `hash` `null` or a 64-hex SHA-256; `approved_at` `null` or ISO-8601 UTC; both null or both set |
| `evidence` | `null` or the last `vbw prove` result (defined in M2) |
| `lease` | `null` or `{ "run", "session", "started_at", "agents": [] }`: the active run that scopes the guards (defined in M3) |

Unknown top-level keys are rejected: an unknown key is a typo or a newer
schema, and both must be loud.
