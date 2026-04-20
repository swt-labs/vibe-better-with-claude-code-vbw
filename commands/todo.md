---
name: vbw:todo
category: supporting
disable-model-invocation: true
description: Add an item to the persistent backlog in STATE.md.
argument-hint: <todo-description> [--priority=high|normal|low]
allowed-tools: Read, Edit, Bash
---

# VBW Todo: $ARGUMENTS

## Context

- Working directory: current workspace root.
- Plugin cache root: `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"` (respects non-default `CLAUDE_CONFIG_DIR`; always quote — path may contain spaces).

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."
2. **Missing description:** STOP: `Usage: /vbw:todo <description> [--priority=high|normal|low]`
3. **Restricted mode:** If the current permission mode does not allow edits, STOP: "`/vbw:todo` needs write access to update `.vbw-planning/STATE.md`. If you're in read-only or another restricted mode, switch to a write-enabled mode (for example bypass permissions) and rerun the command."

## Steps

1. **Resolve context:** Always use `.vbw-planning/STATE.md` for todos — project-level data lives at the root, not in milestone subdirectories. If `.vbw-planning/STATE.md` does not exist, STOP: "STATE.md not found. Session startup normally recovers archived state automatically — try restarting your Claude session, or run /vbw:init to set up your project."
2. **Parse args:** Description (non-flag text), --priority (default: normal). Format: high=`[HIGH]`, normal=plain, low=`[low]`. Append `(added {YYYY-MM-DD})`.
3. **Add plain todo to STATE.md:** Find `## Todos` section. Replace "None." / placeholder or append after last item.
4. **Capture extended detail (conditional).** Check whether the description from step 2 contains any of these: file paths, reproduction steps, stack traces, code references, error messages, or multi-sentence design rationale. Only evaluate the current `$ARGUMENTS` text — do not scan prior conversation history.
   - **If triggered:** The todo has rich context worth preserving for later execution.
     1. **Resolve plugin root.** Determine the plugin root path. Always quote derived paths (they may contain spaces). Try in order:
        (a) The `local/` subdirectory under the plugin cache root (i.e. `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw/local/"`), if it exists and contains `scripts/hook-wrapper.sh`.
        (b) The numerically highest versioned directory under the plugin cache root — list subdirectories matching a dotted-version pattern (e.g. `1.30.0`), sort by each numeric component (major, minor, patch), pick the highest, and accept it only if it contains `scripts/hook-wrapper.sh`.
        (c) Any other (non-versioned) subdirectory under the plugin cache root — pick the newest by name, accept only if it contains `scripts/hook-wrapper.sh`. This covers non-standard cache layouts.
        (d) The session symlink `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`, or any existing `/tmp/.vbw-plugin-root-link-*` symlink whose target contains `scripts/hook-wrapper.sh`.
        (e) Extract `--plugin-dir <path>` from the process tree (`ps axww`) and use that path if it contains `scripts/hook-wrapper.sh`.
        Store the resolved path as `PLUGIN_ROOT` for subsequent helper calls.
     2. If plugin root cannot be resolved, leave the plain todo line from step 3 unchanged, do not append a ref tag, do not write `.vbw-planning/todo-details/HASH.json` yourself, and continue to step 5 with a warning that extended detail was not saved.
     3. Extract a brief one-line summary (first sentence or the user's explicit title) — this is already the `STATE.md` bullet text from step 3.
     4. Compute a hash: `printf '%s' "<summary text>" | shasum | cut -c1-8`
     5. Build a JSON detail object: `{"summary": "<brief summary>", "context": "<full description, max 2000 chars>", "files": ["<any file paths mentioned>"], "added": "<YYYY-MM-DD>", "source": "user"}`
     6. Store it through the canonical helper — pipe JSON via heredoc to avoid shell-quoting issues with apostrophes or special characters in user text:
        ```bash
        bash "${PLUGIN_ROOT}/scripts/todo-details.sh" add HASH - <<'DETAIL_JSON'
        <json>
        DETAIL_JSON
        ```
     7. Parse the helper's stdout JSON. Only when the parsed stdout is valid JSON with `status="ok"` may you:
        - edit the exact todo line you just added in `STATE.md` to append `(ref:HASH)` after the `(added YYYY-MM-DD)` tag
        - later report `Extended detail saved (ref:HASH).`
     8. If the helper's stdout is not valid JSON or the parsed `status` is anything other than `ok`, leave the plain todo line from step 3 unchanged, do not append a ref tag, and do not write `.vbw-planning/todo-details/HASH.json` yourself.
   - **If not triggered** (simple one-liner with no structural context): skip — no ref tag, no detail storage. Brief bullets keep STATE.md scannable and token-efficient for context compilation. The detail file preserves context that would otherwise be lost when the todo is executed in a later session.
5. **Confirm:** Display ✓ + formatted item + Next Up (/vbw:status). If detail was captured successfully after step 4.7, also display: `Extended detail saved (ref:HASH).` If step 4 triggered but helper-backed storage did not succeed, warn that the plain todo was added but extended detail was not saved.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — ✓ success, Next Up, no ANSI.
