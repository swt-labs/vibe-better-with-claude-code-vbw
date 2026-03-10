---
name: vbw:init
category: lifecycle
disable-model-invocation: true
description: Set up environment, scaffold .vbw-planning, detect project context, and bootstrap project-defining files.
argument-hint:
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, LSP
---

# VBW Init

<!-- Full init flow: Steps 0-4 handle environment/scaffold/hooks/mapping/summary -->
<!-- Steps 5-8 handle auto-bootstrap: detect scenario, run inference (brownfield/GSD), confirm with user, generate project files -->

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break; done; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; rm -f "$LINK"; ln -s "$REAL_R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

Existing state:
```
!`ls -la .vbw-planning 2>/dev/null || echo "No .vbw-planning directory"`
```
Project files:
```
!`ls package.json pyproject.toml Cargo.toml go.mod Gemfile build.gradle pom.xml mix.exs 2>/dev/null || echo "No detected project files"`
```
Skills:
```
!`for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; [ -d "$_d/skills/" ] && ls "$_d/skills/" 2>/dev/null && break; done || echo "No global skills"`
```
```
!`ls .claude/skills/ 2>/dev/null || echo "No project skills"`
```

## Guard

1. **Already initialized:** If .vbw-planning/config.json exists, STOP: "VBW is already initialized. Use /vbw:config to modify settings or /vbw:vibe to start building."
2. **jq required:** `command -v jq` via Bash. If missing, STOP: "VBW requires jq. Install: macOS `brew install jq`, Linux `apt install jq`, Manual: https://jqlang.github.io/jq/download/ — then re-run /vbw:init." Do NOT proceed without jq.
3. **Brownfield detection:** Check for existing source files (stop at first match):
   - Git repo: `git ls-files --error-unmatch . 2>/dev/null | head -5` — any output = BROWNFIELD=true
   - No git: Glob `**/*.*` excluding `.vbw-planning/`, `.claude/`, `node_modules/`, `.git/` — any match = BROWNFIELD=true
   - All file types count (shell, config, markdown, C++, Rust, CSS, etc.)

## Steps

<!-- Steps 0-4: Infrastructure setup (environment, scaffold, hooks, mapping, summary) -->
<!-- Steps 5-8: Auto-bootstrap (scenario detection, inference, bootstrap execution, completion) -->

### Step 0: Environment setup (settings.json)

**CRITICAL: Complete ENTIRE step (including writing settings.json) BEFORE Step 1. Use AskUserQuestion for prompts. Wait for answers. Write settings.json. Only then proceed.**

**Resolve config directory:** Try in order: env var `CLAUDE_CONFIG_DIR` (if set and directory exists), `~/.config/claude-code` (if exists), otherwise `~/.claude`. Store result as `CLAUDE_DIR`. Use it for all config paths in this command.

Read `CLAUDE_DIR/settings.json` (create `{}` if missing).

**0a. Agent Teams:** Check `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` == `"1"`.
- Enabled: display "✓ Agent Teams — enabled", go to 0b
- Not enabled: AskUserQuestion: "⚠ Agent Teams is not enabled\n\nVBW uses Agent Teams for parallel builds and codebase mapping.\nEnable it now?"
  - Approved: set to `"1"`. Declined: display "○ Skipped."

**0b. Statusline:** Read `statusLine` (may be string or object with `command` field).

| State | Condition | Action |
|-------|-----------|--------|
| HAS_VBW | Value contains `vbw-statusline` | Display "✓ Statusline — installed", skip to 0c |
| HAS_OTHER | Non-empty, no `vbw-statusline` | AskUserQuestion (mention replacement) |
| EMPTY | Missing/null/empty | AskUserQuestion |

AskUserQuestion text: "○ VBW includes a custom status line showing phase progress, context usage, cost, duration, and more — updated after every response. Install it?" (If HAS_OTHER, mention existing statusline would be replaced.)

