# VBW Phase Auto-Detection Protocol

Single source of truth for detecting the target phase when the user omits the phase number from a command. Referenced by `${VBW_PLUGIN_ROOT}/commands/vibe.md` and the QA protocol (`qa.md`, hidden from `/help`).

## Overview

When `$ARGUMENTS` contains no explicit phase number, commands use this protocol to infer the correct phase from the current planning state. Detection logic varies by command type because each command targets a different stage of the phase lifecycle.

Note: `/vbw:vibe` has additional state detection that precedes phase scanning (see its State Detection section). The algorithms below are used once the command has determined that phase-level detection is needed.

## Resolve Phases Directory

Phases always live at `.vbw-planning/phases/` (root-canonical).

All directory scanning below uses this path.

## Detection by Command Type

### Planning Commands (`/vbw:vibe --plan`, `/vbw:vibe --discuss`, `/vbw:vibe --assumptions`)

**Goal:** Find the next phase that needs planning.

**Algorithm:**
1. List phase directories in numeric order (`01-*`, `02-*`, ...)
2. For each directory, check for `*-PLAN.md` files
3. The first phase directory containing NO `*-PLAN.md` files is the target
4. If found: use that phase
5. If all phases have plans: report "All phases are planned. Specify a phase to re-plan: `/vbw:vibe --plan N`" and STOP

### Discussion Gate (`require_phase_discussion` config)

When `require_phase_discussion=true` in config, the lifecycle command (`/vbw:vibe`) adds a discussion step before planning:

**Algorithm:**
1. During the dual-condition scan (same as Lifecycle Command below), before checking for `needs_plan_and_execute`:
2. If a phase has NO `*-PLAN.md` files AND NO `*-CONTEXT.md` files, it returns `needs_discussion` instead of `needs_plan_and_execute`
3. If `*-CONTEXT.md` exists (discussion already happened), it falls through to normal `needs_plan_and_execute`
4. When `require_phase_discussion=false` (default): this check is skipped entirely

### Build Command (`/vbw:vibe --execute`)

**Goal:** Find the next phase that is planned but not yet built.

**Algorithm:**
1. List phase directories in numeric order
2. For each directory, check for `*-PLAN.md` and `*-SUMMARY.md` files
3. The first phase where `*-PLAN.md` files exist but at least one plan lacks a corresponding `*-SUMMARY.md` is the target
4. If found: use that phase
5. If all planned phases are fully built: report "All planned phases are built. Specify a phase to rebuild: `/vbw:vibe --execute N`" and STOP

**Matching logic:** Plan file `NN-PLAN.md` corresponds to summary file `NN-SUMMARY.md` (same numeric prefix).

### QA Protocol (`qa.md`)

**Goal:** Find the next phase that is built but not yet verified.

**Algorithm:**
1. List phase directories in numeric order
2. If a phase has active QA remediation (`remediation/qa/.qa-remediation-stage` with stage `verify`), that phase is the QA target and writes to the persisted `verification_path` for the current round.
3. If `phase-detect.sh` reports `first_qa_attention_phase` with `qa_attention_status=pending`, `failed`, or `verify`, that phase is the QA target even when an older verification artifact already exists or terminal UAT has already been recorded.
4. Otherwise, for each built phase, resolve authoritative QA verification using `resolve-verification-path.sh`.
   - Default/brownfield phases: numbered final → brownfield plain → latest wave fallback.
   - After QA remediation reaches `stage=done`: the authoritative artifact is the round-scoped `remediation/qa/round-{RR}/R{RR}-VERIFICATION.md` only. If that artifact is missing, fail closed — do NOT fall back to the frozen phase-level verification file.
5. The first built phase with no authoritative QA verification artifact is the target.
6. When every phase is otherwise complete, `phase-detect.sh` may retarget `next_phase_state` away from `all_done` if `first_qa_attention_phase` is set:
   - `qa_attention_status=pending` → `next_phase_state=needs_verification` (so `/vbw:vibe` re-runs QA inline before any archive flow)
   - `qa_attention_status=failed|verify` → `next_phase_state=needs_qa_remediation`
   - When retargeting to `needs_verification`, preserve the machine-readable reason from `qa_attention_reason` in `qa_reason` so `/vbw:vibe` can explain why QA is being rerun.
