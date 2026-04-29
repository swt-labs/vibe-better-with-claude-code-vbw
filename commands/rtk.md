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
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then R="${SESSION_LINK}"; fi; if [ -z "$R" ]; then ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "$link/scripts/hook-wrapper.sh" ]; then printf '%s\n' "$link"; break; fi; done || true); [ -n "$ANY_LINK" ] && R="$ANY_LINK"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -n "$R" ]; then REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$SESSION_LINK" "$REAL_R" >/dev/null 2>&1 || true; bash "$REAL_R/scripts/rtk-manager.sh" status --json 2>/dev/null && exit 0; fi; echo '{"status_unavailable":true,"summary":"RTK status unavailable","next_action":"install","compatibility":"unknown"}'`
```

AskUserQuestion reference: @${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

## Guard

- Store the Plugin root output above as `{plugin-root}`.
- Do not run RTK install, update, hook activation, or uninstall unless the user explicitly invoked the matching RTK subcommand or confirmed the no-args menu.
- `/vbw:rtk install` and no-args install/repair selections are explicit consent for complete setup: binary install, RTK config bootstrap, Claude Code hook activation, and hook verification/fallback.
- `/vbw:rtk init` is explicit consent for hook-only setup/repair for an RTK binary that is already on PATH.
- Keep separate confirmation for destructive or ambiguous manage flows such as update and uninstall.
- Default `status` is read-only and offline. Only `status --check-updates`, `install`, or `update` may query GitHub release metadata.
- Managed setup must not use `sudo`, edit shell profiles, or pipe downloaded scripts into `sh`.

## Behavior

### Step 1: Parse intent

Recognized subcommands: `status`, `install`, `init`, `verify`, `update`, `uninstall`.

If no subcommand is provided, use the RTK state JSON to present one bounded AskUserQuestion:

- header: `RTK setup`
- question: `What do you want to do?`
- options: choose 2–4 relevant visible options only:
  - `Install or repair RTK setup` first when `status_unavailable=true`
  - `Install RTK and enable Claude hook` first when `rtk_present=false`
  - `Verify RTK/VBW coexistence` second when `status_unavailable=true` or `rtk_present=false`
  - `Update RTK binary` when `update_available=true`
  - `Enable Claude Code hook` when `rtk_present=true` and `global_hook_present=false`
  - `Show PATH guidance` when `managed_by_vbw=true` and `binary_install_state="installed_not_on_path"`
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

Display `summary`, `rtk_version`, `latest_version` when present, `config_state`, `config_path`, `compatibility`, and `next_action`. Do not run `rtk gain` unless the user explicitly asks for stats/metrics.

### Step 3: Install setup or update binary

For `/vbw:rtk install` or a no-args install/repair selection, first run the dry-run setup preflight and show it verbatim:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" install --dry-run
```

The install preflight must show compact lines for `Method`, `Will run`, `Writes`, `Fallback`, `Restart`, `Risk`, and `Next step`. State once that the explicit subcommand or selected install/repair option is consent for binary install plus hook setup. Then run exactly one mutating helper command; do not ask a second install question:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" install --yes
```

If the helper reports the install directory is not on `PATH`, show the PATH line and do not offer hook activation until the user has made the binary visible.

For `/vbw:rtk update`, first run the dry-run preflight and show it verbatim:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" update --dry-run
```

Ask for one explicit update confirmation after the preflight. If confirmed, run:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" update --yes
```

### Step 4: Enable or repair hook

For `/vbw:rtk init`, run:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" init --dry-run
```

Show the `RTK hook preflight` verbatim. It must mention `rtk init -g --auto-patch`, possible RTK config and Claude Code user config writes, jq fallback patching, restart requirement, and the PreToolUse `updatedInput` risk from Claude Code issue #15897. State once that the explicit `init` subcommand is consent for hook setup/repair, then run:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" init --yes
```

Do not disable, reorder, or weaken VBW `bash-guard.sh`.

### Step 5: Verify

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" verify
```

Static verification may confirm binary, config state/path, settings hook, RTK docs/artifacts, and VBW hook presence. Runtime compatibility is PASS only when the helper reports `compatibility=verified` with a validated runtime smoke proof source. Otherwise report `hook_active_unverified` or `risk` and show the manual smoke steps.

### Step 6: Uninstall/manage

For `/vbw:rtk uninstall`, choose the helper path from RTK state:

- If `managed_by_vbw=true` and either `global_hook_present=true` or `settings_json_valid=false`, first run:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" uninstall --dry-run --deactivate-hook
```

Ask for one explicit confirmation that names both Claude Code hook deactivation/settings repair risk and VBW-managed binary removal. If confirmed, run:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" uninstall --yes --deactivate-hook
```

- If `managed_by_vbw=true` and `global_hook_present=false`, first run:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" uninstall --dry-run
```

Ask for confirmation. If confirmed, run:

```bash
bash "{plugin-root}/scripts/rtk-manager.sh" uninstall --yes
```

- For externally managed installs, do not delete the binary. Show package-manager/manual uninstall guidance from the helper output instead.

## Output

Keep output compact:

- current RTK state, including config state/path when present
- preflight details for mutating operations
- exact next action
- compatibility caveat when hook is active but unverified