If approved, set `statusLine` to:
```json
{"type": "command", "command": "bash -c 'for _d in \"${CLAUDE_CONFIG_DIR:-}\" \"$HOME/.config/claude-code\" \"$HOME/.claude\"; do [ -z \"$_d\" ] && continue; f=$(ls -1 \"$_d\"/plugins/cache/vbw-marketplace/vbw/*/scripts/vbw-statusline.sh 2>/dev/null | sort -V | tail -1 || true); [ -f \"$f\" ] && exec bash \"$f\"; done'"}
```
Object format with `type`+`command` is **required** — plain string fails silently.
If declined: display "○ Skipped. Run /vbw:config to install it later."

**0c. Write settings.json** if changed (single write). Display summary:
```
Environment setup complete:
  {✓ or ○} Agent Teams
  {✓ or ○} Statusline {add "(restart to activate)" if newly installed}
```

### Step 0.5: GSD import (conditional)

**Timing rationale:** Detection happens after environment setup (Step 0) but before scaffold (Step 1) to ensure:
- settings.json writes complete before any directory operations
- .vbw-planning/gsd-archive/ is created before scaffold creates .vbw-planning/
- User sees GSD detection early in the init flow
- Index generation (if implemented) can run after scaffold completes

**Index structure**: The INDEX.json file generated by `scripts/generate-gsd-index.sh` contains:
- `imported_at`: UTC timestamp
- `gsd_version`: From .planning/config.json (or "unknown")
- `phases_total`, `phases_complete`: Counts based on SUMMARY file presence
- `milestones`: Extracted from ROADMAP.md h2 headers
- `quick_paths`: Relative paths to key archive files (roadmap, project, phases, config)
- `phases`: Array of {num, slug, plans, status} per phase directory

See `docs/migration-gsd-to-vbw.md` for full field descriptions and usage examples.

**Detection:** Check for .planning/ directory: `[ -d .planning ]`

- **NOT found:** skip silently to Step 1 (no display output)
- **Found:** proceed with import flow:
  1. Display: "◆ GSD project detected"
  2. AskUserQuestion: "GSD project detected. Import work history?\n\nThis will copy .planning/ to .vbw-planning/gsd-archive/ for reference.\nYour original .planning/ directory will remain untouched."
     - Options: "Import (Recommended)" / "Skip"
  3. If user declines:
     - Display: "○ GSD import skipped"
     - Proceed to Step 1
  4. If user approves:
     - Create directory: `mkdir -p .vbw-planning/gsd-archive`
     - Copy contents: `cp -r .planning/* .vbw-planning/gsd-archive/`
     - Display: "◆ Generating index..."
     - Run: `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/generate-gsd-index.sh`
     - Display: "✓ GSD project archived to .vbw-planning/gsd-archive/ (indexed)"
     - Set GSD_IMPORTED=true flag for later steps
     - Proceed to Step 1

### Step 1: Scaffold directory

Read each template from ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/templates/` and write to .vbw-planning/:

| Target | Source |
|--------|--------|
| .vbw-planning/PROJECT.md | `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/templates/PROJECT.md |
| .vbw-planning/REQUIREMENTS.md | `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/templates/REQUIREMENTS.md |
| .vbw-planning/ROADMAP.md | `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/templates/ROADMAP.md |
| .vbw-planning/STATE.md | `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/templates/STATE.md |
| .vbw-planning/config.json | `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/defaults.json |

Create `.vbw-planning/phases/`. Ensure config.json includes `"prefer_teams": "auto"` and `"model_profile": "quality"`.

AskUserQuestion (single select):
- "How should VBW planning artifacts be tracked in git?"
  - `manual` (default): don't auto-ignore or auto-commit planning files
  - `ignore`: keep `.vbw-planning/` ignored in root `.gitignore`
  - `commit`: track `.vbw-planning/` + `CLAUDE.md` at lifecycle boundaries

AskUserQuestion (single select):
- "When should VBW push commits?"
  - `never` (default)
  - `after_phase` (push once after a phase completes)
  - `always` (push after each commit when upstream exists)

Write selected values to `.vbw-planning/config.json`:

```bash
jq '.planning_tracking = "'"$PLANNING_TRACKING"'" | .auto_push = "'"$AUTO_PUSH"'"' .vbw-planning/config.json > .vbw-planning/config.json.tmp && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
```

