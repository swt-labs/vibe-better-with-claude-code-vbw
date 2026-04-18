---
name: vbw:uninstall
category: advanced
disable-model-invocation: true
description: Cleanly remove all VBW traces from the system before plugin uninstall.
argument-hint:
allowed-tools: Read, Write, Edit, Bash, Glob, AskUserQuestion
---

# VBW Uninstall

## Context

Settings:
```
!`for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; [ -f "$_d/settings.json" ] && cat "$_d/settings.json" 2>/dev/null && break; done || echo "{}"`
```
Planning dir:
```text
!`ls -d .vbw-planning 2>/dev/null && echo "EXISTS" || echo "NONE"`
```
CLAUDE.md:
```text
!`ls CLAUDE.md 2>/dev/null && echo "EXISTS" || echo "NONE"`
```

## Steps

**Resolve config directory:** Try in order: env var `CLAUDE_CONFIG_DIR` (if set and directory exists), `~/.config/claude-code` (if exists), otherwise `~/.claude`. Store result as `CLAUDE_DIR`.

### Step 1: Confirm intent

Display Phase Banner "VBW Uninstall" explaining system-level config removal. Project files handled separately. Ask confirmation.

### Step 2: Clean statusLine

Read `CLAUDE_DIR/settings.json`. If statusLine contains `vbw-statusline`: remove entire statusLine key, display ✓. If not VBW's: "○ Statusline is not VBW's — skipped".

### Step 3: Clean Agent Teams env var

If `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` exists: ask user (it's a Claude Code feature other tools may use). Approved: remove (if env then empty, remove env key). Declined: "○ Agent Teams setting kept".

### Step 4: Project data

If `.vbw-planning/` exists: ask keep (recommended) or delete. Delete: `rm -rf .vbw-planning/`.

### Step 5: CLAUDE.md cleanup

If CLAUDE.md exists: ask keep or delete.

### Step 6: Summary

Display Phase Banner "VBW Cleanup Complete" with ✓/○ per step. Then:
```
➜ Final Step
  /plugin uninstall vbw@vbw-marketplace
  Then optionally: /plugin marketplace remove vbw-marketplace
```
**Do NOT run plugin uninstall yourself** — it would remove itself mid-execution.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — Phase Banner (double-line box), ✓ completed, ○ skipped, Next Up, no ANSI.
