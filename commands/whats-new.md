---
name: vbw:whats-new
category: advanced
disable-model-invocation: true
description: View changelog and recent updates since your installed version.
argument-hint: "[version]"
allowed-tools: Read, Glob
---

# VBW What's New $ARGUMENTS

## Context

Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]; then R="${CLAUDE_PLUGIN_ROOT}"; elif [ -d "${VBW_CACHE_ROOT}/local" ]; then R="${VBW_CACHE_ROOT}/local"; else V=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && R="${VBW_CACHE_ROOT}/${V}"; if [ -z "$R" ]; then L=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; rm -f "$LINK"; ln -s "$R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

## Guard

1. **Missing changelog:** ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/CHANGELOG.md` missing → STOP: "No CHANGELOG.md found."

## Steps

1. Read ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/VERSION` for current_version.
2. Read ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/CHANGELOG.md`, split by `## [` headings.
   - With version arg: show entries newer than that version.
   - No args: show current version's entry.
3. Display Phase Banner "VBW Changelog" with version context, entries, Next Up (/vbw:help). No entries: "✓ No changelog entry found for v{version}."

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — double-line box, ✓ up-to-date, Next Up, no ANSI.