Then align git ignore behavior with config:

```bash
PG_SCRIPT="`!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/planning-git.sh"
if [ -f "$PG_SCRIPT" ]; then
  bash "$PG_SCRIPT" sync-ignore .vbw-planning/config.json
else
  echo "VBW: planning-git.sh unavailable; skipping .gitignore sync" >&2
fi
```

### Step 1.5: Install git hooks

1. `git rev-parse --git-dir` — if not a git repo, display "○ Git hooks skipped (not a git repository)" and skip
2. Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/install-hooks.sh`, display based on output:
   - Contains "Installed": `✓ Git hooks installed (pre-push)`
   - Contains "already installed": `✓ Git hooks (already installed)`

### Step 1.7: GSD isolation (conditional)

**1.7a. Detection:** `[ -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands/gsd" ] || [ -d "$HOME/.config/claude-code/commands/gsd" ] || [ -d ".planning" ] || [ -d ".vbw-planning/gsd-archive" ]`
- None true: GSD_DETECTED=false, display nothing, skip to Step 2
- Any true: GSD_DETECTED=true, proceed to 1.7b

**1.7b. Consent:** AskUserQuestion: "GSD detected. Enable plugin isolation?\n\nThis adds a PreToolUse hook that prevents GSD commands and agents from\nreading or writing files in .vbw-planning/. VBW commands are unaffected."
Options: "Enable (Recommended)" / "Skip". If declined: "○ GSD isolation skipped", skip to Step 2.

**1.7c. Create isolation:** If approved:
1. `echo "enabled" > .vbw-planning/.gsd-isolation`
2. `echo "session" > .vbw-planning/.vbw-session`
3. Display: `✓ GSD isolation enabled` + `✓ .vbw-planning/.gsd-isolation (flag)` + `✓ Plugin Isolation section will be added to CLAUDE.md in Step 3.5`

Set GSD_ISOLATION_ENABLED=true for Step 3.5.

### Step 2: Brownfield detection + discovery

**2a.** If BROWNFIELD=true:
- Count source files by extension (Glob), excluding .vbw-planning/, node_modules/, .git/, vendor/, dist/, build/, target/, .next/, __pycache__/, .venv/, coverage/
- Store SOURCE_FILE_COUNT. Check for test files, CI/CD, Docker, monorepo indicators.
- Add Codebase Profile to STATE.md.

**2b.** Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/detect-stack.sh "$(pwd)"`. Save full JSON. Display: `✓ Stack: {comma-separated detected_stack items}`

**2.5. LSP setup (language servers + Claude plugins):**

Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-lsp.sh` with the `detected_stack` JSON array from Step 2b and `CLAUDE_DIR/settings.json` path. Capture the JSON output.

If `env_needed=false` AND all plugins have `plugin_enabled=true`: display `✓ LSP — already configured`, skip to 2c.

Otherwise, display detected languages and recommended LSP plugins, then proceed through sub-steps:

**2.5a (env flag):** If `env_needed=true`:
- AskUserQuestion: "○ LSP Tools\n\nEnable LSP tools for Claude Code? This adds ENABLE_LSP_TOOL=1 to settings.json,\ngiving Claude access to goToDefinition, findReferences, and other code navigation tools."
  - Approved: set `env.ENABLE_LSP_TOOL` to `"1"` in `CLAUDE_DIR/settings.json` (same write pattern as Step 0c)
  - Declined: display "○ LSP env flag skipped"

**2.5b (binary check):** For each plugin where `binary_installed=false`:
- If `install_cmd` is not null: AskUserQuestion: "Install {description} language server?\nCommand: `{install_cmd}`"
  - Approved: run command via Bash
  - Declined: display "○ {description} — skipped"
- If `install_cmd` is null (install_url only): display "○ {description} — manual install: {install_url}"

**2.5c (marketplace catalog):** If any plugins have `plugin_enabled=false`:
- Check catalog: `unset CLAUDECODE && claude plugin marketplace list 2>&1 | grep -q "{org}"` (using the `org` from the first pending plugin)
- If catalog missing: AskUserQuestion: "LSP plugins are published on the `{org}` marketplace catalog. Add it?"
  - Approved: run `unset CLAUDECODE && claude plugin marketplace add {org} 2>&1`
  - Declined or fails: display "○ Marketplace catalog not available — skipping plugin installs" and skip 2.5d

