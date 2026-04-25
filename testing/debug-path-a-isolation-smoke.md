# `/vbw:debug` Path A isolation smoke

Manual smoke runbook for verifying that `/vbw:debug` Path A keeps hypothesis investigators report-only until teardown, then hands implementation to one fresh post-synthesis `vbw:vbw-debugger` only when the synthesized result is `needs_change`.

Use this when you need reviewer-verifiable evidence for debug-investigator isolation. This is intentionally a manual smoke, not CI automation — it exercises live Claude behavior against a consumer repo.

## Provenance rules

- Run from a **consumer smoke worktree or sandbox**, not from the VBW plugin repo and not from the base consumer repo checkout.
- Load the candidate VBW checkout only through `--plugin-dir`.
- Force Path A with both:
  - `prefer_teams=always` in the consumer smoke worktree config, and
  - `--competing` on the `/vbw:debug` prompt.
- If the smoke prompt should stop after the debug investigation result, say so explicitly so inline QA/UAT does not muddy the evidence.

## What to prove

### `already_fixed` case

1. `/vbw:debug` enters **Competing Hypotheses (3 parallel)**.
2. Three hypothesis investigators are spawned as `vbw:vbw-debugger` teammates.
3. All three investigators report, receive shutdown requests, and the orchestrator runs `TeamDelete` plus residual cleanup.
4. No post-synthesis implementation owner is spawned.
5. Through the investigation and teardown checkpoint, the **source tree** remains unchanged.

### `needs_change` case

1. `/vbw:debug` enters **Competing Hypotheses (3 parallel)**.
2. Three hypothesis investigators are spawned as `vbw:vbw-debugger` teammates.
3. All three investigators report, receive shutdown requests, and the orchestrator runs `TeamDelete` plus residual cleanup.
4. Only **after** teardown does the orchestrator spawn one fresh post-synthesis implementation owner.
5. That fresh implementation owner is the only actor that changes project source files.

## Interpreting expected `.vbw-planning` state

`/vbw:debug` may create expected lifecycle bookkeeping under `.vbw-planning/debugging/`, and `already_fixed` completion paths may create a planning-artifact boundary commit depending on config.

For the isolation proof, distinguish:

- **source-tree changes** — the user-facing repo files under investigation
- **debug-session bookkeeping** — expected state under `.vbw-planning/debugging/`

When checking whether investigators stayed report-only, inspect source-tree changes directly and call out any expected `.vbw-planning/debugging/` noise separately.

## Suggested fixture shape

Seed two committed shell fixtures in the consumer smoke worktree before invoking `ccr code`:

### `already_fixed`

- `smoke/vbw-debug-path-a/already_fixed/status.sh`
  - prints `status: pass`
- `smoke/vbw-debug-path-a/already_fixed/check.sh`
  - expects exact output `status: pass`

### `needs_change`

- `smoke/vbw-debug-path-a/needs_change/status.sh`
  - prints `status: fail`
- `smoke/vbw-debug-path-a/needs_change/check.sh`
  - expects exact output `status: pass`

Commit those fixtures first so spawned agents and task worktrees see the same baseline.

## Consumer worktree setup

Resolve the real consumer repo from the candidate plugin checkout:

```bash
cd /absolute/path/to/vbw-candidate-worktree
bash scripts/resolve-debug-target.sh repo
```

Create a disposable consumer smoke worktree:

```bash
CONSUMER_REPO=/absolute/path/to/consumer-repo
SMOKE_LABEL=smoke-debug-path-a-isolation
CONSUMER_NAME=$(basename "$CONSUMER_REPO")
CONSUMER_PARENT=$(cd "$CONSUMER_REPO/.." && pwd)
SMOKE_BASE="${CONSUMER_PARENT}/${CONSUMER_NAME}-worktrees"
SMOKE_WORKTREE="${SMOKE_BASE}/${SMOKE_LABEL}"

mkdir -p "$SMOKE_BASE"
git -C "$CONSUMER_REPO" worktree add --detach "$SMOKE_WORKTREE" HEAD
cd "$SMOKE_WORKTREE"
```

Force Path A routing in the disposable consumer worktree only:

```bash
tmp=$(mktemp)
jq '.prefer_teams = "always"' .vbw-planning/config.json > "$tmp"
mv "$tmp" .vbw-planning/config.json
```

## Pre-run evidence capture

Capture a source-tree baseline before each smoke run:

```bash
git rev-parse HEAD
git status --short
git diff --stat -- . ':(exclude).vbw-planning/debugging/**'
```

## `already_fixed` smoke prompt

Run from the **consumer smoke worktree** with the candidate plugin checkout passed via `--plugin-dir`:

```bash
printf '%s\n' \
  'Smoke test of /vbw:debug Path A orchestration. Follow the competing-hypotheses team workflow end-to-end for this run. Do not collapse to direct verification even if the first local check is conclusive. Stop after the debug investigation result; do not continue into QA or UAT.' \
  '/vbw:debug The previous report said smoke/vbw-debug-path-a/already_fixed/check.sh still fails, but the expected current behavior is that `bash smoke/vbw-debug-path-a/already_fixed/check.sh` exits 0 and prints `status: pass`. Confirm whether any code change is still required. --competing' \
  | ccr code -p --verbose --output-format stream-json --include-partial-messages --dangerously-skip-permissions \
      --plugin-dir /absolute/path/to/vbw-candidate-worktree
```

Verify:

- transcript shows `Competing Hypotheses (3 parallel)`
- transcript shows three `vbw:vbw-debugger` hypothesis spawns
- transcript shows shutdown requests, `TeamDelete`, and residual cleanup
- transcript does **not** show a post-synthesis implementation-owner spawn
- source-tree baseline remains unchanged through the teardown checkpoint

## `needs_change` smoke prompt

```bash
printf '%s\n' \
  'Smoke test of /vbw:debug Path A orchestration. Follow the competing-hypotheses team workflow end-to-end for this run. Do not collapse to a single direct fix. Stop after the bug-investigation result and do not continue into QA or UAT.' \
  '/vbw:debug The smoke fixture at smoke/vbw-debug-path-a/needs_change/check.sh currently fails because the expected output is `status: pass` but status.sh prints the wrong word. Investigate the root cause and fix it. --competing' \
  | ccr code -p --verbose --output-format stream-json --include-partial-messages --dangerously-skip-permissions \
      --plugin-dir /absolute/path/to/vbw-candidate-worktree
```

Verify:

- transcript shows three hypothesis-investigator spawns first
- transcript shows shutdown requests, `TeamDelete`, and residual cleanup before implementation
- transcript shows one fresh post-synthesis implementation owner after teardown
- only that implementation owner changes the source tree
- `bash smoke/vbw-debug-path-a/needs_change/check.sh` exits `0` after the fix

## Reviewer checklist

When quoting evidence for review, capture these five facts explicitly:

1. smoke provenance: consumer smoke worktree or sandbox + candidate plugin via `--plugin-dir`
2. Path A routing was forced (`prefer_teams=always` and `--competing`)
3. `already_fixed`: three investigators, full teardown, no implementation owner
4. `needs_change`: three investigators, full teardown, one fresh implementation owner
5. source-tree stability until the implementation-owner handoff

Keep the evidence concise. Quote decisive excerpts, not full raw transcripts.