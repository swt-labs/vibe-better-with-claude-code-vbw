# Changelog

All notable changes to VBW will be documented in this file.

## [1.35.0] - 2026-04-19

### Added

- **`lifecycle`** -- Add post-archive lifecycle hook for cleanup after plan archival. (PR #481)
- **`caveman`** -- Integrate caveman token compression language for reduced context usage. (PR #456)
- **`run-all`** -- Add execution contract verification script. (PR #454)
- **`fix`** -- Add fix-commit marker and context for inline QA/UAT. (PR #446)
- **`commands`** -- Deprecate standalone /qa and /verify commands in favor of integrated flow. (PR #439)
- **`state-consistency`** -- Add cross-file state consistency checks at lifecycle boundaries. (PR #420)
- **`debug`** -- Make /debug self-contained by absorbing QA and UAT inline. (PR #415)
- **`summary`** -- Add ac_results frontmatter for acceptance criteria reconciliation. (PR #403)
- **`research`** -- Backfill all frontmatter fields during migration. (PR #401)
- **`research`** -- Add standalone research storage with staleness tracking. (PR #397)
- **`vibe`** -- Add skill evaluation at remediation recovery spawn sites. (PR #393)
- **`testing`** -- Add AskUserQuestion maxItems contract test. (PR #389)
- **`debug`** -- Separate active and completed debug sessions into subdirectories. (PR #387)
- **`debug`** -- Add standalone debug session lifecycle with integrated QA/UAT flow. (PR #385)
- **`skills`** -- Add visible skill evaluation reporting in agent output. (PR #384)
- **`scripts`** -- Add todo detail registry for rich context preservation. (PR #375)
- **`vibe`** -- Auto-continue UAT remediation when re-verification finds issues. (PR #366)
- **`map`** -- Add advisory MCP tool guidance for Scout agents. (PR #355)
- **`lifecycle`** -- Auto-promote known issues to STATE.md Todos at lifecycle boundaries. (PR #354)
- **`report`** -- Add LLM-based classification and template matching for issue filing. (PR #345)
- **`report`** -- Add /vbw:report command for self-diagnosis and bug reporting. (PR #336)
- **`discussion-engine`** -- Add codebase-first assumptions mode. (PR #333)
- **`discussion-engine`** -- Add recommendation-led questions. (PR #331)

### Changed

- **`ghcp`** -- Add custom agentic development flow for GitHub Copilot users. (PR #476)
- **`testing`** -- Sanitize README path example and add docs contract checks. (PR #473)
- **`known-issues`** -- Fail closed on degraded known-issues status probes. (PR #465)
- **`skills`** -- Add Step 5b global path contract test. (PR #463)
- **`testing`** -- Auto-throttle local run-all suites across worktrees. (PR #449)
- **`gitignore`** -- Update .gitignore entries. (PR #442)
- **`report`** -- Add contract test for temp-file diagnostic handoff. (PR #417)
- **`cleanup`** -- Remove accidentally committed fix-issue agent file. (PR #408)
- **`report`** -- Add contract test for template alignment and classification. (PR #399)
- **`copilot`** -- Add Copilot cloud-agent onboarding instructions for VBW. (PR #377)
- **`docs`** -- Clarify UAT remediation round-cap semantics. (PR #372)
- **`ghcp`** -- Expose local VBW development agents for GitHub Copilot. (e1a878b)
- **`gitignore`** -- Add presentation source doc to .gitignore. (2718d3b)

### Fixed

- **`list-todos`** -- Replace AskUserQuestion with display-and-stop pattern. (PR #490)
- **`vibe`** -- Extract AskUserQuestion contract into shared reference. (PR #489)
- **`agents`** -- Prevent stop-hook recovery ambient context and cross-thread contamination. (PR #479)
- **`context`** -- Stabilize cache-context target resolution. (PR #477)
- **`testing`** -- Stabilize run-all overlap auto-tune test. (PR #475)
- **`commands`** -- Consolidate agent settings resolution. (PR #474)
- **`debug-target`** -- Add configurable debug target and root CLAUDE symlink. (PR #472)
- **`tests`** -- Stabilize hook-wrapper cache env isolation. (PR #471)
- **`commands`** -- Eliminate embedded inline plugin-root spans. (PR #468)
- **`run-all`** -- Harden command contracts against local drift. (PR #464)
- **`phase-detect`** -- Harden flaky QA routing under parallel load. (PR #462)
- **`testing`** -- Eliminate statusline SIGPIPE flake. (PR #461)
- **`report`** -- Consolidate diagnostic helpers into /vbw:report. (PR #460)
- **`state-updater`** -- Harden temp file operations against parallel BATS flakiness. (PR #457)
- **`init`** -- Align CLAUDE_CONFIG_DIR prose with resolve-claude-dir.sh semantics. (PR #455)
- **`skills`** -- Unify global skills path resolution around CLAUDE_DIR cascade. (PR #445)
- **`phase-detect`** -- Harden QA pending detection under parallel BATS. (PR #441)
- **`tests`** -- Stabilize live PID fixtures. (PR #440)
- **`session-start`** -- Replace inline sed parser with shared extract_summary_status(). (PR #438)
- **`skills`** -- Correct global install path display to ~/.claude/skills/. (PR #437)
- **`scripts`** -- Remove extract_summary_status() override in recover-state.sh. (PR #432)
- **`tests`** -- Replace hardcoded dead PIDs with get_dead_pid helper. (PR #430)
- **`scripts`** -- Stabilize phase-detect QA pending status under parallel BATS. (PR #429)
- **`vibe`** -- Self-heal retryable phase-detect cache with sentinel and blank handling. (PR #427)
- **`qa-gate`** -- Skip change-evidence checks for plan-amendment-only remediation rounds. (PR #425)
- **`hooks`** -- Bypass task-verify for non-commit tasks. (PR #423)
- **`tests`** -- Harden run_phase_detect retry with exponential backoff. (PR #419)
- **`suggest-next`** -- Add debug-session awareness to fix case. (PR #416)
- **`security-filter`** -- Anchor directory patterns as path components. (PR #412)
- **`tests`** -- Use _ORIG_HOME for real HOME capture after setup_temp_dir. (PR #410)
- **`tests`** -- Fix flaky phase-detect.bats under parallel execution. (PR #409)
- **`report`** -- Persist diagnostics to temp file for reliable issue filing. (PR #400)
- **`qa-result-gate`** -- Support gitignored planning directory evidence in corroboration. (PR #395)
- **`track-known-issues`** -- Aggregate accepted-process-exception outcomes across remediation rounds. (PR #394)
- **`config`** -- Sync config.md settings table with defaults.json. (PR #392)
- **`debug`** -- Handle legacy migration failures in find_latest_unresolved and list. (PR #391)
- **`commands`** -- Address AskUserQuestion maxItems:4 violations. (PR #383)
- **`scripts`** -- Route to needs_uat_remediation when round UAT shows issues_found. (PR #370)
- **`commands`** -- Disambiguate step 4 task list from TaskCreate delegation. (PR #368)
- **`skills`** -- Require explicit skill outcome blocks for subagent spawns. (PR #364)
- **`qa-remediation`** -- Remove hardcoded MAX_ROUNDS=3 cap on remediation loop. (PR #362)
- **`hooks`** -- Fix CC 2.1.94 hook breakage (zsh nomatch, BSD awk locale, test isolation). (PR #359)
- **`qa-remediation`** -- Stop false remediation loops from docs-only rounds and carried known issues. (PR #358)
- **`known-issues`** -- Persist phase known-issues lifecycle through QA remediation. (PR #352)
- **`execute`** -- Enforce real team semantics in /vbw:vibe. (PR #351)
- **`research`** -- Use phase-wide RESEARCH.md naming for Plan mode. (PR #350)
- **`report`** -- Always auto-file issues; remove --file-issue flag. (PR #346)
- **`report`** -- Add scope guardrails to prevent unauthorized side effects. (PR #343)
- **`vibe`** -- Clarify routing prohibition to require AskUserQuestion tool call. (PR #342)
- **`testing`** -- Ungate verify-vibe.sh and add to CI. (PR #334)

## [1.34.1] - 2026-04-03

### Added

- **`hooks`** -- Prefer native `agent_id`/`agent_type` fields for subagent detection across start, stop, health, and compaction hooks, with backward-compatible fallback for legacy payload shapes. (PR #321)
- **`ci`** -- Add Discord release notification workflow that posts rich embeds with release notes when a GitHub release is published. (PR #314)

### Changed

- **`config`** -- Canonicalize `prefer_teams` aliases by removing `when_parallel` as a distinct mode, normalizing legacy values to `always|auto|never` via a shared helper, and adding contract test coverage. (PR #320)
- **`ci`** -- Add `.github/references` to `.gitignore`.

### Fixed

- **`vibe`** -- Fold Milestone UAT Recovery's two sequential AskUserQuestion calls into a single three-option question, eliminating the redundant yes/no entry gate. (PR #327)
- **`vibe`** -- Add explicit `AskUserQuestion` tool-call directives at all confirmation gates in the routing table, co-locating tool instructions with routing decisions. (PR #326)
- **`commands`** -- Add missing tools (AskUserQuestion, Agent, team management) to `allowed-tools` frontmatter across 14 command files, and add contract test for consistency. (PR #323)
- **`archive`** -- Use the Write tool instead of Bash for SHIPPED.md creation so PostToolUse hooks fire for artifact tracking. (PR #319)
- **`verify`** -- Keep execute-time UAT generation human-only by explicitly excluding programmatic and UI-automation checks from UAT in `execute-protocol.md`. (PR #318)
- **`verify`** -- Add `--remediation-kind` filter to `compile-verify-context.sh` so UAT remediation re-verification scans only the UAT directory when both QA and UAT remediation exist. (PR #317)

## [1.34.0] - 2026-04-01

### Added

- **`qa`** -- Add QA gate enforcement that blocks UAT until QA passes, treats deviations as defects, and auto-loops dev agents through a remediation state machine before UAT can start. (PR #296)
- **`qa`** -- Write per-round `R{RR}-VERIFICATION.md` into round directories, making each QA remediation round a self-contained artifact set while preserving phase-level verification as frozen QA history. (PR #299)
- **`scope`** -- Persist milestone-level scope decisions in a new `CONTEXT.md` artifact capturing decomposition rationale, requirement mapping, key decisions, and deferred ideas. Route project-level decisions into STATE.md. (PR #292)
- **`testing`** -- Reduce full test-suite latency from ~4m to ~1m via parallelized BATS execution, CI matrix sharding, auto-sized worker counts, and workspace-scoped cache/temp isolation. (PR #303)

### Fixed

- **`vibe`** -- Route active UAT via metadata-only routing from `phase-detect.sh` and direct file read, eliminating the fragile precomputed extraction payload that caused intermittent zero-issue counts during template expansion. (PR #311)
- **`statusline`** -- Use `-ge` instead of `-gt` for cache mtime comparison so lifecycle artifacts written in the same second correctly invalidate stale statusline values. (PR #309)
- **`uat`** -- Add consistency guard to `extract-uat-issues.sh` that detects when the awk parser produces zero issues but frontmatter declares a non-zero count, outputting `uat_extract_error=true` instead of misleading zeros. (PR #307)
- **`qa`** -- Prevent deviation laundering through metadata-only remediation rounds by hardening classification rules, original FAIL carry-forward, and deterministic gate evidence requirements. Also fix first-UAT scope selection, fail-closed UAT finalization, and statusline lifecycle labeling. (PR #301)
- **`debugger`** -- Enable MCP tool access for Debugger and QA agents by switching from `tools:` allowlists to `disallowedTools:` denylists, and add skill pre-evaluation at spawn points. (PR #289)
- **`plan`** -- Remove team creation from Plan mode so Scout and Lead are always spawned as plain sequential subagents, fixing incorrect concurrent execution that broke Scout-before-Lead dependency. (PR #287)
- **`statusline`** -- Anchor root resolution to script location instead of agent CWD, fixing monorepo scenarios where agents navigate to sub-packages. (PR #267)

## [1.33.2] - 2026-03-24

### Added

- **`scripts`** -- Add `resolve-artifact-path.sh` for deterministic artifact filename resolution, replacing inline LLM-computed filenames across plan, summary, research, context, UAT, and verification artifacts. (PR #277)
- **`agents`** -- Enable MCP tool access for VBW subagents by switching Scout from a restrictive `tools:` allowlist to a `disallowedTools:` denylist pattern, and adding MCP evaluation guidance to orchestrator commands. (PR #280)

### Fixed

- **`hooks`** -- Exempt remediation round summaries (`R{RR}-SUMMARY.md`) from the file-guard terminal-status check that blocks SUMMARY writes with non-terminal status values. (PR #255)
- **`state`** -- Restore canonical `## Current Phase` section in STATE.md after milestone archive, introduce shared phase-state helpers, and harden brownfield/archive recovery for consistent phase status across all downstream readers. (PR #256)
- **`statusline`** -- Resolve `.vbw-planning/config.json` by walking up from CWD instead of using bare relative paths, fixing monorepo subdirectory hook execution. (PR #259)
- **`vibe`** -- Re-route after milestone UAT "Start fresh" instead of dead-ending, by re-running phase-detect after marking milestones as remediated. (PR #269)
- **`phase-detect`** -- Add `needs_verification` as a first-class state to eliminate ambiguous `auto_uat` routing, and prohibit UAT delegation to subagents. (PR #271)
- **`uat`** -- Fix `advance` from `verify` stage to start a new remediation round instead of dead-ending as a no-op. (PR #282)
- **`uat`** -- Normalize LLM-generated UAT status synonyms (`all_pass`, `passed`, `verified`, etc.) to canonical forms so phase-detect recognizes them as terminal statuses. (PR #284)

## [1.33.1] - 2026-03-17

### Added

- **`statusline`** -- Normalize context percentages and X/Y totals to Claude Code's usable autocompact window, including override-aware calculations for larger context windows. (PR #250)

### Changed

- **`docs`** -- Clarify the v1.33.0 release wording across the changelog, Discord draft, and published GitHub release notes. (PR #245)
- **`docs`** -- Remove the temporary v1.33.0 Discord draft file from the repository. (PR #247)

### Fixed

- **`statusline`** -- Treat HTTP 429 usage responses as stale OAuth tokens, back off retries to 5 minutes, and skip usage fetches when nonessential traffic is disabled. (PR #251)

## [1.33.0] - 2026-03-14

### Added

- **`remediation`** -- Store UAT remediation artifacts in dedicated `remediation/round-XX/` directories with `RXX-*` filenames, while keeping legacy flat layouts readable via fallback logic. (PR #236)
- **`remediation`** -- Add dedicated remediation research, plan, and summary templates so remediation rounds use their own structured artifacts instead of overloading phase-level files. (PR #236)
- **`statusline`** -- Add four display controls to hide the limits line, hide it only for API-key sessions, suppress the build/agent line in tmux, or collapse the statusline to a single line in tmux. (PR #118)
- **`statusline`** -- Color the `[VBW]` badge dynamically based on whether VBW context is active in the current session. (PR #213)
- **`dx`** -- Add `scripts/dev-setup.sh` plus an optional `claude-vbw` launcher to automate local VBW setup, teardown, status checks, and launching Claude Code against a local clone. (PR #212)
- **`ci`** -- Require pull requests to link an issue, recognizing closing keywords, bare issue refs, full issue URLs, and sidebar-linked issues. (PR #194)

### Changed

- **`qa`** -- QA now persists `VERIFICATION.md` through `write-verification.sh` directly instead of relying on a heredoc escape hatch or parent-command passthrough. (PR #231)
- **`skills`** -- Fix forced skill evaluation for spawned agents by moving skill injection to `SubagentStart`, so team and subagent workflows reliably receive the skills they need; also stop accidental YAML turn ceilings from capping agents that should be unlimited. (PR #197)
- **`session-start`** -- Warn when GSD is co-installed to reduce cross-wired `/gsd:*` versus `/vbw:*` workflows in VBW sessions. (PR #197)
- **`remediation`** -- Make remediation planning and execution self-contained and sequential so remediation no longer inherits normal execute-mode wave/team behavior or creates unnecessary worktrees. (PR #236)
- **`todo`** -- Make `/vbw:todo` and `/vbw:list-todos` fail cleanly in restricted permission modes with actionable guidance. (PR #227)
- **`release`** -- Make release-audit changelog insertion non-interactive: generated entries are written immediately and completed before the separate README prompt. (PR #243)
- **`prompts`** -- Add and clarify AskUserQuestion spacing guidance so dialogs do not obscure surrounding output. (PR #241)
- **`config`** -- Change the default `prefer_teams` setting from `always` to `auto` so VBW only spins up teams when parallelism is useful. (PR #236)

### Fixed

- **`verify`** -- Limit post-remediation re-verification to the latest remediation round, carry prior UAT issues forward into targeted tests, and write remediation UAT files into the round directory instead of the phase root. (PR #236)
- **`compact`** -- Clear stale `.context-usage` data at session boundaries and stamp it with session IDs so new sessions do not inherit false high-context warnings from old sessions. (PR #239)
- **`statusline`** -- Fix stale completion counts after reset/undo, count only valid completed summaries, and render remediation/UAT lifecycle states more accurately. (PRs #197, #236)
- **`statusline`** -- Fix first-render reliability by seeding caches on session start and avoiding blocking stdin reads. (PR #236)
- **`agents`** -- Add explicit mechanical `shutdown_response` tool-call instructions so shutdown requests are acknowledged through the team protocol. (PR #226)
- **`teams`** -- Clean stale or orphaned VBW team directories before `TeamCreate` and after `TeamDelete` to prevent ghost agent labels in Claude Code's status bar. (PR #230)
- **`worktree`** -- Fully remove residual `.vbw-worktrees/` directories and stale git worktree metadata during cleanup, including locked worktrees. (PR #229)
- **`watchdog`** -- Kill tmux panes that get stuck indefinitely during compaction. (PR #190)
- **`agents`** -- Prune dead PIDs from `.agent-pids` on session start. (PR #228)
- **`ci`** -- Harden linked-issue enforcement with `synchronize` coverage, tighter matching rules, clearer failure messages, explicit permissions, and updated docs/templates. (PR #196)

## [1.32.2] - 2026-02-26

### Fixed

- **`release`** -- Finalize Step 4 now checks remote branch existence before attempting deletion, preventing spurious error output when the branch was already removed by PR merge. (PR #184)

## [1.32.1] - 2026-02-26

### Fixed

- **`release`** -- Finalize now auto-merges the release PR (marks ready, waits for checks, merges, pulls) instead of requiring manual GitHub merge. Prepare returns to main after pushing release branch. Changelog extraction uses awk instead of sed for macOS compatibility. (PR #181)

## [1.32.0] - 2026-02-26

### Added

- **`release`** -- Version bump now accounts for pending release branches. Computes bump base as highest of local, remote, and pending semver values with dry-run/no-push safety contracts preserved. (PR #178)
- **`plugin`** -- Exclude release command from marketplace installs via `.claude-plugin/exclude` patterns. (PR #161)

### Changed

- **`gitignore`** -- Ignore `.claude` directory to keep user-local Claude Code state out of version control. (PR #158)

### Fixed

- **`release`** -- Correct git date format placeholders (`%cd --date=short` instead of `%Y-%m-%d`) and clarify tag existence checks to test stdout content rather than exit code. (PR #175)
- **`release`** -- Robust grep pattern eliminates false positives from `[Unreleased]` section indirection; changelog entries now target versioned headers directly. (PR #173)
- **`release`** -- Auto-create versioned changelog section and populate from merged PRs and commits when section is missing. (PR #170)
- **`release`** -- Two-phase prepare/finalize workflow respects branch protection rules by using draft PRs instead of direct pushes to main. (PR #163)
- **`commands`** -- Add symlink fallback and robust grep pattern for plugin root resolution when `CLAUDE_PLUGIN_ROOT` is unset. (PR #168)
- **`commands`** -- Add phase-detect fallback to prevent template-block race condition when phase-detect.sh runs concurrently. (PR #165)
- **`commands`** -- Revert session-key from SHA1 to deterministic value and inject `session_id` from hook stdin for reliable session tracking. (PR #154)
- **`planning`** -- Enforce deterministic plan filename convention (`PLAN.md`) to prevent naming drift across phases. (PR #164)
- **`auto-uat`** -- Trigger verification mid-milestone before continuing execution, ensuring UAT gates are not bypassed. (PR #149)

## [1.31.0] - 2026-02-23

### Added

- **`auto-uat`** -- Auto UAT detection and routing for unverified phases. New `auto_uat` config flag runs `/vbw:verify` inline after QA instead of only suggesting it. Config controls whether UAT runs inline or is merely suggested. (PR #135)
- **`require-phase-discussion`** -- New `require_phase_discussion` config flag gates plan execution behind a mandatory discussion step per phase. Undiscussed phases route to `needs_discussion` instead of jumping to `needs_plan_and_execute`. (PR #123)
- **`deterministic-verification`** -- Deterministic VERIFICATION.md generation via `write-verification.sh`. Per-category 6-col verification tables derived from §4–§7 semantics. Replaces ad-hoc QA agent output with structured, reproducible verification artifacts. (PR #138)
- **`remediation`** -- Seeding of ROADMAP.md and STATE.md for remediation phases. Pre-seed CONTEXT.md with UAT report for in-phase remediation. Pre-seeded discussion annotations in Next Up hints. Skip discuss step for in-phase UAT remediation.
- **`config`** -- Multi-location `CLAUDE_CONFIG_DIR` fallback across all scripts and commands. Removes hardcoded `$HOME/.claude` assumptions. (PR #116 by @halindrome)
- **`context`** -- Pre-flight context guard to prevent mid-workflow compaction from disrupting agent execution.
- **`brand`** -- Horizontal bars format for LLM-generated output, replacing box-drawing characters.
- **`suggest-next`** -- Annotate pre-seeded discussion in Next Up hints for remediation phases.

### Changed

- **`docs`** -- Source-validated GSD comparison document added. Consolidated 6 config sections into unified Configuration section in README. Execution Model section added. Contributing guide rewritten with QA review process and local dev setup. Default settings reference and runtime feature flags details added. (PRs #133, #125, #119)
- **`verify`** -- Added "Skip" option for checkpoint testing. CHECKPOINT loop now blocking with explicit wait-for-input via AskUserQuestion. Clarified UAT test requirements and banned automated checks. Updated code blocks to specify language for formatting clarity.
- **`suggest-compact`** -- Replaced `eval jq` with safe direct assignment. Dynamic token cost calculated from actual file sizes instead of hardcoded estimates.
- **`suggest-next`** -- Removed misleading `--resume` from verify `issues_found` output.
- **`execute-protocol`** -- Enhanced user interaction for first test results with CHECKPOINT and AskUserQuestion.
- **`commands`** -- Replaced shared temp file with deterministic symlink path. Updated inline script execution syntax for clarity. Used fenced code blocks for template processor execution. Removed dead `CLAUDE_PLUGIN_ROOT` fallback in `!` expressions.
- **`codeowners`** -- Added dpearson2699 as code owner.
- **`ci`** -- Improved ShellCheck and shell syntax check steps. Removed branch restriction for pull requests.

### Fixed

- **`phase-detect`** -- Prioritize earlier incomplete phases over later UAT issues (fixes #145). Add `require_phase_discussion` gate to earlier-incomplete scan. Collect all phases with UAT issues. Exclude SOURCE-UAT from UAT globs and cross-reference remediation phases. Implement `latest_non_source_uat` function for UAT file retrieval. Replace `ls`-pipe patterns with glob for-loops. Use `find` for file counting instead of `ls|wc -l`. Exclude SOURCE-UAT.md from UAT scanning globs. (PRs #146, #142)
- **`archive`** -- Detect unresolved UAT in shipped milestones, block archive on UAT issues. Deterministic milestone slug derivation via script. (PR #121)
- **`plugin-root`** -- Replace model-executed `CLAUDE_PLUGIN_ROOT` with inline load-time resolution. Content validation and process-tree fallback for `--plugin-dir`. Hardened resolver policy and runtime callsites. Replace `ls` glob with `find` for zsh compatibility. Use temp file for deterministic plugin root resolution. Added preamble for plugin root resolution in skills. (PR #137)
- **`symlink`** -- Canonicalize symlink target via `pwd -P` to survive cache deletion. Spin-wait guard for symlink race condition. (PR #144)
- **`hooks`** -- Add quad-resolution fallback for local dev mode (`--plugin-dir`).
- **`uat`** -- Flow discovered issues into remediation pipeline. Enhanced UAT issue detection and remediation suggestions. Make CHECKPOINT loop blocking with explicit wait-for-input. Multiple QA rounds: pad normalization, orphan guard, mid-execution guard, numeric sort, `sort -V` portability. (PR #142)
- **`vibe`** -- Read phase-detect live to avoid stale routing state. Fallback to preamble phase-detect on transient live-read failures. Avoid shared default session key collisions. Standardize deterministic session-key fallback. Run phase-detect.sh atomically in preamble.
- **`resume`** -- Use phase-detect.sh for deterministic state detection instead of inline logic.
- **`recovery`** -- Automatic state recovery wired into session-start via `recover-state.sh`. 5 rounds of QA hardening.
- **`remediation`** -- Pre-seed CONTEXT.md with UAT report for in-phase remediation. Skip discuss step for in-phase UAT remediation. Update sed commands to create backup files during ROADMAP.md and STATE.md edits. Seed ROADMAP.md and STATE.md for remediation phases.
- **`guards`** -- Narrow milestone path guards to prevent false positives. Harden milestone path guards in bash scripts.
- **`routing`** -- Harden milestone path guards in bash scripts to prevent cross-milestone pollution.
- **`cache`** -- Handle empty plugin cache globs under pipefail. Bridge local dev plugin root into marketplace cache. 5 rounds of QA hardening on cache operations.
- **`cache-nuke`** -- Handle empty plugin cache globs under `pipefail`.
- **`config`** -- Remove dir-existence check from `resolve-claude-dir.sh`. Fix bare `HOME/.claude` references in scripts. Auto-UAT runs UAT inline, not just suggests.
- **`session-start`** -- Bridge local dev plugin root into marketplace cache. Remove unused `PHASES_DIR` assignment.
- **`verify`** -- Add trailing newline to CHECKPOINT expected line. Use bash builtins for cross-platform portability. Enhance user interaction by adding AskUserQuestion for checkpoint responses.
- **`lint`** -- Resolve SC2034 warnings in `extract-verified-items.sh`.
- **`tests`** -- Hardened for BATS 1.10 compatibility — avoid backtick escaping incompatible with bats 1.10. Harden stale cache test against SIGINT from bats runner. Plugin root resolver safety and callsite checks. 6 rounds of QA on test suite. Regression tests for deterministic path pattern.
- **`docs`** -- Update defaults for lease locks and event recovery settings. Fix all markdown lint errors in README. Remove `.markdownlint.json` configuration file. Update plugin root resolution documentation.

## [1.30.1] - 2026-02-20

### Added

- **`session-start`** -- Shipped milestones detection and QA verification script for post-ship validation.
- **`context`** -- Pre-flight context guard to prevent mid-workflow compaction from disrupting agent execution.

### Changed

- **`milestone`** -- Removed ACTIVE-file milestone indirection. Slug derivation and decision/todo extraction enhanced in milestone scripts.
- **`flags`** -- Partially reverted flag graduation — restored 9 flags as configurable. Legacy key fallback added to all consumer scripts. Runtime defaults aligned with legacy fallback behavior.
- **`suggest-compact`** -- Replaced eval jq with safe direct assignment. Dynamic token cost from actual file sizes.
- **`worktree`** -- Defaults to off. Fixed merge args, normalized boundary paths, added branch-exists fallback.

### Fixed

- **`crash-recovery`** -- Avoid false fallback and preserve last words when SUMMARY.md missing.
- **`uat`** -- 4 rounds of QA fixes: pad normalization, orphan guard, mid-execution guard, numeric sort, sort -V portability, false remediation fallback.
- **`vibe`** -- Hardened UAT remediation routing and chain enforcement. Auto-route UAT remediation from /vbw:vibe.
- **`milestone`** -- Fixed rename-default-milestone slug derivation, post-ship state, collision guard, phases/ guard, generic tag strip, contract scope.
- **`scripts`** -- Null-safe jq patterns for false-default booleans. Tightened artifact globs. Removed unused variables (SC2034). Removed unreachable exit in validate-contract.sh.
- **`config`** -- Graduated v2_token_budgets. Stripped graduated V2/V3 flags from brownfield configs. Synced EXPECTED_FLAG_COUNT after worktree_isolation addition.
- **`tests`** -- Updated 90+ tests for graduated flags and portable paths. Fixed BATS_TEST_TMPDIR usage. Updated rollout-stage counts.

## [1.30.0] - 2026-02-19

### Added

- **`crash-recovery`** -- Agent crash recovery via `last_assistant_message` from CC 2.1.47 SubagentStop hook. `agent-stop.sh` captures agent final output to `.agent-last-words/` when SUMMARY.md missing. `validate-summary.sh` uses crash recovery files as fallback (60s freshness window). `session-start.sh` auto-cleans stale files (7-day TTL). Event log tracks `agent_shutdown` events with `last_message_length` metric.
- **`bash-classifier-tests`** -- 55 new BATS tests validating all 26 VBW hook bash patterns against CC 2.1.47 stricter permission classifier. Tests cover hook-wrapper.sh resolution, individual script invocations, bash-guard.sh pattern matching, and end-to-end integration. All patterns confirmed classifier-safe with zero changes needed to hooks.json.
- **`agent-memory`** -- Native `memory` frontmatter added to all 7 agents. Core agents (lead, dev, qa, debugger, architect) use `memory: project` for cross-session learning. Ephemeral agents (scout, docs) use `memory: local`.
- **`agent-restrictions`** -- Native `Task(agent_type)` spawn restrictions added to all 7 agents. Lead can only spawn Dev. Debugger can only spawn Debugger (competing hypotheses). Dev, architect, docs cannot spawn agents. Scout and QA already lacked Task capability.
- **`cc-version-table`** -- Claude Code version requirements table added to README with minimum versions for key features (hooks, teams, classifier, memory).
- **`token-analysis`** -- v1.30.0 token analysis document covering CC Alignment + Worktree Isolation impact: 85 scripts, 57 test files, 825 BATS tests. Per-request +12% (enforcement content), 73% reduction vs stock teams.
- **`worktree-isolation`** — Git worktree-per-plan isolation for Dev agents
  (6 scripts, enabled by default via `worktree_isolation` config, set `"off"` to disable).

### Changed

- **`feature-flags`** -- Graduated 20 always-true feature flags (6 v2_*, 14 v3_*). Removed dead else-branches from 18+ scripts. Consolidated duplicate flags (`v3_lock_lite` → `v3_lease_locks`, `v3_contract_lite` → `v2_hard_contracts`). Graduated v3 observability flags (metrics, schema_validation, smart_routing, monorepo_routing, validation_gates, delta_context).
- **`config`** -- `v2_token_budgets` now defaults to `false` in config/defaults.json. CC manages context natively.
- **`compaction`** -- Plan mode compaction workaround removed (CC 2.1.47 handles natively). Instructions updated to clarify CC-native vs VBW-specific behavior.
- **`update`** -- `/vbw:update` no longer displays restart requirement. Changes active immediately (CC 2.1.45+).
- **`token-budgets`** -- Added inline documentation to config/token-budgets.json explaining budget sizing rationale (1-4% of agent context windows) and per-task complexity scaling (0.6x-1.6x multipliers).

### Deprecated

- **`file-guard`** -- `scripts/file-guard.sh` marked as worktree-deprecation candidate with header comment.

### Removed

- **`lock-lite`** — Deprecated script removed (replaced by lease-lock.sh).

## [1.21.31] - 2026-02-19

### Added

- **`skills`** -- Installation scope selection step (project vs global) when installing skills. (PR #91 by @Aperrix)
- **`discovered-issues`** -- Pre-existing test failures surfaced as "Discovered Issues" across `/vbw:fix`, `/vbw:debug`, `/vbw:qa`, and `/vbw:verify` instead of being silently dropped. New DEVN-05 deviation code for dev agent. (PR #99 by @dpearson2699)
- **`debugger-report`** -- New `debugger_report` schema type replacing incorrectly-shaped `blocker_report` usage by the Debugger agent. Role Authorization Matrix updated. (PR #99 by @dpearson2699)
- **`state-persistence`** -- Root STATE.md content (todos, key decisions, project-level notes) now persists across milestone shipping. New `migrate-orphaned-state.sh` and `persist-state-after-ship.sh` scripts. (PR #103 by @dpearson2699)

### Changed

- **`bootstrap`** -- Codebase mapping bootstrap across all agents now uses META.md gating and "whichever exist" qualification to avoid wasted tool calls. Compaction re-reads codebase files. (PR #99 by @dpearson2699)
- **`bootstrap`** -- Key Decisions section removed from CLAUDE.md template. Existing decision rows migrated to STATE.md. Deprecated section handling added. (PR #93 by @dpearson2699)
- **`requirements`** -- Added minimum Claude Code version table to README documenting CC 2.1.47+ requirement for agent teams model routing and plan mode native support.

### Fixed

- **`help`** -- CLAUDE_CONFIG_DIR fallback added to backtick expansion in help.md for non-standard config paths. (PR #101 by @halindrome)
- **`hooks`** -- Circuit breaker added to `task-verify.sh` preventing infinite loop when failed verification re-triggers itself. Expanded stop words in session-stop.sh. (PR #95 by @dpearson2699)

### Compatibility

- **Agent Teams Model Routing** -- Requires Claude Code >= 2.1.47. Earlier versions had silently broken model routing for team teammates, causing all agents to use the default model instead of role-specific model profiles. If you experience agents using incorrect models (e.g., all agents using Sonnet when configured for Opus/Haiku), upgrade to Claude Code 2.1.47 or later.

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