7. If found: use that phase
8. If all built phases are verified: report "All phases verified." and STOP

**Verification result parsing:** `result:` is authoritative when present. Legacy `status:` is accepted only when `result:` is absent and only for `PASS`, `FAIL`, or `PARTIAL`. A blank or unrecognized `result:` must not fall back to `status:`.

### Lifecycle Command (`/vbw:vibe`)

> **v2 State Machine:** As of v2, `/vbw:vibe` uses a state machine that checks for project existence, phase existence, and completion status BEFORE reaching phase detection. The algorithm below only runs for States 3-4 (phases exist but need planning or execution). States 1 (no project), 2 (no phases), and 5 (all done) are detected by the state machine and never reach this algorithm. See `commands/vibe.md` State Detection section for the full routing logic.

**Goal:** Find the next phase that needs either planning or execution (or both). Used by States 3-4 of the implement state machine.

**Algorithm (dual-condition):**
1. List phase directories in numeric order
2. For each directory, check for `*-PLAN.md` and `*-SUMMARY.md` files
3. Two match conditions (first match wins):
   - **Needs plan + execute:** Directory contains NO `*-PLAN.md` files
   - **Needs execute only:** Directory contains `*-PLAN.md` files but at least one plan lacks a corresponding `*-SUMMARY.md`
4. If found: use that phase, noting which condition matched
5. If all phases are fully built: report "All phases are implemented. Specify a phase: `/vbw:vibe N`" and STOP

**Matching logic:** Same as Build Command -- Plan file `NN-PLAN.md` corresponds to summary file `NN-SUMMARY.md` (same numeric prefix).

## Announcement

Always announce the auto-detected phase before proceeding. Format:

```
Auto-detected Phase {NN} ({slug}) -- {reason}
```

Reasons by command type:
- Planning: "next phase to plan"
- Build: "planned, not yet built"
- Implement: "needs plan + execute" or "planned, needs execute"
- QA: "built, not yet verified"

Then continue with the rest of the command as if the user had typed that phase number.

## Diagnostic Variables

`phase-detect.sh` also emits diagnostic variables alongside phase state:

- `misnamed_plans=true|false` — Set to `true` when any phase directory contains type-first filenames (e.g., `PLAN-01.md` instead of `01-PLAN.md`). Commands should run `normalize-plan-filenames.sh` on all phase directories before proceeding when this is `true`.
- `qa_status=none|pending|passed|failed|remediating|remediated` — Current QA gate state for the primary phase routed toward verification or QA remediation.
- `qa_reason=none|<reason>` — Machine-readable reason for `qa_status=pending`. Use this to explain why QA is being rerun instead of emitting a generic pending-QA message.
- `qa_attention_status=none|pending|failed|verify` — QA state for the first otherwise-complete phase that still needs QA attention, including terminal-UAT phases that would otherwise allow archive routing.
- `qa_attention_reason=none|<reason>` — Machine-readable reason for `qa_attention_status=pending`. When `phase-detect.sh` retargets `all_done` to `needs_verification`, this reason is copied to `qa_reason`.

QA reason tokens:

- `missing_verification_artifact` — No authoritative VERIFICATION.md exists for the current phase/round.
- `verification_result_missing` — A verification artifact exists but has neither an authoritative `result:` nor a valid legacy `status:` value.
- `verification_result_unrecognized` — A verification artifact has an unsupported `result:` value, or an unsupported legacy `status:` when `result:` is absent.
- `qa_gate_rerun_required` — `qa-result-gate.sh` returned `QA_RERUN_REQUIRED` for an otherwise parseable artifact.
- `qa_gate_output_missing` — `qa-result-gate.sh` did not return a usable routing directive.
- `working_tree_changed` — Product files have uncommitted changes, so QA freshness cannot be trusted.
- `verified_at_commit_mismatch` — `verified_at_commit` differs from the current product-code commit.
- `git_status_failed` — The freshness check could not run `git status` successfully.
- `git_log_failed` — The freshness check could not resolve product-code history.
- `product_commit_unavailable` — No product-code commit could be resolved.
- `product_changed_after_verification` — Brownfield artifact without `verified_at_commit` predates the latest product-code commit.
- `freshness_baseline_unavailable` — The fallback timestamp freshness baseline could not be established.
