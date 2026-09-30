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
| 1 | milestone `shipped` | `milestone` (start the next milestone) | yes |
| 2 | no requirements | `spec` (write requirements in `.vbw/spec.md`) | yes |
| 3 | an `auto` requirement without checks, or no phases | `plan` (plan workflow: phases, plans, contract checks) | no |
| 4 | contract not approved (never approved, or changed since) | `approve` (review and approve the contract) | yes |
| 5 | a plan is `blocked` | `unblock` (a builder reported a blocker) | yes |
| 6 | plans ready to build: not `done`, every `after` plan `done` | `build` (the ready plans: one wave) | no |
| 7 | a fix is `escalated` | `escalate` (the fix cap was reached) | yes |
| 8 | current evidence has scope violations | `scope` (commits changed files outside their plans) | yes |
| 9 | a fix is `open` | `fix` (fix workflow for its requirement) | no |
| 10 | an `auto` requirement is not `proven`, or the evidence is of another contract | `prove` | no |
| 11 | a `human` requirement is `open` | `accept` (one scenario at a time) | yes |
| 12 | a `human` requirement is `rejected` | `fix` (turn the rejection into a fix item) | no |
| 13 | otherwise | `ship` | yes |

Fix items and their attempt cap are defined in docs/proof.md.
