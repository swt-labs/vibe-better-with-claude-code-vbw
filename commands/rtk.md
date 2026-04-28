---
name: vbw:rtk
category: supporting
disable-model-invocation: true
description: Install, update, verify, and manage optional RTK tool-output compression.
argument-hint: [status|install|init|verify|update|uninstall]
allowed-tools: Read, Bash, AskUserQuestion
---

# VBW RTK $ARGUMENTS

## Context

Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then R="${SESSION_LINK}"; fi; if [ -z "$R" ]; then ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "$link/scripts/hook-wrapper.sh" ]; then printf '%s\n' "$link"; break; fi; done || true); [ -n "$ANY_LINK" ] && R="$ANY_LINK"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; LINK="${SESSION_LINK}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

RTK state:
```json
!`PLUGIN_ROOT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; bash "$PLUGIN_ROOT/scripts/rtk-manager.sh" status --json 2>/dev/null || echo '{"summary":"RTK status unavailable","next_action":"status","compatibility":"unknown"}'`
```

AskUserQuestion reference: @${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

## Guard

- Store the Plugin root output above as `{plugin-root}`.
- Do not run RTK install, update, hook activation, or uninstall unless the user explicitly invoked the matching RTK subcommand or confirmed the no-args menu.
- Binary install/update and Claude Code hook activation are separate operations. Never combine them into one confirmation.
- Default `status` is read-only and offline. Only `status --check-updates`, `install`, or `update` may query GitHub release metadata.

## Behavior

### Step 1: Parse intent

Recognized subcommands: `status`, `install`, `init`, `verify`, `update`, `uninstall`.

If no subcommand is provided, use the RTK state JSON to present one bounded AskUserQuestion:

- header: `RTK setup`
- question: `What do you want to do?`
- options: choose 2–4 relevant visible options only:
  - `Install RTK binary` when `rtk_present=false`
  - `Update RTK binary` when `update_available=true`
  - `Enable Claude Code hook` when `rtk_present=true` and `global_hook_present=false`
  - `Verify RTK/VBW coexistence` when `global_hook_present=true` and `compatibility` is not `verified`
  - `Uninstall/manage RTK` when `managed_by_vbw=true` or `global_hook_present=true`
  - `Exit` when no action is wanted

For bounded AskUserQuestion replies:
- accept direct option intent that clearly matches a visible choice
- accept unambiguous visible option-number replies such as `#1`, `option 2`, or `2`
- accept hybrid replies anchored to a visible option number such as `#2 please`
- re-ask only when the reply is ambiguous or invalid for the same question
- do NOT add an extra visible `Other` option

### Step 2: Status

For `/vbw:rtk status`:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" status --json
```

For `/vbw:rtk status --check-updates`:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" status --json --check-updates
```

Display `summary`, `rtk_version`, `latest_version` when present, `compatibility`, and `next_action`. Do not run `rtk gain` unless the user explicitly asks for stats/metrics.

### Step 3: Install or update binary

For install/update, first run the dry-run preflight and show it verbatim:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" install --dry-run
```

or:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" update --dry-run
```

The preflight must show `Installed`, `Latest`, `Method`, `Will run`, `Writes`, `Does not do`, `Next step`, and `Risk`. It must state that VBW-managed code does not use `sudo`, does not edit shell profiles, does not edit Claude settings, does not run `rtk init -g`, and does not pipe downloaded shell scripts into sh.

Ask for one explicit confirmation after the preflight. If confirmed, run exactly one mutating helper command:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" install --yes
```

or:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" update --yes
```

If the helper reports the install directory is not on `PATH`, show the PATH line and do not offer hook activation until the user has made the binary visible.

### Step 4: Enable hook

Before hook activation, run:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" init --dry-run
```

Show the `RTK hook preflight` verbatim. It must mention `rtk init -g`, possible writes to Claude Code user config, restart requirement, and the PreToolUse `updatedInput` risk from Claude Code issue #15897.

Ask for a separate explicit confirmation. If confirmed, run:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" init --yes
```

Do not disable, reorder, or weaken VBW `bash-guard.sh`.

### Step 5: Verify

For `/vbw:rtk verify`:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" verify
```

Static verification may confirm binary, settings hook, RTK docs/artifacts, and VBW hook presence. Runtime compatibility is PASS only when the helper reports `compatibility=verified` with a validated runtime smoke proof source. Otherwise report `hook_active_unverified` or `risk` and show the manual smoke steps.

### Step 6: Uninstall/manage

For `/vbw:rtk uninstall`, first run:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" uninstall --dry-run
```

Ask for confirmation. If confirmed, run:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" uninstall --yes
```

For externally managed installs, do not delete the binary. Show package-manager/manual uninstall guidance from the helper output instead.

## Output

Keep output compact:

- current RTK state
- preflight details for mutating operations
- exact next action
- compatibility caveat when hook is active but unverified
