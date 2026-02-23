---
name: vbw:update
category: advanced
disable-model-invocation: true
description: Update VBW to the latest version with automatic cache refresh.
argument-hint: "[--check]"
allowed-tools: Read, Bash, Glob
---

# VBW Update $ARGUMENTS

## Context

Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | sed -n 's/.*--plugin-dir  *\([^ ]*\).*/\1/p' | head -1); [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; rm -f "$LINK"; ln -s "$R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

**Resolve config directory:** `CLAUDE_DIR` = env var `CLAUDE_CONFIG_DIR` if set, otherwise `~/.claude`. Use for all config paths below.

## Steps

### Step 1: Read current INSTALLED version

Read the **cached** version (what user actually has installed):
```bash
cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/*/VERSION 2>/dev/null | sort -V | tail -1
```
Store as `old_version`. If empty, fall back to ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/VERSION`.

**CRITICAL:** Do NOT read ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/VERSION` as primary — in dev sessions it resolves to source repo (may be ahead), causing false "already up to date."

### Step 2: Handle --check

If `--check`: display version banner with installed version and STOP.

### Step 3: Check for update

```bash
curl -sf --max-time 5 "https://raw.githubusercontent.com/yidakee/vibe-better-with-claude-code-vbw/main/VERSION"
```
Store as `remote_version`. Curl fails → STOP: "⚠ Could not reach GitHub to check for updates."
If remote == old: display "✓ Already at latest (v{old_version}). Refreshing cache..." Continue to Step 4 for clean cache refresh.

### Step 4: Nuclear cache wipe

```bash
bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/cache-nuke.sh
```
Removes CLAUDE_DIR/plugins/cache/vbw-marketplace/vbw/, CLAUDE_DIR/commands/vbw/, /tmp/vbw-* for pristine update.

### Step 5: Perform update

Same version: "Refreshing VBW v{old_version} cache..." Different: "Updating VBW v{old_version}..."

**CRITICAL: All `claude plugin` commands MUST be prefixed with `unset CLAUDECODE &&`** — without this, Claude Code detects the parent session's env var and blocks with "cannot be launched inside another Claude Code session."

**Refresh marketplace FIRST** (stale checkout → plugin update re-caches old code):
```bash
unset CLAUDECODE && claude plugin marketplace update vbw-marketplace 2>&1
```
If fails: "⚠ Marketplace refresh failed — trying update anyway..."

Try in order (stop at first success):
- **A) Platform update:** `unset CLAUDECODE && claude plugin update vbw@vbw-marketplace 2>&1`
- **B) Reinstall:** `unset CLAUDECODE && claude plugin uninstall vbw@vbw-marketplace 2>&1 && unset CLAUDECODE && claude plugin install vbw@vbw-marketplace 2>&1`
- **C) Manual fallback:** display commands for user to run manually, STOP.

**Clean stale global commands** (after A or B succeeds):
```bash
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
rm -rf "$CLAUDE_DIR/commands/vbw" 2>/dev/null
```
This removes stale copies that break ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`` resolution. Commands load from the plugin cache where ``!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`` is guaranteed.

### Step 5.5: Ensure VBW statusline

Read `CLAUDE_DIR/settings.json`, check `statusLine` (string or object .command). If contains `vbw-statusline`: skip. Otherwise update to:
```json
{"type": "command", "command": "bash -c 'f=$(ls -1 \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/vbw-marketplace/vbw/*/scripts/vbw-statusline.sh 2>/dev/null | sort -V | tail -1) && [ -f \"$f\" ] && exec bash \"$f\"'"}
```
Use jq to write (backup, update, restore on failure). Display `✓ Statusline restored (restart to activate)` if changed.

### Step 6: Verify update

```bash
NEW_CACHED=$(cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/*/VERSION 2>/dev/null | sort -V | tail -1)
```
Use NEW_CACHED as authoritative version. If empty or equals old_version when it shouldn't: "⚠ Update may not have applied. Try /vbw:update again after restart."

### Step 7: Display result

Use NEW_CACHED for all display. Same version = "VBW Cache Refreshed" banner + "Changes active immediately". Different = "VBW Updated" banner with old→new + "Changes active immediately" + "/vbw:whats-new" suggestion.

**Edge case:** If Step 6 verification failed (NEW_CACHED empty/unchanged when upgrade expected): keep restart suggestion as diagnostic fallback.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — double-line box, ✓ success, ⚠ fallback warning, Next Up, no ANSI.
