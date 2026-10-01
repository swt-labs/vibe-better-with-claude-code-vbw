#!/usr/bin/env bash
# SessionStart: in a VBW project (the session's project directory holds
# .vbw/record.json, as for the guard), tell the model where the project stands
# and what comes next, in one line. Started in a subdirectory of a VBW project:
# say that the guards are off. Never a resume directive (ledger D289).
#
# Also, in every session: remove VBW 1's command copies (build plan K15).

root=${CLAUDE_PROJECT_DIR:-$PWD}
vbw="${0%/*}/../bin/vbw"

# VBW 1 copied its commands to <claude-dir>/commands/vbw/. User commands take
# precedence over plugin skills, so those copies would run VBW 1 instead of
# /vbw:init, /vbw:vibe and the rest (ledger D290). Only the config directory
# this session uses can shadow its commands, so only that one is cleaned
# ($CLAUDE_CONFIG_DIR, else ~/.config/claude-code if present, else ~/.claude).
# Remove only VBW's own copies (frontmatter "name: vbw:..."), and the directory
# once empty.
removed=0
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  claude_dir=$CLAUDE_CONFIG_DIR
elif [ -d "$HOME/.config/claude-code" ]; then
  claude_dir="$HOME/.config/claude-code"
else
  claude_dir="$HOME/.claude"
fi
if [ -d "$claude_dir/commands/vbw" ]; then
  for f in "$claude_dir/commands/vbw"/*.md; do
    [ -f "$f" ] || continue
    if awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && /^---$/ { exit 1 } /^name: vbw:/ { found = 1; exit } END { exit !found }' "$f"; then
      rm -f "$f" && removed=$((removed + 1))
    fi
  done
  rmdir "$claude_dir/commands/vbw" 2> /dev/null || true
fi

context=""
[ "$removed" -eq 0 ] || context="VBW removed $removed outdated VBW 1 command copies that would have run instead of the VBW 2 commands. Tell the user once: run /reload-skills now (or restart Claude Code) before using any /vbw: command, because this session loaded the old copies. "

if [ -f "$root/.vbw/record.json" ]; then
  state=$(cd "$root" && "$vbw" status 2>&1 < /dev/null | head -n 1)
  next=$(cd "$root" && "$vbw" next 2>&1 < /dev/null | head -n 1)
  context="${context}VBW project ($state). Next: $next. Continue with /vbw:vibe. The vbw command is on PATH (vbw help)."
elif [ -d "$root/.vbw-planning" ]; then
  context="${context}This project has a VBW 1 plan (.vbw-planning/). Tell the user once: VBW 2 leaves it untouched, and /vbw:vibe or /vbw:convert brings it into VBW 2 through a few questions."
else
  top=$(git -C "$root" rev-parse --show-toplevel 2> /dev/null || true)
  if [ -n "$top" ] && [ -f "$top/.vbw/record.json" ]; then
    context="${context}This session started inside the VBW project at $top, not at its root, so the VBW guards are off. Tell the user to start Claude Code at $top."
  fi
fi

# The copies were loaded before this hook ran, so this session still has them:
# the user must reload before typing a /vbw: command. A systemMessage reaches
# the user at once; the context alone would wait for their first prompt.
notice=""
[ "$removed" -eq 0 ] || notice="VBW 2 removed the old VBW 1 commands. Type /reload-skills (or restart Claude Code) before using any /vbw: command."

[ -z "$context" ] || jq -n --arg c "$context" --arg n "$notice" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}} + (if $n == "" then {} else {systemMessage: $n} end)'