**2.5d (plugin install):** For plugins where `plugin_enabled=false`:
- AskUserQuestion: "Install Claude LSP plugins for: {comma-separated descriptions}?"
  - Approved: run `unset CLAUDECODE && claude plugin marketplace update {org} 2>&1` once, then for each: `unset CLAUDECODE && claude plugin install {plugin} 2>&1`
  - Declined: display "○ LSP plugins — skipped"

Display summary: `✓ LSP — {N} language server(s) configured` or `○ LSP — skipped`
If any settings.json changes or plugins installed: display `(restart Claude Code to activate LSP)`

**2c. Codebase mapping (adaptive):**
- Greenfield (BROWNFIELD=false): skip. Display: `○ Greenfield — skipping codebase mapping`
- SOURCE_FILE_COUNT < 200: run map **inline** — read ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/commands/map.md` and follow directly
- SOURCE_FILE_COUNT >= 200: run map **inline** (blocking) — display: `◆ Codebase mapping started ({SOURCE_FILE_COUNT} files)`. **Do NOT run in background.** The map MUST complete before proceeding to Step 3.

**2d. find-skills bootstrap:** Check `find_skills_available` from detect-stack JSON.
- `true`: display "✓ Skills.sh registry — available"
- `false`: AskUserQuestion: "○ Skills.sh Registry\n\nVBW can search the Skills.sh registry (~2000 community skills) to find\nskills matching your project. This requires the find-skills meta-skill.\nInstall it now?" Options: "Install (Recommended)" / "Skip"
  - Approved: `npx skills add vercel-labs/skills --skill find-skills -g -y`
  - Declined: "○ Skipped. Run /vbw:skills later to search the registry."

### Step 3: Convergence — augment and search

**3a.** Verify mapping completed. Display `✓ Codebase mapped ({document-count} documents)`. If skipped (greenfield): proceed immediately.

**3b.** If `.vbw-planning/codebase/STACK.md` exists, read it and merge additional stack components into detected_stack[].

**3b2. Auto-detect conventions:** If `.vbw-planning/codebase/PATTERNS.md` exists:
- Read PATTERNS.md, ARCHITECTURE.md, STACK.md, CONCERNS.md
- Extract conventions per ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/commands/teach.md` (Step R2)
- Write `.vbw-planning/conventions.json`. Display: `✓ {count} conventions auto-detected from codebase`

If greenfield: write `{"conventions": []}`. Display: `○ Conventions — none yet (add with /vbw:teach)`

**3c. Parallel registry search** (if find-skills available): run `npx skills find "<stack-item>"` for ALL detected_stack items **in parallel** (multiple concurrent Bash calls). Deduplicate against installed skills. If detected_stack empty, search by project type. Display results with `(registry)` tag.

**3d. Unified skill prompt:** Combine curated (from 2b) + registry (from 3c) results into single AskUserQuestion multiSelect. Tag `(curated)` or `(registry)`. Max 4 options + "Skip". Install selected: `npx skills add <skill> -g -y`.

### Step 3.5: Generate bootstrap CLAUDE.md

VBW needs its rules and state sections in a CLAUDE.md file. /vbw:vibe regenerates later with project content.

**Brownfield handling:** Read root `CLAUDE.md` via the Read tool.
- **Exists:** The user already has a CLAUDE.md. Do NOT overwrite it and do NOT assume the first heading/core-value lines belong to VBW. Preserve all user-authored content verbatim. Only refresh exact canonical VBW-owned sections already emitted by VBW (`## Active Context`, `## VBW Rules`, `## Plugin Isolation`) and add `## Code Intelligence` only if no Code Intelligence heading/guidance already exists anywhere in the file. Display `✓ CLAUDE.md (VBW sections refreshed in place)`.
- **Does not exist:** Create a new `CLAUDE.md` via `bootstrap-claude.sh` during Step 7f. Do NOT hand-compose the file here.

