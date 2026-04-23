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
- [ ] Run a no-side-effect CCR preflight
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

### 4.5. Split routing coverage from completion coverage when the consumer repo is heavyweight

If the real consumer repo needs repo-specific prerequisites before the target command can reach the behavior you need to verify — for example package installs, service startup, credentials, proprietary toolchains, or flaky network fetches — do not force a single smoke run to prove everything.

- Use the **consumer smoke worktree** to verify provenance, routing, and that the command starts correctly in a real consumer repo.
- Use a **sandbox repo** to verify command-layer completion behavior when the real consumer repo's prerequisites are likely to block completion for reasons unrelated to the plugin.
- Report the split explicitly in the summary.
- If the command never reaches the lifecycle point you needed to verify, report the real-consumer run as **inconclusive for completion behavior**, not as a plugin regression.

### 5. Always invoke `ccr code`, not plain `claude`

Use the router entrypoint the user actually runs:

```bash
ccr code --help
```

Do not assume the plain `claude` binary is the right executable in this environment.

### 5.5. Run a no-side-effect preflight first

Before a longer smoke run, verify the router, auth, and provider path with a trivial prompt from the same cwd and `--plugin-dir`, but **without** `--append-system-prompt`:

```bash
cd /absolute/path/to/consumer-smoke-worktree && \
printf '%s\n' 'Smoke test preflight. Reply with OK. Do not modify files.' \
  | ccr code -p --dangerously-skip-permissions --plugin-dir /absolute/path/to/candidate-plugin-checkout
```

Use this to catch problems early:
- not logged in / expired auth
- router or provider validation failures
- wrong cwd or wrong `--plugin-dir`

If the preflight fails, fix that first instead of starting the real smoke command.

### 6. Run `ccr code` from the consumer smoke worktree or sandbox

Before each smoke command, explicitly `cd` into the consumer smoke worktree or sandbox repo. Do not rely on ambient shell state.

### 6.5. Shape sandbox repos for subagent-driven flows

When the smoke target can spawn subagents or task worktrees (for example `/vbw:debug`, `/vbw:fix`, or any flow that asks the agent to inspect repo files), the sandbox repo shape matters:

- Commit the **minimal seed fixtures** that define the bug premise before invoking `ccr code`.
- If the smoke depends on a file being present, absent, or containing exact text, make that file part of `HEAD` first so subagent worktrees and git-based checks see the same evidence.
- Keep runtime artifacts such as `.vbw-planning/` untracked unless the smoke specifically needs tracked planning state, but do not assume untracked repo fixtures will appear inside subagent worktrees.
- For snapshot-backed numbered selection flows (for example `/vbw:list-todos` followed by `/vbw:debug 1`), keep both commands in the **same persistent session**. Separate one-shot `-p` invocations do not share the numbered snapshot.
- When driving that persistent session through repeated `-p` calls, create the first call with `--session-id <uuid>` and continue later calls with `-r <uuid>` instead of repeating `--session-id`. Reusing `--session-id` on the follow-up call can fail with `Session ID ... is already in use.`

Good sandbox shape for an already-fixed debug smoke:

1. Create sandbox repo.
2. Commit the fixture file whose content establishes the premise.
3. Run `/vbw:init`.
4. Add the todo.
5. Run `/vbw:list-todos` and `/vbw:debug N` in the same session.

For print-mode automation, that means: first call uses `--session-id`, second call uses `-r` for the same UUID.

### 7. Pipe the prompt through stdin

If `ccr code -p "...prompt..."` reports an input error, switch to stdin and keep it that way for the run:

```bash
cd /absolute/path/to/consumer-smoke-worktree && \
printf '%s\n' '/vbw:fix Investigate a SwiftData save failure during tests.' \
  | ccr code -p --dangerously-skip-permissions --plugin-dir /absolute/path/to/candidate-plugin-checkout
```

Use `printf '%s\n'` instead of `echo` so punctuation and backslashes are preserved in a shell-portable way.

### 8. Prefer inline smoke instructions; use `--append-system-prompt` only when proven compatible

Default to putting the smoke-test constraints directly into the piped prompt text. Some router/provider combinations reject extra system inputs and fail with errors such as `context_management: Extra inputs are not permitted`.

Use inline prompt text first:

```text
Smoke test only. Avoid code edits. Keep output concise. Focus on diagnosis and reporting.
```

For routing-only probes, make the stop condition explicit in the prompt text:

```text
Smoke test only. Stop after choosing skills and mode. Do not modify project files. Keep output concise.
```

Only use `--append-system-prompt` if you already know the active router/provider accepts extra system inputs.

If a run fails with a validation/provider error mentioning extra inputs, `context_management`, or rejected system prompts:
- re-run immediately **without** `--append-system-prompt`
- keep the smoke constraints inline for the rest of that run
- do not treat that failure as evidence about the VBW command itself

### 9. Capture the right evidence

Always capture:
- command exit code
- transcript/project path proving the smoke cwd was the consumer smoke worktree or sandbox

Then capture the claim-matched evidence you actually need:
- **Visible-selection claim** → capture a visible `Skills:` line
- **Activation/logging claim** → capture `.vbw-planning/.skill-decisions.log` deltas
- **Domain-skill claim** → capture task-specific keyword matches when relevant, such as the framework, database, or failure term named in the prompt

#### Standard smoke pattern

```bash
cd /absolute/path/to/consumer-smoke-worktree && \
printf '%s\n' \
  'Smoke test only. Avoid code edits. Keep output concise. Focus on diagnosis and reporting.' \
  '/vbw:research Research a persistence or startup failure during tests.' \
  | ccr code -p --dangerously-skip-permissions \
      --plugin-dir /absolute/path/to/candidate-plugin-checkout
```

#### Visible `Skills:` capture pattern

If plain output does not surface the `Skills:` line, use this dedicated stream-capture mode:

```bash
cd /absolute/path/to/consumer-smoke-worktree && \
printf '%s\n' \
  'Smoke test only. Avoid code edits. Keep output concise. Focus on diagnosis and reporting.' \
  '/vbw:fix Investigate a persistence or schema failure during tests.' \
  | ccr code -p --verbose --dangerously-skip-permissions \
      --plugin-dir /absolute/path/to/candidate-plugin-checkout \
      --output-format stream-json --include-partial-messages
```

Then search the captured output for `Skills:`.

#### Routing-only probe pattern

Use this when you only need mode/skill-selection behavior and do not want the workflow to keep going:

```bash
cd /absolute/path/to/sandbox-repo && \
printf '%s\n' \
  'Smoke test only. Stop after choosing skills and mode. Do not modify project files. Keep output concise.' \
  '/vbw:vibe --execute 1' \
  | ccr code -p --permission-mode plan --dangerously-skip-permissions \
      --plugin-dir /absolute/path/to/candidate-plugin-checkout
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
- **Real consumer repo requires heavy repo-specific setup before the target behavior can complete** → split coverage: use the consumer smoke worktree for provenance/routing/startup and a sandbox repo for command-layer completion behavior.
- **Plain `-p` invocation reports missing input** → switch to stdin and keep it that way.
- **`--append-system-prompt` triggers a validation/provider error** → retry without it and move the smoke constraints inline into the piped prompt.
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
- For completion-path claims, the command actually reached the lifecycle point being claimed; if repo-specific prerequisites blocked earlier, the result is only routing/provenance coverage or an inconclusive completion check.
- The base consumer repo checkout did not become the smoke cwd or collect smoke artifacts.
- Any sandbox use is called out explicitly.
- The plugin repo is not being misrepresented as the smoke-test cwd.
