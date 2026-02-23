---
name: vbw:help
category: supporting
disable-model-invocation: true
description: Display all available VBW commands with descriptions and usage examples.
argument-hint: [command-name]
allowed-tools: Read, Glob, Bash
---

# VBW Help $ARGUMENTS

## Context

Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]; then R="${CLAUDE_PLUGIN_ROOT}"; elif [ -d "${VBW_CACHE_ROOT}/local" ]; then R="${VBW_CACHE_ROOT}/local"; else V=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && R="${VBW_CACHE_ROOT}/${V}"; if [ -z "$R" ]; then L=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; rm -f "$LINK"; ln -s "$R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

## Behavior

### No args: Display all commands

Run the help output script and display the result exactly as-is (pre-formatted terminal output):

```
!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/help-output.sh"`
```

Display the output above verbatim. Do not reformat, summarize, or add commentary. The script dynamically reads all command files and generates grouped output.

### With arg: Display specific command details

Read ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/commands/{name}.md` (strip `vbw:` prefix if present). Display:
- **Name** and **description** from frontmatter
- **Category** from frontmatter
- **Usage:** `/vbw:{name} {argument-hint}`
- **Arguments:** list from argument-hint with brief explanation
- **Related:** suggest 1-2 related commands based on category

If command not found: "⚠ Unknown command: {name}. Run /vbw:help for all commands."