Do not append `## Project Conventions` or `## Commands` to `CLAUDE.md`.

### Step 4: Present summary

Display Phase Banner then file checklist (✓ for each created file).

**GSD import status** (conditional):
- If GSD_IMPORTED=true: Display "✓ GSD project archived ({file count} files, indexed)" where file count = `find .vbw-planning/gsd-archive -type f | wc -l`, then display sub-bullet: "  • Index: .vbw-planning/gsd-archive/INDEX.json"
- If .planning exists but GSD_IMPORTED=false: Display "○ GSD import skipped"

Then show conditional lines for GSD isolation, statusline, codebase mapping, conventions, skills.

<!-- Auto-bootstrap flow begins here — seamless continuation from infrastructure setup -->

### Step 5: Scenario detection

<!-- Scenario detection: uses BROWNFIELD flag (Guard), gsd-archive (Step 0.5), codebase/ (Step 2c) -->
<!-- Order matters: check GSD_MIGRATION first since GSD projects may also be brownfield -->
<!-- HYBRID is an edge case fallback — should not occur after Step 2c mapping completes -->

Display transition message: `◆ Infrastructure complete. Defining project...`

Detect the initialization scenario based on flags set in earlier steps:

1. **GREENFIELD:** BROWNFIELD=false (set in Guard step). No existing codebase to infer from.
2. **GSD_MIGRATION:** `.vbw-planning/gsd-archive/` directory exists (created in Step 0.5). Has GSD work history to import.
3. **BROWNFIELD:** BROWNFIELD=true AND `.vbw-planning/codebase/` directory exists (created in Step 2c mapping). Has codebase context to infer from.
4. **HYBRID:** BROWNFIELD=true but `.vbw-planning/codebase/` does not exist. Edge case — should not occur after Step 2c, but handle gracefully by treating as GREENFIELD.

Check conditions in order (GSD_MIGRATION first since a GSD project may also be brownfield):

```
if [ -d .vbw-planning/gsd-archive ]; then SCENARIO=GSD_MIGRATION
elif [ "$BROWNFIELD" = "true" ] && [ -d .vbw-planning/codebase ]; then SCENARIO=BROWNFIELD
elif [ "$BROWNFIELD" = "true" ]; then SCENARIO=HYBRID
else SCENARIO=GREENFIELD
fi
```

Display the detected scenario:
- GREENFIELD: `○ Scenario: Greenfield — new project`
- BROWNFIELD: `◆ Scenario: Brownfield — existing codebase detected`
- GSD_MIGRATION: `◆ Scenario: GSD Migration — importing work history`
- HYBRID: `○ Scenario: Hybrid — treating as greenfield (no mapping)`

No user interaction in this step. Proceed immediately to Step 6.

### Step 6: Inference & confirmation

<!-- Inference scripts: infer-project-context.sh outputs {name, tech_stack, architecture, purpose, features} -->
<!-- Each field has {value, source} for attribution. Null value = not detected but still displayed (REQ-03) -->
<!-- infer-gsd-summary.sh outputs {latest_milestone, recent_phases, key_decisions, current_work} -->
<!-- Confirmation UX: 3 options prevent NL misinterpretation; field picker for targeted corrections -->

Run inference scripts based on the detected scenario, display results, and confirm with the user. Always show inferred data even if fields are null (REQ-03).

**6a. Greenfield branch** (SCENARIO=GREENFIELD or SCENARIO=HYBRID):
- Display: `○ Greenfield — no codebase context to infer`
- Set SKIP_INFERENCE=true
- Skip to Step 7 (discovery questions will be asked inline)

**6b. Brownfield branch** (SCENARIO=BROWNFIELD):
- Run inference: `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/infer-project-context.sh .vbw-planning/codebase/ "$(pwd)"`
- Capture JSON output to `.vbw-planning/inference.json` via Bash
- Parse the JSON and display inferred fields:
  ```
  ◆ Inferred project context:
    Name:         {name.value} (source: {name.source})
    Tech stack:   {tech_stack.value | join(", ")} (source: {tech_stack.source})
    Architecture: {architecture.value} (source: {architecture.source})
    Purpose:      {purpose.value} (source: {purpose.source})
    Features:     {features.value | join(", ")} (source: {features.source})
  ```
