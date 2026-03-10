---
name: vbw:list-todos
category: supporting
disable-model-invocation: true
description: List pending todos from STATE.md and select one to act on.
argument-hint: [priority filter]
allowed-tools: Read, Edit, Bash, AskUserQuestion
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

2. **Load todos:** Run `bash "${PLUGIN_ROOT}/scripts/list-todos.sh" {priority-filter}` (omit filter arg if none provided). Parse the JSON output.

3. **Handle status:**
   - `"error"`: STOP with the `message` value.
   - `"empty"`: Display the `display` value. Run `bash "${PLUGIN_ROOT}/scripts/suggest-next.sh" list-todos empty` and display. Exit.
   - `"no-match"`: Display the `display` value. Run `bash "${PLUGIN_ROOT}/scripts/suggest-next.sh" list-todos empty` and display. Exit.
   - `"ok"`: Continue to step 4.

4. **Display list:** Show the `display` value from the script output, followed by:
   ```text
   Reply with a number to select, or `q` to exit.
   ```

5. **Handle selection:** Wait for user to reply with a number. If invalid: "Invalid selection. Reply with a number (1-N) or `q` to exit."

6. **Show selected todo:** Display the full `text` from the matching `items` entry.

7. **Offer actions:** Use AskUserQuestion:
   - header: "Action"
   - question: "What would you like to do with this todo?"
   - options:
     - "/vbw:fix — Quick fix, one commit, no ceremony"
     - "/vbw:debug — Investigate with scientific method"
     - "/vbw:vibe — Full lifecycle (plan → execute → verify)"
     - "/vbw:research — Research only, no code changes"
     - "Remove — Delete from todo list"
     - "Back — Return to list"

8. **Execute action:** Use the `section` and `state_path` values from the script output for edit operations.
   - **/vbw:fix, /vbw:debug, /vbw:vibe, /vbw:research:** Remove the `line` value from the todo section in STATE.md. If no todos remain, replace with "None." Log to `## Recent Activity` with format `- {YYYY-MM-DD}: Picked up todo via /vbw:{command}: {text}`. Then display:
     ```text
     ✓ Todo picked up.

     ➜ Run: /vbw:{command} {todo text}
     ```
     Do NOT execute the command. STOP after displaying the suggested command.
   - **Remove:** Remove the `line` value from the todo section in STATE.md. If no todos remain, replace with "None." Log to `## Recent Activity` with format `- {YYYY-MM-DD}: Removed todo: {text}`. Confirm: "✓ Todo removed." Run `bash "${PLUGIN_ROOT}/scripts/suggest-next.sh" list-todos` and display.
   - **Back:** Return to step 4.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — ✓ success, ➜ Next Up, no ANSI.
