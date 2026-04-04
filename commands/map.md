---
name: vbw:map
category: advanced
disable-model-invocation: true
description: Analyze existing codebase with adaptive Scout teammates to produce structured mapping documents.
argument-hint: [--incremental] [--package=name] [--tier=solo|duo|quad]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, Agent, TeamCreate, TaskCreate, SendMessage, TeamDelete, Skill, LSP
---

# VBW Map: $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break; done; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
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

Overrides: --tier flag forces tier. Agent Teams not enabled → force solo (`⚠ Agent Teams not enabled — using solo mode`). `prefer_teams='never'` in config → force solo (`⚠ prefer_teams=never — using solo mode`).
Display: `◆ Sizing: {SOURCE_FILE_COUNT} source files → {tier} mode`

Read `prefer_teams` before applying tier:
```bash
PREFER_TEAMS=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/normalize-prefer-teams.sh .vbw-planning/config.json 2>/dev/null || echo "auto")
```
If `PREFER_TEAMS` is `never`, force solo regardless of file count or --tier flag.

### Step 1.3: Detect code-analysis MCP capabilities

Inspect the available tool names in the system context (the deferred tools list in `<system-reminder>` blocks). Tool names follow the pattern `mcp__{server_name}__{tool_name}`. Pattern-match the **tool_name suffix** (the portion after the last `__`) against these capability signatures:

**Pass 1: Name-suffix matching**

```
CAPABILITY_ARCHITECTURE     := tool name ending in: get_architecture, analyze_architecture, extract_architecture, get_repo_outline, get_symbol_importance
CAPABILITY_SYMBOL_SEARCH    := tool name ending in: search_graph, find_symbols, search_symbols, workspace_symbol
CAPABILITY_DEPENDENCY_GRAPH := tool name ending in: query_graph, get_dependencies, analyze_dependencies, dependency_graph, find_importers, get_layer_violations
CAPABILITY_CALL_TRACING     := tool name ending in: trace_call_path, find_callers, call_hierarchy, find_importers, get_blast_radius
CAPABILITY_CODE_SEARCH      := tool name ending in: search_code, code_search, search_sections, get_section, get_sections
CAPABILITY_CODE_SNIPPET     := tool name ending in: get_code_snippet, read_function, get_function, get_symbol_source, get_section_context
CAPABILITY_HOTSPOT_ANALYSIS := tool name ending in: detect_changes, hotspot_analysis, complexity_analysis, get_blast_radius, get_changed_symbols, find_dead_code, get_broken_links, get_doc_coverage
CAPABILITY_INDEX            := tool name ending in: index_repository, index_status, index_local, index_repo, index_folder
CAPABILITY_OUTLINE          := tool name ending in: get_file_outline, get_repo_outline, get_document_outline, get_toc, get_toc_tree
CAPABILITY_IMPACT_ANALYSIS  := tool name ending in: get_blast_radius, get_changed_symbols, find_dead_code, get_layer_violations, get_doc_coverage, get_broken_links
CAPABILITY_CLASS_HIERARCHY  := tool name ending in: get_class_hierarchy, class_hierarchy, get_inheritance
```

Note: some tools (e.g., `find_importers`, `get_blast_radius`) map to multiple categories — this is intentional as they provide data useful for multiple mapping documents.

For each detected capability, store the full tool name (e.g., `mcp__codebase-memory-mcp__get_architecture`). This produces a **`MCP_MAP_CAPABILITIES`** set mapping capability categories to specific tool names. Multiple tools may match the same category (list all).

**Pass 2: Description-based matching (unclassified tools only)**

For each MCP tool not matched by Pass 1, use `ToolSearch` to load its schema and read its `description` field. Match the description text against these semantic keyword sets (case-insensitive):

