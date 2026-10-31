# The plan of record: `.vbw/record.json`

The single machine-readable answer to "what are we building, what is proven,
what is next". Only the kernel (`vbw`) writes it. Humans edit `.vbw/spec.md`;
agents act through `vbw` subcommands. Git holds the history: every VBW commit
carries `VBW-Plan:`/`VBW-Req:` trailers, so the record stays small. Only the
commits made since the record was first committed count as its own
([docs/proof.md](proof.md#whose-commits-vbw-judges)): ids start again in a new
record, so an older roadmap's trailers name nothing of it.

VBW commits its record and its check files to the branch checked out when it runs. `vbw init` says so once, naming the branch (or the commit, on a detached HEAD), and `vbw doctor` shows it any time. No setting changes it, and nothing refuses or asks.

## VBW's own files stay visible to git

VBW keeps `.vbw/.gitignore` with `runtime/` and the un-hide lines `!record.json`, `!spec.md`, `!map.md` and `!.gitignore` (the last so a project-wide `*` rule cannot hide the file itself).
They keep a rule such as `*.json` or `*.md` from hiding the plan files, whether it sits in the project's `.gitignore`, in `.git/info/exclude` or in a global excludes file.

`vbw init` writes these lines to `.vbw/.gitignore` and says so in one line.
An existing project gets the un-hide lines at its next VBW commit, committed along with the record.
VBW never edits the project's .gitignore.

**The whole-folder case.** A rule that hides the whole `.vbw/` folder (`.vbw/` or `*`) cannot be undone by any line inside it. VBW then names the hidden file and the rule's source as `git check-ignore -v` gives it (file, line, pattern):

- `vbw init` says so.
- `vbw doctor` fails with it and exits 1.
- `vbw approve` refuses with it and commits nothing.
- Other VBW commits print a `vbw: warning:` naming the hidden file; they never skip it silently.

The fix: remove that line, or change it to .vbw/runtime/

## Guarantees

- **One writer, atomic:** every mutation takes the project lock, writes a
  temporary file in `.vbw/runtime/`, validates it, and renames it into place.
  A reader never sees a partial or invalid record.
- **Validated on every read and write:** `plugin/lib/record.jq` is the
  definition. A record that fails validation is reported as corrupt with the
  first violation; the kernel never "repairs" it silently.
- **A record of any size is supported:** VBW never puts the record, or
  anything built from all of it, on a command line. The operating system caps
  command-line size (macOS 1 MB for all arguments together, Linux 128 KB for
  one), and a long-lived project's record can pass that. VBW hands record data
  to `jq` through files and pipes, so every `vbw` command keeps working however
  large the record grows.
- **Key order:** the writer puts `schema`, `lease`, `protected` and `checks`
  first, in that order, then the rest. Every record VBW writes is schema 4 (5
  while it holds a helper's chosen effort) and has all four. A record with another key order, written by an older VBW, still
  works.
- **The glance:** `.vbw/runtime/glance.json` holds the record's `schema`,
  `lease` and `protected` for the guards (docs/guards.md), besides what the
  status line shows. Every record write rewrites it in the same locked write and
  sets the record's file time one second back, so the glance stays newer. Any
  `vbw` command rewrites a missing or out-of-date glance.
  While a run is open it also holds `holder`, `{run, session, session_name}`
  (`null` otherwise): the name of the chat that holds the run, on this computer
  only. The record and `costs.runs` never carry `session_name`.
  It is never the source of truth, and it is safe to delete.
- **Stable ids:** ids are assigned once and never reused or renumbered.
- **Versioned:** `schema` is an integer. A newer kernel migrates older records
  forward in one tested step; an older kernel refuses a newer record (see
  Versioning).

## Shape (schema 4)

```json
{
  "schema": 4,
  "lease": null,
  "protected": ["tests/pay.test.ts"],
  "checks": [
    { "id": "C1", "req": "R1", "run": ["npm", "test", "--", "tests/pay.test.ts"],
      "files": ["tests/pay.test.ts"] }
  ],
  "project": { "name": "Shop" },
  "milestone": { "id": "M1", "title": "Checkout", "status": "active" },
  "shipped": [],
  "requirements": [
    { "id": "R1", "text": "A customer can pay by card", "proof": "auto", "status": "failing", "milestone": "M1" }
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
  "evidence": null
}
```

| Field | Rules |
|---|---|
| `schema` | `4`, `5` while `settings.efforts` is set, or `6` once a decision carries `plans`: VBW writes every record as schema 4 and raises it to 5 only for a chosen effort and to 6 only for a decision that names its plans, so an older VBW asks to be updated instead of calling the record corrupt. Corrupt: a schema 4, 5 or 6 record with no `protected` list, a `protected` list that differs from the checks, a `protected` list on a record below schema 4, `settings.efforts` on a schema other than 5 or 6, schema 5 without `settings.efforts`, a decision with `plans` on a schema other than 6, schema 6 without one, or any other value (older VBWs wrote 1 to 3, see Versioning) |
| `project.name` | non-empty string |
| `project.interview` | optional: the interview's answers kept in the project, `{ "level", "depth", "involvement", "at" }`: all three answers from the allowed values (`plugin/lib/interview.json`) and an ISO-8601 UTC time `at`; no other keys. Absent when the answers are kept private or not given yet. `vbw interview keep project` writes it (docs/interview.md). Added within schema 1: a record without it stays valid, so the schema stays 1 |
| `project.declined` | optional: the suggestions the user declined, `[{ "text", "at" }]`, each a non-empty `text` and an ISO-8601 UTC time `at`; no other keys. `vbw suggest decline TEXT` appends one (a text equal to an existing one, ignoring case and spacing, is not added again); `vbw suggest list` prints them and `vbw next --json` returns the texts as `declined`. They are never offered again in the project (docs/interview.md). Absent until something is declined. Added within schema 1: a record without it stays valid, so the schema stays 1 |
| `project.results` | optional: the folders of saved test results named in the spec's `## Test results` section, a non-empty array of unique relative folder paths, each ending in `/`, with no `.` or `..` parts and outside `.vbw/`. `vbw spec sync` writes it and removes it when the spec names none; it is part of the contract, so a change needs approval (docs/proof.md). A passed phase is not checked by QA again for changes only inside these folders. Absent when the spec names none. Added within schema 1: a record without it stays valid, so the schema stays 1 |
| `project.leave_out` | optional: the git-ignored paths a clean copy leaves out, the spec's `## Clean copy` list: a non-empty array of unique relative paths as written in the spec, with no `.` or `..` parts, not absolute, outside `.vbw/` and `.git/`. `vbw spec sync` writes it and removes it when the spec lists none; it is part of the contract, so a change needs approval (docs/proof.md). Absent when the spec lists none. Added within schema 4: a record without it stays valid, so the schema stays 4 |
| `milestone` | the current milestone: `id` `M<n>`, non-empty `title`, `status` `active`, `shipped` or `parked` (the loop gave the milestone up, docs/loop.md). `vbw milestone start TITLE` opens the next one after shipping or parking; `vbw milestone rename TITLE` names the current one until it ships |
| `shipped` | the shipped milestones, in order: `{ "id", "title", "at" }`. The current milestone is in this list exactly when its status is `shipped`. Shipped requirements, plans and checks stay in the record, and their checks keep running in every proof as regression guards |
| `parked` | optional: the milestones the loop gave up, in order: `{ "id", "title", "at", "reason", "ids"? }`, with `at` an ISO-8601 UTC time, a non-empty `reason` and `ids` the phase, requirement and fix ids (`P<n>`, `R<n>`, `F<n>`) the park freed, no other keys. The next phase, requirement and fix number count past `ids`, since the parked commits keep them in their trailers. The current milestone is in this list exactly when its status is `parked`. A parked milestone's work is reverted by `git revert` commits and removed from `requirements`, `phases`, `plans`, `checks` and `fixes`; its cost is frozen as a ship freezes it. Written only by `vbw loop park` |
| `requirements[]` | `id` `R<n>` unique; non-empty `text`; `milestone` the milestone it belongs to (the current or a shipped one); `proof` `auto` or `human`; `status` `open`, `failing`, `proven`, `accepted` or `rejected`. A `human` requirement is never `proven`/`failing`; an `auto` requirement is never `accepted`/`rejected`. Requirements mirror `.vbw/spec.md` (`vbw spec sync`). Optional `rules[]` on an `auto` requirement: the conditions, edge and error cases its text states, each `{ "text", "check", "plan"?, "retired"? }` with non-empty `text`, `check` the id of one of that requirement's own checks and an optional `plan`, a plan of that requirement that builds the rule's code (its mutation break is asked of that plan, docs/proof.md); the plan is named on every rule of the requirement or on none, and `vbw apply` refuses it otherwise; no other keys, and a `human` requirement cannot carry rules. A rule's address is `Rn.k`, its place in the array (`R1.2` is the second rule of `R1`). `retired`, a non-empty reason, marks a rule `vbw apply --patch` retired (docs/workflows.md): it keeps its place, so no address moves, is owed no mutation break, and its `check` and `plan` may name items that no longer exist. `rules: []`, or rules that are all retired, means pending: listed rules are required but not yet given. `vbw apply` writes them; `vbw spec sync` resets them to `[]` when a requirement's text or proof changes (docs/proof.md, Rules) |
| `checks[]` | `id` `C<n>` unique; `req` an existing `auto` requirement; `run` argv; optional `files[]` (relative, no `..`), `exit` (0–255), `output` (a regular expression), `timeout` (1–3600 s), `alone` (boolean: the check never runs beside another VBW check, docs/proof.md). A requirement's checks are the checks whose `req` names it. Full semantics in docs/proof.md |
| `phases[]` | `id` `P<n>` unique; non-empty `title`; `milestone` as for requirements; `reqs[]` non-empty, existing requirements. Optional `goal` and `criteria[]` (the Architect's outcome and goal-backward success criteria) and `qa` (`{result, tier, tree, at, note?, rounds?}`: QA's verdict, `vbw qa record`; `tree` is a digest of the phase's own inputs (its files, its tests, its goal and plan) combined with the tests of the phases it builds on (their checks and check files), as committed, not a git tree id; the schema is unchanged. The per-input digests that name the reason for a re-check live in the clone cache `<git-common-dir>/vbw/qa.json`, which is not part of the record. Each phase's entry there also holds the version of how its fingerprint was computed and the commit it was taken at; the record itself is unchanged). Optional rigor fields (docs/rigor.md): `tier` (`express`, `standard` or `deep`), `proposed` (the Architect's tier), `reasons[]` (why the tier), `predicted` (the tier the phase began at), `escalations[]` (`{at, from, to, reason}`, one per raise) and `outcome` (`{tier, predicted, held, fix_rounds, qa_findings, escalations}`, written once when the phase finishes). A phase has no stored status: it is derived from its plans (`planned`, `building`, `built` when every plan is done) |
| `plans[]` | `id` `P<n>.<m>` unique, prefix equals `phase`; `phase` an existing phase; optional `tasks[]` (the Lead's, one commit each) and `role` (`dev`, or `docs` for a documentation plan); non-empty `title`; `reqs[]` non-empty, existing requirements; `files[]` non-empty, relative project paths (no `..`, no duplicates; a path ending in `/` is a directory and covers every file under it, for the guards, the proof's scope check and wave scheduling); `after[]` existing plan ids, no cycles; `status` `planned`, `building`, `done` or `blocked`; optional `note` (why it is blocked; it survives every `vbw apply`, as mutations do, and goes with `vbw plan done` or reset). A plan's commits are not stored: they are the commits whose `VBW-Plan:` trailer names it (`git log`); optional `mutations` (an array, written by `vbw mutate`): a break `{ rule: {req, text} | task, what, files, checks, result (red or survivor), at, head }` with optional `tree` (the committed code it ran on, each submodule at its own `HEAD`: the key of "already ran on the unbroken code"), `strengthened` and `pending`, files the plan may strengthen (the files of its own rules' checks); a task with nothing to break `{ task, none, at }`; a rule with no code to break `{ rule: {req, text}, none, at, head }`, `head` being the 40-hex commit of the committed code the judged run was current for. Mutations never enter the contract fingerprint |
| `fixes[]` | `id` `F<n>` unique; exactly one of `req` (an existing requirement) or `command` (a name in `commands`); optional `source` `qa` (a QA finding: only QA closes it) and, for a finding, `phase` (an existing phase: the one whose QA found it; a verdict changes only its own phase's findings, D332); optional `restore`, a file path, on a requirement's fix that is not a finding (`vbw fix restore`: a proof closes it once the file no longer deviates, docs/proof.md); `attempts` integer ≥ 0; `status` `open`, `fixed`, `closed` or `escalated` (lifecycle in docs/proof.md); `note` string |
| `recommendation` | optional: the what's-next recommendation, `{ "at", "top", "runners" }` or `{ "at", "empty": true }`, no other keys. `at` is an ISO-8601 UTC time; `top` is `{ "text", "reason", "size", "source"? }` with non-empty text and reason and a size of `small`, `medium` or `large`; `runners` holds zero to two `{ "text", "size", "source"? }`. A `source` is a todo id or a requirement id. `vbw recommend` (JSON on stdin) writes it, replacing any earlier one, and refuses a malformed one, a source that is not open, a declined pick, `empty` while work is open, and any open run; `vbw status` shows it (`--json`: `recommendation`, null when none). A stored recommendation makes the record schema 3 |
| `todos[]` | `id` `T<n>` unique; non-empty `text`; `status` `open`, `in_progress`, `done` or `dropped`. Optional `sort` (`next` or `later`) and `size` (`small`, `medium` or `large`), both or neither (`vbw todo add --sort next --size small TEXT`; `vbw todo sort ID next small` sets or replaces both on an open item; `vbw triage` and `vbw todo list` show next first, then later, then unsorted) |
| `decisions[]` | `id` `D<n>` unique; non-empty `text`; optional `why` (non-empty: the reason the user gave); `at` an ISO-8601 UTC timestamp; optional `plans` (an approval's decision: the ids of the plans that approval changed, which `vbw show decisions --since-approval PLAN` reads; a record holding one is schema 6). `vbw decide TEXT [WHY]` records one |
| `commands` | object of name → argv (a non-empty array of non-empty strings): the project's own test, lint and build commands, kept in line with the `## Commands` section of `.vbw/spec.md` by `vbw spec sync` (`vbw init` writes the detected ones there; docs/proof.md). Recording a command never runs it; `vbw prove` runs only commands whose argv hash has consent (see Consent) |
| `settings` | `profile` `quality`, `balanced` (default: Opus for the Architect and the Lead, Sonnet for every other role) or `budget`: the models VBW 1's team runs on (QA never runs below Sonnet) (`vbw config`, `lib/profiles.json`); optional `rigor` `auto` (the default when unset), `express`, `standard` or `deep`: computes each phase's tier or forces it (`vbw config rigor`, docs/rigor.md); optional `autonomy` `guided`, `balanced` (the default when unset) or `hands-off`: how much `/vbw:vibe` does on its own (`/vbw:profile`); `autonomy_cap` steps per autonomous run (1–500, default 25); optional `motion` `full`, `calm` or `off`: how much the VBW panel animates (`vbw config set motion`; unset, the panel picks `full` for users new to code and `calm` otherwise; test mode is always `off`); optional `command_timeout` a whole number of seconds from 1 to 86400 (3600 when unset): how long `vbw prove` lets a project command run, shared with the project (`vbw config set command_timeout`, docs/proof.md); optional `check_budget` a whole number of seconds from 1 to 86400 (120 when unset): how long a unit of a proof may take before the reports name it over budget, never a limit (`vbw config set check_budget`, docs/proof.md); optional `models` overrides per agent (`architect`, `lead`, `dev`, `qa`, `scout`, `debugger`, `docs`; the earlier names `planner`, `critic`, `builder` are renamed to `lead`, `qa`, `dev` on first use); optional `efforts`, a helper's chosen effort for every step of that role over the profile's table (`architect`, `lead`, `dev`, `qa`, `scout`, `debugger`, `docs`, each `low`, `medium`, `high`, `xhigh` or `max`; `vbw config set effort.dev high`, `default` removes it, and without any the key goes): a record holding it is schema 5 |
| `evidence` | `null` or the last `vbw prove` result: `at`, `contract` (the hash proved), `tree` (the git tree id of the working folder's project files), `head` (the tree of the committed code the checks ran on; both decide freshness, docs/proof.md), `record` (the SHA-256 of the record without its evidence as that proof left it: with `tree` and `head` unchanged it tells a deliberate re-run from a record-only change, docs/proof.md), `full` (true when nothing was reused, no command was skipped and the quick command did not stand in; evidence without it counts as full, docs/proof.md), `passed`, `checks` and `commands` (name → `{status, exit, seconds, tail, fp, at}`), `test_files` (path → the same, when the spec declares a single-file form; `commands.test` is then one summary result marked `of_files: true`) `scope[]` violations and `undone`, an array of `{commit, plan, by}` (the 40-hex id of a commit the scope check left unjudged, the plan its trailer names, the 40-hex id of the commit that undid it; `[]` when none; a malformed entry makes the record corrupt) (docs/proof.md). A record written before this field still reads, and `vbw show evidence` prints nothing for it. `deviations` is an array of `{file, plan, commit, at, change, by}`: a file a plan of the current milestone delivered that `HEAD` no longer holds as VBW's last commit of it (`commit`, a commit id, made at `at`) left it; `change` is `deleted` or `changed`, `by` the ids of the commits outside any plan that changed it after (`[]` when only a merge did); `plan` is the plan that owns the file. It is `[]` when there are none, a malformed entry makes the record corrupt, and evidence without it lists none (docs/proof.md, Delivered files). A result that ran carries `why` (the reason it ran); a reused result, the test command's included, carries `reused: true` and keeps the `at` of the proof that really ran it. Reuse follows each unit's read list (the files it opened and the folders it listed), kept in the clone at `.git/vbw/runs.json`, never in the record (docs/proof.md). `own` is where the proof's time went, in seconds: `planning`, `copies`, `tracking`, `saving`, `record` (VBW's own steps, measured by the clock) and `wall` (the whole command, up to the end of its record step; `tracking` is summed over units that run side by side, so the steps can add up to more than `wall`); a malformed `own` makes the record corrupt. `causes` lists the whole-proof causes that made units run (`[]` when the reuse rule decided alone); it stays small however many files a commit adds: more than three unseen files are one cause with their count and the first three paths (docs/proof.md). `vbw show evidence` prints the steps and each unit's reason, and says `not recorded` for both on a record written before these fields (docs/proof.md). A proof that reused anything has `full` false; QA and shipping accept it all the same A unit's `seconds` is a number to a tenth of a second (whole seconds in an older record). |
| `converted` | optional: `{ "from": ".vbw-planning", "at" }`, set by `vbw legacy done` once a VBW 1 plan was brought in (docs/convert.md) |
| `protected` | always present, right after `lease`: the sorted list of every file an approved check protects (the union of all checks' `files`), each path once; an empty list when there are no checks. The writer keeps it equal to the checks on every write. The guards read it instead of the checks (docs/guards.md). Corrupt when it is missing on schema 4, when it differs from the checks, or when it is on a record below schema 4 |
| `lease` | `null` or `{ "run", "kind", "started_at", "files" }`: the active run (`kind` `plan`, `build`, `fix`, `qa` or `map`; `files` the paths its agents may write: `null` for any, `[]` for none) that the guards hold subagents to (docs/workflows.md); optionally `session` (the session that opened it; the holder's name is never stored in the lease), for a build run `editable` (the check files a survivor of `vbw mutate` opened: those that a check of the plan's own rules names, shared with other requirements' checks or not, added as the survivor is recorded; the Dev may edit them to strengthen the test) and, for a fix run with a requirement fix of any source (a proof's fix too), `editable` (the check files of the fixes' requirements that other requirements do not use, which the Dev may edit; a project-command fix opens none) and, only when a fix of the run comes from QA, `new_tests: true` (the Dev may create new test files); optionally `cost` (`lease.cost`): the opening session's figures `{ "usd" }` when `vbw run start` saw them, or null |
| `costs` | optional: what runs and milestones cost, `{ "runs", "milestones" }`, no other keys. `runs[]` holds `{ "id", "kind", "session", "milestone", "started", "ended", "cost" }`: the run's id and kind, the session that ran it (or null), an existing milestone id, ISO-8601 UTC times, and `cost` either `{ "usd" }` or null when the figures were not seen (never 0, never a guess). `milestones` maps an existing milestone id to `{ "baseline", "total"? }`: `baseline` has, per session, `{ "usd", "at" }` as that session stood when the milestone started; `total` is `{ "usd", "sessions" }`, frozen when the milestone ships. Keys are exact, dollars are non-negative numbers, `sessions` a non-negative integer. Only dollars are measured (docs/costs.md); a record written while tokens were still stored also carries `in` and `out` beside every `usd`, both or neither: it stays valid, and they are never read or shown. Only `vbw run start`, `vbw run end`, `vbw ship` and `vbw milestone start` write it; the status line, the hooks and the panel never do (docs/costs.md). Added within schema 4: a record without it stays valid, so the schema stays 4 |
| `loop` | optional: the loop (docs/loop.md), no other keys. `items[]` holds, in the order started, `{ "id", "text", "proof", "status", "milestone"?, "req"?, "head"?, "baseline"?, "retried"?, "reverts"?, "left"?, "cost"?, "reason"?, "at"?, "opened_at"?, "stepped_at"?, "away"?, "budget"? }`: the backlog id `T<n>`, a snapshot of its text, `proof` `auto` or `human`, `status` `waiting`, `in_progress`, `shipped` or `parked`, the milestone opened for it, its requirement's id (`req`, kept from its open so the report still names it after a later milestone carries a skipped `[human]` requirement over), the commit (`head`, 40 hex digits) and per-session `baseline` taken at its start, `retried` (`{ fixes, plans }`), `reverts`, `left` (the commits a park left in place, each with why, as one sentence), `cost` (`{ usd }` or null), the `reason` it was parked and the time `at`; `opened_at`, the time the loop opened it, `stepped_at`, the time of the loop's last step on it, `away`, the whole seconds the loop was stopped while it was in progress (left out of its time), and `budget` (`{ seconds, basis }`, and `planned: true` once the plan set it), its time budget (docs/loop.md). A new loop that names the item an ended loop left in progress carries that item over, every field kept. A park fills `reverts` (the revert commits), `left` when it left a commit, `reason` and `cost` (frozen), and sets `status` to `parked`; `retried` holds the fix and plan ids already retried once. `ceiling` is null (`--no-ceiling`) or `{ usd, finish_item }` with `usd` above 0. `session` is the starting session or null; `started_at` an ISO-8601 UTC time; `baseline` the figures of each session when the loop started, as a milestone's baseline (`costs`). `stopping` is `{ at, session }`, set by `vbw loop stop`; `asked` is `{ item, instruction }`, the not-ready contract the loop handed back to the session (D334), removed by the next step that answers it; `ended` is `{ at, reason }` and `report` the relative path of the loop's report. Only `vbw loop start`, `vbw loop stop`, `vbw loop next` and `vbw loop park` write it. Added within schema 4: a record without it stays valid, so the schema stays 4 |

Unknown keys are rejected, at the top level and inside every item: an unknown
key is a typo, a stale field or a newer schema, and all three must be loud.

## Versioning

A VBW reads every schema up to its own (`VBW_SCHEMA_MAX`, currently 6). Every
record this VBW writes is schema 4, or 5 while it holds `settings.efforts`
(VBW 2.1.13): a VBW up to 2.1.12 reads up to schema 4, so it asks to be updated
for such a record, and a project without a chosen effort stays readable by it.
A record becomes schema 6 once an approval records the plans it changed
(`decisions[].plans`, #705), which happens from the second contract approval
in a clone on: a VBW that reads up to schema 5 asks to be updated for it.

Records of schemas 1 to 3, which an older VBW wrote, have no `protected` list.
They are still read, and they become schema 4 on their next write. There is no
migration command. An older VBW that opens a record this VBW wrote says it
needs a newer VBW.

History of what older VBWs wrote:
a record whose checks use `alone` was schema 2, so an older VBW asks to update
instead of calling the record corrupt. A sorted todo (`sort` and `size`) or a stored
`recommendation` made it schema 3.

The last pass of each check is not in the record. The read lists that decide reuse are
a cache in the clone (`runs.json` in the git directory, see docs/proof.md), so a record never
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
