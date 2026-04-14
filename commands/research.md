---
name: vbw:research
category: advanced
disable-model-invocation: true
description: Run standalone research by spawning Scout agent(s) for web searches and documentation lookups.
argument-hint: <research-topic> [--parallel]
allowed-tools: Read, Write, Bash, Glob, Grep, WebFetch, WebSearch, Agent, Skill, LSP
---

# VBW Research: $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then R="${SESSION_LINK}"; fi; if [ -z "$R" ]; then ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "$link/scripts/hook-wrapper.sh" ]; then printf '%s\n' "$link"; break; fi; done || true); [ -n "$ANY_LINK" ] && R="$ANY_LINK"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; LINK="${SESSION_LINK}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

Current project:
```
!`cat .vbw-planning/PROJECT.md 2>/dev/null || echo "No project found"`
```

## Guard

- No $ARGUMENTS: STOP "Usage: /vbw:research <topic> [--parallel]"

## Steps

1. **Parse:** Strip any `--parallel` flag from $ARGUMENTS and store it separately for Step 2 routing. If the remaining $ARGUMENTS contains a `(ref:HASH)` suffix (8 hex characters), extract the hash and strip the ref tag. Store remaining text (minus flags and ref) as the topic. If a ref was found, load extended detail:
    ```bash
    bash "`!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/todo-details.sh" get <hash>
    ```
    Parse the JSON output. If `status` is `"ok"`, store `detail.context` and `detail.files` for Step 3. If `status` is `"not_found"` or `"error"`, and `.vbw-planning/STATE.md` exists, append `- {YYYY-MM-DD}: Detail for ref HASH could not be loaded` under the `## Activity Log` section (or the first heading beginning with `## Activity`) in `.vbw-planning/STATE.md`; if that file does not exist, skip logging. In all cases, continue without detail.
    If no ref suffix, $ARGUMENTS minus flags = topic.
    **Post-parse validation:** If the topic is empty or whitespace-only after stripping flags and ref, check whether a ref was found AND its detail loaded successfully (status `"ok"`). If yes, proceed — the detail provides the research context. If no ref was found, or the ref detail failed to load, STOP: `"Usage: /vbw:research <topic> [--parallel]"`.
    `--parallel` controls Scout fan-out (Step 2) and must not be included in the topic text passed to Scout.
2. **Scope:** Single question = 1 Scout. Multi-faceted or --parallel = 2-4 sub-topics.
3. **Spawn Scout:**
   - Resolve Scout model:
     ```bash
    RESEARCH_EFFORT=$(jq -r '.effort // "balanced"' .vbw-planning/config.json 2>/dev/null)
     SCOUT_MODEL=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh scout .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
     if [ $? -ne 0 ]; then echo "$SCOUT_MODEL" >&2; exit 1; fi
    SCOUT_MAX_TURNS=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "$RESEARCH_EFFORT")
    if [ $? -ne 0 ]; then echo "$SCOUT_MAX_TURNS" >&2; exit 1; fi
     ```
   - Display: `◆ Spawning Scout (${SCOUT_MODEL})...`
    - Before composing the Scout task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this specific task. The spawned prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>` when one or more installed skills apply, or `<skill_no_activation>` when none apply. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none apply — {reason}") so the user has visibility before the agent is spawned. Only include skills whose description matches the task at hand.
   - Also evaluate available MCP tools in your system context. If any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research topic (e.g., Apple Docs for Apple APIs, web search MCPs for multi-source queries), note them in the Scout's task context so it prioritizes those tools over generic WebSearch/WebFetch where applicable.
  - Spawn vbw-scout as subagent(s) via Task tool. **Set `subagent_type: "vbw:vbw-scout"` and `model: "${SCOUT_MODEL}"` in the Task tool invocation. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).**
```text
<skill_activation>
Call Skill('{relevant-skill-1}').
Call Skill('{relevant-skill-2}').
</skill_activation>

<task_context>
Research: {topic or sub-topic}.
Project context: {tech stack, constraints from PROJECT.md if relevant}.
Extended context from todo detail (include only if detail was loaded in Step 1): {detail.context}. Related files: {detail.files, comma-separated}.
</task_context>

<output_path>{resolved save path}</output_path>

<output_format>
Write your complete findings to the output_path file.
</output_format>
```
  When no installed skills apply, use this variant instead:
```text
<skill_no_activation>
Evaluated installed skills for this task. No installed skills apply. Reason: {brief task-specific reason}.
</skill_no_activation>

<task_context>
Research: {topic or sub-topic}.
...
</task_context>
```
    - If save path is unknown yet (user hasn't confirmed), omit `<output_path>` — Scout returns findings in response, and the orchestrator writes them after user confirms a path.
    - Parallel: up to 4 simultaneous Tasks, each with `subagent_type: "vbw:vbw-scout"`, same `model: "${SCOUT_MODEL}"` and the same maxTurns conditional (pass when non-empty, omit when empty).
4. **Synthesize:** Single: present directly. Parallel: merge, note contradictions, rank by confidence.
5. **Persist:** Ask "Save findings? (y/n)". If yes, determine save path:
   - **Phase-scoped** (an active VBW phase exists in `.vbw-planning/phases/`): default to `.vbw-planning/phases/{phase-dir}/RESEARCH.md` (existing behavior, unchanged).
   - **Standalone** (no active phase): create a standalone research session:
     ```bash
     RESEARCH_SLUG=$(printf '%s' "{topic}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 50)
     eval "$(bash "`!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/research-session-state.sh" start .vbw-planning "$RESEARCH_SLUG")"
     ```
     Use `$research_file` as the save path. After writing findings, mark complete:
     ```bash
     bash "`!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/research-session-state.sh" complete .vbw-planning "$research_id"
     ```
   If Scout already wrote the file (output_path was included in prompt), confirm it exists. If Scout returned findings in response (no output_path), write findings to the confirmed path.
```
➜ Next Up
  /vbw:vibe --plan {NN} -- Plan using research findings
  /vbw:vibe --discuss {NN} -- Discuss phase approach
  /vbw:debug "description mentioning {topic}" -- auto-discovers this research
  /vbw:fix "description mentioning {topic}" -- auto-discovers this research
```

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md: single-line box for findings, ✓ high / ○ medium / ⚠ low confidence, Next Up Block, no ANSI.