```
CAPABILITY_ARCHITECTURE     := description contains: "architecture", "structure overview", "entry point", "package breakdown", "codebase overview"
CAPABILITY_SYMBOL_SEARCH    := description contains: "find symbol", "search symbol", "locate function", "locate class", "symbol lookup", "find definition"
CAPABILITY_DEPENDENCY_GRAPH := description contains: "dependency", "import graph", "module relationship", "dependency tree"
CAPABILITY_CALL_TRACING     := description contains: "call graph", "caller", "callee", "call chain", "call hierarchy", "who calls", "what calls"
CAPABILITY_CODE_SEARCH      := description contains: "search code", "text search", "content search", "search source", "search section"
CAPABILITY_CODE_SNIPPET     := description contains: "source code for", "retrieve function", "retrieve symbol", "get source", "extract code", "symbol source"
CAPABILITY_HOTSPOT_ANALYSIS := description contains: "complexity", "hotspot", "change impact", "risk score", "blast radius", "dead code", "unreachable"
CAPABILITY_INDEX            := description contains: "index repository", "index folder", "index codebase", "reindex", "build index", "index local"
CAPABILITY_OUTLINE          := description contains: "outline", "table of contents", "file structure", "symbol list", "section hierarchy"
CAPABILITY_IMPACT_ANALYSIS  := description contains: "impact", "blast radius", "breaking change", "dead code", "coverage gap", "broken link", "layer violation"
CAPABILITY_CLASS_HIERARCHY  := description contains: "inheritance", "class hierarchy", "type hierarchy", "class relationship", "subclass", "superclass"
```

Rules:
1. Pass 1 (name suffix) always takes priority — Pass 2 only runs on tools not already classified
2. A tool can match at most one category in Pass 2 (first match wins, categories checked in the order listed above)
3. If a tool's description matches no keyword set, skip it — do not force-classify
4. Tools classified by Pass 2 are added to MCP_MAP_CAPABILITIES with the same structure as Pass 1 results

If any capabilities are detected (from either pass), also check for `CAPABILITY_INDEX` — if an indexing tool is available, note it for the graph freshness instruction in downstream steps.

Display:
- If capabilities detected: `◆ MCP: {N} code-analysis capabilities detected ({M} by name, {K} by description) — will delegate structural analysis`
- If none: `○ MCP: No code-analysis tools detected — using file-based analysis`

**IMPORTANT:** Do NOT hardcode any MCP server names in the detection logic. Only tool name suffix patterns and description keywords matter. Detection is purely capability-based.

### Step 2: Detect monorepo

**JS/Node patterns:** Check lerna.json, pnpm-workspace.yaml, packages/ or apps/ with sub-package.json, root workspaces field.

**Multi-component detection:** Count distinct build system roots at different paths. Build system markers: package.json, Cargo.toml, go.mod, pyproject.toml, build.gradle, pom.xml, *.xcodeproj, Podfile, pubspec.yaml. If 2+ markers found at different directory levels (not just root), treat as monorepo.

If monorepo + --package: scope to that package.

### Step 3: Execute mapping (tier-branched)

**Step 3-solo:** Orchestrator analyzes each domain sequentially, writes to `.vbw-planning/codebase/`:

**MCP-accelerated analysis (when MCP_MAP_CAPABILITIES is non-empty):**
If code-analysis MCP capabilities were detected in Step 1.3, use them as the primary data source for each domain. The orchestrator calls MCP tools directly instead of broad Glob/Read/Grep sweeps.

Execution order:
1. If CAPABILITY_INDEX detected: call the index tool to ensure graph freshness
2. If CAPABILITY_ARCHITECTURE detected: call it first — its output (language breakdown, packages, entry points, routes, hotspots, cross-service boundaries) feeds STACK.md, ARCHITECTURE.md, and STRUCTURE.md
3. Per domain, prefer MCP tools over file reads:
   - Domain 1 (STACK.md + DEPENDENCIES.md): architecture extraction for languages/packages, dependency graph for inter-module deps, outline for file organization. Fall back to Read for manifest files (package.json, go.mod version strings).
   - Domain 2 (ARCHITECTURE.md + STRUCTURE.md): architecture extraction for entry points/routes/hotspots, call tracing for data flow, symbol search for module layout, class hierarchy for inheritance chains, outline for structural overview. Fall back to Glob for directory tree.
   - Domain 3 (CONVENTIONS.md + TESTING.md): code search for naming/test patterns, code snippet for style examples. Fall back to Read for config files (.eslintrc, .prettierrc, CI YAML).
   - Domain 4 (CONCERNS.md): hotspot analysis for risk areas, call tracing for high fan-out, dependency graph for coupling, impact analysis for blast radius/dead code/broken links/layer violations. Fall back to Read for non-code concern notes.
