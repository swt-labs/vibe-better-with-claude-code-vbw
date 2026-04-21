---
name: running-ccr-smoke-tests
description: 'Use this skill when asked to run or verify a VBW smoke test through claude-code-router (`ccr code`), check visible `Skills:` output, validate `.vbw-planning/.skill-decisions.log`, or confirm consumer-smoke-worktree versus `--plugin-dir` provenance.'
argument-hint: '[smoke-goal]'
---

# Running CCR smoke tests

Use this skill when validating VBW behavior with `ccr code` so future issue-fix runs do not have to rediscover the router entrypoint, the consumer repo path, or the provenance checks.

## Core rule

- Do **not** run the smoke test with the VBW plugin repo or plugin worktree as the working directory.
- Do **not** run the smoke test directly in the base consumer repo checkout.
- Create or reuse a **disposable consumer smoke worktree** and run `ccr code` there, or use a **sandbox repo** when the real consumer repo cannot exercise the flow.
- Use the candidate VBW checkout only as `--plugin-dir`.
- When documenting results, say: **"smoke-tested from a consumer smoke worktree or sandbox while loading the candidate plugin checkout via `--plugin-dir`"**.
- If the transcript path encodes the plugin repo or the base consumer repo checkout instead of the consumer smoke worktree/sandbox, treat the smoke result as suspect until proven otherwise.

## Expected inputs

- Candidate plugin checkout path, usually the current VBW worktree under test.
- Preferred consumer repo path, resolved from the VBW checkout with:
  - `bash scripts/resolve-debug-target.sh repo`
- Smoke worktree label such as `smoke-fix-issue-502` or `smoke-skill-audit`.
- Optional sandbox path such as `/tmp/vbw-skill-smoke-<issue>` for phase-routed flows the real consumer repo cannot exercise.

## Location roles

Keep these four locations distinct throughout the run:

- **Candidate plugin checkout** — the VBW repo checkout under test. Pass this path only through `--plugin-dir`.
- **Consumer repo** — the real target repo used to resolve the testing target and create/remove the smoke worktree. Do not run `ccr code` from this checkout.
- **Consumer smoke worktree** — the disposable worktree created from the consumer repo. This is the real cwd for consumer-repo smoke tests.
- **Sandbox repo** — a temporary repo used only when the consumer repo cannot exercise the required phase-routed flow.

## Workflow

Copy this checklist into the run if the task is multi-step:

```text
CCR Smoke Test Progress:
- [ ] Confirm candidate plugin checkout/worktree path
- [ ] Resolve real consumer repo path
- [ ] Create or enter the consumer smoke worktree
- [ ] Decide consumer worktree vs sandbox per flow
- [ ] Run smoke command(s) with `ccr code`
- [ ] Capture visible `Skills:` evidence when needed
- [ ] Capture `.skill-decisions.log` deltas
- [ ] Verify transcript/project path provenance
- [ ] Confirm the base consumer repo and plugin checkout did not become the smoke cwd
```

### 1. Confirm the candidate plugin path

Treat the candidate plugin checkout as the path passed to `--plugin-dir`. In issue-fix runs, this is usually the feature worktree, not the main plugin repo checkout.

### 2. Resolve the real consumer repo first

From the VBW checkout, resolve the preferred smoke target with:

```bash
bash scripts/resolve-debug-target.sh repo
```

- If it returns an absolute path, use that repo as the source checkout for the consumer smoke worktree.
- If it fails and the smoke target must represent real consumer-repo behavior, ask the user for the real consumer repo path.
- Use a dedicated sandbox repo only when the real consumer repo is unavailable or cannot exercise the targeted flow.
- If it resolves to the same path as the candidate plugin checkout, stop and correct the target. The smoke cwd must be the consumer smoke worktree or sandbox, never the candidate plugin checkout.

### 3. Create or enter the consumer smoke worktree

Use a disposable worktree derived from the consumer repo checkout so smoke artifacts do not land in the production checkout.

