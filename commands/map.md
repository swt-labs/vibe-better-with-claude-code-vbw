---
name: vbw:map
category: advanced
disable-model-invocation: true
description: Analyze existing codebase with adaptive Scout teammates to produce structured mapping documents.
argument-hint: [--incremental] [--package=name] [--tier=solo|duo|quad]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
---

# VBW Map: $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | sed -n 's/.*--plugin-dir  *\([^ ]*\).*/\1/p' | head -1); [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; rm -f "$LINK"; ln -s "$R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```
Existing mapping: `!`ls .vbw-planning/codebase/ 2>/dev/null || echo "No codebase mapping found"``
META.md:
```
!`cat .vbw-planning/codebase/META.md 2>/dev/null || echo "No META.md found"`
```
Project files: `!`ls package.json pyproject.toml Cargo.toml go.mod Gemfile build.gradle pom.xml 2>/dev/null || echo "No standard project files found"``
Git HEAD: `!`git rev-parse HEAD 2>/dev/null || echo "no-git"``
Agent Teams: `!`echo "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}"``

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."
2. **No git:** WARN "Not a git repo -- incremental mapping disabled." Continue in full mode.
3. **Empty project:** No source files → STOP: "No source code found to map."

## Steps

### Step 1: Parse arguments and detect mode

- **--incremental**: force incremental refresh
- **--package=name**: scope to single monorepo package
- **--tier=solo|duo|quad**: force specific tier (overrides auto-detection)

**Mode detection:** If META.md exists + git repo: compare `git_hash` to HEAD. <20% files changed = incremental, else full. No META.md or no git = full. Store MAPPING_MODE and CHANGED_FILES.

### Step 1.5: Size codebase and select tier

Count source files (Glob), excluding: .vbw-planning/, node_modules/, .git/, vendor/, dist/, build/, target/, .next/, __pycache__/, .venv/, coverage/. If --package, scope to that dir. Store SOURCE_FILE_COUNT.

| Tier | Files | Strategy | Scouts |
|------|-------|----------|--------|
| solo | <200 | Orchestrator maps inline | 0 |
| duo | 200-1000 | 2 scouts, combined domains | 2 |
| quad | 1000+ | Full 4-scout team | 4 |

Overrides: --tier flag forces tier. Agent Teams not enabled → force solo (`⚠ Agent Teams not enabled — using solo mode`).
Display: `◆ Sizing: {SOURCE_FILE_COUNT} source files → {tier} mode`

### Step 2: Detect monorepo

**JS/Node patterns:** Check lerna.json, pnpm-workspace.yaml, packages/ or apps/ with sub-package.json, root workspaces field.

**Multi-component detection:** Count distinct build system roots at different paths. Build system markers: package.json, Cargo.toml, go.mod, pyproject.toml, build.gradle, pom.xml, *.xcodeproj, Podfile, pubspec.yaml. If 2+ markers found at different directory levels (not just root), treat as monorepo.

If monorepo + --package: scope to that package.

### Step 3: Execute mapping (tier-branched)

**Step 3-solo:** Orchestrator analyzes each domain sequentially, writes to `.vbw-planning/codebase/`:
- Domain 1 (Tech Stack): STACK.md + DEPENDENCIES.md
- Domain 2 (Architecture): ARCHITECTURE.md + STRUCTURE.md
- Domain 3 (Quality): CONVENTIONS.md + TESTING.md
- Domain 4 (Concerns): CONCERNS.md
Display ✓ per domain. After all 7 docs written, skip Step 3.5, go to Step 4.

---

**Step 3-duo:** Create Agent Team with 2 Scouts via TaskCreate:

Scout A (Tech + Architecture): analyze tech stack, deps, architecture, structure. Send 2 scout_findings messages (domain: "tech-stack" with STACK.md+DEPENDENCIES.md, domain: "architecture" with ARCHITECTURE.md+STRUCTURE.md). Mode: {MAPPING_MODE}. Schema ref: ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/handoff-schemas.md`

Scout B (Quality + Concerns): analyze quality, conventions, testing, debt, risks. Send 2 scout_findings messages (domain: "quality" with CONVENTIONS.md+TESTING.md, domain: "concerns" with CONCERNS.md). Mode: {MAPPING_MODE}. Schema ref: ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/handoff-schemas.md`

**Scout model (effort-gated):** Fast/Turbo: `Model: haiku`. Thorough/Balanced: inherit session model.
**Scout turn budget (effort-gated):** Resolve with `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "{effort}"` and pass `maxTurns: ${SCOUT_MAX_TURNS}` to each Scout TaskCreate.
Wait for all findings. Proceed to Step 3.5.

---

**Step 3-quad:** Create Agent Team with 4 Scouts via TaskCreate. Each sends scout_findings with their domain. Schema ref: ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/handoff-schemas.md`
- Scout 1 (Tech Stack): STACK.md + DEPENDENCIES.md
- Scout 2 (Architecture): ARCHITECTURE.md + STRUCTURE.md
- Scout 3 (Quality): CONVENTIONS.md + TESTING.md
- Scout 4 (Concerns): CONCERNS.md

Security: PreToolUse hook handles enforcement. **Scout model:** same as duo. **Scout turn budget:** same as duo (`maxTurns: ${SCOUT_MAX_TURNS}` on each TaskCreate).

**Scout communication (effort-gated):**

| Effort | Messages |
|--------|----------|
| Thorough | Cross-cutting findings + contradiction flags for INDEX.md Validation Notes |
| Balanced | Cross-cutting findings only |
| Fast | Blockers only |

Use targeted `message` not `broadcast`. Wait for all findings. Display ✓ per scout.

### Step 3.5: Write mapping documents from Scout reports

**Skip if solo** (docs already written). Parse each scout_findings JSON message. If parse fails, treat as plain markdown. Write 7 docs to `.vbw-planning/codebase/`: STACK.md, DEPENDENCIES.md, ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, CONCERNS.md. Verify all 7 exist.

### Step 4: Synthesize INDEX.md and PATTERNS.md

Read all 7 docs. Produce:
- **INDEX.md:** Cross-referenced index with key findings + "Validation Notes" for contradictions
- **PATTERNS.md:** Recurring patterns: architectural, naming, quality, concern, dependency

### Step 5: Create META.md and present summary

**HARD GATE — Shutdown before presenting results:** Solo: no team, skip. Duo/Quad: send `shutdown_request` to each teammate, wait for `shutdown_response` (approved=true), re-request if rejected, then TeamDelete. Only THEN proceed to META.md and user output. Failure to shut down leaves agents running and consuming API credits.

Write META.md: mapped_at, git_hash, file_count, document list, mode, monorepo flag, mapping_tier.

Display per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md: Phase Banner (Codebase Mapped, Mode, Tier), ✓ per document, Key Findings (◆), Next Up block.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — Phase Banner (double-line box), File Checklist (✓), ◆ for findings, ⚠ for warnings, Next Up Block, no ANSI.
