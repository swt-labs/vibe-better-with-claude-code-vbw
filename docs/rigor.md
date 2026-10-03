# Adaptive rigor: how much checking a phase gets

VBW gives each phase a tier: `express`, `standard` or `deep`. A small, safe
phase gets one Dev and no QA agent; a risky or large one gets the full team.
VBW picks the tier from measured signals, raises it on its own when a run goes
badly, and never lowers it once work on the phase has begun.

```
$ vbw show phase P1
P1 Add the done command [built]
...
qa: pass (deep, 2026-10-03T16:30:25Z): 24/24 checks
tier: deep (predicted standard)
  - requirements: 3
  - files: 2 (673 bytes)
  - risk: none
  - breaks: none
  - tests: project test command
escalated standard -> deep (2026-10-03T16:29:12Z): QA needs a second round

$ vbw show rigor
P1 deep (predicted standard), finished: requirements: 3; files: 2 (673 bytes); risk: none; breaks: none; tests: project test command
prediction held for 0 of 1 finished phases (0%)
```

## The floor

`vbw apply` computes a floor for every phase from the signals below. The tier
is the highest tier any signal asks for.

| Signal | standard | deep |
|---|---|---|
| requirements in the phase | 3-5 | 6 or more |
| files in its plans | 5-9 | 10 or more |
| bytes of those files that exist | 100,000 | 500,000 |
| risk words in the files' paths, the phase title and goal, or its requirements: sign-in, payments, data migration, secrets, deletion, CI | | any |
| proven requirements of other phases whose plans touch the same files | 1-3 | 4 or more |
| existing files to change but no project test command | yes | |

The reasons are stored with the tier and printed by `vbw show phase ID` and
`vbw show contract`, so the tier is never a mystery. The Architect may raise a
phase above its floor; `vbw apply` refuses a lower tier than the floor. The
raise is kept as the phase's `proposed` tier.

## The early decision

Before planning, `vbw next --json` at the `plan` step carries `detail.tier`.
It is `express` only when the milestone has one requirement, it is `auto`, its
text names no risk category (the words above), the repository tracks at most
30 files (`git ls-files`, counted; no file is read) and `vbw config rigor` is
`auto` or `express`. Otherwise it is `standard`, or `deep` when the mode is
`deep`. A forced `express` stays `express` on a bigger request.

At an express `plan` step the router skips mapping and the planning workflow:
it reads the files the request names, then runs `vbw apply` with one phase
(tier `express`), one plan and one check that fails today, and goes to
approval. No project file changes before the contract is approved. If apply
computes a higher floor, the normal planning workflow runs instead.

## What each tier runs

`plugin/lib/tiers.json` holds one row per profile and tier. In the `balanced`
profile:

| Tier | Agents | QA | Models |
|---|---|---|---|
| `express` | one Dev | `quick`, and only when needed (below) | Dev and QA on Sonnet |
| `standard` | Lead, a Dev per plan, QA | `standard` | Sonnet |
| `deep` | Scout, Lead, a Dev per plan, QA | `deep` | Sonnet |

`quality` runs Dev on Opus from `standard` up and QA at `deep` for both upper
tiers; `budget` runs `express` on Haiku and `standard` QA at `quick`. Read the
file for the exact table. Your own model overrides (`vbw config set model.dev opus`) win over the table.

An express phase has exactly one plan: `vbw apply` refuses more.

**Express and QA.** An express phase skips QA when all its requirements are
`auto` and its proof passes. It gets QA if it has a `human` requirement or has
escalated.

## Forcing a tier

```
vbw config rigor           # print the mode (default: auto)
vbw config rigor deep      # every phase is deep
vbw config rigor auto      # compute again
```

A forced mode sets the tier of phases that have not started and have no
escalations, and records `forced: vbw config rigor deep` as the reason. `auto`
recomputes them and keeps a tier the Architect raised. Phases already started
keep their tier.

## Escalation

While a phase runs, VBW raises its tier one step (`deep` stays `deep`) and
records when, from, to and why. These events raise it:

| Event | Reason recorded | Raise |
|---|---|---|
| a Dev blocks a plan (`vbw plan block`) | `Dev blocked P1.2: ...` | one step |
| a fix needs a second round | `fix F1 needs a second round` | one step |
| QA finds a problem in an express phase | `QA found a problem in R1: ...` | one step |
| QA fails the phase a second time | `QA needs a second round` | one step |
| a commit touches a risk path | `touches a risk path: payments (src/pay.ts)` | to `deep` |
| a commit changes more than twice the planned files (at least 4) | `grew beyond its plan: 6 files for 2 planned` | one step |
| a proven requirement fails | `proven requirement R1 failed` | one step |

The same reason is never recorded twice. Later steps use the raised tier's
agents, QA tier and models.

`vbw tier raise PHASE TIER REASON` raises a tier by hand, for example from the
router:

```
vbw tier raise P1 deep "touches the billing export"
```

It refuses a tier that is not higher than the current one. Nothing in VBW
lowers a tier during a run: not planning again, not `vbw config rigor`.

## The outcome record

When a phase finishes (plans done, requirements proven or accepted, no open
fix, QA passed where its tier calls for it), the kernel writes its `outcome`
once:

| Field | Meaning |
|---|---|
| `tier` | the tier it finished at |
| `predicted` | the tier it began at |
| `held` | `true` when `tier` equals `predicted` |
| `fix_rounds` | fix attempts on its requirements |
| `qa_findings` | fixes opened by QA |
| `escalations` | number of escalation events |

`vbw show rigor` lists every phase's tier and prediction, then how often the
prediction held among finished phases.

## Cost

VBW records no cost. The `outcome` counts rounds, findings and escalations,
not tokens or dollars. Cost is measured per session by the benchmark
(docs/benchmark.md).