4. Write documents in the same format as brute-force analysis — document structure must be identical regardless of data source. Downstream consumers (infer-project-context.sh, compile-context.sh, init.md Step 3b/3b2) parse these documents by section headers.

**If MCP_MAP_CAPABILITIES is empty:** proceed with existing brute-force analysis (Glob/Read/Grep) unchanged:
- Domain 1 (Tech Stack): STACK.md + DEPENDENCIES.md
- Domain 2 (Architecture): ARCHITECTURE.md + STRUCTURE.md
- Domain 3 (Quality): CONVENTIONS.md + TESTING.md
- Domain 4 (Concerns): CONCERNS.md

Display ✓ per domain. After all 7 docs written, skip Step 3.5, go to Step 4.

---

**Step 3-duo:** **Pre-TeamCreate cleanup:** `bash "${VBW_PLUGIN_ROOT}/scripts/clean-stale-teams.sh" 2>/dev/null || true`. Create team via TeamCreate: `team_name="vbw-map-duo"`, `description="Codebase Map (duo)"` with 2 Scouts via TaskCreate. **Set `subagent_type: "vbw:vbw-scout"` on each Scout TaskCreate.**

Scout A (Tech + Architecture): analyze tech stack, deps, architecture, structure. Write findings directly to the output paths. Include in prompt:
```
<output_paths>
.vbw-planning/codebase/STACK.md
.vbw-planning/codebase/DEPENDENCIES.md
.vbw-planning/codebase/ARCHITECTURE.md
.vbw-planning/codebase/STRUCTURE.md
</output_paths>
```
Mode: {MAPPING_MODE}. After writing all 4 files, send a `scout_findings` message (domain: "tech-and-architecture") with `cross_cutting` findings only (file contents already written). Schema ref: ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/handoff-schemas.md`

Scout B (Quality + Concerns): analyze quality, conventions, testing, debt, risks. Write findings directly to the output paths. Include in prompt:
```
<output_paths>
.vbw-planning/codebase/CONVENTIONS.md
.vbw-planning/codebase/TESTING.md
.vbw-planning/codebase/CONCERNS.md
</output_paths>
```
Mode: {MAPPING_MODE}. After writing all 3 files, send a `scout_findings` message (domain: "quality-and-concerns") with `cross_cutting` findings only. Schema ref: ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/handoff-schemas.md`

**Scout model (effort-gated):** Fast/Turbo: `Model: haiku`. Thorough/Balanced: inherit session model.
**Scout turn budget (effort-gated):** Resolve with `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "{effort}"`. If `SCOUT_MAX_TURNS` is non-empty, pass `maxTurns: ${SCOUT_MAX_TURNS}` to each Scout TaskCreate. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).
**Skill pre-evaluation:** Before composing Scout task descriptions, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to codebase mapping. If any skills are relevant, the Scout prompt MUST start with `<skill_activation>{For each relevant skill: "Call Skill({skill-name})"}</skill_activation>`. Only include skills whose description matches the task at hand. If no skills are relevant, omit the skill_activation block entirely.
**MCP code-analysis delegation:** If `MCP_MAP_CAPABILITIES` (from Step 1.3) is non-empty, prepend the following `<mcp_code_analysis>` block to each Scout's task description. If `MCP_MAP_CAPABILITIES` is empty, omit the block entirely (Scout prompts unchanged from pre-MCP behavior).

