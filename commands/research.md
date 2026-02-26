---
name: vbw:research
category: advanced
description: Run standalone research by spawning Scout agent(s) for web searches and documentation lookups.
argument-hint: <research-topic> [--parallel]
allowed-tools: Read, Write, Bash, Glob, Grep, WebFetch
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
  - Spawn vbw-scout as subagent(s) via Task tool. **Add `model: "${SCOUT_MODEL}"` and `maxTurns: ${SCOUT_MAX_TURNS}` parameters.**
```
Research: {topic or sub-topic}.
Project context: {tech stack, constraints from PROJECT.md if relevant}.
Return structured findings.
```
  - Parallel: up to 4 simultaneous Tasks, each with same `model: "${SCOUT_MODEL}"` and `maxTurns: ${SCOUT_MAX_TURNS}`.
4. **Synthesize:** Single: present directly. Parallel: merge, note contradictions, rank by confidence.
5. **Persist:** Ask "Save findings? (y/n)". If yes: write to .vbw-planning/phases/{phase-dir}/RESEARCH.md or .vbw-planning/RESEARCH.md.
```
➜ Next Up
  /vbw:vibe --plan {NN} -- Plan using research findings
  /vbw:vibe --discuss {NN} -- Discuss phase approach
```

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md: single-line box for findings, ✓ high / ○ medium / ⚠ low confidence, Next Up Block, no ANSI.
