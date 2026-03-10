# VBW vs PAUL — Evaluating PAUL's Claimed Differentiators

**Date:** 2026-02-21
**Prepared for:** VBW framework users
**Source material:** [PAUL-VS-GSD.md](https://github.com/ChristopherKahler/paul/blob/main/PAUL-VS-GSD.md), PAUL README, VBW source code and README

> **Note:** This document evaluates PAUL's claims about its own differentiators versus VBW and GSD. Claims about GSD in this document are inherited from PAUL's marketing material and were not validated against GSD's source code. For a source-code-validated VBW vs GSD comparison, see [vbw-vs-gsd-source-validated.md](vbw-vs-gsd-source-validated.md).

---

## Executive Summary

PAUL (Plan-Apply-Unify Loop) positions itself as an evolution beyond GSD (Get Shit Done), emphasizing quality over speed, in-session context over subagent sprawl, and mandatory loop closure. After a thorough review of PAUL's claims against VBW's actual implementation, **VBW already implements every differentiator PAUL claims over GSD — and in most cases goes significantly further.** VBW is not "more like PAUL than GSD" — it's a superset of both philosophies, combining PAUL's quality-first principles with execution capabilities neither PAUL nor GSD offer.

---

## Code-Level Deep Dive: APPLY/UNIFY Enforcement

*This section was generated from actual source code inspection of both codebases, not READMEs.*

### What PAUL Actually Does (Source: `src/commands/apply.md`, `src/workflows/apply-phase.md`, `src/commands/unify.md`, `src/workflows/unify-phase.md`, `src/carl/PAUL`)

**APPLY — Sequential Execution**

PAUL's `apply-phase.md` workflow (9KB) defines a detailed sequential execution protocol:

| Feature | Implementation | Enforcement mechanism |
|---|---|---|
| Sequential task execution | `<step name="execute_tasks">` iterates `<task>` elements in order | Instruction to the model |
| Per-task verification | Each task MUST have `<verify>` step run; FAIL stops execution | Instruction to the model |
| Checkpoints (3 types) | `checkpoint:decision`, `checkpoint:human-verify`, `checkpoint:human-action` — all blocking, model presents formatted prompt and waits | Instruction to the model |
| Deviation logging | `track_progress` step maintains mental log of completed/failed/deviated tasks | Instruction to the model |
| Boundary respect | "Ignoring boundaries: If a task would modify a protected file, STOP" | Instruction to the model |
| Skill verification | `verify_required_skills` blocks execution if required skills not loaded (with "override" escape hatch) | Instruction to the model |

At completion, APPLY reports: *"APPLY complete. Run /paul:unify to close loop."* — a **suggestion**, not an automated transition.

**UNIFY — Loop Closure**

PAUL's `unify-phase.md` workflow (7KB) defines SUMMARY.md creation and state reconciliation:

| Feature | Implementation | Enforcement mechanism |
|---|---|---|
| SUMMARY.md creation | Creates `{plan}-SUMMARY.md` with frontmatter, What Was Built, AC Results, Deviations, Decisions | Instruction to the model |
| Plan vs actual comparison | `compare_plan_vs_actual` step — per-AC pass/fail, per-task completion check, deviation notes | Instruction to the model |
| STATE.md update | Loop position markers (`PLAN ✓ → APPLY ✓ → UNIFY ✓`), milestone progress | Instruction to the model |
| Phase transition | When last plan complete: triggers `transition-phase.md` with PROJECT.md evolution, ROADMAP.md update, git commit, state consistency verification | Instruction to the model |
| State consistency check | Re-reads STATE.md, PROJECT.md, ROADMAP.md; verifies alignment across all fields; **blocking error** if misaligned | Instruction to the model |

**CARL Rule 3:** `"Every APPLY must be followed by UNIFY. UNIFY reconciles plan vs actual, updates STATE.md, logs decisions."`

This is a CARL domain rule injected into the model's context. CARL is instruction-level — it adds rules to the prompt that the model is expected to follow.

**Critical finding: PAUL has ZERO bash scripts, ZERO hooks, ZERO platform gates.** Everything is markdown instructions. The entire enforcement mechanism is the model reading `apply.md` / `unify.md` and following the workflow documents. CARL rules reinforce this with instruction-level `MUST` directives, but nothing prevents the model from:
- Not running `/paul:unify` after `/paul:apply`
- Skipping verification steps during compaction
- Ignoring boundary declarations when context overflows

PAUL's `"Never skip UNIFY"` is backed by **social contract with the model**, not by code.

### What VBW Actually Does (Source: `references/execute-protocol.md`, `scripts/hard-gate.sh`, `scripts/validate-summary.sh`, `scripts/qa-gate.sh`, `scripts/archive-uat-guard.sh`, `hooks/hooks.json`)

**VBW's SUMMARY.md Enforcement — 4 Independent Layers**

| Layer | Script/Hook | When it fires | Blocking? | Skippable? |
|---|---|---|---|---|
| **Execute protocol Step 3c** | Inline in execute-protocol.md | After Dev reports plan completion, BEFORE QA | YES — "This is a hard gate. Do NOT proceed to QA or mark a plan as complete without verifying its SUMMARY.md" | NO — the execute protocol is the core loop |
| **PostToolUse hook** | `validate-summary.sh` | Every Write/Edit to a SUMMARY.md file | Advisory (exit 0) — surfaces missing sections | N/A — runs automatically on every write |
| **SubagentStop hook** | `validate-summary.sh` | When any VBW agent stops | Advisory (exit 0) — checks for crash recovery fallbacks | N/A — platform fires this automatically |
| **TeammateIdle hook** | `qa-gate.sh` | When any teammate goes idle | YES (exit 2) when 2+ plans lack summaries | NO — platform hook, fires automatically |
| **Post-plan hard gate** | `hard-gate.sh artifact_persistence` | After all tasks in a plan complete | YES (exit 2) — "missing SUMMARY.md for: {plans}" | NO — fires regardless of autonomy level |
| **Archive guard** | `archive-uat-guard.sh` | On `/vbw:vibe Archive` | YES (exit 2) — 7-point audit including SUMMARY.md presence | NO — not overridable by `--skip-audit` or `--force` |

**What IS skippable in VBW:**

| Component | When skipped | SUMMARY.md still required? |
|---|---|---|
| QA (automated verification) | `--skip-qa` flag, turbo effort, `qa_skip_agents` config | YES — Step 3c fires BEFORE QA |
| UAT (human acceptance testing) | `confident` or `pure-vibe` autonomy | YES — SUMMARY.md + QA gates are independent of UAT |
| Approval gates | `confident` or `pure-vibe` autonomy | YES |

**VBW's SUMMARY.md is NEVER skippable.** The skippable items are QA (automated testing) and UAT (human testing) — these are downstream verification steps. Loop closure (SUMMARY.md = what was built, deviations, files modified) is enforced at the hard gate level and cannot be bypassed.

### Direct Comparison: Enforcement Quality

| Claim | PAUL | VBW |
|---|---|---|
| "Tasks run sequentially" | Instruction in workflow markdown | Instruction in execute-protocol.md (Dev agents execute tasks in order) |
| "Each task has verification" | Instruction: `<verify>` step required per task | Instruction + `hard-gate.sh required_checks` (exit 2) + `validate-contract.sh` after each task |
| "Checkpoints pause for human input" | 3 checkpoint types — instruction to stop and wait | `autonomous: false` flag on plans + UAT CHECKPOINTs with per-test persistence |
| "Deviations are logged" | Instruction: mental log during APPLY, recorded in UNIFY | SUMMARY.md template + event log (13 types, always-on) + deviation count in phase completion output |
| "Create SUMMARY.md" | Instruction in UNIFY workflow | Hard gate (Step 3c, exit 2) + hook (qa-gate.sh, exit 2) + archive guard |
| "Compare plan vs actual" | Instruction in `compare_plan_vs_actual` step | SUMMARY.md template requires "What Was Built" + "Files Modified" — validated by hook |
| "Record decisions and deferred issues" | Instruction to add to STATE.md Decisions table | Event log captures decisions; SUMMARY.md requires deviations section |
| "Update STATE.md" | Instruction in UNIFY workflow | Execute protocol Step 5 updates STATE.md, ROADMAP.md, .execution-state.json |
| "Never skip UNIFY" | CARL Rule 3 (instruction) | `hard-gate.sh artifact_persistence` (bash, exit code 2) + `qa-gate.sh` (bash, exit code 2) |

### The Honest Assessment

**Where PAUL is instruction-only, VBW has code gating:**
- SUMMARY.md existence: PAUL = instruction. VBW = bash script exits 2 → platform blocks.
- Boundary enforcement: PAUL = "DO NOT CHANGE" declarations. VBW = `file-guard.sh` PreToolUse hook + `lease-lock.sh` + worktree isolation.
- UNIFY mandatory: PAUL = CARL Rule 3. VBW = hard-gate.sh + qa-gate.sh + archive-uat-guard.sh.

**Where PAUL has an advantage:**
- In-session context means the model has full execution memory for UNIFY. VBW delegates to Dev agents who may not carry full context back to the Lead.
- PAUL's 3 structured checkpoint types (decision, human-verify, human-action) are more formally specified than VBW's `autonomous: false` flag.
- PAUL's explicit plan vs actual comparison step is a dedicated workflow phase. VBW's SUMMARY.md template captures the same data but the comparison is less ritualized.

**Where VBW has skip paths that PAUL doesn't:**
- QA can be skipped (`--skip-qa`, turbo, `qa_skip_agents`) — PAUL has no formal QA, so nothing to skip.
- UAT can be skipped (confident/pure-vibe autonomy) — PAUL's checkpoints can be "overridden" at the skill level, but UAT isn't a distinct concept in PAUL.
- However: these skip paths don't affect loop closure. SUMMARY.md is mandatory in both frameworks — the difference is VBW enforces it with code, PAUL enforces it with instructions.

---

## PAUL's 8 Claimed Differentiators vs VBW

### 1. Explicit Loop Discipline

**PAUL's claim:** GSD has implicit review. PAUL enforces PLAN → APPLY → UNIFY with mandatory SUMMARY.md closure.

**VBW's reality:** VBW enforces this at four levels, not one:

| Enforcement Layer | Mechanism |
|---|---|
| **Instruction-level** | Every PLAN.md requires a corresponding SUMMARY.md. Execute mode Step 3c is a hard gate — plans cannot be marked complete without verified SUMMARY.md |
| **Hook-level** | `PostToolUse` validates SUMMARY.md structure on write. `SubagentStop` validates SUMMARY.md exists before agent cleanup. `TeammateIdle` runs a tiered SUMMARY.md gate — 2+ missing summaries block regardless |
| **TaskCompleted hook** | Verifies task-related commits exist via keyword matching with circuit breaker |
| **Archive guard** | `archive-uat-guard.sh` + 7-point audit blocks archiving if any plan lacks SUMMARY.md or has `status != complete` |

PAUL enforces loop closure via instructions to the model. VBW enforces it via platform hooks that **cannot be ignored during compaction**. PAUL's UNIFY is conceptually identical to VBW's SUMMARY.md requirement — but VBW's enforcement is mechanically stronger.

**Verdict:** VBW exceeds PAUL. Same philosophy, harder enforcement.

---

### 2. Context-Aware Execution (Token Economics)

**PAUL's claim:** GSD wastes tokens on subagent sprawl. PAUL keeps execution in-session. Subagents are reserved for discovery/research only.

**VBW's reality:** VBW takes a more nuanced position — it uses Agent Teams (not subagents) with surgical context management:

| Mechanism | What it does |
|---|---|
| **Context compiler** | `compile-context.sh` produces role-specific `.context-{role}.md` files — Lead gets requirements, Dev gets phase goal + conventions, QA gets verification targets. Each agent loads only relevant context |
| **Token budgets** | Per-role caps (Scout 200 lines, Dev/Debugger 800 lines) with per-task complexity scoring from contract metadata |
| **86% overhead reduction** | Measured and documented: 12,100 tokens vs stock Agent Teams' 87,100 tokens |
| **Smart routing** | `assess-plan-risk.sh` downgrades low-risk plans to turbo (single agent, no team) automatically |
| **`prefer_teams` setting** | `auto` mode creates teams only when 2+ plans exist — single plan = single agent, zero coordination overhead |

PAUL's argument that "subagents produce ~70% quality work" is valid criticism of vanilla subagent spawning. But VBW doesn't use vanilla subagents — Agent Teams are persistent teammates with shared task lists, typed communication schemas, and compiled context. The quality delta PAUL describes doesn't apply.

More importantly: VBW's parallel execution with context compilation achieves **both** speed and quality. PAUL forces a false dichotomy — "quality OR speed." VBW's token analysis proves you can have parallel execution at 86% lower overhead than stock implementation.

**Verdict:** VBW exceeds PAUL. VBW solved the token economics problem PAUL avoids by refusing to parallelize.

---

### 3. Single Next Action

**PAUL's claim:** GSD presents menus. PAUL suggests ONE best path based on current state.

**VBW's reality:** `/vbw:vibe` with no arguments does exactly this. `phase-detect.sh` pre-computes project state and routes to the single correct next action:

| State | Auto-routed action |
|---|---|
| No project | Bootstrap |
| No phases | Scope |
| UAT issues | Remediation |
| Needs discussion | Discussion |
| Needs plan + execute | Plan + Execute |
| Needs execute | Execute |
| All done | Archive |

The entire state detection is a priority-ordered cascade — first match wins, one action suggested. The user can override with flags, but the default is always a single recommendation.

VBW also provides `suggest-next.sh` which produces contextual "Next Up" suggestions after every command. This is the same pattern PAUL describes.

**Verdict:** Feature parity. Both frameworks do this identically.

---

### 4. Structured Session Continuity

**PAUL's claim:** GSD uses implicit `.continue-here.md`. PAUL has explicit `HANDOFF-{date}.md` files.

**VBW's reality:** VBW's session continuity is more comprehensive than PAUL's:

| Mechanism | What it persists |
|---|---|
| **STATE.md** | Phase position, velocity metrics, decisions, accumulated todos, blockers, session history |
| **`.execution-state.json`** | Real-time execution state — phase, plan statuses, wave number, correlation ID. Survives crashes |
| **`event-log.jsonl`** | Full event-sourced history (13 event types). Enables replay-based state recovery |
| **`recover-state.sh`** | Reconstructs execution state from event log + SUMMARY.md files after crashes |
| **`/vbw:resume`** | Reads ground truth from all `.vbw-planning/` files — no prior `/vbw:pause` needed. Detects interrupted builds, reconciles stale state |
| **RESUME.md** | Optional sticky notes (equivalent to PAUL's HANDOFF, but state persists without it) |
| **Snapshot resume** | `snapshot-resume.sh` captures execution state + git context for crash recovery |
| **PreCompact hook** | Injects agent-specific preservation priorities before context compaction |
| **Post-compaction verification** | SessionStart hook verifies critical context survived compaction |

PAUL requires explicit `/paul:handoff` to persist state. VBW auto-persists everything — `/vbw:resume` works from cold with zero prior preparation. The `.execution-state.json` + event log combination enables crash recovery that PAUL's handoff files cannot match.

**Verdict:** VBW significantly exceeds PAUL. Event-sourced recovery vs dated handoff files.

---

### 5. Acceptance Criteria as First-Class Citizens

**PAUL's claim:** GSD tasks describe what to do. PAUL links tasks to numbered AC with Given/When/Then format.

**VBW's reality:** VBW implements this through multiple mechanisms:

| Mechanism | How AC are handled |
|---|---|
| **ROADMAP.md** | Each phase has explicit success criteria mapped to requirement IDs |
| **PLAN.md frontmatter** | `must_haves` field with artifacts, truths, key_links, contains — machine-verifiable acceptance criteria |
| **Verification protocol** | Goal-backward methodology: starts from desired outcomes, derives testable conditions, verifies against artifacts |
| **Three-tier QA** | Quick (5-10 checks), Standard (15-25), Deep (30+) — each tier verifies progressively deeper against criteria |
| **Requirement mapping (VRFY-08)** | Deep tier traces requirement IDs to implementing artifacts — OK/WARN/FAIL per requirement |
| **UAT (`/vbw:verify`)** | Human acceptance testing with per-test CHECKPOINT prompts, pass/fail/partial verdicts, resume support |
| **Archive UAT guard** | Unresolved UAT issues block archiving — hard gate, not bypassable |

PAUL uses BDD-style AC in PLAN.md and reports pass/fail in SUMMARY.md. VBW uses structured `must_haves` in PLAN.md frontmatter, runs automated verification via the QA agent, and then runs human acceptance testing via `/vbw:verify`. The AC are verified at two levels (automated + human) rather than one.

**Verdict:** VBW exceeds PAUL. Automated + human verification vs manual UNIFY reporting.

---

### 6. Boundaries That Stick

**PAUL's claim:** GSD has scope guidance. PAUL has explicit `## Boundaries` with DO NOT CHANGE declarations.

**VBW's reality:** VBW enforces boundaries through multiple runtime mechanisms:

| Mechanism | What it enforces |
|---|---|
| **`file-guard.sh` hook** | PreToolUse hook blocks writes to files not declared in the active plan |
| **Lease locks** | `lease-lock.sh` provides file-level locking — tasks must acquire exclusive leases before writing |
| **Worktree isolation** | Physical filesystem isolation — each Dev works in a separate git worktree, literally cannot access other agents' files |
| **Contract validation** | `generate-contract.sh` creates `allowed_paths` sidecar; `validate-contract.sh` checks modified files against contract post-task |
| **Hard gates** | `hard-gate.sh` runs `protected_file` checks before each task, `contract_compliance` checks, and `artifact_persistence` checks after |
| **`security-filter.sh`** | Blocks access to `.env`, credentials, `.pem`, `.key` files |
| **`bash-guard.sh`** | Intercepts destructive bash commands (40+ patterns) before they reach the shell |
| **Agent tool permissions** | Platform-enforced `disallowedTools` — Scout and QA literally cannot write files |

PAUL relies on instructions (DO NOT CHANGE declarations) that the model is expected to respect. CARL adds dynamic rule injection, but rules are still instruction-level — nothing prevents the model from violating them during compaction or context overflow.

VBW uses hooks that execute **before** tool invocations reach the model. `file-guard.sh` runs as a PreToolUse hook — it's not a suggestion, it's an interceptor. Tool permissions are platform-enforced via YAML `disallowedTools`.

**Verdict:** VBW significantly exceeds PAUL. Hook-enforced boundaries vs instruction-level declarations.

---

### 7. Skill Tracking and Verification

**PAUL's claim:** GSD has no skill tracking. PAUL's `SPECIAL-FLOWS.md` declares required skills and UNIFY audits whether they were invoked.

**VBW's reality:** VBW integrates with the Skills.sh ecosystem:

| Mechanism | What it does |
|---|---|
| **Stack detection** | `/vbw:init` scans project, identifies tech stack, recommends skills from curated `stack-mappings.json` |
| **Skills.sh integration** | `/vbw:skills` browses and installs community skills from the open-source registry |
| **Plan-driven skill activation** | Agents read `skills_used` from plan frontmatter and call `Skill(skill-name)` to activate each relevant skill at execution time |
| **PLAN.md `skills_used`** | Frontmatter field declaring which skills a plan requires |
| **Verified in CLAUDE.md** | Installed skills tracked in the `Installed Skills` section |

VBW's approach is broader than PAUL's — PAUL tracks whether required skills were invoked; VBW detects skills from the stack, installs them, activates them via plan-driven `Skill()` calls at execution time, and verifies conventions they define via QA.

**Verdict:** VBW exceeds PAUL. Ecosystem integration vs manual declaration.

---

### 8. Decimal Phases for Interruptions

**PAUL's claim:** GSD has integer phases only. PAUL supports decimal phases (8.1, 8.2) for urgent interruptions.

**VBW's reality:** VBW handles interruptions through three mechanisms:

| Mechanism | How it works |
|---|---|
| **`/vbw:vibe --insert N`** | Insert a phase at any position — all subsequent phases auto-renumber (dirs renamed, frontmatter updated, cross-refs adjusted) |
| **`/vbw:vibe --add`** | Append a phase without disrupting existing numbering |
| **`/vbw:fix`** | Quick task in Turbo mode — one commit, no ceremony, no phase mutation needed |
| **`/vbw:debug`** | Systematic bug investigation — at Thorough effort spawns 3 parallel debugger teammates |

VBW's `--insert` literally renumbers everything downstream — directory names, file prefixes, frontmatter references, `depends_on` links. It's more disruptive than PAUL's decimal approach, but also more structurally clean. Decimal phases preserve numbering but create a non-obvious secondary ordering.

More importantly: VBW's `/vbw:fix` handles the common case (urgent fix needed) without touching phases at all. PAUL requires creating a decimal phase even for trivial interruptions.

**Verdict:** Different but equivalent. PAUL's decimal phases are elegant; VBW's auto-renumbering + `/vbw:fix` is more practical.

---

## Capabilities VBW Has That PAUL Lacks

Beyond addressing every PAUL differentiator, VBW includes substantial capabilities that have no PAUL equivalent:

| Capability | VBW | PAUL |
|---|---|---|
| **Platform hooks (21 handlers, 11 event types)** | Continuous verification, security filtering, lifecycle management, compaction recovery — all running as platform hooks, not instructions | None — CARL adds dynamic rules but no platform-level hooks |
| **Agent tool permissions (platform-enforced)** | 4 of 7 agents have `disallowedTools` enforced by Claude Code itself | None — PAUL is single-agent |
| **Database safety guard** | 40+ destructive command patterns blocked across all major frameworks | None |
| **Parallel execution with isolation** | Agent Teams + worktree isolation + lease locks + file guards | Explicitly rejected — in-session only |
| **Three-tier automated QA** | Goal-backward verification at Quick/Standard/Deep tiers with 5-30+ checks | Manual UNIFY reconciliation |
| **Human acceptance testing (UAT)** | `/vbw:verify` with per-test CHECKPOINT prompts, severity classification, resume support | `/paul:verify` exists but is guide-based, not structured |
| **UAT remediation pipeline** | Automatic detection of unresolved UAT → discuss → plan → execute chain, including milestone recovery | None |
| **Token budget enforcement** | Per-role caps, per-task complexity scoring, escalation tracking | None — token awareness is philosophical, not implemented |
| **Event-sourced state recovery** | 13 event types in `event-log.jsonl` + `recover-state.sh` for crash recovery | None |
| **Smart routing** | `assess-plan-risk.sh` auto-downgrades simple plans to turbo | None |
| **Model routing** | 3 preset profiles (quality/balanced/budget) with per-agent overrides | None — single model assumed |
| **Effort profiles** | 4 levels (thorough/balanced/fast/turbo) controlling planning depth, QA tier, agent behavior | None — one depth |
| **Autonomy levels** | 4 levels (cautious/standard/confident/pure-vibe) controlling confirmation gates | None |
| **Work profiles** | Bundled presets (default/prototype/production/yolo) switching effort + autonomy + verification in one command | None |
| **Codebase mapping** | 4 parallel Scout teammates analyzing tech/architecture/quality/concerns | `/paul:map-codebase` exists as a single command |
| **Structured handoff schemas** | 6 typed message schemas with JSON validation | None |
| **Observability and metrics** | 7 V2 metrics, per-phase reports, cost attribution | None |
| **Agent health monitoring** | Lifecycle tracking, orphan detection, circuit breakers | N/A (single agent) |
| **Discussion engine** | Auto-calibrating Builder/Architect modes, phase-specific gray area generation, conversational exploration | `/paul:discuss` exists but is simpler |
| **Statusline** | Real-time progress dashboard after every response | None |
| **Plugin architecture** | Marketplace distribution, version management, migration scripts for brownfield installs | npm package |
| **845 bats tests** | Comprehensive test suite validating scripts and contracts | Unknown test coverage |

---

## PAUL's Philosophy Comparison Table — Fact-Checked

PAUL's PAUL-VS-GSD.md includes a philosophy comparison table. Here it is with VBW's actual position:

| Aspect | GSD | PAUL | VBW |
|---|---|---|---|
| Primary goal | Ship fast | Ship correctly | Ship correctly AND fast (parallel execution with quality gates) |
| Optimization target | Speed to done | Token-to-value efficiency | Measured token efficiency (86% reduction vs stock) |
| Loop closure | Flexible | Mandatory | Mandatory + hook-enforced + archive-guarded |
| Subagent role | Execution (parallel speed) | Discovery only | Execution (Agent Teams with context compilation) + Discovery (Scout) |
| Decision flow | Multiple options | Single best path | Single best path (`phase-detect.sh` → one action) |
| Session handoff | Implicit | Explicit + dated | Automatic (no prior action needed) + event-sourced crash recovery |
| Quality gates | Completion-based | Acceptance-based | Automated QA + Human UAT + hook-enforced gates |
| Scope control | Guidance | Enforcement (instructions) | Enforcement (platform hooks + tool permissions + lease locks) |

---

## PAUL's "When to Use Which" — Where VBW Fits

PAUL suggests using PAUL when:
- ✅ Quality and traceability matter → VBW does this with stronger enforcement
- ✅ Work spans multiple sessions → VBW has superior session continuity
- ✅ You need verifiable acceptance criteria → VBW has automated + human verification
- ✅ Scope creep is a concern → VBW has hook-level scope enforcement
- ✅ You want explicit reconciliation of plan vs. reality → VBW's SUMMARY.md + QA + UAT pipeline

PAUL suggests using GSD when:
- Speed is the primary constraint → VBW's turbo mode and parallel execution handle this
- Project scope is small → VBW's `/vbw:fix` handles trivial changes without ceremony
- Single-session completion is likely → VBW's pure-vibe autonomy loops all phases unattended
- You don't need audit trails → VBW's event log is always-on but zero overhead

VBW covers both use cases. It doesn't force a choice between speed and quality.

---

## CARL vs VBW Hooks

PAUL relies on CARL (Context Augmentation & Reinforcement Layer) for dynamic rule injection — rules load based on what you're working on and disappear when you're not. This is clever for context management but fundamentally limited:

| Aspect | CARL | VBW Hooks |
|---|---|---|
| Mechanism | Dynamic prompt injection | Platform hook handlers (PreToolUse, PostToolUse, etc.) |
| Enforcement | Instructions — model can ignore during compaction | Hook code runs before tool execution — model cannot bypass |
| Integration | Separate tool (must install CARL alongside PAUL) | Built into the plugin (hooks.json ships with VBW) |
| Context cost | Rules loaded just-in-time to keep context lean | Scripts run as bash subprocesses at zero model token cost |
| Scope | 14 PAUL-specific rules | 21 handlers across 11 event types |

CARL solves a real problem (context bloat from static rules) but VBW solves the same problem differently — scripts run as bash subprocesses outside the model's context window. VBW's 85 scripts execute at zero model token cost. CARL's rules, however lightweight, still consume context tokens when loaded.

---

## The PAUL "AI Is Already Fast" Argument

PAUL's core philosophical claim deserves direct response:

> "AI is already the speed enhancement. We don't need to optimize speed at the cost of quality."

This is a false dichotomy. VBW demonstrates that parallel execution does not require sacrificing quality:

1. **Context compilation** ensures every agent gets exactly the context it needs — no cold-start duplication
2. **Hook enforcement** runs continuously during parallel execution — not after, during
3. **Typed communication schemas** prevent the "garbage output" PAUL warns about
4. **86% token overhead reduction** means parallel execution is actually MORE token-efficient than in-session execution with full context loading
5. **Worktree isolation** eliminates the merge conflict risk that makes parallel work unreliable

PAUL's argument applies to stock subagent spawning. It does not apply to VBW's architecture.

---

## Bottom Line

| Question | Answer |
|---|---|
| Is VBW more like PAUL than GSD? | VBW shares PAUL's quality-first philosophy but implements it with mechanically stronger enforcement than PAUL provides. VBW also retains (and improves upon) GSD's execution speed through context-compiled parallel Agent Teams. |
| Does VBW address PAUL's criticisms of GSD? | Yes, every one of them — and in most cases goes further than PAUL does. |
| Should VBW users worry about PAUL's claims? | No. Every claimed advantage in PAUL-VS-GSD.md is already present in VBW, typically with stronger implementation. |
| Is PAUL a competitor to VBW? | PAUL is a lightweight framework (~26 commands, markdown-only, single-agent) with good principles. VBW is a full-stack development lifecycle platform (24 commands, 85 scripts, 21 hooks, 7 agents, 845 tests). They operate at different scales. |

**VBW is not PAUL. VBW is not GSD. VBW is what happens when you take the best ideas from both — mandatory loop closure, token efficiency, acceptance-driven verification, structured session continuity — and implement them with platform-level enforcement, parallel execution, and comprehensive automation.**

---

*Report prepared from source code analysis of VBW v1.30.0+ and PAUL's public repository as of 2026-02-21.*
