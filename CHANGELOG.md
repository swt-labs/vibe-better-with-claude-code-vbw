# Changelog

All notable changes to VBW will be documented in this file.

## [1.21.31] - 2026-02-19

### Added

- **`skills`** -- Installation scope selection step (project vs global) when installing skills. (PR #91 by @Aperrix)
- **`discovered-issues`** -- Pre-existing test failures surfaced as "Discovered Issues" across `/vbw:fix`, `/vbw:debug`, `/vbw:qa`, and `/vbw:verify` instead of being silently dropped. New DEVN-05 deviation code for dev agent. (PR #99 by @dpearson2699)
- **`debugger-report`** -- New `debugger_report` schema type replacing incorrectly-shaped `blocker_report` usage by the Debugger agent. Role Authorization Matrix updated. (PR #99 by @dpearson2699)
- **`state-persistence`** -- Root STATE.md content (todos, key decisions, project-level notes) now persists across milestone shipping. New `migrate-orphaned-state.sh` and `persist-state-after-ship.sh` scripts. (PR #103 by @dpearson2699)

### Changed

- **`bootstrap`** -- Codebase mapping bootstrap across all agents now uses META.md gating and "whichever exist" qualification to avoid wasted tool calls. Compaction re-reads codebase files. (PR #99 by @dpearson2699)
- **`bootstrap`** -- Key Decisions section removed from CLAUDE.md template. Existing decision rows migrated to STATE.md. Deprecated section handling added. (PR #93 by @dpearson2699)

### Fixed

- **`help`** -- CLAUDE_CONFIG_DIR fallback added to backtick expansion in help.md for non-standard config paths. (PR #101 by @halindrome)
- **`hooks`** -- Circuit breaker added to `task-verify.sh` preventing infinite loop when failed verification re-triggers itself. Expanded stop words in session-stop.sh. (PR #95 by @dpearson2699)

## [1.21.30] - 2026-02-17

### Added

- **`rolling-summary`** -- New `scripts/compile-rolling-summary.sh` compiles prior SUMMARY.md files into a condensed `ROLLING-CONTEXT.md` (<200 lines). Integrated into `compile-context.sh` and `cache-context.sh` hash. Feature-flagged via `v3_rolling_summary` config. Archive and execute modes call it automatically.
- **`correlation-id`** -- `scripts/log-event.sh` auto-resolves `correlation_id` from `VBW_CORRELATION_ID` env var or `.execution-state.json`. Execute protocol generates UUID at phase start. Zero caller changes required — all shell callers get correlation threading for free.

### Changed

- **`readme`** -- Updated token efficiency section with v1.21.30 analysis (17% per-request reduction). Consolidated comparison table. Linked all 5 analysis reports. Fixed agent count (6→7). Trimmed Manifesto section.
- **`statusline`** -- Halved progress bar widths for compact display.
- **`agent-start`** -- Added tmux pane detection for PID→pane_id tracking.
- **`agent-stop`** -- Added tmux pane auto-close on agent stop.
- **`session-stop`** -- Added `.agent-panes` to cleanup list.

## [1.21.29] - 2026-02-17

### Added

- **`shutdown-protocol`** -- Agent shutdown request/response schema and handlers for all agents. Message types `shutdown_request`/`shutdown_response` added to `message-schemas.json`. Agents gracefully terminate on orchestrator request. 4 rounds of QA hardening. (PR #90 by @dpearson2699)
- **`codebase-mapping`** -- Bootstrap codebase mapping for dev, qa, lead, and architect agents. Agents now reference PATTERNS.md, DEPENDENCIES.md, ARCHITECTURE.md, and CONCERNS.md from `.vbw-planning/codebase/` when available. (#78, #79, #80, #81 by @dpearson2699)
- **`list-todos`** -- New `/vbw:list-todos` command to browse and act on pending todos with milestone context resolution.
- **`config`** -- Effort-aware agent `maxTurns` resolution. Unlimited turns via `0`/`false`. Documented in README.

### Changed

- **`todos`** -- Migrated from `### Pending Todos` to flat `## Todos` structure. Todo extraction delegated to `list-todos.sh` for token efficiency.
- **`vibe`** -- Scout returns findings to orchestrator instead of writing files directly. Add/Insert Phase modes now load codebase mapping. Strengthened Lead shutdown HARD GATE with compaction-resilient verification and pre-chain checks.
- **`execute`** -- Post-summary improvisation blocked with STOP + Discovered Issues pattern. Post-shutdown verification gate added for Pure-Vibe loop safety.
- **`readme`** -- Updated hook diagram for SubagentStart/Stop hardening, added Agent Turn Limits section.

### Fixed

- **`hooks`** -- Isolation marker lifecycle causing false blocks. Compaction and session-stop marker races. CLAUDE_PLUGIN_ROOT fallback for `--plugin-dir` installs. Role alias normalization and concurrency hardening for agent-start/stop. YAML frontmatter context required for expanded VBW command detection. Security-filter path-based root resolution with stale TTL. Commit keyword matching skipped for role-only task subjects. Docs role added to lifecycle hook matchers and token budgets. 14 regression tests added.
- **`hooks`** -- Missing `hookEventName` in session-start.sh and blocker-notify.sh. Skip commit gate for `[analysis-only]` tasks.
- **`agents`** -- Lead shutdown gates strengthened to prevent tmux pane accumulation. PR review diff-vs-repo rule added to CLAUDE.md.
- **`commands`** -- CLAUDE_PLUGIN_ROOT resolution in model-executed contexts. Slug validation and milestone resolution alignment in pause.md.

## [1.21.28] - 2026-02-16

### Added

- **`debugger`** -- Codebase mapping bootstrap now references PATTERNS.md and DEPENDENCIES.md in addition to ARCHITECTURE.md and CONCERNS.md. Compiled context includes dynamic "Codebase Map Available" hint section for debugger role. Cache invalidation when mapping files change. (PR #77 by @dpearson2699)
- **`debug`** -- Codebase bootstrap instruction added to both Path A (team) and Path B (single) debugger task prompts. (PR #77 by @dpearson2699)

### Fixed

- **`statusline`** -- Replace `tr` with `sed` for UTF-8 progress bar characters on Linux. GNU `tr` corrupts multi-byte characters (█ ░ ▓) by processing byte-by-byte.

## [1.21.26] - 2026-02-16

### Added

- **`discussion-engine`** -- Unified discussion engine replacing three competing subsystems (bootstrap discovery, phase discovery, phase discussion). One engine, three entry points (`/vbw:vibe`, `/vbw:vibe --discuss N`, `/vbw:discuss N`). Auto-calibrates between Builder and Architect modes from conversation signals. Generates phase-specific gray areas instead of keyword-matched templates. ~1095 lines removed, ~180 lines added.
- **`discuss`** -- New `/vbw:discuss [N]` standalone command for explicit phase discussions.
- **`agent-health`** -- New agent health monitoring system with start/stop/idle/cleanup/orphan-recovery subcommands, lifecycle hooks (SubagentStart, SubagentStop, TeammateIdle, Stop), and integration tests.
- **`circuit-breaker`** -- Circuit breaker protocol added to all agent definitions for resilient failure handling.
- **`compaction`** -- Enhanced compaction recovery with TaskGet reminder for better context restoration.
- **`debugger`** -- Bootstrap investigation from codebase mapping when available.

### Changed

- **`vibe`** -- Bootstrap B2 now delegates to the discussion engine instead of 6-round rigid questioning. Plan mode no longer auto-asks 1-3 questions; users run `/vbw:discuss` explicitly if they want context. Discuss mode replaced with a 5-line engine delegation.
- **`bootstrap-requirements`** -- Removed tier-based annotation (table_stakes/differentiators/anti_features) and research cross-referencing. Reads simplified `discovery.json` schema directly.
- **`readme`** -- Updated all counts (31k lines, 81 scripts, 23 commands, 7 agents, 461 tests). Added `/vbw:discuss` command, Docs agent, agent health monitoring, discussion engine references.

### Removed

- **`discovery-protocol`** -- Deleted 800-line `references/discovery-protocol.md`. Replaced by `references/discussion-engine.md` (~150 lines).

### Fixed

- **`teams`** -- Remove stale tmux forced in-process workaround, restore split-pane mode.
- **`token-budget`** -- Switch from line-based to character-based budgets, default to head truncation, remove cross-task escalation.
- **`ci`** -- Add executable bit to `agent-health.sh`. Remove unused variables in `token-baseline.sh` (SC2034). Use `CLAUDE_CONFIG_DIR` fallback in `agent-health.sh`.

## [1.21.18] - 2026-02-16

### Fixed

- **`hooks`** -- Skip commit gate for `[analysis-only]` tasks. Debugger agents in team mode no longer get blocked by the TaskCompleted hook when investigating hypotheses without applying fixes. Contributed by [@dpearson2699](https://github.com/dpearson2699) (#71, fixes #70).
- **`hooks`** -- Add missing `hookEventName` to session-start.sh (3 outputs) and blocker-notify.sh (1 output). Without this field, Claude Code's schema validator silently dropped all VBW context injection on session start. Also hardens compaction marker handling for clock skew and corrupted markers. Contributed by [@dpearson2699](https://github.com/dpearson2699) (#73, fixes #72).

## [1.21.17] - 2026-02-15

### Fixed

- **`planning-git`** -- Add 24 missing transient runtime artifacts to `ensure_transient_ignore()` — session tracking, metrics, caching, events, snapshots, logging, watchdog, and codebase mapping files are now excluded from `planning_tracking=commit` commits. Contributed by [@dpearson2699](https://github.com/dpearson2699) (#69, fixes #66).

## [1.21.16] - 2026-02-15

### Added

- **`max-turns`** -- Agent turn-budget resolver with effort-based scaling (thorough=1.5x, balanced=1x, fast=0.8x, turbo=0.6x), per-agent defaults, and config override support. Contributed by [@dpearson2699](https://github.com/dpearson2699) (#64).

### Fixed

- **`hooks`** -- Prevent false isolation blocks by tightening SubagentStart/Stop/TeammateIdle/TaskCompleted matchers from 6 to 24 patterns for correct VBW agent detection. Contributed by [@dpearson2699](https://github.com/dpearson2699) (#64).
- **`compact`** -- Role-matched snapshot restore prefers snapshots from the same agent role after compaction, with fallback to latest. Task-level resume hints from event log provide in-progress task and resume candidate context. Contributed by [@Solvely-Colin](https://github.com/Solvely-Colin) (#65).
- **`agents`** -- Add docs agent to max-turns resolver and fix missing EOF newline in resolve-agent-max-turns.sh.

## [1.21.15] - 2026-02-15

### Added

- **`agents`** -- New docs agent (vbw-docs) for documentation tasks with Sonnet as default model across all profiles, plus `qa_skip_agents` config to auto-skip QA for documentation work.

## [1.21.14] - 2026-02-15

### Fixed

- **`prompt-preflight`** -- Stop deleting `.vbw-session` marker on non-`/vbw:` prompts. The marker was being removed mid-workflow when users sent follow-up messages (plan approvals, answers), causing `security-filter.sh` to block Write/Edit calls to `.vbw-planning/`. Cleanup now only happens at session end via `session-stop.sh`.
- **`hook-wrapper`** -- Add `CLAUDE_CONFIG_DIR` fallback in SIGHUP handler. Previously used bare `$HOME/.claude` without respecting custom config directory.
- **`shellcheck`** -- Fix SC2155 warnings (declare and assign separately) in `tmux-watchdog.sh`, `session-start.sh`, `clean-stale-teams.sh`, `doctor-cleanup.sh`. Fix SC2034 unused variable in `doctor-cleanup.sh`.
- **`security-filter`** -- Remove `.vbw-planning/` self-blocking. The marker-based isolation (`.gsd-isolation` + `.active-agent` + `.vbw-session`) caused false blocks in too many scenarios: orchestrator after team deletion, agents before markers set, Read calls before prompt-preflight runs. GSD isolation is enforced by CLAUDE.md instructions + `.planning/` block (VBW→GSD direction).

## [1.21.11] - 2026-02-15

### Added

- **`help`** -- Dynamic help output from command frontmatter. Added `category:` field to all 22 commands and `scripts/help-output.sh` that reads frontmatter to generate grouped, formatted help. Zero tokens, zero drift.
- **`tmux`** -- PID tracking utility for agent process registration and cleanup on SubagentStop.
- **`tmux`** -- Watchdog script for tmux detach detection, launched on session start.
- **`tmux`** -- SIGHUP trap fallback in hook-wrapper for tmux disconnect resilience.
- **`tmux`** -- Forced in-process mode auto-patch when tmux is detected.
- **`session`** -- Orphan claude process cleanup on SessionStart.
- **`session`** -- Stale team cleanup script with paired tasks directory cleanup, integrated into SessionStart.
- **`compaction`** -- Pre-compact agent state snapshots with agent metadata, restore in post-compact hook.
- **`doctor`** -- Runtime health checks: cleanup preview, --cleanup flag, cleanup logging with summary counts.

### Fixed

- **`doctor`** -- Remove `local` keyword from top-level case block (bash compatibility).

### Documentation

- **`gitignore`** -- Runtime files (snapshots, watchdog, doctor logs) documented in .gitignore.

---

## [1.21.10] - 2026-02-15

### Fixed

- **`commands`** -- Plugin root preamble dual-fallback. When `CLAUDE_PLUGIN_ROOT` is empty (observed in some marketplace installs), the backtick preamble now resolves via the plugin cache using the same `sort -V | tail -1` pattern established by PR #54 for hooks. Zero regression when `CLAUDE_PLUGIN_ROOT` is set — the fallback never fires. 15 command preambles + 4 backtick bash calls updated. Extends PR #50's preamble architecture with PR #54's dual-fallback philosophy.
- **`testing`** -- `verify-plugin-root-resolution.sh` updated to recognize both simple and dual-fallback preamble forms.

---

## [1.21.9] - 2026-02-15

### Added

- **`security`** -- Database safety guard. PreToolUse hook (`bash-guard.sh`) intercepts every Bash command and blocks 40+ destructive patterns across Laravel, Rails, Django, Prisma, Knex, Sequelize, TypeORM, Drizzle, Diesel, SQLx, Ecto, raw SQL clients, Redis, MongoDB, and Docker volumes. Fires on all agents with Bash access (Dev, QA, Lead, Debugger). Override with `VBW_ALLOW_DESTRUCTIVE=1` or `bash_guard=false` config.
- **`security`** -- `config/destructive-commands.txt` blocklist file, extensible per-project via `.vbw-planning/destructive-commands.local.txt`.
- **`agents`** -- `## Database Safety` prompt sections added to vbw-qa, vbw-dev, vbw-debugger, and vbw-lead agents.
- **`contracts`** -- `forbidden_commands` gate type in `hard-gate.sh` for per-plan command restrictions.
- **`templates`** -- `forbidden_commands: []` field added to PLAN.md template.
- **`docs`** -- `docs/database-safety-guard.md` — full design document with flowchart, pattern table, override guide, and architecture decisions.
- **`readme`** -- Database safety guard in Features section, Settings Reference (`bash_guard`), Security hook diagram updated.

---

## [1.21.8] - 2026-02-15

### Added

- **`readme`** -- Feature Flags Reference documenting all 20 v2/v3 flags with descriptions, dependencies, and toggle instructions. Settings Reference for all config keys. Planning & Git section for `planning_tracking` and `auto_push`. (PR #62, @dpearson2699)
- **`readme`** -- Contributors section now uses [contrib.rocks](https://contrib.rocks/) auto-updating image.

### Changed

- **`config`** -- `/vbw:config` feature flags display uses human-friendly labels instead of raw `v2_`/`v3_` prefixed keys. (PR #62, @dpearson2699)

---

## [1.21.7] - 2026-02-15

### Added

- **`planning_tracking` + `auto_push` config** — Control how VBW planning artifacts are tracked in git. Three modes: `manual` (default), `ignore` (auto-gitignore `.vbw-planning/`), `commit` (auto-commit at lifecycle boundaries: bootstrap, plan, execute, archive). Push behavior: `never`/`after_phase`/`always`. New `scripts/planning-git.sh` with sync-ignore, commit-boundary, and push-after-phase subcommands. `/vbw:init` asks preference during setup. (PR #59, @dpearson2699)
- **Contributors section in README** — Added [@dpearson2699](https://github.com/dpearson2699), [@halindrome](https://github.com/halindrome), and [@navin-moorthy](https://github.com/navin-moorthy).

---

## [1.21.6] - 2026-02-15

### Fixed

- **`scripts/migrate-config.sh`** — Brownfield config migration extracted into shared script. SessionStart hook and `/vbw:config` both run migration, ensuring missing v2/v3 flags are backfilled even when hooks didn't fire. Legacy `agent_teams` key renamed to `prefer_teams` and cleaned up. (PR #57, @dpearson2699)

### Added

- **`scripts/migrate-config.sh --print-added`** — Generic defaults merge from `config/defaults.json`. Future config keys auto-backfill without code changes. `/vbw:config` now shows a notice when settings were added. (PR #58, @dpearson2699)

---

## [1.21.5] - 2026-02-15

### Fixed

- **`hooks.json` + `hook-wrapper.sh`** — Hooks now resolve `CLAUDE_PLUGIN_ROOT` via dual fallback: cache path first, then `--plugin-dir` path. Previously, `--plugin-dir` installs had no `CLAUDE_PLUGIN_ROOT` set, causing all hook scripts to silently fail. New `resolve-claude-dir.bats` and `sessionstart-compact-hooks.bats` tests added. (PR #54, @dpearson2699)

---

## [1.21.4] - 2026-02-15

### Fixed

- **`statusline-cache-isolation.bats`** — CI runners now have git identity configured in test setup(), fixing "Author identity unknown" failures on GitHub Actions. Default branch detection is now dynamic instead of hardcoding "main". Statusline also renders repo label on detached HEAD. (PR #46, @dpearson2699)
- **`commands/*.md`** — 15 commands now include `Plugin root: !` backtick preamble so `${CLAUDE_PLUGIN_ROOT}` resolves correctly in model-executed Bash blocks. Previously the variable expanded to empty string, silently breaking all path references. Regression test added. (PR #50, @dpearson2699)
- **`research-persistence.bats`** — Tests now use tracked `templates/RESEARCH.md` as fixture instead of gitignored `.vbw-planning/` runtime state. CI no longer depends on local development artifacts existing at repo root. (PR #56, @dpearson2699)

### Added

- **`.github/CODEOWNERS`** — `* @yidakee` ensures all PRs auto-request code owner review.
- **Branch protection** — main branch now requires passing CI and PR review before merge.

---

## [1.21.3] - 2026-02-14

### Fixed

- **`session-start.sh`** — Config migration now backfills `prefer_teams` for users who initialized before v1.20.8, defaulting to `"always"`. Previously these users had the old boolean `agent_teams` but no `prefer_teams` enum, causing silent config drift.
- **`session-start.sh`** — jq migration failures now log a warning to stderr instead of failing silently. Users see a clear message when config migration encounters malformed JSON.

### Testing

- **16 new tests** across 2 new test files:
  - `tests/config-migration.bats` (9 tests) — empty config, partial config, full config no-op, idempotent migration, malformed JSON handling, EXPECTED_FLAG_COUNT sync validation, prefer_teams migration, prefer_teams preservation, count=23 validation
  - `tests/research-persistence.bats` (7 tests) — Phase 1 RESEARCH.md section format, research-warn.sh JSON schema (4 cases), compile-context RESEARCH.md inclusion, flag-disabled path verification
- Test suite: 383 → 397 total tests (zero regressions)

### Documentation

- **`research-persistence`** — Documented Scout write path, test coverage, and known hook isolation limitation for RESEARCH.md creation

---

## [1.21.2] - 2026-02-14

### Fixed

- **`/vbw:config`** — Feature flags (`v3_*`, `v2_*`) now displayed in config output. Previously these flags existed in `config.json` but were invisible to users — the only way to discover or toggle them was manual JSON editing. Now shown as a dedicated "Feature Flags" section with descriptions and toggle hint. (Reported by @dpearson2699)

---

## [1.21.1] - 2026-02-14

### Fixed

- **`vbw-debugger`** — Increased maxTurns from 40 to 80. The scientific method protocol (reproduce + hypothesize + evidence + diagnose + fix + verify) legitimately needs more turns for complex bugs in large codebases. (Reported by @dpearson2699, #43)

### Added

- **`vbw-debugger`** — Turn budget awareness: debugger now proactively checkpoints its state (hypotheses, evidence, files examined, next steps) when running long, preventing context loss on turn exhaustion. (Proposed by @dpearson2699, #44)

---

## [1.21.0] - 2026-02-14

### Community Contributions

- **PR #41** (@halindrome) — Statusline cache isolation: per-repo cache key with cross-platform hash
- **PR #36** (@dpearson2699) — CI consolidation, contributor workflow improvements, ShellCheck fixes

### Fixed

- **`vbw-statusline.sh`** — Statusline cache key now includes a hash of `git rev-parse --show-toplevel`, preventing cross-repo cache leakage when running Claude Code in multiple repos. Cross-platform hash: `md5sum` (Linux) -> `md5` (macOS) -> `cksum` (fallback). Local-only repos (no remote) display directory name instead of leaking another repo's data. (Thanks @halindrome)
- **`pre-push-hook.sh`** — Relaxed to consistency-only checks: verifies 4 version files match but no longer requires VERSION to change on every push. Removes ~30 lines of false-positive-prone enforcement. (Thanks @dpearson2699)
- **`resolve-claude-dir.sh`** — Added `export` to `CLAUDE_DIR` assignment so sourcing scripts can access it. (Thanks @dpearson2699)
- **`bootstrap-project.sh`** — Removed unused `CREATED` variable (ShellCheck SC2034). (Thanks @dpearson2699)
- **`bootstrap-requirements.sh`** — Removed unused `COMPETITORS` and `ANSWERED_COUNT` variables (ShellCheck SC2034). (Thanks @dpearson2699)

### Changed

- **CI workflows** — Consolidated `.github/workflows/verification.yml` into `ci.yml`: shell syntax check + 4 contract verification steps now run as part of the test job. One workflow instead of two overlapping ones. (Thanks @dpearson2699)
- **`CLAUDE.md`** — Removed version bump instruction (contributor concern, not end-user relevant); push guard retained. (Thanks @dpearson2699)
- **`CONTRIBUTING.md`** — Rewritten Version Management section: describes manual merge-time bumping, no release-please references. (Thanks @dpearson2699)

### Testing

- **10 new tests** in `tests/statusline-cache-isolation.bats` for cache key isolation, cross-repo leakage prevention, no-remote directory name display, stale cleanup, and non-git directory handling. (Thanks @halindrome)

---

## [1.20.9] - 2026-02-14

### Community Contributions

- **PR #35** (@dpearson2699) — Security filter bypass fix: `hook-wrapper.sh` exit code 2 passthrough
- **PR #32** (@dpearson2699) — Progress dashboard fix: `state-updater.sh` milestone-aware path resolution

### Fixed

- **`hook-wrapper.sh`** — exit code 2 (Claude Code's "block tool call" signal) was silently converted to exit 0, disabling the security filter for `.env`, `.pem`, `.key` files. Now passes exit 2 through correctly. (Thanks @dpearson2699)
- **`session-start.sh`** — compaction-marker check prevents error output during compaction cycles. (Thanks @dpearson2699)
- **`map-staleness.sh`** — compaction-marker skip and `_diag()` stderr helper for hook mode. (Thanks @dpearson2699)
- **`post-compact.sh`** — `.compaction-marker` added to cleanup. (Thanks @dpearson2699)
- **`state-updater.sh`** — three bugs fixed: missing `.execution-state.json` no longer skips STATE.md/ROADMAP.md updates; reads `.plans[]` (current schema) instead of only `.phases{}` (old schema); `planning_root_from_phase_dir()` resolves milestone-aware paths instead of hardcoded `.vbw-planning/`. (Thanks @dpearson2699)

### Testing

- **14 new tests** in `tests/sessionstart-compact-hooks.bats` for compaction marker, hook wrapper exit codes, and session start behavior. (Thanks @dpearson2699)
- **4 new tests** in `tests/state-updater.bats` for milestone-aware path resolution and schema support. (Thanks @dpearson2699)

---

## [1.20.8] - 2026-02-14

### Added

- **`config`** -- New `prefer_teams` config option (`always`|`when_parallel`|`auto`) replaces boolean `agent_teams`. Default `always` creates Agent Teams for all operations, maximizing color-coded UI visibility
- **`vibe.md`** -- Plan mode respects `prefer_teams` — creates team even for Lead-only when set to `always`
- **`debug.md`** -- Debug mode respects `prefer_teams` — uses team path for all bugs when set to `always`

### Fixed

- **`init.md`** -- Config scaffold creates `prefer_teams` instead of deprecated `agent_teams`
- **`session-start.sh`** -- Reads `prefer_teams` config instead of `agent_teams`
- **`phase-detect.sh`** -- Reads `prefer_teams` config instead of `agent_teams`

### Changed

- **`config.md`** -- Settings reference table updated for `prefer_teams` enum
- **`test_helper.bash`** -- Test fixtures updated for `prefer_teams` config

---

## [1.20.7] - 2026-02-14

### Fixed

- **`vbw-statusline.sh`** -- OAuth token lookup now detects keychain access denial vs API key usage. Users with OAuth (Pro/Max) whose keychain blocks terminal access now see an actionable diagnostic message instead of misleading "N/A (using API key)". Added `VBW_OAUTH_TOKEN` env var as escape hatch. Uses `claude auth status` to distinguish auth methods when credential store fails.

---

## [1.20.6] - 2026-02-14

### Community Contributions

- **PR #38** (@navin-moorthy) -- Human UAT verification gate with CHECKPOINT UX

### Added

- **`commands/verify.md`** -- New `/vbw:verify` command for human acceptance testing with per-test CHECKPOINT loop, resume support, and severity inference
- **`templates/UAT.md`** -- UAT result template with YAML frontmatter for structured pass/fail/partial tracking
- **`execute-protocol`** -- Step 4.5 UAT gate after QA pass (autonomy-gated: cautious + standard only)
- **`vibe.md`** -- `--verify` flag, Verify Mode section, and NL keyword detection (verify, uat, acceptance test, etc.)
- **`execute-protocol`** -- TeamCreate for multi-agent execution (2+ plans get colored labels, status bar entries, peer messaging)
- **`vibe.md`** -- TeamCreate for Plan mode when Scout + Lead co-spawn (research + planning as coordinated team)

### Changed

- **`suggest-next.sh`** -- UAT suggestions surfaced after QA passes (cautious + standard autonomy)
- **`execute-protocol`** -- Step 5 shutdown now conditional on team existence (skip for single plan/turbo)

---

## [1.20.5] - 2026-02-13

### Community Contributions

- **PR #27** (@halindrome) -- CLAUDE_CONFIG_DIR support across all hooks and scripts
- **PR #29** (@dpearson2699) -- Fix 6 command names missing `vbw:` prefix for discovery

### Added

- **`resolve-claude-dir.sh`** -- Central helper for Claude config directory resolution

### Fixed

- **`hooks`** -- All 21 hook commands now respect `CLAUDE_CONFIG_DIR` environment variable
- **`commands`** -- 6 commands missing `vbw:` prefix now discoverable under `/vbw:*`
- **`doctor`** -- Plugin cache check respects custom config directory
- **`verify-vibe`** -- Removed unused `GLOBAL_MIRROR` variable

### Changed

- **`scripts`** -- 8 scripts source central resolver instead of inline fallback pattern

### Testing

- **`resolve-claude-dir`** -- 19 new bats tests for CLAUDE_CONFIG_DIR resolution

---

## [1.20.4] - 2026-02-13

### Fixed

- **`shellcheck`** -- resolved all shellcheck warnings across scripts. Removed unused variables, quoted command substitutions, added targeted disables for intentional patterns (ls|grep for zsh compat, git `@{u}` syntax, read-consumed vars).
- **`ci`** -- bats tests now pass on GitHub Actions Ubuntu runner. Added git user config for phase-detect tests, fixed cross-platform `stat` flag order (GNU first, BSD fallback) in resolve-agent-model.
- **`scripts`** -- added executable bit to 6 scripts missing chmod +x: generate-incidents.sh, lease-lock.sh, recover-state.sh, research-warn.sh, route-monorepo.sh, smart-route.sh.
- **`testing`** -- corrected command name expectation in verify-commands-contract.sh. Test now accepts both bare names (`map`) and prefixed names (`vbw:map`) since the plugin system auto-prefixes.

---

## [1.20.3] - 2026-02-13

### Changed

- **`discovery-protocol`** -- complete rewrite of `references/discovery-protocol.md` for coherence and completeness. B2 bootstrap and Discuss mode logic fully specified with gap fixes from research. Removed brittle line number references from Integration Points.
- **`vibe`** -- updated Discuss mode and Bootstrap B2 to align with rewritten discovery protocol.

---

## [1.20.2] - 2026-02-13

### Community Contributions

Merges 10 pull requests from **[@dpearson2699](https://github.com/dpearson2699)** (Derek Pearson). These contributions identified bugs, proposed fixes, and directly influenced the v1.20.0 architecture. Previously closed without proper merge credit — now properly merged and attributed.

### Merged

- **#10** -- `fix(update)`: identified `CLAUDE_PLUGIN_ROOT` breakage when commands copied to user directory.
- **#11** -- `fix(compile-context)`: fixed unpadded phase number resolution in `compile-context.sh`.
- **#12** -- `fix(stack)`: identified nested manifest scanning gap in `detect-stack.sh`, added iOS/Swift mappings.
- **#13** -- `fix(map)`: identified zsh `nomatch` glob crash, triggering a repo-wide zsh compatibility audit.
- **#14** -- `fix(todo)`: fixed STATE.md/todo.md heading mismatch causing unreliable insertion after `/vbw:init`.
- **#15** -- `test(verification)`: built repo-wide verification harness (228+ tests, GitHub Actions CI, command frontmatter validation).
- **#17** -- `fix(bootstrap)`: hardened CLAUDE.md bootstrap with centralized isolation, brownfield stripping, input guardrails.
- **#19** -- `refactor(isolation)`: designed the two-layer defense model and auto-migration that ships as the canonical isolation architecture.
- **#22** -- `fix(vibe)`: identified and fixed scope mode writing lifecycle actions into Todos section.
- **#24** -- `fix(hooks)`: systematic audit of `hookEventName` compliance across 8 hook scripts.

### Added (from Derek's PRs, beyond v1.20.1)

- **`ci`** -- GitHub Actions CI workflow (`.github/workflows/verification.yml`) for automated PR and push checks.
- **`testing`** -- repo-wide test harness: `testing/run-all.sh`, `verify-bash-scripts-contract.sh`, `verify-commands-contract.sh`.
- **`bootstrap`** -- `scripts/verify-claude-bootstrap.sh` with 27 contract tests.
- **`hooks`** -- `hookEventName` compliance added to 7 additional hook scripts (`post-compact`, `map-staleness`, `prompt-preflight`, `validate-commit`, `validate-frontmatter`, `validate-summary`).
- **`stack`** -- expanded `config/stack-mappings.json` with iOS/Swift and recursive detection entries.

---

## [1.20.1] - 2026-02-13

### Fixed

- **`update`** -- prefix all `claude plugin` commands with `unset CLAUDECODE &&` to prevent "cannot be launched inside another Claude Code session" error when running `/vbw:update` from within an active session.
- **`statusline`** -- remove misleading agent count that counted all system-wide `claude` processes instead of VBW-managed agents.

## [1.20.0] - 2026-02-13

### Added

- **`doctor`** -- `/vbw:doctor` health check command with 10 diagnostic checks: jq installed, VERSION file, version sync, plugin cache, hooks.json validity, agent files, config validation, script permissions, gh CLI, sort -V support. `disable-model-invocation: true`.
- **`templates`** -- CONTEXT.md and RESEARCH.md templates for agent context compilation and research output structure.
- **`blocker-notify`** -- TaskCompleted hook auto-notifies blocked agents when their blockers resolve, preventing teammate deadlocks.
- **`control-plane`** -- lightweight Control Plane dispatcher (`scripts/control-plane.sh`, 328 lines) that sequences all enforcement scripts into a unified flow. Four actions: pre-task (contract → lease → gate), post-task (gate → release), compile (context compilation), full (all-in-one). Fail-open on script errors, JSON result output, lease conflict retry with 2s wait. 15 unit tests + 3 integration tests.
- **`rollout-stage`** -- 3-stage progressive flag rollout automation (`scripts/rollout-stage.sh`). Stages: observability (threshold 0), optimization (threshold 2), full (threshold 5). Actions: check prerequisites, advance flags atomically, status report with all 14 v3_ flags. Stage definitions in `config/rollout-stages.json`. Supports `--dry-run`. 10 tests.
- **`token-baseline`** -- per-phase token usage measurement and comparison (`scripts/token-baseline.sh`). Actions: measure (aggregate from event log), compare (delta with direction indicators), report (markdown with budget utilization by role). Baselines saved to `.baselines/token-baseline.json`. 10 tests.
- **`token-intelligence`** -- per-task token budgets computed from contract metadata. Complexity scoring (must_haves weight 1, files weight 2, dependencies weight 3) maps to 4 tier multipliers. Fallback chain: per-task → per-role → config defaults. Token cap escalation emits `token_cap_escalated` event and reduces remaining budget for subsequent tasks. 12 tests.
- **`context-index`** -- `context-index.json` manifest generated in `.cache/` with key-to-path mapping per role/phase. Atomic writes via mktemp+mv. Updated on every cache miss, timestamps refreshed on cache hits. 6 tests.
- **`execute-protocol`** -- Control Plane orchestration block in Step 3, context compilation and token budget guards in Steps 3-4, cleanup in Step 5. Individual scripts (generate-contract.sh, hard-gate.sh, compile-context.sh, lock-lite.sh) preserved as independent fallbacks.

### Changed

- **`isolation`** -- consolidated to single root CLAUDE.md with context isolation rules for both VBW and GSD plugins.
- **`agents`** -- removed dead `memory: project` from all 6 agent frontmatters. Clarified standalone vs teammate session scope in debugger.
- **`references`** -- fixed internal references in verification-protocol.md (S5→§5/VRFY-06). Added per-model cost basis to model-profiles.md methodology note.
- **`README`** -- token efficiency section updated with v1.20.0 numbers (8,807 lines bash, 63 scripts, 21 commands, 11 references). Command/hook counts updated to 21. Typo and incomplete sentence fixes.
- **`compile-context`** -- ROADMAP metadata parser fixed (`### Phase` → `## Phase` to match actual format). Scout, Debugger, and Architect roles extended with conventions, research, and delta files. Code slices added to Debugger and Dev contexts.
- **`token-budget`** -- extended argument parsing for contract path and task number. Per-task budget computation with complexity scoring. Escalation config added to `config/token-budgets.json`.
- **`detect-stack`** -- expanded coverage for Python, Rust, Go, Elixir, Java, .NET, Rails, Laravel, Spring. 4 new manifest file detections.
- **`control-plane`** -- `context_compiler` default harmonized from `false` to `true` to match phase-detect.sh and defaults.json.
- **`config`** -- all 20 V2/V3 feature flags available in project config (default: off, enable via `/vbw:config`). 15 flags added to migration: lock_lite, validation_gates, smart_routing, event_log, schema_validation, snapshot_resume, lease_locks, event_recovery, monorepo_routing, hard_contracts, hard_gates, typed_protocol, role_isolation, two_phase_completion, token_budgets.

### Fixed

- **`task-verify`** -- bash 3.2 compatibility: replaced `case...esac` inside piped command substitution with `grep -Ev` stop word filter. macOS bash 3.2.57 parsing bug.
- **`bump-version`** -- added `--offline` flag to skip remote GitHub fetch for CI/air-gapped environments.
- **`phase-detect`** -- compaction threshold now configurable via `compaction_threshold` in config.json (default: 130000).
- **`scope`** -- prevent lifecycle actions from polluting Todos.
- **`init`** -- remove `*.sln` glob that crashes zsh on macOS.
- **`teams`** -- auto-notify blocked agents when blockers clear.
- **`defaults`** -- harmonize model_profile fallback to quality across all scripts.
- **`migration`** -- comprehensive flag migration and jq boolean bug fix.
- **`release`** -- resolve 8 findings from 6-agent pre-release verification.
- **`validate-commit`** -- heredoc commit messages no longer overwritten by `-m` flag extraction. macOS sed compatibility fix.
- **`session-start`** -- zsh glob compatibility across session-start, snapshot-resume, lock-lite, and file-guard scripts.
- **`security-filter`** -- stale marker detection (24h threshold) prevents false positive blocks on old markers.

### Documentation

- **`tokens`** -- v1.20.0 Full Spec Token Analysis (664 lines): 258 commits, 6 milestones, per-request -7.3%, ~85% coordination overhead reduction maintained despite 33% codebase growth.

### Tests

- **86 new tests** across 5 new test files: hooks-isolation-lifecycle.bats (10), phase0-bugfix-verify.bats (16), token-budgets.bats (12), context-index.bats (6), control-plane.bats (18), rollout-stage.bats (10), token-baseline.bats (10). Plus 4 context metadata tests. Test suite: 237 → 323 (zero regressions).

---

## [1.10.18] - 2026-02-12

### Added

- **`isolation`** -- context isolation to prevent GSD insight leakage into VBW sessions. New `### Context Isolation` subsection in Plugin Isolation instructs Claude to ignore `<codebase-intelligence>` tags and use VBW's own codebase mapping. bootstrap-claude.sh now strips 8 known GSD section headers when regenerating CLAUDE.md from existing files.

---

## [1.10.17] - 2026-02-12

### Added

- **`config`** -- interactive granular model configuration. Second menu in `/vbw:config` Model Profile flow offers "Use preset profile" or "Configure each agent individually". Individual path presents 6 agent questions across 2 rounds (4+2 split), writes model_overrides to config.json, and displays before/after cost estimate. Status display marks overridden agents with asterisk (*). Feature implemented in commits 1ac752b through 91da54f (Phase 1, Plan 01-01).
- **`init`** -- GSD project detection and import. Step 0.5 detects existing `.planning/` directory before scaffold, prompts for import consent, copies to `.vbw-planning/gsd-archive/` (preserves original), generates INDEX.json with phase metadata and quick paths. Enables seamless migration from GSD to VBW with zero-risk import.
- **`scripts`** -- generate-gsd-index.sh for lightweight JSON index generation (<5s performance). Creates INDEX.json with imported_at, gsd_version, phases_total, phases_complete, milestones, quick_paths, and phases array for fast agent reference without full archive scan.
- **`help`** -- GSD Import section documenting detection flow during /vbw:init, archive structure (.planning/ → gsd-archive/), INDEX.json generation, and isolation options.
- **`docs`** -- migration-gsd-to-vbw.md comprehensive migration guide (273 lines, 9 sections) covering import process, archive structure, version control best practices, INDEX.json format, usage patterns, GSD isolation, migration strategies (full/incremental/archive-only), troubleshooting scenarios, and FAQ.
- **`bootstrap`** -- 5 reusable bootstrap scripts in scripts/bootstrap/ (project, requirements, roadmap, state, claude). Each accepts arguments only, outputs to specified path, uses set -euo pipefail. Enables shared file generation between /vbw:init and /vbw:vibe.
- **`inference`** -- brownfield intelligence engine. infer-project-context.sh (247 lines) reads codebase mapping to extract project name, tech stack, architecture, purpose, and features with source attribution. infer-gsd-summary.sh (163 lines) reads GSD archives for latest milestone, recent phases, key decisions, and current work.
- **`init`** -- auto-bootstrap flow (Steps 5-8). After infrastructure setup, init detects scenario (greenfield/brownfield/GSD migration/hybrid), runs inference engine, presents always-show confirmation UX with 3 options (accept/adjust/define from scratch), field-level correction, then calls bootstrap scripts to generate all project files. Seamless flow with no pause between mapping and project definition.

### Changed

- **`vibe`** -- Bootstrap mode (B1-B6) refactored to call extracted bootstrap scripts via ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/. Discovery logic stays inline, file generation delegated to shared scripts. Verified standalone mode, config compliance, and zero regression across all 11 modes.

---

## [1.10.15] - 2026-02-11

### Added

- **`statusline`** -- model profile display on L1 after Effort field. Shows current active profile (quality/balanced/budget) dynamically from config.json.

### Changed

- **`defaults`, `init`, `session-start`, `suggest-next`, `statusline`** -- default model profile changed from "balanced" to "quality". New VBW installations and auto-migrations now use Opus for Lead/Dev/Architect/Debugger by default for better output quality.

### Fixed

- **`pre-push-hook`** -- hook now skips enforcement in non-VBW repos. Added early exit guard that checks for VERSION and scripts/bump-version.sh files. If both absent, hook exits cleanly without blocking pushes. Fixes issue where installing VBW plugin blocked git pushes in existing brownfield repositories.

---

## [1.10.14] - 2026-02-11

### Added

- **`model-profiles`** -- cost control via model profile configuration. Three preset profiles (quality/balanced/budget) with per-agent model assignments, plus per-agent override support for advanced users.
- **`config`** -- model profile selection in `/vbw:config` interactive menu with quality/balanced/budget options. Settings table displays current profile and all 6 agent model assignments.
- **`config`** -- CLI arguments `/vbw:config model_profile <profile>` for direct profile switching and `/vbw:config model_override <agent> <model>` for per-agent overrides.
- **`vibe`** -- Phase Banner displays active model profile during Plan and Execute modes.
- **`execute-protocol`** -- agent spawn messages include model name in parentheses format: "◆ Spawning {agent} ({model})...".
- **`model-routing`** -- agent model resolution helper script (`scripts/resolve-agent-model.sh`) with hybrid architecture pattern: commands read config, helper handles merge/override logic.
- **`init`** -- new projects seeded with `model_profile: "quality"` in config.json.
- **`session-start`, `suggest-next`, `statusline`** -- auto-migration adds `model_profile: "quality"` to existing projects without the field.

### Changed

- **`vibe`, `execute-protocol`, `debug`, `research`, `qa`** -- all agent-spawning commands now pass explicit `model` parameter to Task tool based on active profile and overrides.
- **`references`** -- new `model-profiles.md` with complete preset definitions, cost comparison table, and override syntax documentation.
- **`effort-profiles`** -- all 4 effort profile files updated to clarify effort controls planning depth while model profile controls cost.
- **`help`** -- Model Profiles section added with command examples and cost estimates.
- **`README`** -- Cost Optimization section added with 3-profile comparison table and usage guidance.

---

## [1.10.13] - 2026-02-11

### Fixed

- **`statusline`** -- distinguish auth expired from network failure in usage limits. Previously, both a stale OAuth token (401/403) and a network timeout showed the same "fetch failed" message. Now shows "auth expired (run /login)" for auth failures, keeping "fetch failed (retry in 60s)" for actual network issues.

---

## [1.10.12] - 2026-02-11

### Fixed

- **`init`** -- preserve existing `CLAUDE.md` in brownfield projects. `/vbw:init` Step 3.5 was blindly overwriting the user's root `CLAUDE.md`. Now reads first — if it exists, appends VBW sections to the end instead of clobbering. Same brownfield-awareness added to `/vbw:vibe` Bootstrap B6 and Archive Step 8.

---

## [1.10.11] - 2026-02-11

### Fixed

- **`config`** -- respect `CLAUDE_CONFIG_DIR` env var across all scripts and commands. Users who set `CLAUDE_CONFIG_DIR` to relocate their Claude config directory were hitting hardcoded `~/.claude/` paths. All 9 affected files now resolve via `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` fallback pattern — zero breakage for existing users.

---

## [1.10.10] - 2026-02-11

### Fixed

- **`refs`** -- purge all stale `/vbw:implement` and standalone command references from shipped code
- **`meta`** -- correct stale counts in README (9→10 reference files, 11→15 disable-model-invocation commands) and agent memory (27→20 commands, 18→20 hooks, 8→11 event types)

---

## [1.10.9] - 2026-02-11

### Fixed

- **`hooks`** -- `qa-gate.sh` tiered SUMMARY.md gate: commit format match now only grants a 1-plan grace period; 2+ missing summaries block regardless. Replaces `||` logic where format match bypassed missing summaries entirely.
- **`references`** -- `execute-protocol.md` Step 3b hardened to mandatory 4-step verification gate. No plan marked complete without verified SUMMARY.md.
- **`docs`** -- README TeammateIdle hook description updated to reflect tiered gate. CHANGELOG execute.md references corrected to execute-protocol.md. qa-gate.sh comments fixed (GSD → conventional).

---

## [1.10.8] - 2026-02-11

### Added

- **`/vbw:vibe`** -- single intelligent lifecycle command replacing 10 absorbed commands (implement, plan, execute, discuss, assumptions, add-phase, insert-phase, remove-phase, archive, audit). 293 lines, 11 modes, 3 input paths (state detection, NL intent parsing, flags), mandatory confirmation gates. 76/76 automated verification checks PASS.
- **`references/execute-protocol.md`** -- execution orchestration logic (Steps 2-5) extracted from execute.md for on-demand loading by vibe.md Execute mode. Zero per-request cost.
- **`scripts/verify-vibe.sh`** -- 241-line automated verification script validating all 25 vibe command requirements across 6 groups.
- **Context compiler milestone** -- 3-phase optimization reducing agent context loading by 25-35% across all project sizes. 14 feat/refactor commits, 65/65 QA checks (3 phases, all PASS). Agents now receive deterministic, role-specific context instead of loading full project state.
- **`scripts/compile-context.sh`** -- new script producing `.context-lead.md` (filtered requirements + decisions), `.context-dev.md` (phase goal + conventions + bundled skills), `.context-qa.md` (verification targets). Config-gated with `context_compiler` toggle.
- **`config`** -- `context_compiler` toggle (default: `true`) in `config/defaults.json`. Setting to `false` reverts all compilation to direct file reads.
- **`compiler`** -- skill bundling reads `skills_used` from PLAN.md frontmatter, resolves from `~/.claude/skills/`, bundles into Dev context. No-op when no skills referenced.
- **`hooks`** -- compaction marker system: `compaction-instructions.sh` writes `.compaction-marker` with timestamp on PreCompact. `session-start.sh` cleans marker at session start for fresh-session guarantee.

### Changed

- **`commands`** -- all 6 commands (execute, plan, qa, discuss, assumptions, implement) now use pre-computed `phase-detect.sh` output instead of loading 89-line `phase-detection.md` reference doc.
- **`commands`** -- plan.md, execute.md, implement.md call `compile-context.sh` before agent spawn with config-gated fallback to direct file reads.
- **`agents/vbw-dev.md`** -- removed STATE.md from Stage 1 (never used). Added marker-based conditional re-read with "when in doubt, re-read" conservative default.
- **`agents/vbw-qa.md`** -- replaced `verification-protocol.md` runtime reference with inline 12-line format spec. Tier provided in task description instead of loaded from full protocol.

### Fixed

- **`hooks`** -- `pre-push-hook.sh` restored to actual validation logic (was replaced by delegator wrapper causing infinite recursion).
- **`hooks`** -- `qa-gate.sh` tightened to tiered SUMMARY.md gate. Commit format match now only grants a 1-plan grace period; 2+ missing summaries block regardless. Replaces previous `||` logic where format match could bypass missing summaries entirely.
- **`references`** -- `execute-protocol.md` Step 3b hardened: SUMMARY.md verification gate is now a mandatory 4-step checkpoint after Dev completion. No plan marked complete without verified SUMMARY.md.

### Removed

- **`commands`** -- 29 commands consolidated to 20. Ten lifecycle commands hard-deleted: `implement`, `plan`, `execute`, `discuss`, `assumptions`, `add-phase`, `insert-phase`, `remove-phase`, `archive`, `audit`. All absorbed into `/vbw:vibe` (single intelligent router with 11 modes). Global commands mirror cleaned. No aliases, no deprecation shims.

---

## [1.10.6] - 2026-02-10

### Fixed

- **`hooks`** -- `state-updater.sh` now updates ROADMAP.md progress table and phase checkboxes when PLAN.md or SUMMARY.md files are written. Previously only STATE.md was updated, leaving ROADMAP.md permanently stale after bootstrap.
- **`hooks`** -- `pre-push-hook.sh` restored to actual validation logic. Commit `da97928` accidentally replaced it with the `.git/hooks/pre-push` delegator wrapper, causing infinite recursion that hung every `git push`.

---

## [1.10.5] - 2026-02-10

### Added

- **`discovery`** -- intelligent questioning system for `/vbw:implement`. Discovery protocol reference (`references/discovery-protocol.md`) with profile-gated depth (yolo=skip, prototype=1-2, default=3-5, production=thorough), scenario-then-checklist format, and example questions.
- **`config`** -- `discovery_questions` toggle (default: `true`) in `config/defaults.json`. Disabling skips all discovery prompts.
- **`implement`** -- bootstrap discovery (State 1) rewrites static B2 questions with intelligent scenario+checklist flow, feeding answers into REQUIREMENTS.md.
- **`implement`** -- phase-level discovery (States 3-4) asks 1-3 lightweight questions scoped to the phase goal before planning. Checks `discovery.json` to avoid re-asking.
- **`discuss`** -- answers now written to `discovery.json` for cross-command memory, so `/vbw:discuss` and implement share the same question history.

### Changed

- **`hooks`** -- `state-updater.sh` auto-advances STATE.md to the next incomplete phase when all plans in a phase have summaries. Sets status to "active" on plan writes.
- **`hooks`** -- `pre-push-hook.sh` simplified to a thin delegator routing to the latest cached plugin script via `sort -V | tail -1`.
- **`profile`** -- added Discovery depth column to built-in effort profiles table.
- **`config`** -- added `discovery_questions` to settings reference table.

---

## [1.10.4] - 2026-02-10

### Changed

- **`statusline`** -- removed Cost field from Line 4. Moved Prompt Cache from usage line (L3) back to context line (L2) after Tokens field.
- **`README`** -- promoted "What You Get Versus Raw Claude Code" comparison table from subsection to top-level section, moved above Project Structure for better visibility.

---

## [1.10.3] - 2026-02-10

### Changed

- **`statusline`** -- removed Cost field from Line 4. Status line now shows Model, Time, Agents, and VBW/CC versions only.

---

## [1.10.2] - 2026-02-10

### Added

- **Token compression milestone** -- 3-phase optimization compressing all VBW instruction content. 23 commits, 80/80 QA checks. Commands 53% smaller (4,804→2,266 lines), agents 47% (426→227), templates 49% (382→196), references 72% (1,795→497 across 17→8 files), CLAUDE.md 20% (118→94), live artifacts 58% (431→179). Total coordination overhead vs stock teams: 62%→**75% reduction**.
- **`docs/token-compression-milestone-analysis.md`** -- full analysis report with per-phase breakdowns, token math, before/after examples, and methodology. Companion to the existing stock teams comparison report.

### Changed

- **README token efficiency table** -- updated with post-compression numbers. Base context 70%→83%, agent coordination 80%→87%, context duplication 70%→81%, total overhead 62%→75%. Subscription rows reframed from misleading "worth $X/mo extra" to "X% more work done" with clear "equivalent capacity" language.
- **Statusline reduced to 4 lines** -- removed Economy line (L5: per-agent cost breakdown, $/line, cache hit%). Moved Prompt Cache display from context line (L2) to usage line (L3) after Extra field, showing hit%, write, and read counts.

---

## [1.10.1] - 2026-02-10

### Changed

- **Statusline Line 2** -- "Cache" renamed to "Prompt Cache" for clarity on context window line.
- **Statusline Line 5 (Economy)** -- now shows per-agent cost breakdown (Dev, Lead, QA, Scout, Architect, Debugger, Other) sorted by cost descending, replacing the grouped workflow categories (Build, Plan, Verify). "Cache" also renamed to "Prompt Cache" on this line.

---

## [1.0.99] - 2026-02-10

### Fixed

- **`security-filter.sh`** -- `.planning/` block now conditional on VBW markers, so GSD can write to its own directory when VBW is not the active caller. Previously blocked GSD unconditionally in every project.
- **`/vbw:init`** -- creates `.vbw-session` marker after enabling GSD isolation, so the security filter allows VBW writes during the remainder of the init flow (codebase mapping).

### Changed

- **Autonomy level rename** -- `dangerously-vibe` renamed to `pure-vibe` across all commands, references, README, and changelog. Tone adjusted to be informative without scare language.
- **Statusline economy line** -- renamed "Cache" to "Prompt Cache" for clarity.

---

## [1.0.98] - 2026-02-10

### Added

- **Token economy engine** -- per-agent cost attribution in the statusline. Each render cycle computes cost delta and attributes it to the active agent (Dev, Lead, QA, Scout, Debugger, Architect, or Other). Accumulated in `.vbw-planning/.cost-ledger.json`. Displays `Cost: $X.XX` on Line 4 and a full economy breakdown on Line 5 (per-agent costs sorted descending, percentages, cache hit rate, $/line metric). Economy line suppressed when total cost is $0.00.
- **Agent lifecycle hooks** -- `SubagentStart` hook writes active agent type to `.vbw-planning/.active-agent` via `scripts/agent-start.sh`. `SubagentStop` hook clears the marker via `scripts/agent-stop.sh`. Enables cost attribution to know which agent incurred each cost delta.
- **`/vbw:status` economy section** -- status command reads `.cost-ledger.json` and displays per-agent cost breakdown when cost data is available. Guarded on file existence and non-zero total.
- **GSD isolation** -- two-layer defense preventing GSD from accessing `.vbw-planning/`. Layer 1: root `CLAUDE.md` Plugin Isolation section (advisory). Layer 2: `security-filter.sh` PreToolUse hard block (exit 2) when `.gsd-isolation` flag exists and no VBW markers present. Two marker files (`.active-agent` for subagents, `.vbw-session` for commands) prevent false positives. Opt-in during `/vbw:init` with automatic GSD detection.

### Changed

- **Statusline cache consolidation** -- 6 cache files (`-ctx`, `-api`, `-git`, `-agents`, `-branch`, `-model`) reduced to 3 (`-fast`, `-slow`, `-cost`). Grouped by update frequency to reduce file I/O.
- **Pure shell formatting** -- `awk` replaced with shell functions (`fmt_tok`, `fmt_cost`, `fmt_dur`) for token, cost, and duration formatting. Eliminates 3 subprocesses per render cycle.
- **`session-stop.sh` cost persistence** -- session stop hook now reads `.cost-ledger.json` and appends a cost summary line to `.session-log.jsonl` before cleanup.
- **`post-compact.sh` cost cleanup** -- compaction hook resets cost-tracking temp files (`.active-agent`, stale cache entries) to prevent attribution drift after context compaction.
- **README statusline documentation** -- updated hook counts (18/10 to 20/11), added SubagentStart to hook diagram, documented economy line in statusline description.
- **`/vbw:init` GSD detection** -- Step 1.7 checks `~/.claude/commands/gsd/` and `.planning/` to detect GSD. Prompts for isolation consent only when GSD is present; silent skip otherwise.

---

## [1.0.97] - 2026-02-09

### Added

- **`suggest-next.sh`** -- context-aware Next Up suggestions (ADP-03). New script reads project state (phases, QA results, map existence, milestone context) and returns ranked suggestions. 12 commands updated to call it instead of hardcoded static blocks. After QA fail, suggests `/vbw:fix` instead of `/vbw:archive`; when codebase map is missing, injects `/vbw:map` hint.

### Changed

- **`templates/SUMMARY.md`** -- slimmed frontmatter to consumed fields only (TAU-05). Removed `duration`, `subsystem`, `tags`, `dependency_graph`, `tech_stack`, `key_files` (never read by any command). Added `tasks_completed`, `tasks_total`, `commit_hashes` (actually consumed by status and QA). Saves ~80-120 output tokens per SUMMARY write.
- **`references/shared-patterns.md`** -- added Command Context Budget tiers (TAU-02 formalization). Documents Minimal/Standard/Full context injection convention so future commands don't cargo-cult STATE.md injections.

### Removed

- **`/vbw:status --metrics`** -- removed broken flag that referenced `tokens_consumed` and `compaction_count` fields which never existed in the SUMMARY template.

---

## [1.0.96] - 2026-02-09

### Fixed

- **`/vbw:update`** -- version display now uses the actual cached version after install, not the GitHub CDN estimate. Fixes misleading "Updating to vX.Y.Z" and false version mismatch warnings when CDN lags behind the marketplace.

---

## [1.0.95] - 2026-02-09

### Fixed

- **`hooks`** -- all 18 hook commands now exit 0 when the plugin cache is missing, preventing "PostToolUse:Bash hook error" spam during `/vbw:update`. Previously, `cache-nuke.sh` deleted the cache but hooks kept firing and failing until the cache was re-populated.

---

## [1.0.94] - 2026-02-09

### Changed

- **`config`** -- default autonomy level changed from `pure-vibe` to `standard`. New installations now require plan approval and stop after each phase for review, giving users guardrails by default.

---

## [1.0.93] - 2026-02-09

### Changed

- **`commands`** -- lazy reference loading (TAU-01). Cross-command `@`-references in `implement.md` and `init.md` replaced with deferred `Read` instructions so `plan.md`, `execute.md`, and `map.md` are only loaded when the model reaches the state that needs them. Removed unused STATE.md injections from `fix`, `todo`, and `debug` commands. Saves 200-500 tokens per invocation for states that don't use the deferred files.

---

## [1.0.92] - 2026-02-09

### Changed

- **`/vbw:update`** -- always runs full cache refresh even when already on latest version. Fixes corrupted caches or stale hook schemas without requiring a version bump.

---

## [1.0.91] - 2026-02-09

### Added

- **`statusline`** -- hourly update check with visual indicator. When a newer VBW version is available, Line 4 turns yellow bold showing `VBW {current} → {latest} /vbw:update`. Cached 1 hour, single curl, zero overhead otherwise.

---

## [1.0.90] - 2026-02-09

### Fixed

- **`hooks.json` invalid event types** -- `PostCompact` (not a valid Claude Code event) replaced with `SessionStart` matcher `"compact"`. `NotificationReceived` renamed to `Notification`. Fixes fresh install validation error on newer Claude Code versions.
- **`notification-log.sh` field mismatch** -- script was reading `.sender`/`.summary` (non-existent fields). Now reads `.notification_type`, `.message`, and `.title` per the `Notification` event schema.
- **README event type count** -- corrected "11 event types" to "10 event types" after PostCompact was merged into SessionStart.

### Added

- **`README Quick Start`** -- prominent warning against using `/clear`, explaining Opus 4.6 auto-compaction and directing users to `/vbw:resume` for context recovery.

---

## [1.0.87] - 2026-02-09

### Fixed

- **`install-hooks.sh` resolves .git from project root** -- scripts used `dirname "$0"` to find `.git`, which resolves to the plugin cache directory (`~/.claude/plugins/cache/...`) for marketplace users instead of the user's project. Now uses `git rev-parse --show-toplevel`. Also replaces symlink-based hook install with a standalone wrapper script that delegates to the latest cached plugin version via `sort -V | tail -1`.
- **`pre-push-hook.sh` uses git for repo root** -- replaced `dirname "$0"` + relative path navigation (`../../`) with `git rev-parse --show-toplevel`. Works regardless of invocation method (symlink, direct call, or delegated from hook wrapper).
- **`session-start.sh` hook install guard** -- auto-install check now uses `git rev-parse --show-toplevel` to find the project's `.git/hooks/` instead of checking relative to `$PWD`.

---

## [1.0.86] - 2026-02-09

### Fixed

- **`/vbw:release` GitHub auth** — `gh release create` now extracts `GH_TOKEN` from the git remote URL when `gh auth` is not configured, instead of failing silently.
- **Statusline layout** — moved Diff (`+N -M`) from Line 4 to Line 1 after repo:branch. Added `Files:` and `Commits:` labels to the staged/modified and ahead-of-upstream indicators.

---

## [1.0.84] - 2026-02-09

### Changed

- **Context Diet: `disable-model-invocation` on 13 commands** — manual-only commands (add-phase, assumptions, audit, discuss, insert-phase, map, pause, qa, release, resume, skills, todo, whats-new) no longer load descriptions into always-on context. ~7,500+ tokens/session savings.
- **Context Diet: brand reference consolidation** — `vbw-brand-essentials.md` made self-contained (~50 lines), removing 329-line `vbw-brand.md` injection from 27 command references.
- **Context Diet: effort profile lazy-loading** — monolithic `effort-profiles.md` split into index + 4 individual profile files. Commands load only the active profile (~270 tokens/execution savings).
- **Context Diet: initialization guard consolidation** — `plan.md` guard deduplicated to shared-patterns reference.
- **Script Offloading: `phase-detect.sh`** — new script pre-computes 22 key=value pairs for project state, replacing 7 inline bash substitutions in `implement.md` (~800 tokens/invocation savings).
- **Script Offloading: SessionStart rich state injection** — `session-start.sh` now injects milestone, phase position, config values, and next-action hint via `additionalContext` (~100-200 tokens/command savings).
- **Script Offloading: compaction instructions** — CLAUDE.md Compact Instructions section + enhanced `compaction-instructions.sh` with main session detection guide context preservation during auto-compact.
- **Script Offloading: inline substitution cleanup** — 10 inline `config.json` cats removed from 6 commands (plan, execute, status, qa, fix, implement). Config pre-injected by SessionStart.
- **Agent Cost Controls: model routing** — Scout→haiku, QA→sonnet (40-60% cost reduction). Lead/Dev/Debugger/Architect inherit session model.
- **Agent Cost Controls: `maxTurns` caps** — all 6 agents capped (Scout: 15, QA: 25, Lead: 50, Dev: 50, Debugger: 75, Architect: 30). Prevents runaway spending.
- **Agent Cost Controls: reference deduplication** — 3 redundant `@` references removed from agent files (~1,600 tokens/agent spawn savings).
- **Agent Cost Controls: `state-updater.sh` enhancement** — auto-updates STATE.md plan counts when PLAN.md or SUMMARY.md files are written (PostToolUse hook, no LLM involvement).
- **Agent Cost Controls: effort-profiles and model-cost docs** — updated for consistency with new Scout/QA frontmatter model fields.

---

## [1.0.83] - 2026-02-09

### Added

- **`/vbw:release` pre-release audit** — new audit section runs after guards but before mutations. Finds commits since last release, checks changelog coverage against them, detects stale README counts (command count, hook count), presents branded findings with `✓`/`⚠` symbols, and offers to generate missing changelog entries or fix README numbers. Skippable with `--skip-audit`. Respects `--dry-run`.
- **`/vbw:release` git tagging** — creates annotated git tag `v{version}` on the release commit.
- **`/vbw:release` GitHub release** — creates a GitHub release via `gh release create` with changelog notes extracted from the versioned section. Gracefully warns if `gh` is unavailable. Skipped when `--no-push`.
- **Statusline local commit count** — `↑N` indicator (cyan) on Line 1 shows commits ahead of upstream.

### Changed

- **Statusline Line 1 consolidates all git/GitHub info** — clickable `repo:branch` link moved from Line 4 to Line 1, replacing the duplicate `Branch: X` field. Staged, modified, and ahead-of-upstream indicators all on Line 1.
- **Statusline Line 4 cleaned up** — removed duplicate GitHub link (now on Line 1).
- **Statusline progress bars fixed and unified** — all usage bars (Session, Weekly, Sonnet, Extra) now width 20, matching the Context bar. Previously Sonnet was width 10 and Extra was width 5, causing bars to render empty at low percentages (e.g., 7% × 10 = 0 filled blocks). Added minimum-1-block guarantee for any non-zero percentage.

---

## [1.0.82] - 2026-02-09

### Fixed

- **`/vbw:update` false "already up to date"** — Step 1 now reads the cached plugin version (`~/.claude/plugins/cache/`) instead of `${CLAUDE_PLUGIN_ROOT}/VERSION`, which resolves to the source repo in dev sessions and falsely matches the remote.

---

## [1.0.80] - 2026-02-09

### Added

- **Autonomy levels** — new `autonomy` config setting with 4 levels: `cautious` (stops between plan and execute, plan approval at Thorough+Balanced), `standard` (current default behavior), `confident` (skips "already complete" confirmations, disables plan approval), `pure-vibe` (loops ALL phases in a single `/vbw:implement`, no confirmations, no plan approval — only error guards stop). Configured via `/vbw:config` or `/vbw:config autonomy <level>`. Default: `pure-vibe`.
- **Autonomy-effort interaction in EFRT-07** — plan approval gate now respects autonomy overrides: `cautious` expands plan approval to Balanced effort, `confident`/`pure-vibe` disable it entirely regardless of effort level.
- **Full Autonomy Levels section in README** — gate behavior table, per-level descriptions, and effort interaction docs.
- **CLAUDE.md** — project-level instructions file for VBW's own development (rules, key decisions, installed skills, learned patterns, state).
- **Lead agent progress display** — `vbw-lead.md` now emits `◆`/`✓` progress lines at each stage (Research, Decompose, Self-Review, Output) and per-plan confirmation lines.
- **Plan command progress display** — `plan.md` shows phase banner, effort level, and Lead agent lifecycle (`Spawning...`, `✓ complete`, `Validating...`) during planning.

### Changed

- **`/vbw:resume` rewritten as ground-truth restoration** — no longer requires `/vbw:pause` first. Reads STATE.md, ROADMAP.md, PLAN.md, SUMMARY.md, and `.execution-state.json` directly. Computes phase progress, detects interrupted builds, and presents a full context restoration dashboard with project name, core value, decisions, todos, blockers, and a smart Next Up block. RESUME.md from `/vbw:pause` is consumed as bonus session notes if present.
- **`/vbw:pause` simplified** — reduced to a lightweight note-taking command. Removed state gathering (STATE.md, ROADMAP.md scanning) since state auto-persists in `.vbw-planning/`. Now just writes user notes to RESUME.md. Description updated: "Save session notes for next time (state auto-persists)."
- **`/vbw:help` table descriptions** — pause row updated to "Save session notes for next time (state auto-persists)", resume row updated to "Restore project context from .vbw-planning/ state".
- **README flow diagram** — rewritten for v2 state machine architecture. Greenfield path shows auto-chain to `/vbw:implement`. Central hub shows 5-state detection. Granular alternatives (`/vbw:discuss`, `/vbw:plan`, `/vbw:execute`) shown as optional.
- **README Quick Tutorial** — rewritten to emphasize implement-only flow (`init → implement → archive → release`). Removed `/vbw:status` from tutorial, added `/vbw:release`, added advanced user callout pointing to full 27-command reference.
- **`/vbw:audit` description** — fixed stale "milestone for shipping readiness" to "completion readiness" in frontmatter and help table.

---

## [1.0.73] - 2026-02-09

### Added

- **`/vbw:archive` command** — created from `ship.md` with updated terminology. Close out completed work, run audit, archive state to `.vbw-planning/milestones/`, tag the git release, and update project docs. Replaces `/vbw:ship`.
- **5-state lifecycle router in `/vbw:implement`** — full rewrite as a state machine that auto-detects project state: State 1 (no project) runs bootstrap flow absorbing `/vbw:new`, State 2 (no phases) delegates to `/vbw:plan` scoping mode, State 3 (unplanned phases) delegates to `/vbw:plan`, State 4 (planned phases) delegates to `/vbw:execute`, State 5 (all complete) shows completion with `/vbw:archive` suggestion
- **Scoping Mode in `/vbw:plan`** — Mode Detection section routes to Scoping Mode (no args + no phases) or Phase Planning Mode (existing behavior). Scoping Mode asks "What do you want to build?", gathers requirements, and creates phases
- **v2 state machine note in `phase-detection.md`** — documents that phase detection (dual-condition algorithm) only applies to States 3-4 of the implement router
- **`/vbw:implement` exception in `shared-patterns.md`** — Initialization Guard now skips for `/vbw:implement` since it handles uninitialized state via State 1 bootstrap

### Changed

- **`/vbw:implement` is now the one command** — smart router through the full lifecycle, replacing the previous plan+execute combo. Users only need to remember one command; it auto-detects everything
- **`/vbw:implement` State 2 delegates to `/vbw:plan`** — scoping logic moved from inline steps to `@`-reference delegation to `plan.md`, matching the pattern used by States 3-4
- **Milestones become internal** — users never see the "milestone" concept. The `.vbw-planning/milestones/` directory structure and ACTIVE file mechanism are preserved under the hood, but no commands expose them directly
- **`/vbw:help` fully rewritten** — lifecycle header updated to `init → implement → plan → execute → archive`, command tables restructured for v2 architecture, Phase Management section replaces Milestones & Phases, Git Branches paragraph removed, Getting Started flow leads with `/vbw:implement`
- **Guard clauses updated across 4 commands** — `audit.md`, `resume.md`, `status.md` guard messages now reference `/vbw:implement` instead of removed commands; `audit.md` description updated from "milestone for shipping readiness" to "completion readiness"
- **Next Up blocks updated across 3 commands** — `audit.md`, `execute.md`, `status.md` now reference `/vbw:archive` instead of `/vbw:ship`
- **`/vbw:init` rewired for v2** — auto-launch changed from `@commands/new.md` to `@commands/implement.md`, guard clause updated, CLAUDE.md bootstrap template references `/vbw:implement`, all 6 stale references replaced
- **`memory-protocol.md` updated** — CLAUDE.md command table now lists `/vbw:implement` (bootstrap) and `/vbw:archive` instead of `/vbw:new` and `/vbw:ship`. Ship Cleanup section renamed to Archive Cleanup
- **`vbw-brand.md` updated** — Shipped milestone box and Next Up suggestions reference `/vbw:archive`
- **README.md fully updated** — ASCII flow diagram reflects v2 lifecycle (init → implement → plan/execute → qa → archive), Quick Tutorial rewritten with `/vbw:implement` bootstrap and `/vbw:archive`, command tables updated (removed 4 rows, added archive, updated implement description), brownfield path references `/vbw:implement`
- **`/vbw:implement` migration note cleaned up** — removed `(not /vbw:ship)` parenthetical from rule note (was a Phase 1 migration reminder, now unnecessary)
- Command count: 30 → 27 across README, help, CONTRIBUTING, and both marketplace.json files

### Removed

- **`commands/new.md`** — project definition flow absorbed into `/vbw:implement` State 1 bootstrap (auto-detected when no `.vbw-planning/` exists)
- **`commands/ship.md`** — renamed to `/vbw:archive` with updated terminology throughout
- **`commands/milestone.md`** — milestones are now internal; managed automatically by the planning and archiving system
- **`commands/switch.md`** — removed with milestone commands; single-milestone mode is the default for solo developers

---

## [1.0.71] - 2026-02-09

### Added

- **`/vbw:release` command** — bump version, finalize changelog, commit, and push in one step. Runs `bump-version.sh` across all 4 version files, renames `[Unreleased]` to the new version in CHANGELOG.md, commits, and pushes. Supports `--dry-run`, `--no-push`, `--major`, `--minor`.

---

## [1.0.70] - 2026-02-09

### Added

- **Frontmatter description validation hook** — new `validate-frontmatter.sh` PostToolUse hook catches multi-line and empty `description` fields in markdown frontmatter at write time, preventing silent breakage of plugin command/skill discovery. Non-blocking (warning only).
- **Automatic git hook installation** — new `scripts/install-hooks.sh` is idempotent, warns without overwriting user-managed hooks, and is called automatically by `/vbw:init` (Step 1.5) and silently by `session-start.sh` when the pre-push hook is missing. `CONTRIBUTING.md` updated to reference the script instead of manual `ln -sf` commands.
- **Execution state capture in pause/resume** — `/vbw:pause` now saves in-flight execution state (active phase, plan statuses, progress) into RESUME.md. `/vbw:resume` reconciles stale state by checking which plans completed (via SUMMARY.md) during the pause gap.
- **Orphaned execution state reconciliation** — `session-start.sh` detects orphaned execution state (status=running from a crashed session), reconciles against SUMMARY.md files, and auto-completes phases where all plans finished.

### Changed

- **`CONTRIBUTING.md` hook setup** — replaced manual `ln -sf` symlink instructions with `bash scripts/install-hooks.sh`. Added note that VBW users get hooks auto-installed.

### Fixed

- **jq dependency detection at all entry points** — `session-start.sh` now warns that all 17 quality gates are disabled when jq is missing. `detect-stack.sh` exits with a JSON error before any jq-dependent logic. `/vbw:init` has a pre-flight check with platform-specific install instructions (brew/apt).
- **Version sync enforcement at commit and push time** — `validate-commit.sh` now runs `bump-version.sh --verify` and warns (non-blocking) when the 4 version files diverge. `pre-push-hook.sh` runs the same check but blocks the push (exit 1) when files are out of sync.
- **jq guard in validate-commit.sh** — hook exits 0 silently when jq is missing instead of producing confusing error output.
- **Atomic file operations in hooks** — `session-stop.sh` writes session log via temp file + append (prevents partial JSON lines). `vbw-statusline.sh` suppresses errors on all 6 cache write paths. `qa-gate.sh` handles empty git repos gracefully.
- **Unsafe temp file path in execute command** — replaced bare `> tmp && mv tmp` with properly-pathed `.vbw-planning/.execution-state.json.tmp` in the jq atomic write example.

## [1.0.69] - 2026-02-09

### Changed

- **Adaptive map sizing** — `/vbw:map` now sizes the mapping strategy to the codebase: solo (< 200 files, no Agent Team), duo (200–1000 files, 2 scouts), quad (1000+ files, 4 scouts). Previously always spawned 4 Scout teammates regardless of project size, causing 6+ minutes of overhead for small codebases.
- **`--tier=solo|duo|quad` override** — force a specific mapping tier via argument, bypassing auto-detection.
- **Solo mode maps inline** — orchestrator analyzes all 4 domains sequentially and writes documents directly, skipping TeamCreate/SendMessage/shutdown overhead entirely.
- **Agent Teams guard in map** — forces solo mode with `⚠` note when Agent Teams is not enabled.
- **`mapping_tier` in META.md** — map output now records which tier was used, displayed in the completion banner.
- **Init flow reorder** — `/vbw:init` no longer shows skill suggestions before codebase mapping completes. Detect-stack results are saved silently (only stack summary shown), mapping runs, then curated + registry suggestions are combined into a single unified prompt.
- **Adaptive mapping in init** — small codebases (< 200 files) run map inline synchronously (~30s), larger codebases launch map in background. Greenfield projects skip mapping entirely.
- **Unified skill prompt** — curated and registry skill suggestions now appear in one AskUserQuestion with `(curated)` / `(registry)` tags, instead of showing curated suggestions early and registry results later.
- **Continuous progress output** — both map and init now display progress per-document (solo) or per-scout (duo/quad) with no silent gaps.

## [1.0.67] - 2026-02-09

### Fixed

- **Brownfield detection is now language-agnostic** — removed hardcoded extension list (`*.ts, *.js, *.py, *.go, *.rs, *.java, *.rb`) from both `init.md` and `new.md`. Detection now cascades: `git ls-files` first, then broad Glob fallback for non-git projects. Shell scripts, C++, CSS, HTML, and any other file type all count.
- **Codebase mapping always runs during init** — removed `(brownfield only)` gate from the Map track. The map command handles empty projects via its own guard, so init no longer needs to pre-filter.

### Changed

- **Removed per-file confirmation gates from `/vbw:new`** — the flow no longer prompts "Does this look right?" for each file (PROJECT.md, REQUIREMENTS.md, ROADMAP.md). Files are written immediately after gathering answers, with a single summary at the end. Users can re-run with `--re-scope` to redefine.

## [1.0.60] - 2026-02-08

### Fixed

- **`eval` removed from statusline** — replaced `eval "$(jq ...)"` with safe `IFS='|' read` parsing for Anthropic usage API response, eliminating shell injection risk (S1)
- **Security filter now fail-closed** — `security-filter.sh` exits 2 (block) on jq failures, empty stdin, or malformed data instead of silently allowing access (S2)
- **Unquoted variables fixed** — replaced unsafe `xargs rm -rf` with `while read` loops in session-start.sh, cache-nuke.sh; quoted `$PROJECT_ROOT` in file-guard.sh; fixed word-splitting in validate-commit.sh (S3)
- **Safe `git reset --hard`** — session-start.sh now checks `git diff --quiet` before resetting marketplace checkout, skips with warning if dirty (S5)
- **Temp file ownership checks** — statusline cache reads now verify file ownership with `[ -O "$file" ]` before trusting cached data (S6)
- **Settings mutation backup** — session-start.sh creates `.bak` before modifying `~/.claude/settings.json`, restores on jq failure (P4)
- **Cache cleanup race condition** — mkdir-based lock prevents concurrent session-start scripts from racing on cache cleanup (R2)
- **`set -u` strict mode** — added to all 13 hook scripts to catch undefined variable typos, with proper `${VAR:-}` defaults (R1)

### Added

- **`sort -V` fallback in hooks** — all 17 hook entries now use `(sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n)` for systems without GNU sort version sorting (P3)
- **`_note` key in hooks.json** — documents the hard-coded cache path coupling and why it cannot be abstracted (M2)
- **`--verify` flag for bump-version.sh** — checks all 4 version files are in sync without bumping, exits 1 with diff report on mismatch (P1)
- **Offline version bump fallback** — bump-version.sh falls back to local VERSION when remote fetch fails instead of hard-exiting (M4)
- **jq availability check** — session-start.sh warns users if jq is missing with install instructions (M3)
- **Version management docs** — CONTRIBUTING.md now documents the 4-file sync, bump-version.sh workflow, and --verify flag (D3)

### Changed

- **Marketplace.json schemas aligned** — root and plugin marketplace.json now share consistent owner, metadata, and license fields (D1)
- **Owner name encoding consistent** — all manifest files use "Tiago Serôdio" with circumflex accent (D2)
- **`.claude/settings.local.json` gitignored** — user-specific permission settings no longer tracked in git (I3)

## [1.0.59] - 2026-02-08

### Fixed

- **Installation instructions cause paste error** — both install commands were in a single code block, so users who copy-pasted got them concatenated into one command with a malformed URL. Split into separate code blocks with explicit Step 1/Step 2 labels and a warning not to paste together.

## [1.0.58] - 2026-02-08

### Changed

- **Init reordering: map before skills** — for brownfield projects, `/vbw:init` now runs codebase mapping (Step 2) before skill discovery (Step 3). Previously, skills were suggested blind, then map ran at the end. Now map output (`STACK.md`) augments `detect-stack.sh` results, so skill suggestions are based on actual codebase analysis rather than just manifest file detection.
- **New Step 3a+: map-augmented stack detection** — after `detect-stack.sh` runs, init reads `.vbw-planning/codebase/STACK.md` to extract additional stack components found through deep code analysis (e.g., frameworks detected in imports, not just in `package.json`). These are merged into `detected_stack[]` for registry search.
- **README flow chart and tutorial updated** — brownfield path now shows map → skills → new sequence. Command table and tutorial text reflect that skill discovery is informed by map data.

## [1.0.56] - 2026-02-08

### Changed

- **Brownfield init auto-chains** — `/vbw:init` now auto-chains to `/vbw:map` then `/vbw:new` when an existing codebase is detected. Previously init stopped at "Next Up: /vbw:new" and the user had to run each command separately.
- **`/vbw:new` Next Up offers discuss and implement** — after project definition, the Next Up block now suggests `/vbw:discuss` and `/vbw:implement` instead of `/vbw:plan`. Reflects the actual user flow: gather context or jump straight to building.
- **Removed brownfield auto-map from `/vbw:new`** — codebase mapping for brownfield projects is now handled by init's auto-chain (init → map → new), eliminating the duplicate brownfield detection in new's Step 6.
- **README flow chart updated** — shows the greenfield/brownfield split at init, with brownfield auto-chaining through map and new. Tutorial and command table updated to match.

## [1.0.55] - 2026-02-08

### Changed

- **Skill wiring through plans** — Lead now reads relevant SKILL.md files during research and wires them into each PLAN.md via `@` references in `<context>` + `skills_used` frontmatter. Dev and QA consume skills through the existing `@` read path instead of separate STATE.md lookups.
- **Lead self-review validates skill wiring** — Stage 3 checklist now enforces that every `skills_used` entry has a matching `@` reference in the plan's context section.
- **QA reads `@`-referenced context** — QA now reads all `@`-referenced files from the plan (including skills), closing the gap where it previously only noted skills from STATE.md.
- **Init summary cleanup** — removed "Suggested: {count}" line from Step 4 summary (redundant after skill installation completes).

## [1.0.54] - 2026-02-08

### Added

- **find-skills bootstrap in `/vbw:init`** — init now offers to install the find-skills meta-skill and searches the Skills.sh registry (~2000 community skills) for matches. Previously init silently skipped registry search with no explanation when curated mappings had no match.
- **`~/.agents/skills/` path support** — `detect-stack.sh` now scans all three skill locations: `~/.claude/skills/`, `.claude/skills/`, and `~/.agents/skills/` (where the skills CLI installs). New `installed.agents` array in JSON output.
- **find-skills bootstrap in `/vbw:skills`** — the skills command now offers to install find-skills when missing instead of silently skipping registry search.
- **Proactive registry search in `/vbw:skills`** — when find-skills is available and detected stack items have no curated mapping, the command automatically searches the registry without requiring `--search`.
- **Better empty state in `/vbw:skills`** — when no stack is detected, shows example search queries instead of a dead end.

### Changed

- **Removed "do NOT mention find-skills during init" restriction** — init now proactively bootstraps find-skills and runs dynamic registry search (Steps 3c-3e)
- **`references/skill-discovery.md` SKIL-06** — find-skills bootstrap now runs during both `/vbw:init` and `/vbw:plan` (was plan-only)
- **`references/skill-discovery.md` SKIL-07** — dynamic discovery triggers during both `/vbw:init` and `/vbw:plan` (was plan-only)
- **`detect-stack.sh` find-skills detection** — checks both `~/.claude/skills/find-skills` and `~/.agents/skills/find-skills`

## [1.0.53] - 2026-02-08

### Fixed

- **Nuclear cache wipe during updates** — /vbw:update now completely wipes ALL cached versions before installing the new one, preventing stale file contamination. Previously, the cache directory could retain old files if the version number matched.
- **Cache integrity verification on session start** — session-start.sh now verifies critical files exist in the cache and nukes it if any are missing. This catches scenarios where files were added in a new version but the cache was already populated.
- **Always-sync global commands** — Global commands at ~/.claude/commands/vbw/ are now unconditionally synced from cache on every session start, not just when file counts differ. This prevents content-level staleness.
- **New scripts/cache-nuke.sh utility** — Standalone cache wipe script that removes plugin cache, global commands, and temp files. Used by /vbw:update and available for manual recovery.

## [1.0.52] - 2026-02-08

### Added

- `/vbw:skills` command: standalone skill discovery and installation from skills.sh — detects tech stack, suggests curated skills, searches the registry, and installs with one command
- `scripts/detect-stack.sh`: helper script that detects project tech stack, cross-references installed skills, and outputs suggestions as JSON — replaces 50+ inline LLM tool calls with one bash call

### Fixed

- `/vbw:init` Step 3 skill discovery never suggested skills on brownfield projects — root cause: SKIL-02 protocol was too complex for inline LLM execution (27 entries x multiple detect patterns). Now uses `detect-stack.sh` for reliable detection
- Wrong install command in `references/skill-discovery.md`: `npx @anthropic-ai/claude-code skills add` does not exist — replaced with correct `npx skills add <name> -g -y`
- Wrong `find-skills` install note in SKIL-06: replaced with correct `npx skills add vercel-labs/skills --skill find-skills -g -y`
- Both `marketplace.json` files said "27 commands" when there were already 28 — updated to 29

### Changed

- Command count: 28 to 29 across README, help, and both marketplace.json files
- `/vbw:init` Step 3 now calls `detect-stack.sh` directly instead of delegating to the 180-line skill-discovery.md protocol

## [1.0.51] - 2026-02-08

### Changed

- Updated statusline screenshot in `assets/statusline.png`

## [1.0.50] - 2026-02-08

### Added

- Security filter blocks `.planning/` directory (GSD's workspace) to prevent cross-tool contamination — `.vbw-planning/` is unaffected

## [1.0.49] - 2026-02-08

### Fixed

- `/vbw:*` prefix missing in autocomplete — root cause: marketplace checkout stuck at v1.0.9 (pre-migration `skills/` structure) while plugin cache had v1.0.48 (`commands/`). Claude Code read commands from the stale marketplace, not the cache
- `/vbw:update` now always runs `marketplace update` before `plugin update` to prevent marketplace staleness
- `session-start.sh` auto-syncs stale marketplace checkout when version mismatch detected

### Added

- Belt-and-suspenders: `session-start.sh` copies commands to `~/.claude/commands/vbw/` (global commands subdirectory pattern, same as GSD) — guarantees `/vbw:*` prefix regardless of plugin system behavior
- `/vbw:uninstall` now cleans up `~/.claude/commands/vbw/` directory

## [1.0.47] - 2026-02-08

### Changed

- Migrated all 28 slash commands from `skills/*/SKILL.md` to `commands/*.md` — autocomplete now shows `/vbw:help` instead of `/help (vbw)`
- Updated `@` references in implement, new, and help commands to point to `commands/` paths
- Updated path references in `references/verification-protocol.md`, `references/phase-detection.md`, and `references/skill-discovery.md`
- Updated project structure in README.md and CONTRIBUTING.md

### Removed

- `skills/` directory (replaced by `commands/`)

## [1.0.46] - 2026-02-08

### Fixed

- Existing users' `statusLine` in `~/.claude/settings.json` not updating after plugin update — users who installed with the old `for f in` glob pattern were stuck on the oldest cached version forever
- `session-start.sh` now auto-migrates the statusLine command to the correct `sort -V | tail -1` pattern on every session start (idempotent, no-op if already correct)

## [1.0.45] - 2026-02-08

### Fixed

- All 17 hook commands and statusline resolved the **oldest** cached version instead of the latest — glob `for f in ...` expands alphabetically (`1.0.27` < `1.0.44`), so hooks always ran stale code after updates
- Same stale-version bug in `skill-hook-dispatch.sh` internal glob loop, `/vbw:plan` map-staleness inline execution, and `/vbw:init` statusline template
- `/vbw:update` Step 5 cache cleanup now verifies removal succeeded and retries if old versions persist

## [1.0.41] - 2026-02-08

### Added

- `/vbw:implement` command: unified plan+execute in one step with dual-condition phase auto-detection (needs plan+execute vs execute-only)
- `references/handoff-schemas.md`: 5 structured JSON schemas for agent-to-agent SendMessage communication (`scout_findings`, `dev_progress`, `dev_blocker`, `qa_result`, `debugger_report`)
- Version bump warning in `validate-commit.sh`: warns when non-version files are staged but VERSION is not (VBW plugin development only, guarded by `name = "vbw"`)
- Implement Command section in `references/phase-detection.md` with dual-condition detection algorithm
- Schema-based Output Format in Scout agent: structured JSON for teammate mode, plain markdown for standalone subagent mode
- Communication sections in Dev, QA, and Debugger agents referencing handoff schemas
- 5 new automation hook scripts: `map-staleness.sh`, `notification-log.sh`, `post-compact.sh`, `prompt-preflight.sh`, `session-stop.sh`, `state-updater.sh`
- `references/shared-patterns.md`: consolidated Initialization Guard and Agent Teams Shutdown Protocol
- Plan self-review step in Lead agent
- Per-plan dependency wiring in `/vbw:execute` (replaces wave-level blocking)
- Per-wave QA overlap with later-wave Dev execution at Thorough/Balanced effort
- Scout model inheritance: Opus at Thorough/Balanced, Haiku at Fast/Turbo (was always inherited)
- REQ-ID tracing and must_haves testability instructions for Lead agent
- `references/vbw-brand-essentials.md`: extracted brand vocabulary as standalone reference

### Changed

- Command count: 27 → 28 across README and help (added `/vbw:implement`)
- 4 agent definitions (scout, dev, qa, debugger) now reference structured handoff schemas
- 4 skills (map, execute, debug, qa) now use structured schema communication with JSON parsing fallback
- `/vbw:execute` teammate communication protocol uses `dev_progress` and `dev_blocker` schemas
- `/vbw:map` Scout task descriptions specify `scout_findings` schema with domain field
- `/vbw:qa` spawn instructions and result parsing reference `qa_result` schema
- `/vbw:debug` competing hypotheses instructions reference `debugger_report` schema
- `/vbw:help` Getting Started now highlights `/vbw:implement` as the quick path
- README hook counts: 12 hooks/7 events → 17 hooks/11 events with expanded descriptions
- Statusline caching: batch formatting, 10s agent TTL, merged GitHub cache
- SUMMARY.md frontmatter simplified; STATE.md performance metrics removed
- REQUIREMENTS.md traceability consolidated to ROADMAP.md
- Init guard and shutdown protocol consolidated across 21 skills via shared-patterns.md
- Security filter regex consolidated; `.planning/` references fixed to `.vbw-planning/`
- Agent meta-justification instructions trimmed for token reduction

### Fixed

- 3 scripts referenced `.planning/` instead of `.vbw-planning/`
- GNU-only `grep -oP` replaced with POSIX-compatible patterns
- STATE/ROADMAP context injections now capped (`head -40`) to prevent token bloat

## [1.0.35] - 2026-02-08

### Added

- `name` field in YAML frontmatter for all 27 skills (was missing from all)
- `disable-model-invocation: true` for 8 lifecycle skills: execute, ship, uninstall, milestone, new, init, switch, remove-phase
- Step 3.5 in `/vbw:map`: lead writes 7 mapping documents from Scout SendMessage reports (Scouts no longer write files)
- Delegate permissionMode explanation note in `/vbw:execute` delegation directive
- VBW-scoped matcher on SubagentStop hook: only triggers for vbw-lead, vbw-dev, vbw-qa, vbw-scout, vbw-debugger, vbw-architect

### Changed

- `/vbw:map` Scout task descriptions: Scouts analyze and send findings via SendMessage instead of writing files directly (preserves platform-enforced read-only guarantee)
- `/vbw:map` Step 3 now uses explicit TaskCreate language matching execute skill convention
- Lead agent tools list: removed Task (was inconsistent with "Never spawns subagents" constraint)
- plugin.json author field: split into separate `name` and `url` fields
- Both marketplace.json files: aligned description ("27 commands"), keywords (6 terms), and category ("development")
- README.md: command count updated from 26 to 27 across all mentions; Lead agent table and permission model updated to remove Task

### Fixed

- PreToolUse hook: consolidated two duplicate security-filter entries (Read|Glob|Grep + Write|Edit) into one combined matcher (4 entries → 3)

## [1.0.34] - 2026-02-08

### Added

- Competing hypotheses for `/vbw:debug`: at Thorough effort + ambiguous bugs, spawns 3 parallel debugger teammates via Agent Teams instead of a single serial investigation
- Teammate mode for debugger agent: SendMessage-based structured reporting (hypothesis, evidence, confidence, fix recommendation)
- Delegation directive in `/vbw:execute`: defensive prose preventing team lead from implementing tasks itself (instruction-enforced guardrail)
- Model cost evaluation reference document: analysis of all 6 agent roles confirming current Opus/Sonnet/Haiku split is optimal
- Skill-hook dispatcher (`skill-hook-dispatch.sh`): runtime skill-hook wiring from config.json
- File-guard hook (`file-guard.sh`): blocks writes to files not declared in active plan's `files_modified`
- Plan approval gate: Dev teammates at Thorough effort spawned with `plan_mode_required` (platform-enforced review)
- TaskCreate blockedBy dependencies: wave execution now uses platform-enforced task ordering instead of prose instructions

### Changed

- Agent table in README expanded to 5 columns: Agent, Role, Tools, Denied, Mode
- Hook diagram in README expanded from 4 to 7 event types (added SubagentStop, SessionStart, PreCompact), grouped by purpose (Verification/Security/Lifecycle)
- Permission Model diagram in README: ungrouped Scout and QA (different capabilities), clarified Architect enforcement tiers
- Hook count corrected from "8 hook events" to "12 hooks across 7 event types" across all README mentions
- Architect agent: Bash removed from tools, added to disallowedTools (platform-enforced)
- QA agent description updated from "Read-only" to "Can run commands but cannot write files"
- `task-verify.sh` rewritten: reads stdin for task context, verifies task-specific commits via keyword matching (2+ threshold)
- `qa-gate.sh` rewritten: uses structural verification (SUMMARY.md existence OR conventional commit format) instead of keyword heuristics
- `security-filter.sh` routing expanded: now covers Write|Edit operations on sensitive files (was Read-only)
- Limitations section: "VBW solves them" softened to "VBW addresses all of them", shutdown attributed to platform, file conflicts mention runtime enforcement

### Fixed

- Lead agent missing Bash and WebFetch in README agent table
- README overstatement: "validates writes and commits continuously" replaced with accurate per-script descriptions
- README overstatement: "QA gate before teammate goes idle" replaced with "structural completion gate"
- README overstatement: "Verifies atomic commit exists" replaced with "verifies task-related commit via keyword matching"
- README overstatement: "VBW's team lead handles graceful shutdown sequencing" replaced with platform attribution
- Architect "Not code. Ever." claim now clarifies Edit/Bash are platform-denied while Write-to-plans is instruction-enforced

## [1.0.26] - 2026-02-07

### Added

- `/vbw:new` command: project definition flow (name, requirements, roadmap, CLAUDE.md) extracted from init
- Windows/WSL disclaimer in README "What Is This" section

### Changed

- `/vbw:init` is now technical setup only: environment config (Agent Teams, statusline), directory scaffold, stack detection, skill discovery. No longer asks project questions — points to `/vbw:new` as next step
- Guard clauses in `/vbw:plan`, `/vbw:status`, `/vbw:audit`, `/vbw:ship` updated to point to `/vbw:new` for missing roadmap
- `/vbw:resume` now detects unfilled templates and suggests `/vbw:new` instead of re-running init
- `/vbw:help` lifecycle flow updated: init -> new -> plan -> build -> ship
- README flow diagram, tutorial, and commands table updated for two-step setup

### Fixed

- All hook commands in hooks.json used `${CLAUDE_PLUGIN_ROOT}` which is not available as an env var in hook execution — replaced with glob-based path discovery pattern. This fixes "PreToolUse:Read hook error" on every Read/Glob/Grep call

## [1.0.25] - 2026-02-07

### Changed

- `/vbw:config` now offers interactive selection for common settings (effort, verification tier, max tasks, agent teams) when called without arguments. Direct `<setting> <value>` syntax still works for power users.

## [1.0.24] - 2026-02-07

### Fixed

- `/vbw:whats-new` now shows the current version's changelog when called without arguments (was showing nothing because it looked for entries newer than current)
- Agent activity indicator moved to Line 4 inline before GitHub link

## [1.0.23] - 2026-02-07

### Added

- Agent activity indicator in statusline Line 5: shows "N agents working" when background agents are active (process-based detection, 3s cache)
- Brownfield auto-map: `/vbw:init` now auto-triggers `/vbw:map` when existing codebase detected instead of just suggesting it

### Fixed

- Statusline "Branch: Phase complete}" corruption: removed unused `Status` field from STATE.md parsing that broke pipe-delimited cache format
- Security filter hook errors: fail-open on malformed input, missing jq, or empty stdin instead of crashing
- Sandbox permission errors in `/vbw:whats-new` and `/vbw:update`: removed `cat ${CLAUDE_PLUGIN_ROOT}/VERSION` from context blocks (plugin root is outside working directory sandbox)
- Stale version in `/vbw:update` whats-new suggestion: removed version argument entirely

## [1.0.20] - 2026-02-07

### Added

- Real-time statusline dashboard: context window bar, API usage limits (session/weekly/sonnet/extra), cost tracking, clickable GitHub link, agent team status
- Manifesto section and Discord invite in README
- Statusline screenshot showcase in README Features section

### Changed

- Renamed `/vbw:build` to `/vbw:execute` to avoid security filter collision with `build/` pattern
- Moved directory scaffold into Step 0 of `/vbw:init` so all setup completes before user questions
- Versioned cache filenames in statusline -- auto-clears stale caches on plugin update
- Simplified `/vbw:whats-new` to read directly from plugin root instead of cache paths (fixes sandbox permission errors)
- Improved `/vbw:update` messaging to clarify "since" version in whats-new suggestion

### Fixed

- Security filter no longer blocks `skills/build/SKILL.md` (resolved by rename to `skills/execute/`)
- Usage limits API: added required `anthropic-beta: oauth-2025-04-20` header
- Extra usage credits display: correctly converts cents to dollars
- Statusline `utilization` field: removed erroneous x100 (API returns 0-100, not 0-1)
- Weekly countdown now shows days when >= 24 hours
- Removed hardcoded `/vbw:plan 1` references (auto-detection handles phase selection)

## [1.0.0] - 2026-02-07

### Added

- Complete agent system: Scout, Architect, Lead, Dev, QA, Debugger with tool permissions and effort profiles
- Full command suite: 25 commands covering lifecycle, monitoring, supporting, and advanced operations
- Codebase mapping with parallel mapper agents, synthesis (INDEX.md, PATTERNS.md), and incremental refresh
- Branded visual output: Unicode box-drawing, semantic symbols, progress bars, graceful degradation
- Skills integration: stack detection, skill discovery, auto-install suggestions, agent skill awareness
- Concurrent milestones with isolated state, switching, shipping, and phase management
- Persistent memory: CLAUDE.md generation, pattern learning, session pause/resume
- Resilience: three-tier verification pipeline, failure recovery, intra-plan resume, observability
- Version management: /vbw:whats-new changelog viewer, /vbw:update plugin updater
- Effort profiles: Thorough, Balanced, Fast, Turbo controlling agent behavior
- Deviation handling: auto-fix minor, auto-add critical, auto-resolve blocking, checkpoint architectural

### Changed

- Expanded from 3 foundational commands to 25 complete commands
- VERSION bumped from 0.1.0 to 1.0.0

## [0.1.0] - 2026-02-06

### Added

- Initial plugin structure with plugin.json and marketplace.json
- Directory layout (skills/, agents/, references/, templates/, config/)
- Foundational commands: /vbw:init, /vbw:config, /vbw:help
- Artifact templates for PLAN.md, SUMMARY.md, VERIFICATION.md, PROJECT.md, STATE.md, REQUIREMENTS.md, ROADMAP.md
- Agent definition stubs for 6 agents