For **Scout A** (Tech + Architecture), include capabilities relevant to STACK.md, DEPENDENCIES.md, ARCHITECTURE.md, STRUCTURE.md:
```
<mcp_code_analysis>
Code-analysis MCP tools are available. Use them as your PRIMARY source for structural analysis before falling back to Glob/Read/Grep.

Available capabilities:
{For each detected capability relevant to this Scout's documents, list: "- {Category}: {full_tool_name} — use for {target documents}"}

Capability-to-document routing:
- Architecture extraction → ARCHITECTURE.md, STACK.md
- Symbol search → STRUCTURE.md (module layout, entry points)
- Dependency graph → DEPENDENCIES.md (inter-module dependencies)
- Call tracing → ARCHITECTURE.md (data flow)
- Outline extraction → STRUCTURE.md (file organization, module layout)
- Class hierarchy → ARCHITECTURE.md (inheritance chains, type relationships)

{If CAPABILITY_INDEX detected:}
IMPORTANT: Call {index_tool_name} first if the graph may be stale (check with index_status if available, otherwise call index_repository at session start).

Fall back to Glob/Read/Grep for:
- External dependency manifests (package.json, go.mod, Cargo.toml — version numbers)
- CI/CD configuration (GitHub Actions YAML, Makefile, Dockerfile)
- Directory tree listing (Glob still needed for exact file paths)
- Non-code assets (images, fonts, binary files)
</mcp_code_analysis>
```

For **Scout B** (Quality + Concerns), include capabilities relevant to CONVENTIONS.md, TESTING.md, CONCERNS.md:
```
<mcp_code_analysis>
Code-analysis MCP tools are available. Use them as your PRIMARY source for structural analysis before falling back to Glob/Read/Grep.

Available capabilities:
{For each detected capability relevant to this Scout's documents, list: "- {Category}: {full_tool_name} — use for {target documents}"}

Capability-to-document routing:
- Code search → CONVENTIONS.md (naming patterns), TESTING.md (test patterns)
- Code snippet → CONVENTIONS.md (code style examples)
- Call tracing → CONCERNS.md (complexity hotspots)
- Hotspot analysis → CONCERNS.md (risk areas, high fan-out)
- Impact analysis → CONCERNS.md (blast radius, dead code, broken links, layer violations)

{If CAPABILITY_INDEX detected:}
IMPORTANT: Call {index_tool_name} first if the graph may be stale (check with index_status if available, otherwise call index_repository at session start).

Fall back to Glob/Read/Grep for:
- CI/CD configuration (GitHub Actions YAML, Makefile, Dockerfile)
- Linter/formatter config (.eslintrc, .prettierrc, tsconfig.json)
- Non-code assets and documentation files
</mcp_code_analysis>
```

Additionally, if MCP tools relevant to non-code-analysis tasks are available (e.g., documentation servers for framework APIs), note them in the Scout task prompt so Scouts can use them alongside local file analysis.
Wait for all findings. Proceed to Step 3.5.

---

