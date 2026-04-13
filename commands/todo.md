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

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."
2. **Missing description:** STOP: `Usage: /vbw:todo <description> [--priority=high|normal|low]`
3. **Restricted mode:** If the current permission mode does not allow edits, STOP: "`/vbw:todo` needs write access to update `.vbw-planning/STATE.md`. If you're in read-only or another restricted mode, switch to a write-enabled mode (for example bypass permissions) and rerun the command."

## Steps

1. **Resolve context:** Always use `.vbw-planning/STATE.md` for todos — project-level data lives at the root, not in milestone subdirectories. If `.vbw-planning/STATE.md` does not exist, STOP: "STATE.md not found. Session startup normally recovers archived state automatically — try restarting your Claude session, or run /vbw:init to set up your project."
2. **Parse args:** Description (non-flag text), --priority (default: normal). Format: high=`[HIGH]`, normal=plain, low=`[low]`. Append `(added {YYYY-MM-DD})`.
3. **Add to STATE.md:** Find `## Todos` section. Replace "None." / placeholder or append after last item.
4. **Capture extended detail (conditional).** Check whether the description from step 2 contains any of these: file paths, reproduction steps, stack traces, code references, error messages, or multi-sentence design rationale. Only evaluate the current `$ARGUMENTS` text — do not scan prior conversation history.
   - **If triggered:** The todo has rich context worth preserving for later execution.
     1. Extract a brief one-line summary (first sentence or the user's explicit title) — this is already the `STATE.md` bullet text from step 3.
     2. Compute a hash: `echo "<summary text>" | shasum | cut -c1-8`
     3. Build a JSON detail object: `{"summary": "<brief summary>", "context": "<full description, max 2000 chars>", "files": ["<any file paths mentioned>"], "added": "<YYYY-MM-DD>", "source": "user"}`
     4. Store it — pipe JSON via heredoc to avoid shell-quoting issues with apostrophes or special characters in user text:
        ```bash
        bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-details.sh add <hash> - <<'DETAIL_JSON'
        <json>
        DETAIL_JSON
        ```
     5. Append `(ref:<hash>)` to the todo line in `STATE.md` (after the `(added ...)` date tag).
   - **If not triggered** (simple one-liner with no structural context): skip — no ref tag, no detail storage. Brief bullets keep STATE.md scannable and token-efficient for context compilation. The detail file preserves context that would otherwise be lost when the todo is executed in a later session.
5. **Confirm:** Display ✓ + formatted item + Next Up (/vbw:status). If detail was captured, also display: "📎 Extended detail saved (ref:HASH)."

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — ✓ success, Next Up, no ANSI.
