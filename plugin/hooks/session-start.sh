#!/usr/bin/env bash
# SessionStart: in a VBW project (the session's project directory holds
# .vbw/record.json, as for the guard), tell the model where the project stands
# and what comes next, in one line, and export this session's id for
# autonomous runs (vbw auto). Started in a subdirectory of a VBW project: say
# that the guards are off. Elsewhere: nothing. Never a resume directive
# (ledger D289); the only write is to Claude Code's own session env file.

input=$(cat)
root=${CLAUDE_PROJECT_DIR:-$PWD}
vbw="${0%/*}/../bin/vbw"

if [ ! -f "$root/.vbw/record.json" ]; then
  top=$(git -C "$root" rev-parse --show-toplevel 2> /dev/null) || exit 0
  [ -f "$top/.vbw/record.json" ] || exit 0
  jq -n --arg top "$top" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext:
    "This session started inside the VBW project at \($top), not at its root, so the VBW guards are off. Tell the user to start Claude Code at \($top)."}}'
  exit 0
fi

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2> /dev/null)
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [[ "$session" =~ ^[A-Za-z0-9_-]+$ ]]; then
  printf 'export VBW_SESSION_ID=%s\n' "$session" >> "$CLAUDE_ENV_FILE"
fi

state=$(cd "$root" && "$vbw" status 2>&1 < /dev/null | head -n 1)
next=$(cd "$root" && "$vbw" next 2>&1 < /dev/null | head -n 1)
jq -n --arg c "VBW project ($state). Next: $next. Continue with /vbw:vibe. The vbw command is on PATH (vbw help)." \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
