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

### Proven requirements a phase could affect

A phase could affect a proven requirement of another phase when their plans
touch the same files. Such a requirement is at risk of breaking, so it counts
toward the `breaks` signal, unless it is guarded.

A requirement is **guarded** when it is `[auto]`, has at least one check, and
every one of its checks is an approved check: the check, and each file it
lists, are the same as in the last contract you approved in this clone. `vbw prove` runs every
check again (a result reused from an earlier proof counts, see
docs/proof.md), so a break would show at once. A guarded requirement does not
raise the tier.

These do raise it:

- a `[human]` requirement a person accepted: no check re-runs it;
- an `[auto]` requirement whose check is not approved yet, or was edited (or
  whose check file was edited) since the approval;
- an `[auto]` requirement with no check.

Guarding only covers this one signal. Many files, a risk word, a missing test
command and the other signals raise the tier as before.

The reasons list both groups. `breaks:` names the requirements that raised the
tier (`none` when none did). `guarded:` names the requirements the phase could
affect that did not, each with its checks; it is left out when there are none.

```
$ vbw show phase P2
P2 Add export [planned]
...
tier: standard
  - requirements: 1
  - files: 2 (900 bytes)
  - risk: none
  - breaks: R3
  - guarded: R1 (C1)
  - tests: project test command
```

Here P2 touches the files of R1 (an `[auto]` requirement guarded by C1) and R3
(a `[human]` requirement). Only R3 raises the tier. `vbw show contract` shows
the same two parts on the phase's line.

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

## The small change

A small change goes from your request to done with one approval and no
planning workflow. `vbw next --json` marks it at the `plan` step:

```json
{ "action": "plan", "detail": { "tier": "standard", "small": true } }
```

`detail.small` is judged on the request: the milestone's requirements that
have no phase yet. It is `true` when there are one or two of them, all `auto`,
together they name at most two files (a file name such as `greet.sh` or
`src/total.js`; the same file named twice counts once), none names a risk
category (the words above) or a risk-path file (such as `.env` or
`.github/workflows/ci.yml`), and `vbw config rigor` is `auto` or `express`.
Requirements already planned in earlier phases, finished or not, `auto` or
`human`, do not count. It does not depend on the size of the repository, so a
small request in a large repository is still small, even though its early tier
(`detail.tier`) is `standard`. A new `human` requirement, three or more new
requirements, three or more named files, a risk word or path, or a forced
`standard` or `deep` makes it `false`.

Example: the milestone already has phase P1 (R1 done, R2 planned). You ask for
one more thing:

```
vbw spec add auto "greet.sh prints HELLO, ANA! for --shout Ana"
```

R3 has no phase yet, names one file and no risk, so `detail.small` is `true`
and `next_phase` is `2`.

When `detail.small` or an `express` tier is set, the router plans the change
itself: it adds one phase at `detail.tier`, numbered from `next_phase`, with
`vbw apply --add` (docs/workflows.md), holding one plan of one or two files,
its check and its rules. That tier is `express` when its signals allow, and
`standard` otherwise, for example in a repository without a project test
command or tracking more than 30 files. P1 and its plans, checks and rules stay as they were. You approve once. Then VBW builds, proves, checks (see
"QA depth") and closes it.

One rule keeps this honest in a large repository. When git tracks more than 30
files, an express phase may cover at most two files. A phase over more than two
files has a `standard` floor, with the reason `files: more than 2 in a
repository tracking 40 files`, and `vbw apply` refuses to store it as express
(`its signals set the floor at standard`). Leave the tier out and the kernel picks `standard`. A
change over two files or on a risk path therefore plans normally, through the
planning workflow.

## What each tier runs

`plugin/lib/tiers.json` holds one row per profile and tier. In the `balanced`
profile:

| Tier | Agents | QA | Models |
|---|---|---|---|
| `express` | one Dev | `quick`, and only when needed (below) | Dev and QA on Sonnet |
| `standard` | Lead, a Dev per plan, QA | `standard` | Lead on Opus; Dev and QA on Sonnet |
| `deep` | Scout, Lead, a Dev per plan, QA | `deep` | Lead on Opus; Scout, Dev and QA on Sonnet |

`quality` runs Dev on Opus from `standard` up and QA at `deep` for both upper
tiers; `budget` runs `express` Dev on Haiku and `standard` QA at `quick`. Read the
file for the exact table. The Lead, Scout and Architect take their models from
`plugin/lib/profiles.json` (`vbw config models` prints them). Your own model overrides (`vbw config set model.dev opus`) win over the table.

**QA never uses Haiku.** In every profile and tier, QA runs on Sonnet or a
stronger model. Other roles keep the models their profile gives them.

An express phase has exactly one plan: `vbw apply` refuses more.

## QA depth

The table gives each phase a QA depth. Size and risk can only lower it. At
the `qa` step, `vbw next --json` carries the depth chosen per phase in
`round.tiers`, and the QA workflow checks each phase at that depth:

```json
{ "action": "qa", "detail": { "phases": ["P1"], "tier": "deep" },
  "round": { "tiers": { "P1": "quick" }, "suite": null } }
```

Here the profile says `deep` (`rigor.P1.qa`), but the change is small, so
`P1` gets a `quick` check. The profile's cell and `detail.tier` stay as they
are.

| The phase's change | `round.tiers` |
|---|---|
| risk is not `none` in its tier reasons, or it has no recorded reasons | the profile's depth |
| 1 or 2 files in its plans | `quick`, never deeper |
| 3 to 9 files | `standard` at most (a profile's `quick` stays `quick`) |
| 10 or more files | the profile's depth |

Files are counted once across the phase's plans. A risky change gets the full
depth however few files it touches. A small, low-risk change never gets a deep
check.

## Documentation changes

Example: a plan that only edits `README.md` goes from `vbw approve` to `ship`
with no check.

A requirement that only changes documentation or wording needs no new check.
Every plan that serves it must change only Markdown (`.md`, `.markdown`) or
reStructuredText (`.rst`) files. Plain `.txt` files are data, not
documents.

For such a requirement:

- the Lead lists no check and no `rules` for it, and `vbw approve` does not
  ask for them;
- `vbw prove` marks it `proven` once its plans are done;
- documentation files do not count as existing code, so a repository with no
  project test command does not raise the phase to `standard` for them.

A small documentation phase is `express`, and an express phase with only
`auto` requirements and a passing proof gets no QA.

Two cases keep their check. A plan that changes documentation and code
together is not exempt: its requirement needs a check, and `vbw approve` says
`R1 has no check` without one. And a project rule that requires a check for the
documentation overrides the exemption. The Lead writes the check, it runs, and
a failing one fails the requirement. State such a rule in your project's own
instructions, for example `CLAUDE.md`.

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
