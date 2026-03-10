# VBW vs GSD — Source-Code-Validated Comparison

**Date:** 2026-07-22
**GSD version reviewed:** v1.20.5 (commit `131f24b`)
**VBW version reviewed:** v1.30.0+
**Source:** GSD repository at `gsd-build/get-shit-done`, VBW local workspace
**Method:** Every claim validated against actual source code via GitHub API, not READMEs or marketing

---

## Executive Summary

VBW and GSD both solve the same core problem — replacing ad-hoc AI coding with structured, phased development workflows. Both are mature, thoughtfully designed systems with significant overlap in philosophy and capability. The key difference is enforcement mechanism: VBW enforces quality gates via platform hooks (bash scripts that return exit code 2 to block tool execution), while GSD enforces quality standards via instruction-level workflows (markdown directing agent behavior) combined with a comprehensive Node.js CLI for verification tooling and 3 advisory hooks.

This document corrects factual inaccuracies in the earlier `vbw-vs-paul-vs-gsd-analysis.md`, which inherited unverified claims about GSD from PAUL's comparison document rather than examining GSD's source code directly.

---

## Corrections to Prior Analysis

The earlier analysis (`vbw-vs-paul-vs-gsd-analysis.md`) made several claims about GSD that do not hold up against the actual source code. These corrections are listed with source references.

### 1. "GSD's primary goal is to ship fast"

**Prior claim:** GSD optimizes for speed. PAUL optimizes for quality. VBW does both.

**Source reality:** GSD's `README.md` describes itself as "a meta-prompting, context engineering and spec-driven development system." Its core value proposition is solving **context rot** — the problem where AI assistants lose coherent state across long development tasks. GSD's workflow includes mandatory discussion phases (`discuss-phase.md`, 18.6KB), research phases with parallel researcher agents (`gsd-phase-researcher`, `gsd-project-researcher`, `gsd-research-synthesizer`), plan verification with 8 dimensions (`gsd-plan-checker`, 24.2KB), and goal-backward verification (`gsd-verifier`, 16.9KB).

The name "Get Shit Done" is branding, not an optimization target. GSD's planner explicitly targets ~50% context usage per plan to leave room for verification. The context monitor warns at 35%/25% remaining context.

**Corrected position:** Both GSD and VBW optimize for structured, quality development. The speed-vs-quality framing was from PAUL's marketing comparison and does not reflect GSD's actual design.

### 2. "GSD has flexible loop closure"

**Prior claim:** GSD's review is implicit. VBW enforces mandatory loop closure.

**Source reality:** GSD's gsd-executor agent (`agents/gsd-executor.md`, 17.5KB) creates SUMMARY.md as part of its execution protocol — this is mandatory per the agent's instructions. The execute-phase workflow (`get-shit-done/workflows/execute-phase.md`, 16.7KB) spot-checks SUMMARY claims. The gsd-verifier creates VERIFICATION.md documenting goal achievement. `gsd-tools.cjs` provides `verify-summary`, `verify phase-completeness`, and `verify artifacts` commands.

**The real difference:** GSD enforces loop closure via agent instructions + CLI verification tools. VBW enforces it via agent instructions + platform hooks with exit code 2 (`hard-gate.sh`, `qa-gate.sh`, `archive-uat-guard.sh`). Both systems require SUMMARY.md — VBW blocks tool execution if it's missing, GSD relies on agents following their instructions.

**Corrected position:** Both enforce loop closure. VBW's enforcement is mechanically stronger (platform hooks that the model cannot bypass). GSD's enforcement is instruction-level but comprehensive (agent protocols + CLI verification suite).

### 3. "GSD quality gates are completion-based"

**Prior claim:** GSD checks completion. VBW and PAUL check acceptance.

**Source reality:** GSD has **goal-backward verification** via `gsd-verifier` (`agents/gsd-verifier.md`, 16.9KB). The verifier starts from desired outcomes and derives testable conditions. GSD's `get-shit-done/references/verification-patterns.md` (16.5KB) defines a 4-level artifact verification framework:

| Level | Check | Automatable? |
|-------|-------|-------------|
| 1. Exists | File present at expected path | Yes |
| 2. Substantive | Real implementation, not stub/placeholder | Yes |
| 3. Wired | Connected to rest of system | Yes |
| 4. Functional | Actually works when invoked | Often human-required |

The plan checker (`gsd-plan-checker`, 24.2KB) verifies plans across 8 dimensions including requirement coverage, task completeness, dependency correctness, key links, scope sanity, verification derivation, context compliance, and Nyquist compliance.

