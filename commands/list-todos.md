---
name: vbw:list-todos
category: supporting
disable-model-invocation: true
description: List pending todos from STATE.md with action hints.
argument-hint: [priority filter]
allowed-tools: Read, Edit, Bash
---

# VBW List Todos $ARGUMENTS

## Context

- Working directory: current workspace root.
- Plugin cache root: `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"` (respects non-default `CLAUDE_CONFIG_DIR`; always quote — path may contain spaces).
- Session startup creates a symlink at `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}` pointing to the plugin root. The cache-based tiers are authoritative; symlinks are a fallback. See Step 1 for full resolution order.

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."
2. **Restricted mode:** If the current permission mode does not allow Bash execution, STOP: "`/vbw:list-todos` needs Bash access to run helper scripts. If you're in read-only or another restricted mode, switch to a write-enabled mode (for example bypass permissions) and rerun the command."

## Steps

1. **Resolve plugin root:** Determine the plugin root path. Always quote derived paths (they may contain spaces). Try in order:
   (a) The `local/` subdirectory under the plugin cache root (i.e. `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw/local/"`), if it exists and contains `scripts/hook-wrapper.sh`.
   (b) The numerically highest versioned directory under the plugin cache root — list subdirectories matching a dotted-version pattern (e.g. `1.30.0`), sort by each numeric component (major, minor, patch), pick the highest, and accept it only if it contains `scripts/hook-wrapper.sh`.
   (c) Any other (non-versioned) subdirectory under the plugin cache root — pick the newest by name, accept only if it contains `scripts/hook-wrapper.sh`. This covers non-standard cache layouts.
   (d) The session symlink `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`, or any existing `/tmp/.vbw-plugin-root-link-*` symlink whose target contains `scripts/hook-wrapper.sh`.
   (e) Extract `--plugin-dir <path>` from the process tree (`ps axww`) and use that path if it contains `scripts/hook-wrapper.sh`.
   If none resolves to a valid directory, STOP: "Plugin root not found. The session startup hook may not have run. Try restarting your Claude session." Store the resolved path as `PLUGIN_ROOT` for subsequent steps.

2. **Load todos through the snapshot helper:** Run:
   ```bash
   bash "${PLUGIN_ROOT}/scripts/todo-lifecycle.sh" list-with-snapshot {priority-filter}
   ```
   Omit the filter arg if none is provided. Parse the JSON output. This helper owns both the fresh `list-todos.sh` lookup and the exact last-view snapshot write. If snapshot persistence fails, it returns the helper error JSON instead of a partial success.

3. **Handle status:**
   - `"error"`: STOP with the `message` value.
   - `"empty"`: Display the `display` value. Run `bash "${PLUGIN_ROOT}/scripts/suggest-next.sh" list-todos empty` and display. Exit.
   - `"no-match"`: Display the `display` value. Run `bash "${PLUGIN_ROOT}/scripts/suggest-next.sh" list-todos empty` and display. Exit.
   - `"ok"`: Continue to step 4.

4. **Display list:** Show the `display` value from the script output exactly as returned (do not append any additional prompt text).

5. **Display action hints and STOP.** Do NOT prompt the user for input — display one of the following as plain text after the todo list, then STOP:

    - **Unfiltered view (`filter=null`):**
       ```text
       ➜ To act on a todo:
             /vbw:vibe N      — full lifecycle (plan → execute → verify)
             /vbw:fix N       — quick fix, one commit
             /vbw:debug N     — investigate with scientific method
             /vbw:research N  — research context with Scout
             remove N         — delete from todo list
       ```
    - **Filtered view (`filter` is non-null):**
       ```text
       ➜ Filtered view:
             remove N         — delete from this displayed list
             delete N         — same as remove N
          /vbw:list-todos  — rerun unfiltered /vbw:list-todos before using /vbw:vibe N, /vbw:fix N, /vbw:debug N, or /vbw:research N
       ```

    If the user says **`remove N`** or **`delete N`** as a follow-up message (not via a slash command):
    - Resolve `N` against the persisted session snapshot, not a fresh rerun:
       ```bash
       bash "${PLUGIN_ROOT}/scripts/resolve-todo-item.sh" <N> --session-snapshot
       ```
       If the resolver returns `status="error"`, STOP with its `message` value.
    - If the resolved item has a non-null `ref`, load detail status first:
       ```bash
       bash "${PLUGIN_ROOT}/scripts/todo-details.sh" get <ref>
       ```
       Record the result as `detail_status=ok|not_found|error`.
       If the item has no ref, use `detail_status=none`.
    - Pipe the selected item JSON from the resolver into the shared helper:
       ```bash
       bash "${PLUGIN_ROOT}/scripts/todo-lifecycle.sh" remove <detail_status> safe
       ```
       If the helper returns `status="error"`, STOP with its `message` value.
       If the helper returns `status="partial"`, display `✓ Todo removed.` and then display its `warning` value.
       If the helper returns `status="ok"`, display `✓ Todo removed.`
    - Run `bash "${PLUGIN_ROOT}/scripts/suggest-next.sh" list-todos` and display. STOP.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — ✓ success, ➜ Next Up, no ANSI.