- For null fields, display: `{field}: (not detected)` — always show every field

**6c. GSD Migration branch** (SCENARIO=GSD_MIGRATION):
- Run GSD inference: `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/infer-gsd-summary.sh .vbw-planning/gsd-archive/`
- Capture JSON output to `.vbw-planning/gsd-inference.json` via Bash
- If `.vbw-planning/codebase/` exists, also run: `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/infer-project-context.sh .vbw-planning/codebase/ "$(pwd)"`
  - Capture to `.vbw-planning/inference.json`
- Display merged results:
  ```
  ◆ Inferred from GSD work history:
    Latest milestone: {latest_milestone.name} ({latest_milestone.status})
    Recent phases:    {recent_phases | map(.name) | join(", ")}
    Key decisions:    {key_decisions | join("; ")}
    Current work:     {current_work.phase} ({current_work.status})
  ```
- If codebase inference also ran, display those fields too (same format as 6b)
- For null fields, display: `{field}: (not detected)` — always show every field

**6d. Confirmation UX** (all non-greenfield scenarios):

Use AskUserQuestion to confirm inferred data:

"Does this look right?"

Options:
- **"Yes, looks right"** → Proceed to Step 7 with inferred data as-is
- **"Close, but needs adjustments"** → Enter correction flow (6e)
- **"Define from scratch"** → Set SKIP_INFERENCE=true, proceed to Step 7

**6e. Correction flow** (when user picks "Close, but needs adjustments"):

Display all fields as a numbered list. Use AskUserQuestion: "Which fields would you like to correct? (enter numbers, comma-separated)"

For each selected field, use AskUserQuestion to ask the user for the corrected value. Update the inference JSON with corrected values.

After all corrections, display updated summary and proceed to Step 7 with corrected data.

Write the final confirmed/corrected data to `.vbw-planning/inference.json` for Step 7 consumption.

### Step 7: Bootstrap execution

<!-- Bootstrap scripts expect specific argument formats — see each script's usage header -->
<!-- bootstrap-project.sh: OUTPUT_PATH NAME DESCRIPTION -->
<!-- bootstrap-requirements.sh: OUTPUT_PATH DISCOVERY_JSON_PATH (discovery.json: {answered[], inferred[]}) -->
<!-- bootstrap-roadmap.sh: OUTPUT_PATH PROJECT_NAME PHASES_JSON (phases.json: [{name, goal, requirements[], success_criteria[]}]) -->
<!-- bootstrap-state.sh: OUTPUT_PATH PROJECT_NAME MILESTONE_NAME PHASE_COUNT -->
<!-- bootstrap-claude.sh: OUTPUT_PATH PROJECT_NAME CORE_VALUE [EXISTING_PATH] -->
<!-- Temporary JSON files (discovery.json, phases.json, inference.json) are cleaned up in 7g -->

Generate all project-defining files using confirmed data from Step 6 or discovery questions.

Display: `◆ Generating project files...`

**7a. Gather project data:**

If SKIP_INFERENCE=true (greenfield or user chose "Define from scratch"):
- Use AskUserQuestion to ask discovery questions:
  1. "What is your project name?"
  2. "Describe your project in one sentence."
  3. "What are the key requirements? (one per line)"
  4. "What phases do you envision? For each, give a name and goal. (e.g., 'Auth - User login and registration')"
- Store answers for bootstrap script input

If SKIP_INFERENCE=false (confirmed/corrected inference data):
- Read `.vbw-planning/inference.json` to get confirmed project context
- Extract: NAME from `name.value`, DESCRIPTION from `purpose.value`
- If GSD_MIGRATION: read `.vbw-planning/gsd-inference.json` for milestone/phase context
- Use AskUserQuestion to ask any remaining questions not covered by inference:
  1. "What are the key requirements?" (pre-fill from inferred features if available)
  2. "What phases do you envision?" (pre-fill from GSD recent_phases if available)

