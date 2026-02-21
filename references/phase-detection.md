# VBW Phase Auto-Detection Protocol

Single source of truth for detecting the target phase when the user omits the phase number from a command. Referenced by `${CLAUDE_PLUGIN_ROOT}/commands/vibe.md`, `${CLAUDE_PLUGIN_ROOT}/commands/qa.md`.

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

### QA Command (`/vbw:qa`)

**Goal:** Find the next phase that is built but not yet verified.

**Algorithm:**
1. List phase directories in numeric order
2. For each directory, check for `*-SUMMARY.md` and `*-VERIFICATION.md` files
3. The first phase where `*-SUMMARY.md` files exist but no `*-VERIFICATION.md` exists is the target
4. If found: use that phase
5. If all built phases are verified: report "All phases verified. Specify a phase to re-verify: `/vbw:qa N`" and STOP

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
Auto-detected Phase {N} ({slug}) -- {reason}
```

Reasons by command type:
- Planning: "next phase to plan"
- Build: "planned, not yet built"
- Implement: "needs plan + execute" or "planned, needs execute"
- QA: "built, not yet verified"

Then continue with the rest of the command as if the user had typed that phase number.