**Corrected position:** GSD is acceptance-based, not completion-based. Both systems use goal-backward/acceptance-driven verification.

### 4. "GSD presents menus / has multiple decision flows"

**Prior claim:** GSD shows multiple options. VBW routes to a single best path.

**Source reality:** GSD's resume-project workflow (`get-shit-done/workflows/resume-project.md`, 9KB) detects project state and routes to a single next action. It checks for incomplete work (`.continue-here` files, plans without summaries, interrupted agents), presents a status box, and routes to the appropriate next workflow. GSD's `AskUserQuestion` API provides structured option selection throughout, but the default flow is state-detected routing.

**Corrected position:** Both systems detect state and suggest a single next action. Feature parity.

### 5. "GSD session handoff is implicit"

**Prior claim:** GSD uses implicit `.continue-here.md`. VBW has auto-persistent state.

**Source reality:** GSD's `pause-work.md` (2.9KB) creates **explicit** `.continue-here.md` files with structured sections: position in workflow, completed work summary, remaining work, key decisions made, current blockers, mental context, and next concrete action. The file is committed as a WIP commit. `resume-project.md` reads `.continue-here`, STATE.md, and PROJECT.md and reconstructs full context.

**The real difference:** GSD requires explicit `/gsd:pause-work` to create a handoff file. VBW auto-persists state via `.execution-state.json` + `event-log.jsonl`, so `/vbw:resume` works from cold without prior `/vbw:pause`. VBW's crash recovery via event-sourced state reconstruction (`recover-state.sh`) is genuinely more robust.

**Corrected position:** GSD's handoff is explicit (structured files), not implicit. VBW's advantage is auto-persistence and crash recovery — state survives without explicit pause.

### 6. "GSD scope control is guidance-only"

**Prior claim:** GSD uses scope guidance. VBW enforces boundaries with hooks.

**Source reality:** GSD's `discuss-phase.md` (18.6KB) includes a `<scope_guardrail>` section with explicit heuristics: "Does this clarify how we implement what's already in the phase, or does it add a new capability that could be its own phase?" It captures out-of-scope suggestions in a "Deferred Ideas" section. GSD's executor (`gsd-executor.md`) defines exactly 4 allowed deviation types: auto-fix bugs, auto-add missing critical functionality, auto-fix blocking issues, and ask about architectural changes. Everything else requires stopping.

**The real difference:** GSD's scope enforcement is instruction-level (agent follows rules in markdown). VBW's scope enforcement is instruction-level + hook-level (`file-guard.sh` blocks writes to undeclared files, `lease-lock.sh` provides file-level locking, `bash-guard.sh` intercepts destructive commands).

**Corrected position:** GSD has structured scope rules with deviation constraints. VBW adds platform-enforced file access control on top of instruction-level rules. VBW's enforcement is stronger.

### 7. "GSD has no platform hooks"

