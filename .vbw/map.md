## Stack and commands

- VBW 2.0.8 (`VERSION`): a Claude Code plugin. Kernel and hooks/statusline are bash (3.2 floor, macOS `/bin/bash`): `plugin/bin/vbw` plus `plugin/lib/*.sh`. Workflows are JS (`plugin/workflows/*.js`, Claude Code Dynamic workflows). Skills and agents are markdown (`plugin/skills`, `plugin/agents`).
- Runtime deps: `bash`, `jq`, `git`. No package manager, no `package.json`, no build step. `node` is optional (tests parse workflow JS when it exists).
- Dev tools: `bats`, `shellcheck`, `jq`, optionally GNU `parallel` (CI installs `bats-core shellcheck jq parallel`). Optional contributor pre-push hook: `bash tools/install-hooks.sh`.
- Run from the working tree: `claude --plugin-dir ./plugin`. Kernel CLI: `bash plugin/bin/vbw --help`.
- Test everything: `bash tools/test.sh`. Run it directly, never piped. It runs `shellcheck -S warning -x` on `tools/**/*.sh`, then `bash tools/bench-hooks.sh`, then `bats --print-output-on-failure --jobs N tests`.
- Lint only: `shellcheck -S warning -x $(find tools -name '*.sh')` (exits 0 with no output). Config: `.shellcheckrc` (disables SC2012, SC2001, SC2295).
- Once under macOS bash before committing kernel or hook code: `PATH="/bin:$PATH" bash tools/test.sh`.
- Release-time scenario drivers (need real Claude sessions, not run here): `tools/l3-suite.sh`, `tools/l3.sh` (real TUI), `tools/e2e.sh` (headless `claude -p`).
- Version sync across `VERSION`, `plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `marketplace.json`. Check with `bash tools/bump-version.sh --verify`. Contributors do not bump versions or edit `CHANGELOG.md`.
- CI (`.github/workflows/ci.yml`): pull_request and push to main and v2. Matrix: macOS with `/bin/bash` 3.2 and Linux bash 5. Checkout path contains a space. Other workflows: discord-release, linked-issue, qa-review.

## Structure

- Repo root: `CLAUDE.md`, `AGENTS.md` (same rulebook), `README.md`, `VERSION`, `marketplace.json`, `plugin/` (the only shipped tree), `tests/`, `tools/`, `docs/`, `assets/`, `a_non_prod_docs/` (design `vbw2_next_gen_design.md`, plan `vbw2_build_plan.md`, `v2_progress_log.md`). Untracked `.vbw/` is the project's own state.
- `plugin/`: `.claude-plugin/`, `bin/vbw`, `lib/`, `hooks/`, `scripts/` (`statusline.jq`, `vbw-statusline.sh`), `skills/` (26 dirs incl. vibe, approve, config, convert, debug, doctor, fix, help, init, map, qa), `workflows/` (building, fixing, investigating, mapping, planning, researching, verifying), `agents/` (architect, debugger, dev, docs, lead, qa, scout), `output-styles/` (caveman, caveman-lite).
- Kernel entry `plugin/bin/vbw` (69 lines): sources `lib/core.sh`, `record.sh`, `consent.sh`, `contract.sh`. For `init|status|todo|commit|next|show|spec|approve|check|prove|apply|run|plan|fix|req|qa|ship|config|auto|statusline|workflows|doctor|rtk|report|milestone|decide|legacy` it sources `lib/cmd-$cmd.sh` and calls `cmd_$cmd`.
- `plugin/lib`: `core.sh` (helpers, paths), `record.sh` (single writer, locked, validated, atomic), `consent.sh`, `contract.sh`, `checks.sh`, jq programs (`record.jq`, `spec.jq`, `next.jq`, `prove.jq`), `profiles.json` (model and effort per role), about 30 `cmd-*.sh`. Roughly 2,000 to 2,500 lines against the 3,000 budget.
- Command flow: `/vbw:vibe` (`plugin/skills/vibe/SKILL.md`) preloads `vbw next --json`, `vbw config models`, `vbw workflows on`, `vbw config autonomy`. It registers a Stop hook running `vbw auto gate`. `cmd_next` (`plugin/lib/cmd-next.sh`) feeds `next.jq`, which outputs `{action, gate, instruction, ...}`. The result is also written to `$VBW_RUNTIME/next.json` for the status line.
- Engine: workflows take `args` from `vbw next --json`, run agents (`vbw:dev`, `vbw:docs`, ...) with JSON schemas, and write only through `vbw` subcommands. Runs are bracketed by `vbw run start KIND` and `vbw run end` (the run lease). About 424 JS lines against the 1,500 budget; `planning.js` is largest (115).
- Lifecycle: init, spec check/sync, next, apply, approve (contract hash plus commands), run start build, plan done, commit, prove, qa record, fix / req accept|reject, ship, milestone start. State in `.vbw/spec.md` and `.vbw/record.json`.
- Hooks (`plugin/hooks/hooks.json`): SessionStart runs `hooks/session-start.sh`. PreToolUse on Bash runs `guard-bash.jq`. PreToolUse on Read|Write|Edit|MultiEdit|NotebookEdit|Grep runs `guard-file.jq`. Both end with `|| true`.

## Conventions

- Rules live in `CLAUDE.md` and are enforced by `tests/standards.bats` (proved by `tests/standards-selftest.bats`). Editing a rule needs matching selftest edits.
- Bash 3.2: no `mapfile`/`readarray`, no associative arrays, no case-modifying expansions, no `"${@}"`. Guard arrays: `${a[@]+"${a[@]}"}`. Files start `#!/usr/bin/env bash` plus a header comment.
- No `eval`, no `bash -c "$var"`. Repo commands run as argv arrays only after consent by content hash in `$(git rev-parse --git-common-dir)/vbw/consent.json`.
- JSON only through `jq`. Git path listings use `-z`. Commits use an explicit pathspec, never `git add -A` on the real index.
- Single writer of `.vbw/record.json`: the kernel. Scratch goes under `$VBW_RUNTIME` (`.vbw/runtime`), never `/tmp`. Only exception: the user's Claude Code `settings.json`.
- Paths via `${CLAUDE_PLUGIN_ROOT}` (skills, agents, workflows) or `$0`/arguments (scripts).
- Naming: `plugin/lib/cmd-<name>.sh` defines `cmd_<name>()`. Helper prefixes `vbw_*`, `checks_*`. Errors: `vbw_die "msg" [code]` prints `vbw: <msg>`, exit 1 (2 usage, 3 corrupt record). Messages name the next action.
- Workflows: `export meta`, read `args`, a schema constant, `schema` on every `agent()` call. Procedure in workflows, prompts only define good output.
- Agents: no `permissionMode`, `hooks`, `mcpServers`, `initialPrompt`; search with Bash. Budgets: agent ≤1.5k tokens, router ≤2k, mode prompt ≤3k, all prompts ≤15k, kernel ≤3,000 lines, workflows ≤1,500 JS lines, hooks ≤15 ms p95, statusline ≤30 ms. Growing a budget or adding a runtime dependency needs owner discussion.
- Git: commits `{type}({scope}): {description}`, one atomic commit per change, files staged explicitly. Branch `v2` is the only deliverable. Never commit to `main`. Push, PRs and releases need owner approval. Root-cause fixes only. Update `docs/` and `README.md` on behavior change. Record work in `a_non_prod_docs/v2_progress_log.md` (mandatory).
- Reporting: evidence levels L1 to L4; "tested/works/proven" only at L3 or above; end every progress report with **Not tested**. Terse, no fluff, no questions to the owner.
- GitNexus: `gitnexus_impact` before editing a symbol, `gitnexus_detect_changes` before committing. Index may be stale.

