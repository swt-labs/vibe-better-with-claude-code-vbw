---
name: vbw:research
category: advanced
disable-model-invocation: true
description: Run standalone research by spawning Scout agent(s) for web searches and documentation lookups.
argument-hint: <research-topic> [--parallel]
allowed-tools: Read, Write, Bash, Glob, Grep, WebFetch, LSP
---

# VBW Research: $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break; done; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; rm -f "$LINK"; ln -s "$REAL_R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

Current project:
```
!`cat .vbw-planning/PROJECT.md 2>/dev/null || echo "No project found"`
```

## Guard

- No $ARGUMENTS: STOP "Usage: /vbw:research <topic> [--parallel]"

## Steps

1. **Parse:** Topic (required). --parallel: spawn multiple Scouts on sub-topics.
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
   - Before composing the Scout task description, evaluate installed skills visible in your system context — read each skill's description and determine if it is relevant to this specific task. If any skills are relevant, the Scout prompt MUST start with a `<skill_activation>` block. Only include skills whose description matches the task at hand. If no skills are relevant, omit the skill_activation block entirely.
  - Spawn vbw-scout as subagent(s) via Task tool. **Set `subagent_type: "vbw:vbw-scout"` and `model: "${SCOUT_MODEL}"` in the Task tool invocation. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).**
```
<skill_activation>
Call Skill('{relevant-skill-1}').
Call Skill('{relevant-skill-2}').
</skill_activation>

<task_context>
Research: {topic or sub-topic}.
Project context: {tech stack, constraints from PROJECT.md if relevant}.
</task_context>

<output_path>{resolved save path}</output_path>

<output_format>
Write your complete findings to the output_path file.
</output_format>
```
  - If save path is unknown yet (user hasn't confirmed), omit `<output_path>` — Scout returns findings in response, and the orchestrator writes them after user confirms a path.
  - Parallel: up to 4 simultaneous Tasks, each with `subagent_type: "vbw:vbw-scout"`, same `model: "${SCOUT_MODEL}"` and the same maxTurns conditional (pass when non-empty, omit when empty).
4. **Synthesize:** Single: present directly. Parallel: merge, note contradictions, rank by confidence.
5. **Persist:** Ask "Save findings? (y/n)". If yes, ask for save path (default: `.vbw-planning/phases/{phase-dir}/RESEARCH.md` or `.vbw-planning/RESEARCH.md`). If Scout already wrote the file (output_path was included in prompt), confirm it exists. If Scout returned findings in response (no output_path), write findings to the confirmed path.
```
➜ Next Up
  /vbw:vibe --plan {NN} -- Plan using research findings
  /vbw:vibe --discuss {NN} -- Discuss phase approach
```

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md: single-line box for findings, ✓ high / ○ medium / ⚠ low confidence, Next Up Block, no ANSI.
