# Copilot cloud agent instructions for VBW

## Start here
- Read `README.md` first, then `CONTRIBUTING.md`, then the relevant files under `commands/`, `scripts/`, `testing/`, `hooks/`, `templates/`, or `references/`.
- This repo is a Claude Code plugin implemented mostly as bash plus command markdown. There is no normal app build; most changes are to shell scripts, slash-command markdown, hook wiring, templates, and tests.
- Keep changes surgical. Many behaviors are enforced by contract tests that grep for exact phrases, tool names, filenames, and command structure.

## Repo shape
- `commands/*.md`: slash-command definitions with YAML frontmatter. Preserve frontmatter shape, explicit `name: vbw:*`, and the repo's direct/dry tone.
- `scripts/*.sh` and `scripts/lib/*.sh`: runtime logic. Prefer reusing existing helpers instead of adding new one-off patterns.
- `hooks/hooks.json`: plugin hook wiring. Hooks must degrade gracefully; they should not break a Claude Code session.
- `testing/` and `tests/`: contract checks and bats coverage. If you change behavior, inspect the matching `testing/verify-*.sh` file before editing.
- `.claude-plugin/plugin.json`, `VERSION`, `.claude-plugin/marketplace.json`, and `marketplace.json`: keep versions aligned only when intentionally doing a release/version task. Do not bump versions for ordinary fixes.

## Working conventions
- Prefer bash and existing repo utilities. Do not introduce Node/Python/Ruby tooling or new dependencies unless the task explicitly requires it.
- Preserve the plugin-root resolution pattern already used in command markdown and hooks. In shell blocks, do not assume `${CLAUDE_PLUGIN_ROOT}` exists as a normal environment variable; reuse the existing `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}` / `ensure-plugin-root-link.sh` pattern instead of inventing a new resolver.
- When editing command markdown, remember the command files are LLM-consumed artifacts. Small wording changes can break tests or behavior.
- If you change command or hook behavior, search `testing/` for the corresponding contract before editing. The test usually documents the intended invariant better than a quick skim of the implementation.
- Keep the repo zero-dependency in spirit: portable bash, `jq`, `git`, and the existing test tools.

## Validation
- Primary local verification entrypoint: `bash testing/run-all.sh`
- Shared lint entrypoint: `bash testing/run-lint.sh`
- CI parity notes:
  - `testing/run-all.sh` expects `jq`, `shellcheck`, and `bats`.
  - CI runs lint, contract checks, bats shards, and serial bats separately; see `.github/workflows/ci.yml`.
- For command or shell changes, also run the most relevant targeted `testing/verify-*.sh` script(s).

## Known onboarding quirks / errors encountered
- `bash testing/run-all.sh` currently fails in a fresh environment if `bats` is missing, even when lint and contract checks pass. Workaround: install `bats-core` before relying on full CI-parity local verification, or at minimum run the relevant non-bats checks explicitly.
- `bash testing/verify-statusline-qa-lifecycle.sh` currently exits with status `141` after printing passing output because `run_statusline_l1()` pipes `vbw-statusline.sh` into `head -1`, which can trigger an expected SIGPIPE. Workaround: treat exit `141` as this known standalone-test quirk, or run the check via `testing/run-all.sh` and inspect the emitted output.
- This repo's `.gitignore` previously ignored `.github/copilot-instructions.md`. If you update this file again, make sure it remains explicitly unignored so the onboarding instructions stay tracked.
