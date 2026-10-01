# `vbw next`: the one answer to "what happens now"

`vbw next` is a pure function of `.vbw/record.json` and whether the current
contract hash has the user's consent (docs/proof.md). The `/vbw:vibe` router,
the autonomy Stop gate and the statusline all ask it; nothing else decides the
lifecycle. `vbw next --json` returns:

```json
{ "action": "build", "gate": false, "instruction": "Run the build workflow for P1.2, P1.3",
  "detail": { "plans": ["P1.2", "P1.3"] } }
```

`gate: true` means a person must act; autonomous runs stop there.

## Decision order (first match wins)

| # | Condition | action | gate |
|---|---|---|---|
| 0 | a run lease is open | `run` (wait for its workflow if it is running in this session; otherwise `vbw run end`) | no |
| 1 | milestone `shipped` | `milestone` (start the next one: `vbw milestone start TITLE`) | yes |
| 2a | no requirements in the current milestone, and a VBW 1 plan (`.vbw-planning/`) not converted yet | `convert` (`/vbw:convert`, or start fresh; docs/convert.md) | yes |
| 2 | no requirements in the current milestone | `spec` (write its requirements in `.vbw/spec.md`) | yes |
| 3 | the current milestone has no phases, an `auto` requirement has no check, or a current `auto` requirement is in no plan | `plan` (plan workflow: phases, plans, contract checks) | no |
| 4 | contract not approved (never approved, or changed since) | `approve` (review and approve the contract) | yes |
| 5 | a plan is `blocked` | `unblock` (a builder reported a blocker) | yes |
| 6 | plans ready to build: not `done`, every `after` plan `done` | `build` (one wave: the ready plans in order, skipping any that shares a file with one already in the wave) | no |
| 7 | a fix is `escalated` | `escalate` (the fix cap was reached) | yes |
| 8 | current evidence has scope violations | `scope` (commits changed files outside their plans) | yes |
| 9 | a fix is `open` | `fix` (`detail.fixes`, and `detail.groups`: fixes whose files overlap, one builder each; a project command's fix may touch any file) | no |
| 10 | an `auto` requirement is not `proven`, or the evidence is stale (another contract, or the project files changed since; docs/proof.md) | `prove` | no |
| 11 | a `human` requirement is `open` | `accept` (one scenario at a time) | yes |
| 12 | otherwise | `ship` (`vbw ship`) | yes |

Rejecting a `human` requirement (`vbw req reject R2 "why"`) opens a fix item at
once, so it is worked by row 9; when the fix is done the requirement returns to
row 11 for acceptance.

Fix items and their attempt cap are defined in docs/proof.md.