**7b. Generate PROJECT.md:**
- Run: `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/bootstrap/bootstrap-project.sh .vbw-planning/PROJECT.md "$NAME" "$DESCRIPTION"`
- Display: `✓ PROJECT.md`

**7c. Generate REQUIREMENTS.md:**
- Create `.vbw-planning/discovery.json` with format: `{"answered": [...], "inferred": [...]}`
  - `answered`: array of requirement strings from user answers
  - `inferred`: array of `{"text": "...", "priority": "Must-have"}` from inference features
- Run: `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/bootstrap/bootstrap-requirements.sh .vbw-planning/REQUIREMENTS.md .vbw-planning/discovery.json`
- Display: `✓ REQUIREMENTS.md`

**7d. Generate ROADMAP.md:**
- Create `.vbw-planning/phases.json` with format: `[{"name": "...", "goal": "...", "requirements": [...], "success_criteria": [...]}]`
  - Build from user-provided phase names/goals
  - Link requirements from discovery data
  - Generate success criteria from phase goals
- Run: `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/bootstrap/bootstrap-roadmap.sh .vbw-planning/ROADMAP.md "$NAME" .vbw-planning/phases.json`
- Display: `✓ ROADMAP.md`

**7e. Generate STATE.md:**
- Determine MILESTONE_NAME: use NAME or first milestone from GSD inference
- Determine PHASE_COUNT from phases.json length
- Run: `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/bootstrap/bootstrap-state.sh .vbw-planning/STATE.md "$NAME" "$MILESTONE_NAME" "$PHASE_COUNT"`
- Display: `✓ STATE.md`

**7f. Generate/update CLAUDE.md:**
- Extract `CORE_VALUE` from `.vbw-planning/PROJECT.md` (`grep -m1 '^\*\*Core value:\*\*' .vbw-planning/PROJECT.md | sed 's/^\*\*Core value:\*\* *//'`)
- If root CLAUDE.md exists: pass it as EXISTING_PATH to preserve non-VBW content
- Run: `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/bootstrap/bootstrap-claude.sh CLAUDE.md "$NAME" "$CORE_VALUE" "CLAUDE.md"`
  - If CLAUDE.md does not exist yet, omit the last argument
- Display: `✓ CLAUDE.md`

**7g. Cleanup temporary files:**
- Remove `.vbw-planning/discovery.json`, `.vbw-planning/phases.json`, `.vbw-planning/inference.json`, `.vbw-planning/gsd-inference.json` (if they exist)
- These are intermediate build artifacts, not project state

**7h. Planning commit boundary (conditional):**
- Run:
  ```bash
  PG_SCRIPT="`!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/planning-git.sh"
  if [ -f "$PG_SCRIPT" ]; then
    bash "$PG_SCRIPT" commit-boundary "bootstrap project files" .vbw-planning/config.json
  else
    echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
  fi
  ```
- Behavior:
  - `planning_tracking=commit`: stages `.vbw-planning/` + `CLAUDE.md` and commits if there are changes
  - `planning_tracking=manual|ignore`: no-op
  - If `auto_push=always`, pushes when branch has an upstream

### Step 8: Completion summary

<!-- Final summary replaces old Step 4 auto-launch of /vbw:vibe -->
<!-- User now has full project-defining files and can run /vbw:vibe when ready -->

Display a banner per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md with the title "VBW Initialization Complete".

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VBW Initialization Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**File checklist:** Display all created/updated files:
- `✓ .vbw-planning/PROJECT.md`
- `✓ .vbw-planning/REQUIREMENTS.md`
- `✓ .vbw-planning/ROADMAP.md`
- `✓ .vbw-planning/STATE.md`
- `✓ CLAUDE.md`
- `✓ .vbw-planning/config.json`
- If planning_tracking=commit and changes existed: `✓ Bootstrap planning artifacts committed`
- If GSD_IMPORTED=true: `✓ GSD project archived`
- If BROWNFIELD=true: `✓ Codebase mapped`

**Next steps:**
```
➜ Next: Run /vbw:vibe to start planning your first milestone
  Or:   Run /vbw:status to review project state
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — Phase Banner (double-line box), File Checklist (✓), ○ for pending, Next Up Block, no ANSI color codes.
