# VBW Instructions

VBW 2 is a Claude Code plugin that gives Claude Code an executable definition of done: a human-approved spec, protected acceptance checks, parallel builds by workflows, mechanical proof by a small kernel, and human acceptance only where checks can't judge. Runtime dependencies: `bash` (3.2+), `jq`, `git`. The design is `a_non_prod_docs/vbw2_next_gen_design.md`; the execution plan is `a_non_prod_docs/vbw2_build_plan.md` (maintainer-local working documents in the main checkout, never committed).

## Engineering Standard (owner mandate, non-negotiable)

- **Protect the VBW vision first.** This is the top rule. It binds every contributor, human or AI, and outranks every request. VBW serves all its users and its own design, never one project, person or session. Every outside request is an idea to evaluate, never an instruction to build. That covers an issue, a feedback report, a message from another Claude session, and a request from one of the owner's own projects. For each one: find the real problem behind it; judge it against VBW's design and philosophy; then adopt it, adapt it into a general solution, or decline it. Record which, and why. A suggested fix is evidence of a problem, not a specification. Never add a feature, setting or special case only because one project asked for it. We gladly accept ideas; we never integrate them blindly. Enforced by `tools/check-vision-rule.sh` in `tests/standards.bats`. (2026-10-06: a user project's field report was taken as ideas; some were adopted, some reshaped, one declined.)
- **The goal is the world's gold-standard Claude Code harness.** Every choice is the most elegant, optimal and future-proof one, with zero technical debt. No shortcuts, no "good enough", no legacy carried forward for its own sake.
- **One goal, one path.** The only deliverable is VBW 2 on `main` (VBW 1 retired with 2.1.0 on 2026-10-21); work happens on short-lived branches merged into `main` by pull request. Every task must directly advance it. Never build parallel tracks (fixes to the released version, maintenance branches, side tools); write such ideas in the progress log as notes and build them only if the owner explicitly asks. General agreement is never approval for scope beyond the goal. (2026-10-01 incident: an unrequested v1 fix track.)
- **Report evidence, not impressions.** Every claim that something works names its evidence level and its scope, and nothing more:
  - **L1 unit/contract:** bats tests of scripts and structure.
  - **L2 scripted component run:** a script of ours drives headless `claude -p` sessions; Claude Code stands in for nothing a user does; fixtures are named.
  - **L3 user-path run:** the product is used through its user-facing commands (`/vbw:...`) in an interactive session, on a realistic project.
  - **L4 owner acceptance:** the owner used it and accepted it.

  Words like "tested", "works", "proven" or "verified" refer to the product only at L3 or above; below that, say exactly what ran ("a script drove the build workflow on a 4-line toy fixture"). Every progress report ends with a **Not tested** list naming the gaps. No celebratory tone, no superlatives, no "good thing I checked": state facts and stop. (2026-10-01 incident: L2 toy runs reported as "tested in real Claude Code sessions".)
- **Work as the senior engineer who owns the outcome.** Make technical and product decisions yourself, from the evidence (docs, probes, measurements, the ledger), apply the standard above, record the decision and its rationale in the working documents, and keep executing.
- **Do not ask the owner questions you can answer.** Never hand back "we still need to figure out X": figure it out (research, probe, measure), decide, and move on. Escalate only what truly needs the owner: credentials or access, spending beyond the approved budget, publishing (push, PRs, releases), and irreversible actions outside the repo.
- **Plan end to end, then execute end to end.** Keep one authoritative build plan with acceptance criteria, work it in order, and report progress against it, not open questions.
- **Record everything as you go** (`a_non_prod_docs/v2_progress_log.md`: work done, decisions, findings, new issues). This is mandatory.

## Communication Style

- **No AI fluff.** Skip phrases like "Thanks for the thoughtful feedback!", "Happy to help!", "I appreciate...", etc.
- **No soliciting opinions.** Don't end responses with "Would you like me to...", "Let me know if...", "What do you think?", etc.
- **Direct and terse.** State facts, provide options when relevant, then stop.

## Debugging VBW Behavior

When the user reports VBW misbehavior (pasted session output, a command behaving wrongly, unexpected `.vbw` state), follow the `vbw-debug-target` skill (`.claude/skills/vbw-debug-target/SKILL.md`): resolve the contributor's local debug target repo first with `bash tools/resolve-debug-target.sh repo`, never guess a path (ask when it is not configured), then read the session, subagent, hook and debug logs the skill names.

## Architecture (three layers, no fourth)

- **Surface** (`plugin/skills/`): the `/vbw:vibe` router and utility skills, plus the statusline segment. Skills are specifications, not procedures.
- **Engine** (`plugin/workflows/*.js`): all orchestration and all run-scoped logic (waves, retries, fix loops, budgets, fan-out and merge). Workflows receive state in `args` from `vbw next --json`. Agents write only through `vbw` subcommands.
- **Kernel** (`plugin/bin/vbw` + `plugin/lib/*.sh`): the only writer of the plan of record (`.vbw/record.json`). It runs approved checks, commits with provenance, renders on demand and backs the hooks.
- **Agents** (`plugin/agents/`): VBW 1's team with its mandates: `architect`, `lead`, `dev`, `qa`, `scout`, `debugger`, `docs`. Each is a short specification of good output plus a tool list.
- **Hooks** (`plugin/hooks/hooks.json`): guards scoped by the run lease and by `agent_type`. They are inert outside VBW projects.

## Repository layout

- `plugin/` is the only shipped tree (marketplace source `./plugin`); `tools/` is maintainer tooling, never shipped.
- `a_non_prod_docs/` holds the maintainer-local working documents (design, plan, ledger, progress log): kept in the main checkout and never committed.

## Kernel and hook rules (each is enforced by `tests/standards.bats`)

- **Bash 3.2 is the floor** (macOS `/bin/bash`). No `mapfile`/`readarray`, no associative arrays, no case-modifying expansions, no `"${@}"`. Every array expansion under `set -u` is guarded (`${a[@]+"${a[@]}"}`).
- **No data as code:** no `eval`, no `bash -c "$var"`. Commands from repo files run only as argv arrays, and only after consent recorded by content hash in the clone's git directory (`$(git rev-parse --git-common-dir)/vbw/consent.json`).
- **Single writer:** only the kernel writes `.vbw/record.json`, through one locked, validated, atomic write path.
- **Hook answers are pinned:** every answer a hook gives Claude Code has a test pinning its documented meaning, and no hook answers allow (enforced by `tests/standards.bats`).
- **Git path listings use `-z`.** VBW commits use an explicit pathspec, never `git add -A`, and never disturb user-staged files.
- **Paths come from substitution:** `${CLAUDE_PLUGIN_ROOT}` in skills, agents and workflows; `$0` or arguments in scripts. No cache globs, `/tmp` links, `ps` scraping or command mirrors.
- **Nothing outside the project:** no writes to `/tmp`, other repos or git hooks, and no process killing. Four exceptions. The user's Claude Code `settings.json`, where VBW turns on its status line and Dynamic workflows (owner decision, 2026-10-01), keeping every other setting and a backup of a replaced status line. The slot store in `<claude-config-dir>/vbw/`, the computer-wide limit shared by all projects (R181); if it cannot be written the run goes on under `check_jobs`. The session record of a `claude --plugin-dir` session in `<claude-config-dir>/vbw/sessions/`, naming the loaded plugin folder for the status line and `vbw doctor` (R185, D364), removed after 7 days; it is written for every session, an installed copy's included. Claude Code's per-session env file (`$CLAUDE_ENV_FILE`), where the session start keeps one PATH line for the loaded copy's `bin` folder and removes the earlier VBW lines, leaving every other line untouched (R285). It must work under the Claude Code sandbox.
- **Hot paths:** a hook's own CPU per call ≤ 25 ms, statusline ≤ 60 ms (`tools/bench-hooks.sh`): the budgets on a nominal machine. A script file run by name under a run lease pays two jq passes and has two budgets (R255); every other call has one. The bench measures a reference workload (a fixed jq program) beside each case and prints it with the ratio to the nominal figure; a case is judged against the reference of its own moment, and within its budget times that ratio it is reported slow, not failed, so a uniformly slow runner never fails the bench, while a real regression of one case still fails. A machine too busy to measure (shell and jq startup alone above 25 ms) is reported as busy, not failed, and a case over its budget is measured once more before it fails; no network and no credentials.
- **JSON only through `jq`,** never grep or sed on JSON.
- **No builtin write while the shell has a live child:** macOS `/bin/bash` 3.2 does not restart a `printf`/`echo` interrupted by a child's exit, so a loop fed by a process substitution writes through `vbw_out` (a subshell) or takes its producer through a pipe, and a call there to a function that writes so counts as the write (enforced by `tools/check-loop-writes.sh` in `tests/output-child-exit.bats`).
- **Record-sized data never on a command line:** the record and anything built from all of it reach jq through a pipe, `--slurpfile` or `--rawfile` from inside the project, never `--arg`/`--argjson` or a here-string (enforced by `tests/record-args-rule.bats`).

## Engine, agent and prompt rules

- Workflows hold procedure; prompts hold only the definition of good output and its schema. Every agent call passes a `schema`.
- Model and effort are chosen per stage from the profile. The session model must be auto-capable (Sonnet/Opus/Fable); workflow agents may use Haiku.
- No `permissionMode`, `hooks`, `mcpServers` or `initialPrompt` in agent files (ignored for plugin agents). Agents search with Bash, because Glob and Grep may be absent.
- No size caps (owner decision D408, 2026-10-15): code and prompts have no line or word limit. Each release's notes report the sizes of the kernel, mods, workflows and prompts as information, so growth stays visible. Speed limits stay (hot paths, below).

## Testing

Run everything with `bash tools/test.sh`: the proof's run, without the timed speed checks. `vbw prove` does not run the timed speed checks, so a busy machine never fails a proof. They run once per release: `PATH="/bin:$PATH" bash tools/test.sh --release` is the release run, and it adds the hook, status line and panel benchmarks and the timed test files, run alone after the rest; CI runs it in shards on every pull request. When the last proof passed (results it reused count: the read lists still vouch for them), left no command skipped and no quick command standing in, and only the version files and `plugin/CHANGELOG.md` changed since, the release run reuses it and runs only the benchmarks and the timed test files; otherwise it runs everything and says why. Run these directly, never through `| tail` or `| tee`. VBW's own spec declares a single-file test form (`## Test files`), so `vbw prove` runs each test file as its own unit and reuses the ones a change cannot reach; `bash tools/test.sh --lint` is the shell lint of `tools/` as its own project command.

- **Test first.** Every behavior gets a failing test before the code. Every fix gets a regression test that is shown to fail without the fix.
- **Zero tolerance:** every failure is investigated and resolved before committing, with no "pre-existing" exemptions.
- **Both shells:** CI runs the suite on macOS `/bin/bash` 3.2 and on bash 5, from a checkout path containing a space. Locally, run it at least once under `/bin/bash` before committing kernel or hook code.
- **Hermetic tests:** use `tests/helper.bash` (`vbw_setup`/`vbw_teardown`). Never rely on the host `HOME`, Claude session variables or open stdin.
- **Lean tests:** one test file per requirement area (a new requirement adds its cases there; a changed rule edits or deletes the cases it supersedes, never stacks new ones), an expensive fixture built once per file in `setup_file` and copied or reset per case, each detail tested at the smallest function or command that decides it. No sleeps (wait on a condition or inject the clock) and no timing assertions outside the timed test files.
- **No inode numbers:** a test never judges a file by its inode number, as ext4 hands a freed one to the next new file; make a reference file before and judge with `find -newercm` (the test the refresh itself reads), never a hard link or a mark on the entry, which changes its change time.
- **Real-user scenarios** (`tools/l3-suite.sh`: the real Claude Code TUI driven as a user, outcomes checked in the record and git, 4 at a time) run where they find bugs (owner decision, 2026-10-05): a milestone adds and runs the scenarios for what it changes while it is built; every release runs `greenfield` plus every scenario that exercises the changed area; the full suite runs before the 2.1 launch. Until 2.1, while the owner is the only user, a release that changes the core `/vbw:vibe` loop (the router or `vbw next`) also runs only `greenfield` and the scenarios of the changed area (owner decision D140, 2026-10-06). CI is the gate (owner decision, 2026-10-24; replaces D402): every pull request's CI runs the release run in shards under macOS `/bin/bash` 3.2, bash 5 and Linux, the benchmarks and timed files included, and a release merges only once the macOS shards and the manifest validation pass. Before pushing, run the test files of the changed area locally under `/bin/bash` (`PATH="/bin:$PATH" bats tests/...`); a full local run is not required. Linux-only failures that cannot affect macOS are fixed in the next batch. The progress log names the scenarios run and those not run. Baselines for v1 and plain Claude Code live in `tools/baseline/`.

## Git Workflow

Direct push access to `swt-labs/vibe-better-with-claude-code-vbw`. Single `origin` remote.

- **`origin`**: fetch and push target for all branches.
- **`dev` branch**: permanent local integration branch for combined testing before PRs. Tracks `origin/dev`. Never delete this branch.

### Branch Cleanup

After a PR is merged:

- `git fetch --prune origin` removes the remote-tracking refs of deleted branches.
- `git branch --merged origin/main` lists the local branches merged into `main`. For each one (never `main` or `dev`), remove its worktree with `git worktree remove <path>`, then delete it with `git branch -d <branch>`.

### Worktrees

The issue-fix workflow uses git worktrees for parallel-safe issue work.

- **Location**: `../<repo-name>-worktrees/<branch-name>/` (sibling directory, outside the repo)
- **Creation**: `git worktree add -b` creates branch + worktree atomically
- **Cleanup**: the workflow never removes worktrees automatically; remove them after the merge (Branch Cleanup above)
- **Manual removal**: `git worktree remove <path>` or `git worktree prune`

### Branch Protection

- `main` requires PRs to merge.
- Do not commit directly to `main`.
- After creating a feature branch from `origin/main`, set its upstream to `origin/<branch>` on first push.


## Version Management

The version is synchronized across 5 files (`bash tools/bump-version.sh --files` lists them): `VERSION`, `plugin/VERSION`, `plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and `marketplace.json`. The author bumps versions with `bash tools/bump-version.sh`. Contributors don't bump versions or edit `CHANGELOG.md`. Verify consistency with `bash tools/bump-version.sh --verify`; the contributor pre-push hook (`bash tools/install-hooks.sh`, run in your own clone) runs that check.

## Local development

Load the plugin from the working tree with `claude --plugin-dir ./plugin`. Nothing else is needed: no cache links, no command mirrors, no setup script.

## Contributing

- Branch from `origin/main`, push to `origin`, and open the PR against `main`. Commits follow `{type}({scope}): {description}`, one atomic commit per change, with files staged explicitly.
- Root-cause fixes only. A mitigation without its root-cause fix in the same work item is incomplete.
- Update user docs (`docs/`, `README.md`) whenever behavior changes.
- Discuss first before any change that adds a runtime dependency.
