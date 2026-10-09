# Contributing to VBW

`AGENTS.md` (also loaded as `CLAUDE.md`) is the authoritative rulebook: engineering standard, architecture, kernel rules, testing. This page covers setup and process.

## The first rule: protect the VBW vision

VBW is built for all its users, around one design. It is not built for any single project. Every request is an idea to evaluate, never an instruction to build. That includes your own issue, a feedback report from a project that uses VBW, and a request from an AI session. We gladly accept ideas; we never integrate them blindly.

Before you propose or build a change:

1. **Name the real problem.** What goes wrong, for whom, and how often? A suggested fix is a clue to the problem, not the answer.
2. **Check it against the design.** Does the solution fit VBW for everyone, or only for the project that asked?
3. **Decide and say why:** adopt it, adapt it into a general solution, or decline it. Write the reason in the issue or the pull request.

A feature, setting or special case that only one project needs will be declined, however well it is built. The full rule is the first item of the Engineering Standard in `AGENTS.md`.

## Prerequisites

- Claude Code with **Dynamic workflows** enabled (`/config`)
- `bash` (macOS `/bin/bash` 3.2 is supported and tested), `jq`, `git`
- For tests: `bats-core`, `shellcheck`; optional `parallel` for parallel runs

## Local development

```bash
git clone https://github.com/swt-labs/vibe-better-with-claude-code-vbw.git
cd vibe-better-with-claude-code-vbw
bash tools/install-hooks.sh          # contributor pre-push check (version files in sync)
claude --plugin-dir ./plugin         # run VBW from your working tree, in any project
```

There is no setup script, no cache link and no command mirror. `--plugin-dir` loads the plugin in place.

## Tests

```bash
bash tools/test.sh                   # shellcheck on tools + the full bats suite
PATH="/bin:$PATH" bash tools/test.sh # the same under macOS /bin/bash 3.2
bash tools/test.sh --shard 2/4       # share 2 of 4, the way CI's macOS jobs run it
bash tools/test.sh --shard 2/4 --list # show that share without running it
```

A new test file needs no list edit: shares are worked out from `tests/*.bats` on every run.

Write the failing test first. Fixes need a regression test shown to fail without the fix. `tests/standards.bats` encodes the engineering rules, so a change that breaks one fails CI.

## Evals and baselines

- `claude plugin eval ./plugin` runs the plugin's eval cases (sandboxed, and they cost model usage).
- `tools/baseline/` measures the released VBW and plain Claude Code on the same tasks (see its README).

### Set your local debug target repo

VBW debugging docs use a **private local pointer file** instead of hard-coding a maintainer's consumer repo path.

Preferred setup is the clone-shared Git common-dir file:

```text
$(git rev-parse --git-common-dir)/info/vbw-debug-target.txt
```

In a standard non-worktree clone, that usually resolves to:

```text
.git/info/vbw-debug-target.txt
```

Set it from the VBW repo root with:

```bash
mkdir -p "$(git rev-parse --git-common-dir)/info"
printf '%s\n' '/absolute/path/to/your-test-repo' > "$(git rev-parse --git-common-dir)/info/vbw-debug-target.txt"
```

This file stays private because it lives under the clone's Git metadata instead of the tracked working tree. All worktrees created from the same clone share it automatically.

Legacy per-checkout fallback:

```text
.claude/vbw-debug-target.txt
```

That legacy file remains supported and gitignored, but it only applies to the checkout/worktree where you create it.

Resolution order for debug-target lookup:

1. `VBW_DEBUG_TARGET_REPO` env var (one-off override, absolute path only)
2. `$(git rev-parse --git-common-dir)/info/vbw-debug-target.txt` in the current clone (preferred persistent local config, shared across worktrees)
3. `./.claude/vbw-debug-target.txt` in the current checkout/worktree (legacy fallback, absolute path only)
4. `<claude-config-dir>/vbw/debug-target.txt` (user-global fallback, absolute path only; `<claude-config-dir>` is resolved by `tools/resolve-claude-dir.sh`: `CLAUDE_CONFIG_DIR` if set, else `$HOME/.config/claude-code` when that directory exists, else `$HOME/.claude`)

Relative paths are rejected so the resolver behaves the same no matter which directory calls it.

Useful checks:

```bash
bash tools/resolve-debug-target.sh repo
bash tools/resolve-debug-target.sh planning-dir
bash tools/resolve-debug-target.sh claude-project-dir
```

If the resolver exits non-zero, configure one of the sources above before debugging VBW behavior.

Root instructions in this repo have one canonical source: `AGENTS.md`. The tracked root `CLAUDE.md` is a symlink to `AGENTS.md` for Claude Code compatibility.


## Pull requests

- Branch from `origin/main`. Commits use `{type}({scope}): {description}`, staged explicitly.
- Fill in the PR template (What / Why / How, plus testing).
- CI runs from a path with a space and validates the plugin manifests. The suite runs three ways:
  - macOS `/bin/bash` 3.2: four machines at once, each running its share (`--shard K/4`). In each share the timing-sensitive files run last, alone. Share 1 also runs the shellcheck lint and the benchmarks.
  - Linux bash 5 (two jobs, Ubuntu latest and 26.04): each runs the full suite.
  - A failing share fails CI.
- What a push runs. The first CI step, "Decide what to test" (`tools/ci-scope.sh`), compares the push with the previous tip and picks one of three:
  - **Full suite:** any change to `plugin/`, `tools/`, `docs/`, root documents, version files, `.github/`, test helpers or fixtures (anything under a `tests/` subfolder), or any path CI does not recognise. A new branch, a force push or a rewritten history also runs the full suite, because there is no safe previous tip to compare with.
  - **Only the changed test files:** when the only changes are top-level `tests/*.bats` files. Deleted files are not run.
  - **No tests:** when the only changes are `.vbw/record.json`, `.vbw/spec.md` or saved test results. Every job still shows success.
  - Saved results folders come from the spec's Test results section. CI trusts only a folder named in the record both before and after the push, so a push cannot name a new folder to skip its own files.
  - To see what CI chose and why, open the run log and read the "Decide what to test" step: it prints `scope=full|some|none`, the files and a plain-language `reason`. Run `bash tools/ci-scope.sh BASE HEAD` locally for the same answer.
- Don't bump versions or edit `CHANGELOG.md`: the maintainer does that at release time (`tools/bump-version.sh`).

## Reporting bugs

Use the bug report template: the `/vbw:*` command involved, reproduction steps, environment (Claude Code version, OS, shell), and the output of `/vbw:doctor`.

## License

MIT (see `LICENSE`).