**Step 3-quad:** **Pre-TeamCreate cleanup:** `bash "${VBW_PLUGIN_ROOT}/scripts/clean-stale-teams.sh" 2>/dev/null || true`. Create team via TeamCreate: `team_name="vbw-map-quad"`, `description="Codebase Map (quad)"` with 4 Scouts via TaskCreate. **Set `subagent_type: "vbw:vbw-scout"` on each Scout TaskCreate.** Each Scout writes its domain files directly via `<output_paths>`, then sends a `scout_findings` message with `cross_cutting` findings only (file contents already written). Schema ref: ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/references/handoff-schemas.md`
- Scout 1 (Tech Stack): `<output_paths>` = `.vbw-planning/codebase/STACK.md`, `.vbw-planning/codebase/DEPENDENCIES.md`
- Scout 2 (Architecture): `<output_paths>` = `.vbw-planning/codebase/ARCHITECTURE.md`, `.vbw-planning/codebase/STRUCTURE.md`
- Scout 3 (Quality): `<output_paths>` = `.vbw-planning/codebase/CONVENTIONS.md`, `.vbw-planning/codebase/TESTING.md`
- Scout 4 (Concerns): `<output_paths>` = `.vbw-planning/codebase/CONCERNS.md`

Security: PreToolUse hook handles enforcement. **Scout model:** same as duo. **Scout turn budget:** same as duo (pass `maxTurns: ${SCOUT_MAX_TURNS}` when non-empty, omit when empty). **Skill pre-evaluation:** same as duo.
**MCP code-analysis delegation:** same as duo — if `MCP_MAP_CAPABILITIES` is non-empty, prepend the `<mcp_code_analysis>` block to each Scout's task description with capabilities routed to their assigned documents:
- Scout 1 (Tech Stack): capabilities relevant to STACK.md + DEPENDENCIES.md (architecture extraction, dependency graph, symbol search, outline)
- Scout 2 (Architecture): capabilities relevant to ARCHITECTURE.md + STRUCTURE.md (architecture extraction, symbol search, call tracing, class hierarchy, outline)
- Scout 3 (Quality): capabilities relevant to CONVENTIONS.md + TESTING.md (code search, code snippet)
- Scout 4 (Concerns): capabilities relevant to CONCERNS.md (hotspot analysis, call tracing, dependency graph, impact analysis)

**Scout communication (effort-gated):**

| Effort | Messages |
|--------|----------|
| Thorough | Cross-cutting findings + contradiction flags for INDEX.md Validation Notes |
| Balanced | Cross-cutting findings only |
| Fast | Blockers only |

Use targeted `message` not `broadcast`. Wait for all findings. Display ✓ per scout.

### Step 3.5: Verify mapping documents written by Scouts

**Skip if solo** (docs already written). Scouts wrote files directly via `<output_paths>`. Verify all 7 docs exist in `.vbw-planning/codebase/`: STACK.md, DEPENDENCIES.md, ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, CONCERNS.md. If any are missing, log `⚠ Missing: {filename}` and write a placeholder from the `scout_findings` message content (fall back to cross_cutting text). Use `cross_cutting` findings from scout_findings messages for INDEX.md Validation Notes in Step 4.

### Step 4: Synthesize INDEX.md and PATTERNS.md

Read all 7 docs. Produce:
- **INDEX.md:** Cross-referenced index with key findings + "Validation Notes" for contradictions
- **PATTERNS.md:** Recurring patterns: architectural, naming, quality, concern, dependency

### Step 5: Create META.md and present summary

**HARD GATE — Shutdown before presenting results:** Solo: no team, skip. Duo/Quad: send `shutdown_request` to each teammate, wait for `shutdown_response` (approved=true) delivered via SendMessage tool call (NOT plain text). If a teammate responds in plain text instead of calling SendMessage, re-send the `shutdown_request`. If rejected, re-request (max 3 attempts per teammate — then proceed). Call TeamDelete. **Post-TeamDelete residual cleanup:** `bash "${VBW_PLUGIN_ROOT}/scripts/clean-stale-teams.sh" 2>/dev/null || true`. Verify: after TeamDelete, there must be ZERO active teammates. If teardown stalls, advise the user to run `/vbw:doctor --cleanup`. Only THEN proceed to META.md and user output. Failure to shut down leaves agents running and consuming API credits.

Write META.md: mapped_at, git_hash, file_count, document list, mode, monorepo flag, mapping_tier, mcp_capabilities.

The `mcp_capabilities` field records which capability categories from Step 1.3 were detected and used during mapping. This serves debugging (users can see whether MCP delegation was active) and incremental mode (future mapping can check if prior mapping used MCP tools and whether those tools are still available).

Example with MCP capabilities:
```yaml
mcp_capabilities:
  - architecture_extraction
  - symbol_search
  - dependency_graph
  - call_tracing
  - code_search
  - hotspot_analysis
```

Example without MCP capabilities:
```yaml
mcp_capabilities: none
```

Display per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md: Phase Banner (Codebase Mapped, Mode, Tier), ✓ per document, Key Findings (◆), Next Up block.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — Phase Banner (double-line box), File Checklist (✓), ◆ for findings, ⚠ for warnings, Next Up Block, no ANSI.
