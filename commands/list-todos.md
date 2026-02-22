---
name: vbw:list-todos
category: supporting
description: List pending todos from STATE.md and select one to act on.
argument-hint: [priority filter]
allowed-tools: Read, Edit, Bash, AskUserQuestion
---

# VBW List Todos $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]; then R="${CLAUDE_PLUGIN_ROOT}"; elif [ -d "${VBW_CACHE_ROOT}/local" ]; then R="${VBW_CACHE_ROOT}/local"; else V=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && R="${VBW_CACHE_ROOT}/${V}"; if [ -z "$R" ]; then L=$(ls -1d "${VBW_CACHE_ROOT}"/* 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; rm -f "$LINK"; ln -s "$R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."

## Steps

1. **Load todos:** Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/list-todos.sh {priority-filter}` (omit filter arg if none provided). Parse the JSON output.

2. **Handle status:**
   - `"error"`: STOP with the `message` value.
   - `"empty"`: Display the `display` value. Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh list-todos empty` and display. Exit.
   - `"no-match"`: Display the `display` value. Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh list-todos empty` and display. Exit.
   - `"ok"`: Continue to step 3.

3. **Display list:** Show the `display` value from the script output, followed by:
   ```text
   Reply with a number to select, or `q` to exit.
   ```

4. **Handle selection:** Wait for user to reply with a number. If invalid: "Invalid selection. Reply with a number (1-N) or `q` to exit."

5. **Show selected todo:** Display the full `text` from the matching `items` entry.

6. **Offer actions:** Use AskUserQuestion:
   - header: "Action"
   - question: "What would you like to do with this todo?"
   - options:
     - "/vbw:fix — Quick fix, one commit, no ceremony"
     - "/vbw:debug — Investigate with scientific method"
     - "/vbw:vibe — Full lifecycle (plan → execute → verify)"
     - "/vbw:research — Research only, no code changes"
     - "Remove — Delete from todo list"
     - "Back — Return to list"

7. **Execute action:** Use the `section` and `state_path` values from the script output for edit operations.
   - **/vbw:fix, /vbw:debug, /vbw:vibe, /vbw:research:** Remove the `line` value from the todo section in STATE.md. If no todos remain, replace with "None." Log to `## Recent Activity` with format `- {YYYY-MM-DD}: Picked up todo via /vbw:{command}: {text}`. Then display:
     ```text
     ✓ Todo picked up.

     ➜ Run: /vbw:{command} {todo text}
     ```
     Do NOT execute the command. STOP after displaying the suggested command.
   - **Remove:** Remove the `line` value from the todo section in STATE.md. If no todos remain, replace with "None." Log to `## Recent Activity` with format `- {YYYY-MM-DD}: Removed todo: {text}`. Confirm: "✓ Todo removed." Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh list-todos` and display.
   - **Back:** Return to step 3.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — ✓ success, ➜ Next Up, no ANSI.