**Prior claim:** GSD has no platform-level hooks (compared to VBW's 21 handlers).

**Source reality:** GSD has 3 JavaScript hooks compiled via esbuild:

| Hook | Event | Function |
|------|-------|----------|
| `gsd-context-monitor.js` | PostToolUse | Warns agent at ≤35% remaining context (WARNING), ≤25% (CRITICAL). Debounced. Injects warnings as `additionalContext` |
| `gsd-statusline.js` | PostToolUse | Displays model, current task, directory, context usage bar. Writes bridge JSON for context monitor |
| `gsd-check-update.js` | SessionStart | Background npm version check. Spawns detached child process |

**The real difference:** GSD's 3 hooks are all **advisory** (informational/warning). VBW's 25 hooks include **blocking** hooks (exit code 2) that prevent tool execution. GSD has no PreToolUse hooks — no platform-level file access control, no destructive command interception, no security filtering.

**Corrected position:** GSD has 3 hooks (advisory). VBW has 25 hooks (mix of advisory and blocking). Both use the platform hook system; VBW uses it for enforcement, GSD uses it for awareness.

### 8. "GSD has no formal QA"

**Prior claim in capabilities table:** GSD has no three-tier automated QA.

**Source reality:** GSD has:
- `gsd-verifier` agent (16.9KB): Goal-backward verification, creates VERIFICATION.md
- `verify-work.md` workflow (14.9KB): Conversational UAT testing with pass/fail/skip, auto-diagnosis via parallel debug agents, auto-plans gap closure
- `gsd-tools.cjs` verification suite: `verify plan-structure`, `verify phase-completeness`, `verify references`, `verify commits`, `verify artifacts`, `verify key-links`
- `gsd-plan-checker` agent (24.2KB): 8-dimension plan verification

**The real difference:** GSD's QA is one tier (verifier agent + UAT), invoked per workflow. VBW has three tiers (Quick 5-10 checks, Standard 15-25, Deep 30+) with the tier selected based on effort profile. VBW's QA is a dedicated agent role (`vbw-qa`) with platform-denied Write/Edit tools; it persists VERIFICATION.md only through a deterministic writer script (`write-verification.sh`). GSD's verifier has full tool access.

**Corrected position:** GSD has formal QA via its verifier agent and UAT workflow. VBW has tiered QA with platform-enforced agent permissions.

### 9. "GSD's codebase mapping is less capable than VBW's 4 scouts"

**Prior claim:** VBW's codebase mapping with "4 parallel Scout teammates" exceeds GSD's single-command map.

**Source reality:** GSD's `/gsd:map-codebase` spawns **4 parallel** `gsd-codebase-mapper` agents, each with a focus area:

| Agent Focus | Output Documents |
|-------------|-----------------|
| `tech` | STACK.md, INTEGRATIONS.md |
| `arch` | ARCHITECTURE.md, STRUCTURE.md |
| `quality` | CONVENTIONS.md, TESTING.md |
| `concerns` | CONCERNS.md |

This produces 7 structured analysis documents consumed by downstream agents during planning and execution. The codebase mapper agent (`agents/gsd-codebase-mapper.md`, large file) includes detailed templates for each document type with prescriptive guidance.

**Corrected position:** Both systems use 4 parallel agents for codebase mapping. GSD produces 7 output documents; VBW's scouts produce consolidated codebase maps. Comparable capability.

---

## Architecture Comparison

### System Scale

| Metric | VBW | GSD |
|--------|-----|-----|
| **Slash commands** | 24 | 30 |
| **Workflows/protocols** | 11 references + execute protocol | 30 workflow files |
| **Agents** | 7 (Lead, Dev, QA, Scout, Debugger, Architect, Docs) | 11 (Executor, Verifier, Planner, Plan-Checker, Debugger, Codebase-Mapper, Phase-Researcher, Project-Researcher, Research-Synthesizer, Roadmapper, Integration-Checker) |
| **Platform hooks** | 25 handlers across 11 event types | 3 handlers across 2 event types |
| **Scripts** | ~97 bash scripts | 1 build script + gsd-tools.cjs (22KB CLI with ~30 subcommands) |
| **Test files** | testing/ + tests/ directories | 7 test files (.cjs, Node's test runner) |
| **Implementation language** | Bash + Markdown | JavaScript + Markdown |
| **Distribution** | Claude Code marketplace plugin | npm package (`get-shit-done-cc`) |
| **State directory** | `.vbw-planning/` | `.planning/` |
| **Platform support** | Claude Code only | Claude Code, OpenCode, Gemini CLI |

### Enforcement Philosophy

Both systems implement the same lifecycle (question → plan → execute → verify → archive) with the same artifacts (PROJECT.md, ROADMAP.md, STATE.md, PLAN.md, SUMMARY.md, VERIFICATION.md). The critical difference is HOW rules are enforced:

**GSD: Instruction-Level + Advisory Hooks + CLI Tooling**

```
┌─────────────────────────────────────────────────────────────┐
│ Workflow .md files define steps → Agent .md files define    │
│ rules → gsd-tools.cjs provides verification CLI → 3 hooks  │
│ provide context awareness (advisory)                        │
│                                                             │
│ Enforcement: Agent follows instructions. CLI verifies       │
│ artifacts. Hooks warn about context. Nothing blocks tool    │
│ execution at platform level.                                │
└─────────────────────────────────────────────────────────────┘
```

**VBW: Instruction-Level + Blocking Hooks + Script Enforcement**

```
┌─────────────────────────────────────────────────────────────┐
│ Commands define steps → Agent .md files define rules →      │
│ ~97 bash scripts enforce + verify → 25 hooks intercept      │
│ tool calls (mix of advisory and blocking)                   │
│                                                             │
│ Enforcement: Agent follows instructions. Scripts verify     │
│ artifacts. Hooks BLOCK tool execution on violations         │
│ (exit code 2). Platform enforces agent tool permissions.    │
└─────────────────────────────────────────────────────────────┘
```

### Where This Matters

| Scenario | GSD | VBW |
|----------|-----|-----|
| Agent tries to write undeclared file | Instruction says don't → agent may or may not comply | `file-guard.sh` PreToolUse hook → exit 2, write blocked |
| Agent skips SUMMARY.md | Instruction says create it → agent may skip under pressure | `hard-gate.sh` + `qa-gate.sh` → exit 2, execution blocked |
| Agent runs `rm -rf` | No interception | `bash-guard.sh` PreToolUse hook → exit 2, command blocked |
| Agent accesses `.env` file | No interception | `security-filter.sh` PreToolUse hook → exit 2, read blocked |
| Context running low | `gsd-context-monitor.js` warns at 35%/25% | No equivalent real-time hook (VBW uses token budgets per-role) |
| Read-only agent tries to write | Agent instructions say read-only | Platform-enforced `disallowedTools` in agent YAML |
| Context compacted | No hook | `compaction-instructions.sh` injects preservation priorities; `post-compact.sh` verifies critical context survived |

---

## Feature-by-Feature Comparison

### Project Initialization

| Feature | VBW | GSD |
|---------|-----|-----|
| **Command** | `/vbw:init` + `/vbw:vibe Bootstrap` | `/gsd:new-project` |
| **Questioning** | Structured discussion via `discussion-engine.md` | Deep questioning via `questioning.md` with checklist |
| **Brownfield detection** | Stack detection via `detect-stack.sh` | Existing code detection + `/gsd:map-codebase` offer |
| **Auto mode** | Pure-vibe autonomy loops all phases | `--auto` flag chains discuss → plan → execute |
| **Config options** | Effort (4 levels) + Autonomy (4 levels) + Work profiles | Mode (YOLO/Interactive) + Depth (3 levels) + Agent toggles |
| **Artifacts created** | PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, CLAUDE.md, config.json | PROJECT.md, ROADMAP.md, STATE.md, config.json |

GSD's questioning methodology (`get-shit-done/references/questioning.md`) is comprehensive, with techniques for challenging vagueness, surfacing assumptions, and finding edges. VBW's discussion engine auto-calibrates between Builder and Architect modes. Both serve the same purpose.

GSD produces PROJECT.md with a Requirements section (validated/active/out-of-scope). VBW produces a separate REQUIREMENTS.md. Equivalent data, different file organization.

### Phase Discussion

| Feature | VBW | GSD |
|---------|-----|-----|
| **Command** | `/vbw:vibe Discuss` | `/gsd:discuss-phase` |
| **Gray area identification** | Auto-generated from phase domain analysis | Auto-generated from phase domain analysis |
| **Scope enforcement** | Instruction-level in discussion engine | `<scope_guardrail>` with heuristics + "Deferred Ideas" capture |
| **Output** | Decisions captured in phase execution context | `CONTEXT.md` with decisions, Claude's discretion areas, deferred ideas |
| **Discussion depth** | Auto-calibrating Builder/Architect modes | 4 questions per area then check, iterative deepening |

Both systems handle phase discussion with comparable sophistication. GSD's discuss-phase.md (18.6KB) has detailed downstream awareness — it explicitly documents how CONTEXT.md feeds into the researcher and planner. VBW's discussion engine integrates into the execution pipeline differently.

### Planning

| Feature | VBW | GSD |
|---------|-----|-----|
| **Research before planning** | Configurable via effort profile | Configurable via `workflow.research` toggle |
| **Plan format** | YAML frontmatter + markdown body with `must_haves` | XML-structured `<task>` elements in PLAN.md with `must_haves` |
| **Plan verification** | Instruction-level checks in execute protocol | `gsd-plan-checker` agent (24.2KB), 8 verification dimensions, max 3 iteration loop |
| **Plan scope** | Per-plan task lists | 2-3 tasks per plan, designed to fit within ~50% context |
| **Dependency handling** | Cross-phase deps in frontmatter | Wave assignment from dependency graph analysis |
| **Quick tasks** | `/vbw:fix` (turbo mode, one commit) | `/gsd:quick` with optional `--full` mode (plan checking + verification) |

GSD's plan checker is notably thorough — 8 verification dimensions with a revision loop (max 3 iterations between planner and checker). VBW's plan validation is part of the execute protocol instructions rather than a dedicated verification agent.

GSD's Nyquist compliance check (ensuring plans don't exceed ~50% context) is a unique feature designed to prevent context overflow during execution.

### Execution

| Feature | VBW | GSD |
|---------|-----|-----|
| **Parallelism** | Agent Teams (persistent teammates with shared task lists) | Wave-based parallel execution (dependency graph → wave grouping) |
| **Isolation** | Worktree isolation (physical filesystem separation) | No filesystem isolation |
| **File access control** | `file-guard.sh` hook + `lease-lock.sh` locking | Instruction-level per-plan file boundaries |
| **Deviation handling** | Event logging, SUMMARY.md deviation section | 4 structured deviation rules in executor agent |
| **Checkpoints** | `autonomous: false` + UAT CHECKPOINTs | 3 formal checkpoint types (human-verify, decision, human-action) |
| **Atomic commits** | One commit per task | One commit per task |
| **SUMMARY.md** | Mandatory (hook-enforced, exit 2) | Mandatory (instruction-enforced) |
| **Context awareness** | Token budgets per agent role | Context monitor hook warns at 35%/25% remaining |
| **Crash recovery** | `.execution-state.json` + `event-log.jsonl` + `recover-state.sh` | `.continue-here.md` + STATE.md |
| **Smart routing** | `assess-plan-risk.sh` auto-downgrades to turbo | No automatic downgrading |

GSD's checkpoint system is more formally specified than VBW's. Three distinct types with structured XML (`checkpoint:human-verify`, `checkpoint:decision`, `checkpoint:human-action`) each with documented presentation formats, usage frequency (90%/9%/1%), and auto-mode bypass rules. GSD's `checkpoints.md` reference (29KB) includes service CLI references, authentication gate protocols, and environment automation patterns.

VBW's worktree isolation and lease locking provide stronger parallel execution guarantees. GSD relies on instruction-level file boundaries.

GSD's 4 deviation rules are well-defined:
1. Auto-fix bugs discovered during implementation
2. Auto-add missing critical functionality with same commit
3. Auto-fix blocking issues from earlier tasks
4. ASK about architectural changes (never auto-deviate)

This is more structured than a general "log deviations" instruction.

### Verification

| Feature | VBW | GSD |
|---------|-----|-----|
| **Automated QA** | 3-tier (Quick/Standard/Deep) via `vbw-qa` agent | Single-tier via `gsd-verifier` agent |
| **QA agent permissions** | Write/Edit tools platform-denied; persists VERIFICATION.md via deterministic writer script | Full tool access (read+write) |
| **Verification methodology** | Goal-backward | Goal-backward |
| **Artifact verification** | SUMMARY.md + VERIFICATION.md | SUMMARY.md + VERIFICATION.md |
| **Verification reference** | `verification-protocol.md` | `verification-patterns.md` (16.5KB, 4-level framework) |
| **Human acceptance testing** | `/vbw:verify` with per-test CHECKPOINTs | `verify-work.md` with conversational UAT |
| **Gap auto-closure** | UAT issues → discuss → plan → execute pipeline | UAT issues → parallel debug agents → auto-plan gaps |
| **Hook enforcement** | `qa-gate.sh` (exit 2) + `hard-gate.sh` (exit 2) | None (instruction-level) |

GSD's `verification-patterns.md` is particularly notable — it provides detailed bash patterns for stub detection, component verification, API route verification, database schema verification, and wiring verification across React/Next.js, Express, Prisma, and other stacks. This is practical, language-specific guidance that VBW's protocol doesn't include.

VBW's tiered QA with platform-enforced read-only agent permissions is genuinely unique. A QA agent with Write/Edit tools disallowed — restricted to persisting only through the deterministic `write-verification.sh` script — provides stronger verification independence.

### Session Continuity

| Feature | VBW | GSD |
|---------|-----|-----|
| **Explicit pause** | `/vbw:pause` creates RESUME.md | `/gsd:pause-work` creates `.continue-here.md` |
| **Cold resume** | `/vbw:resume` works without prior pause | `/gsd:resume-work` reads STATE.md + PROJECT.md + `.continue-here` |
| **Crash recovery** | Event-sourced recovery from `event-log.jsonl` | STATE.md + SUMMARY.md reconstruction |
| **State persistence** | `.execution-state.json` (real-time) + `event-log.jsonl` (13 event types) | STATE.md + `.continue-here.md` |
| **Compaction handling** | `PreCompact` + `SessionStart(compact)` hooks | No compaction hooks |
| **Snapshot resume** | `snapshot-resume.sh` captures execution state + git context | Not available |

VBW's session continuity is genuinely more robust. Event-sourced state recovery, real-time execution state, compaction hooks (preservation priorities before compaction + verification after), and cold resume without prior pause are capabilities GSD lacks.

GSD's `.continue-here.md` is well-structured (7 sections) but requires explicit creation via `/gsd:pause-work`.

### Model Routing

| Feature | VBW | GSD |
|---------|-----|-----|
| **Profiles** | 3 presets (quality/balanced/budget) | 3 presets (quality/balanced/budget) |
| **Per-agent overrides** | Config-based overrides per agent role | Config-based overrides per agent type |
| **Resolution** | `resolve-agent-model.sh` | `resolve-model` command in gsd-tools.cjs |

Feature parity. Both systems support model profiles with per-agent overrides.

### Phase Management

| Feature | VBW | GSD |
|---------|-----|-----|
| **Insert phase** | `/vbw:vibe --insert N` (auto-renumbers everything downstream) | `/gsd:insert-phase` (decimal phases: 8.1, 8.2) |
| **Add phase** | `/vbw:vibe --add` | `/gsd:add-phase` |
| **Remove phase** | Not available | `/gsd:remove-phase` (renumbers subsequent) |
| **Phase completion** | Execute protocol + archive flow | `phase complete` command in gsd-tools.cjs |

Different approaches to interruptions: VBW renumbers directories, file prefixes, frontmatter references, and `depends_on` links. GSD uses decimal phase numbering (cleaner for quick insertions, but creates non-obvious ordering). GSD additionally supports explicit phase removal.

---

## Capabilities Unique to Each System

### VBW-Only Capabilities

| Capability | Implementation | Why It Matters |
|------------|---------------|----------------|
| **Blocking platform hooks (exit 2)** | `hard-gate.sh`, `qa-gate.sh`, `file-guard.sh`, `bash-guard.sh`, `security-filter.sh`, `archive-uat-guard.sh` | Model cannot bypass these during compaction or context overflow |
| **Platform-enforced agent permissions** | `disallowedTools` in agent YAML — Scout cannot write files; QA restricted to persistence via `write-verification.sh` | Verified tool restriction at the platform level, not instruction level |
| **Worktree isolation** | `worktree-create.sh`, `worktree-target.sh`, `worktree-agent-map.sh` | Physical filesystem separation for parallel agents |
| **Lease locks** | `lease-lock.sh` | File-level exclusive locking during parallel execution |
| **Contract system** | `generate-contract.sh`, `validate-contract.sh` with hash integrity | Tasks operate within declared boundaries, hash prevents tampering |
| **Event-sourced state** | `event-log.jsonl` (13 event types) + `recover-state.sh` | Crash recovery via event replay, not just checkpoint files |
| **Database safety guard** | `bash-guard.sh` with 40+ destructive command patterns | Prevents accidental `DROP TABLE`, `rm -rf`, etc. regardless of agent instructions |
| **Compaction hooks** | `compaction-instructions.sh` (PreCompact) + `post-compact.sh` (SessionStart compact) | Preserves critical context through compaction and verifies survival |
| **Tiered QA** | Quick (5-10), Standard (15-25), Deep (30+ checks) with effort-based selection | Right-sized verification based on work complexity |
| **Effort profiles** | 4 levels (thorough/balanced/fast/turbo) controlling planning depth, QA tier, agent behavior | One config controls the depth dial across the entire pipeline |
| **Autonomy levels** | 4 levels (cautious/standard/confident/pure-vibe) controlling confirmation gates | Separate config for human-in-the-loop requirements |
| **Work profiles** | Bundled presets (default/prototype/production/yolo) | One-command switch of effort + autonomy + verification |
| **Skills.sh ecosystem** | Stack detection → skill recommendation → `/vbw:skills` install from registry | Community skill distribution |
| **Observability and metrics** | 7 V2 metrics, per-phase reports, cost attribution | Quantified execution tracking |
| **Agent health monitoring** | `agent-health.sh` lifecycle tracking, orphan detection, circuit breakers | Prevents runaway or orphaned agent processes |
| **Plugin marketplace** | Claude Code marketplace distribution with version management, migration scripts | Brownfield update handling for existing installations |
| **Typed communication schemas** | 6 typed message schemas with JSON validation (`handoff-schemas.md`) | Structured inter-agent communication |

### GSD-Only Capabilities

| Capability | Implementation | Why It Matters |
|------------|---------------|----------------|
| **Multi-platform support** | Claude Code, OpenCode, Gemini CLI | Not locked to one AI coding platform |
| **3 formal checkpoint types** | `checkpoint:human-verify` (90%), `checkpoint:decision` (9%), `checkpoint:human-action` (1%) with structured XML | More precisely categorized human interaction points |
| **8-dimension plan checking** | `gsd-plan-checker` with requirement coverage, task completeness, dependency correctness, key links, scope sanity, verification derivation, context compliance, Nyquist compliance | Dedicated plan verification agent with revision loop |
| **Nyquist compliance** | Plans must fit within ~50% context budget | Prevents context overflow during execution |
| **Language-specific verification patterns** | `verification-patterns.md` (16.5KB) with React, API route, database, and wiring verification patterns | Practical stub detection and wiring verification for common stacks |
| **Context monitor hook** | Real-time context usage tracking with WARNING (35%) and CRITICAL (25%) thresholds | Model awareness of remaining context budget during execution |
| **Statusline** | Real-time progress bar, model, task, directory display after every response | Visual execution tracking (VBW has statusline too but GSD's is hook-based) |
| **Comprehensive CLI tool** | `gsd-tools.cjs` (22KB) with ~30 subcommands for state, phases, roadmap, frontmatter, templates, verification, milestones | Centralized tooling with consistent JSON output |
| **Authentication gate protocol** | Dynamic checkpoint creation when CLI encounters auth errors, with service CLI reference | Structured handling of credential requirements during automated deployment |
| **YOLO mode** | Single toggle for auto-approve everything | Simpler autonomy model for rapid iteration |
| **Milestone audit** | `/gsd:audit-milestone` pre-completion verification | Dedicated quality check before milestone closure |
| **Phase removal** | `/gsd:remove-phase` with auto-renumbering | Can remove phases from roadmap, not just add/insert |
| **Todo system** | `/gsd:add-todo`, `/gsd:check-todos` with area-based organization | Integrated task tracking outside the phase system |
| **Global defaults** | `~/.gsd/defaults.json` for cross-project preferences | Project-independent settings persistence |

---

## Enforcement Comparison: The Core Difference

This is the most important distinction between VBW and GSD. Both systems want the same outcomes — atomic commits, SUMMARY.md closure, verified artifacts, scoped file access. They differ in how they ensure those outcomes.

### GSD's Enforcement Model

GSD relies on **instruction-level enforcement** backed by a comprehensive CLI:

1. **Agent instructions** (markdown): "You MUST create SUMMARY.md", "Only 4 deviation types allowed", "Do NOT modify files outside the plan"
2. **CLI verification** (gsd-tools.cjs): `verify-summary`, `verify plan-structure`, `verify phase-completeness`, `verify artifacts`, `verify key-links`, `verify commits`
3. **Advisory hooks** (3 JS hooks): Context monitor warns about budget, statusline shows progress, update checker runs at session start
4. **Workflow checkpoints** (markdown): Plan checker revision loops, UAT testing, spot-checking

This works well when the model follows instructions faithfully. The risk is that under context pressure (compaction, long sessions, complex multi-agent chains), instruction-level rules can be dropped or degraded.

### VBW's Enforcement Model

VBW layers **platform hook enforcement** on top of instruction-level rules:

1. **Agent instructions** (markdown): Same as GSD — agents told what to do and not do
2. **Script verification** (~97 bash scripts): Equivalent to gsd-tools.cjs but distributed across separate scripts
3. **Blocking hooks** (exit 2): `file-guard.sh`, `bash-guard.sh`, `security-filter.sh`, `qa-gate.sh`, `hard-gate.sh`, `archive-uat-guard.sh`
4. **Platform tool permissions** (YAML): `disallowedTools` enforced by the platform itself
5. **Lifecycle hooks** (advisory): Agent health, session start/stop, compaction, state updates

The blocking hooks (exit 2) are the key differentiator. These run as bash subprocesses BEFORE tool execution reaches the model. The model cannot bypass them through compaction, context overflow, or instruction degradation. They execute at zero model token cost.

### The Trade-Off

| Aspect | GSD Approach | VBW Approach |
|--------|-------------|-------------|
| **Enforcement reliability** | Depends on model instruction adherence | Platform-guaranteed for hook-enforced rules |
| **Enforcement coverage** | Comprehensive via CLI + instructions | Comprehensive via hooks + scripts + instructions |
| **Context cost** | Rules loaded into model context (CLI output consumed) | Hooks run as subprocesses at zero context cost |
| **Platform dependency** | Works across Claude Code, OpenCode, Gemini CLI | Requires Claude Code (hooks, Agent Teams, tool permissions) |
| **Debugging** | Read agent instructions + CLI output | Read hook scripts + hook error logs |
| **Maintenance** | ~22KB JS CLI + ~300KB agent/workflow markdown | ~97 bash scripts + ~200KB agent/command/reference markdown |
| **Token overhead** | CLI output enters context window | Hook scripts invisible to context |

---

## Philosophy Comparison (Corrected)

| Aspect | GSD | VBW |
|--------|-----|-----|
| **Primary goal** | Structured AI development via context engineering | Structured AI development via phased workflows |
| **Optimization target** | Token-to-value efficiency (Nyquist compliance, ~50% context budgets) | Token efficiency (86% overhead reduction vs stock, per-role budgets) |
| **Loop closure** | Instruction-enforced + CLI verification | Instruction-enforced + hook-enforced (exit 2) |
| **Parallel execution** | Wave-based (dependency graph → wave grouping) | Agent Teams (persistent teammates + worktree isolation) |
| **Decision flow** | State-detected single path (resume-project.md) | State-detected single path (phase-detect.sh) |
| **Session continuity** | Explicit pause → `.continue-here.md` with 7 sections | Auto-persistent (`.execution-state.json` + `event-log.jsonl`) |
| **Quality gates** | Goal-backward verification (verifier + plan checker) | Goal-backward verification (QA agent, tiered) + hook gates |
| **Scope control** | Instruction-level (scope guardrails + deviation rules) | Instruction-level + hook-level (file-guard + lease locks) |
| **Enforcement** | Instruction + CLI + advisory hooks | Instruction + scripts + blocking hooks + tool permissions |
| **Multi-platform** | Claude Code, OpenCode, Gemini CLI | Claude Code only |

---

## When to Choose Which

### Choose GSD When

- **You use multiple AI coding tools** — GSD supports Claude Code, OpenCode, and Gemini CLI
- **You prefer Node.js tooling** — `gsd-tools.cjs` is a single CLI tool vs VBW's ~97 bash scripts
- **You want a YOLO mode** — GSD's auto mode chains the full pipeline unattended
- **You trust instruction-level enforcement** — If you're comfortable with model compliance, GSD's advisory approach is lighter-weight
- **You want detailed checkpoint types** — GSD's 3 formal checkpoint types with documented presentation formats are more precisely categorized
- **You want language-specific verification** — GSD's `verification-patterns.md` has practical React/API/DB verification patterns

### Choose VBW When

- **You need platform-enforced quality gates** — VBW's blocking hooks prevent the model from bypassing rules
- **You run long, complex sessions** — VBW's event-sourced state recovery and compaction hooks handle multi-hour sessions and crashes
- **You want tiered QA** — VBW's Quick/Standard/Deep tiers let you right-size verification effort
- **You want filesystem isolation** — VBW's worktree isolation provides physical separation for parallel agents
- **You want fine-grained control** — 4 effort levels × 4 autonomy levels × bundled work profiles
- **You want security enforcement** — `bash-guard.sh` (40+ patterns), `security-filter.sh` (.env, .pem, credentials), and `file-guard.sh` (undeclared file access)
- **You use the Claude Code marketplace** — VBW distributes as a marketplace plugin with migration handling

### Both Are Good Choices When

- You want structured, phased AI development instead of ad-hoc prompting
- You want acceptance-based verification, not just task completion tracking
- You want session continuity across context compactions
- You want model routing with quality/balanced/budget profiles
- You want codebase mapping with parallel agents
- You want discussion/questioning before planning

---

## Data That Matters

### Raw Numbers (Source-Code-Counted)

| Metric | VBW | GSD |
|--------|-----|-----|
| Total markdown content (agents + commands + workflows + references) | ~200KB | ~350KB |
| Executable code (scripts) | ~97 bash scripts | 1 JS CLI (~22KB) + 3 JS hooks (~10KB) + 1 build script |
| Hook handlers | 25 | 3 |
| Blocking hooks (exit 2) | 6+ | 0 |
| Agent count | 7 | 11 |
| Slash commands | 24 | 30 |
| Checkpoint types | 1 (autonomous flag + UAT) | 3 (human-verify, decision, human-action) |
| Platform support | 1 (Claude Code) | 3 (Claude Code, OpenCode, Gemini CLI) |
| Effort/depth profiles | 4 | 3 |
| Verification tiers | 3 | 1 |
| Plan verification dimensions | Execute protocol checks | 8 formal dimensions |

### What the Numbers Don't Tell You

- More hooks ≠ better. VBW's hooks are valuable because specific hooks solve specific problems (file access control, destructive command prevention). Having 25 vs 3 matters only because of what those hooks DO.
- More agents ≠ better. GSD's 11 agents decompose work more granularly; VBW's 7 agents cover the same lifecycle with broader role definitions.
- More markdown ≠ better. GSD's ~350KB of agent/workflow content reflects a different design — detailed inline workflow definitions rather than protocol references.
- Multi-platform support matters if you use multiple tools. If you only use Claude Code, VBW's deeper Claude Code integration is an advantage.

---

*Report prepared from source code analysis of VBW v1.30.0+ repository and GSD v1.20.5 repository (commit 131f24b, accessed via GitHub API 2026-07-22). Every claim is traceable to specific files in each repository.*