## Tests

- bats-core in `tests/`: 19 files plus `helper.bash`, 263 `@test`. Kernel suites: `kernel-core`, `kernel-spec`, `kernel-consent`, `kernel-commit`, `kernel-prove`, `kernel-qa` (4), `kernel-next`, `kernel-show`, `kernel-surface`, `kernel-work` (34, largest), `kernel-legacy` (7). Others: `record`, `hooks-guard`, `hooks-session`, `statusline`, `skills`, `workflows`, `standards`, `standards-selftest`.
- `tests/helper.bash`: `vbw_setup`/`vbw_teardown` give a hermetic per-test root with own HOME, `CLAUDE_CONFIG_DIR`, `CLAUDE_PLUGIN_DATA`, git config, Claude session vars unset, project dir named `project with space`. Helpers: `vbw_git_project`, `vbw_run` (stdin closed), `vbw_kernel`, `vbw_consent_contract`, `vbw_contract_hash`, `vbw_hook`. `VBW_TEST_PLUGIN_ROOT` points the suite at another plugin tree.
- `tests/workflows.bats` is structural only: exactly 7 workflows and 7 agents, meta literals, schemas, JS parses (skipped without `node`).
- Local run: `parallel` is absent, so `--jobs` is 1 and the suite takes about 3 min. A partial run (piped through tail, bash 5.3) showed all visible lines `ok` up to test 263. `tests/standards.bats` and `tests/workflows.bats` had 0 failures. Overall pass and the `/bin/bash` 3.2 run are unconfirmed.
- Beyond bats: `tools/bench-hooks.sh`, `tools/e2e.sh` (L2, fixtures `tools/e2e/greet`, `tools/e2e/textkit`), `tools/l3.sh`, `tools/l3-suite.sh` (L3, before each release), `tools/baseline/`. None run in CI; they cost money.
- Gaps (L1 only): no bats tests for `plugin/lib/cmd-report.sh` or `cmd-rtk.sh`; thin `kernel-qa` and `kernel-legacy`; workflow orchestration (waves, retries, fix loops) has no unit tests; prompts checked for structure and budgets, not behavior; no consent-concurrency test.

