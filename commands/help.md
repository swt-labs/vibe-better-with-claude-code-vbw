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

Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``

## Behavior

### No args: Display all commands

Run the help output script and display the result exactly as-is (pre-formatted terminal output):

```
!`bash ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}/scripts/help-output.sh`
```

Display the output above verbatim. Do not reformat, summarize, or add commentary. The script dynamically reads all command files and generates grouped output.

### With arg: Display specific command details

Read `${CLAUDE_PLUGIN_ROOT}/commands/{name}.md` (strip `vbw:` prefix if present). Display:
- **Name** and **description** from frontmatter
- **Category** from frontmatter
- **Usage:** `/vbw:{name} {argument-hint}`
- **Arguments:** list from argument-hint with brief explanation
- **Related:** suggest 1-2 related commands based on category

If command not found: "⚠ Unknown command: {name}. Run /vbw:help for all commands."