```bash
CONSUMER_REPO=/absolute/path/to/consumer-repo
SMOKE_LABEL=smoke-fix-issue-502
CONSUMER_NAME=$(basename "$CONSUMER_REPO")
CONSUMER_PARENT=$(cd "$CONSUMER_REPO/.." && pwd)
SMOKE_BASE="${CONSUMER_PARENT}/${CONSUMER_NAME}-worktrees"
SMOKE_WORKTREE="${SMOKE_BASE}/${SMOKE_LABEL}"

mkdir -p "$SMOKE_BASE"

if git -C "$CONSUMER_REPO" worktree list --porcelain | grep -Fqx "worktree $SMOKE_WORKTREE"; then
  :
elif [ -e "$SMOKE_WORKTREE" ]; then
  echo "Target smoke worktree path exists but is not a registered worktree: $SMOKE_WORKTREE" >&2
  exit 1
else
  git -C "$CONSUMER_REPO" worktree add --detach "$SMOKE_WORKTREE" HEAD
fi
```

Run all consumer-repo smoke commands from `SMOKE_WORKTREE`, never from `CONSUMER_REPO`.

### 4. Pick the right target for each flow

Use the **consumer smoke worktree** for flows that do not require special phase state:
- `/vbw:debug`
- `/vbw:fix`
- `/vbw:research`
- `/vbw:map`

Use a **sandbox repo** when the real consumer repo cannot exercise a phase-routed flow cleanly, for example:
- consumer repo has `next_phase_state=no_phases`
- you need `/vbw:qa` against a seeded phase
- you need `/vbw:vibe --execute` or `/vbw:vibe --verify` against controlled phase/UAT state

When you split coverage this way, say so explicitly in the verification summary.

### 5. Always invoke `ccr code`, not plain `claude`

Use the router entrypoint the user actually runs:

```bash
ccr code --help
```

Do not assume the plain `claude` binary is the right executable in this environment.

### 6. Run `ccr code` from the consumer smoke worktree or sandbox

Before each smoke command, explicitly `cd` into the consumer smoke worktree or sandbox repo. Do not rely on ambient shell state.

### 7. Pipe the prompt through stdin

If `ccr code -p "...prompt..."` reports an input error, switch to stdin and keep it that way for the run:

```bash
cd /absolute/path/to/consumer-smoke-worktree && \
printf '%s\n' '/vbw:fix Investigate a SwiftData save failure during tests.' \
  | ccr code -p --dangerously-skip-permissions --plugin-dir /absolute/path/to/candidate-plugin-checkout
```

Use `printf '%s\n'` instead of `echo` so punctuation and backslashes are preserved in a shell-portable way.

### 8. Add a smoke-test system prompt

For normal smoke checks, append a short system prompt that reduces side effects and keeps output easy to inspect:

```text
Smoke test only. Avoid code edits. Keep output concise. Focus on diagnosis and reporting.
```

For routing-only probes, make the stop condition explicit:

```text
Smoke test only. Stop after choosing skills and mode. Do not modify project files. Keep output concise.
```

### 9. Capture the right evidence

Always capture:
- command exit code
- transcript/project path proving the smoke cwd was the consumer smoke worktree or sandbox

Then capture the claim-matched evidence you actually need:
- **Visible-selection claim** → capture a visible `Skills:` line
- **Activation/logging claim** → capture `.vbw-planning/.skill-decisions.log` deltas
- **Domain-skill claim** → capture task-specific keyword matches when relevant, such as `SwiftData` / `swiftdata`

#### Standard smoke pattern

```bash
cd /absolute/path/to/consumer-smoke-worktree && \
printf '%s\n' '/vbw:research Research SwiftData persistence failures.' \
  | ccr code -p --dangerously-skip-permissions \
      --plugin-dir /absolute/path/to/candidate-plugin-checkout \
      --append-system-prompt 'Smoke test only. Avoid code edits. Keep output concise. Focus on diagnosis and reporting.'
```