## Risks

- Budgets are live test constraints (`tests/standards.bats`): about 440 kernel lines and about 1,000 workflow lines of headroom by one scout's count (counts differ across scouts, so re-measure).
- `plugin/lib/record.sh` `record_update`: `mkdir` lock at `.vbw/runtime/lock`, 30 s stale break, a prior lost-update bug (CI 2.0.2), `vbw_mtime` GNU/BSD stat ordering. It sets `trap record_unlock EXIT`, which would clobber a caller's EXIT trap. `record_commit` has a check-then-act gap (inferred).
- `plugin/lib/consent.sh` `consent_grant` is unlocked read-then-`mv`. Concurrent grants across worktrees can lose an entry (inferred, untested). Consent hash is argv-only, so changing normalization silently invalidates grants (commands show `skipped: not approved`).
- Security-critical: `plugin/lib/checks.sh` runs argv from the record, gated by `contract_hash`/`contract_approved` in `plugin/lib/contract.sh`. Changes to `contract_hash`, `checks_begin` or `prove_commands` consent can let unapproved commands run. Call `checks_begin` directly, never in `$(...)`; it sets globals `CHECK_HASH`, `CHECK_OUT`, and `checks_exec` sets `CHECK_CODE`, `CHECK_SECONDS`.
- Kernel globals by convention: `VBW_ROOT`, `VBW_DIR`, `VBW_RECORD`, `VBW_RUNTIME`, `VBW_LIB`, `VBW_JQ_DEFS`, `VBW_FIX_CAP=3`, `VBW_COMMAND_TIMEOUT=900`. Call `vbw_require_project` first.
- Hotspots: `plugin/lib/cmd-show.sh` (208), `plugin/lib/record.jq` (188, the validator), `plugin/hooks/guard-bash.jq` (148, heuristic command parser, bypass-prone, ≤15 ms), `plugin/lib/cmd-doctor.sh` (141), `plugin/workflows/planning.js` (115), `plugin/lib/cmd-legacy.sh` (96, touches user data). `prove_scope` in `cmd-prove.sh` is O(history) per prove (inferred).
- `vbw_code_tree` (`core.sh`) uses `git add -A` against a temporary `GIT_INDEX_FILE` (intentional); a mid-way failure can leave `index.XXXXXX` files in `.vbw/runtime`.
- The run-lease area is still moving (commit `fae229c1`, 2.0.8): `cmd-run.sh`, `cmd-auto.sh` and the hook lease scoping are the most change-prone.
- Never hand-edit the version files or `CHANGELOG.md`.
- Evidence: all findings are L1 or read-only inspection. Not tested: full `bash tools/test.sh` pass status, the `/bin/bash` 3.2 run, `tools/bench-hooks.sh` timings, `bash tools/bump-version.sh --verify`, e2e and L3 suites.