#### Visible `Skills:` capture pattern

If plain output does not surface the `Skills:` line, use this dedicated stream-capture mode:

```bash
cd /absolute/path/to/consumer-smoke-worktree && \
printf '%s\n' '/vbw:fix Investigate a SwiftData save or schema failure.' \
  | ccr code -p --verbose --dangerously-skip-permissions \
      --plugin-dir /absolute/path/to/candidate-plugin-checkout \
      --append-system-prompt 'Smoke test only. Avoid code edits. Keep output concise. Focus on diagnosis and reporting.' \
      --output-format stream-json --include-partial-messages
```

Then search the captured output for `Skills:`.

#### Routing-only probe pattern

Use this when you only need mode/skill-selection behavior and do not want the workflow to keep going:

```bash
cd /absolute/path/to/sandbox-repo && \
printf '%s\n' '/vbw:vibe --execute 1' \
  | ccr code -p --permission-mode plan --dangerously-skip-permissions \
      --plugin-dir /absolute/path/to/candidate-plugin-checkout \
      --append-system-prompt 'Smoke test only. Stop after choosing skills and mode. Do not modify project files. Keep output concise.'
```

### 10. Verify provenance before trusting the result

Use these checks:
- The shell cwd for `ccr code` must be the consumer smoke worktree or sandbox.
- The transcript path should encode the consumer smoke worktree or sandbox path, not the candidate plugin checkout or base consumer repo checkout.
  - Consumer worktree example: `~/.claude/projects/-path-to-consumer-repo-worktrees-smoke-fix-issue-502/...`
  - Sandbox example: `~/.claude/projects/-private-tmp-vbw-skill-smoke-502/...`
- The candidate plugin checkout should appear only as `--plugin-dir`.

If the transcript path or cwd points at the plugin repo, do **not** document the smoke test as consumer coverage.

### 11. Verify repo cleanliness when provenance is in doubt

If you suspect the smoke ran in the wrong place:
- run `git status --short` in the base consumer repo checkout
- run `git status --short` in the consumer smoke worktree
- run `git status --short` in the main plugin repo checkout
- run `git status --short` in the candidate plugin checkout if it is a separate worktree
- inspect diffs for unexpected `.vbw-planning` changes

Expected smoke artifacts belong in the **consumer smoke worktree** or **sandbox**, not the base consumer repo checkout or the plugin repo.

## Decision points

- **`resolve-debug-target.sh repo` fails and you need real consumer coverage** → ask for the consumer repo path instead of guessing.
- **Need real consumer coverage** → create or reuse the consumer smoke worktree before running any `ccr code` command.
- **Real consumer repo cannot exercise `/vbw:vibe` or `/vbw:qa`** → use a sandbox for those flows and keep the consumer smoke worktree for `/vbw:debug`, `/vbw:fix`, `/vbw:research`, and `/vbw:map`.
- **Plain `-p` invocation reports missing input** → switch to stdin and keep it that way.
- **Need visible `Skills:` output** → use stream-json + `--verbose` and grep the capture.
- **Need routing proof without side effects** → use `--permission-mode plan` plus the routing-only smoke prompt.
- **Base consumer repo checkout, candidate plugin checkout, or main plugin repo shows unexpected `.vbw-planning` changes** → stop and investigate provenance before writing the verification summary.

## Completion checks

A smoke run is ready to cite only when all are true:
- The working directory was the consumer smoke worktree or sandbox.
- `--plugin-dir` pointed at the candidate plugin checkout.
- Required command outputs were captured for the claim being made.
- Provenance evidence was captured.
- `.skill-decisions.log` and/or visible `Skills:` evidence supports the specific claim being made.
- The base consumer repo checkout did not become the smoke cwd or collect smoke artifacts.
- Any sandbox use is called out explicitly.
- The plugin repo is not being misrepresented as the smoke-test cwd.
