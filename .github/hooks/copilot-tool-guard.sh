#!/usr/bin/env bash

set -euo pipefail

INPUT=$(cat)

json_compact() {
  jq -c "$@"
}

event_name=$(printf '%s' "$INPUT" | jq -r '.hookEventName // empty')

emit_start_context() {
  json_compact -n \
    --arg event "$1" \
    --arg context "Local Copilot execution policy: avoid shell heredocs for GitHub issue/PR/comment bodies. Use gh CLI with --body-file or structured --input instead. Do not run python/python3 in shell for discovery or one-off scripting; use the Pylance RunCodeSnippet tool instead. If a shell approach is blocked, switch to the safer tool path silently instead of narrating terminal-wrapper failures." \
    '{
      hookSpecificOutput: {
        hookEventName: $event,
        additionalContext: $context
      }
    }'
}

if [ "$event_name" = "SessionStart" ] || [ "$event_name" = "SubagentStart" ]; then
  emit_start_context "$event_name"
  exit 0
fi

tool_name=$(printf '%s' "$INPUT" | jq -r '.tool_name // .toolName // empty')
tool_name_lc=$(printf '%s' "$tool_name" | tr '[:upper:]' '[:lower:]')

case "$tool_name_lc" in
  bash|execute|shell|terminal|run_in_terminal|runinterminal)
    ;;
  *)
    exit 0
    ;;
esac

command_text=$(printf '%s' "$INPUT" | jq -r '
  .tool_input.command?
  // (try (.toolArgs | fromjson | .command) catch empty)
  // empty
')

[ -n "$command_text" ] || exit 0

# Strip quoted strings so patterns inside string arguments don't false-positive.
# e.g. echo "requires python3 installed" or echo "use <<EOF for heredocs"
command_unquoted=$(printf '%s' "$command_text" | sed "s/\"[^\"]*\"//g; s/'[^']*'//g")

matches_heredoc=0
matches_python=0

# Strip here-strings (<<<) before heredoc check — they're valid bash, not heredocs
command_no_herestring=$(printf '%s' "$command_unquoted" | sed 's/<<<//g')

if printf '%s\n' "$command_no_herestring" | grep -Eq '(<<-?[[:space:]]*[A-Za-z_][A-Za-z0-9_]*|<<-?[[:space:]]*$)'; then
  matches_heredoc=1
fi

if printf '%s\n' "$command_unquoted" | grep -Eq '(^|[;&|()[:space:]])([^[:space:];|()]+/)?python3?([[:space:]]|$)'; then
  matches_python=1
fi

# Allowlist: specific Python scripts that are part of the agent toolchain
PYTHON_ALLOWLIST=(
  '.github/scripts/wait-github.py'
)
if [ "$matches_python" -eq 1 ]; then
  for allowed in "${PYTHON_ALLOWLIST[@]}"; do
    if printf '%s\n' "$command_text" | grep -qF "$allowed"; then
      matches_python=0
      break
    fi
  done
fi

[ "$matches_heredoc" -eq 1 ] || [ "$matches_python" -eq 1 ] || exit 0

reason_parts=()
context_parts=()

if [ "$matches_heredoc" -eq 1 ]; then
  reason_parts+=("Shell heredocs are blocked for local Copilot execution")
  context_parts+=("For GitHub issue/PR/comment content, write the body to a file and use gh with --body-file, or send structured JSON via gh api --input -")
fi

if [ "$matches_python" -eq 1 ]; then
  reason_parts+=("Python execution via bash is blocked for local Copilot execution")
  context_parts+=("Use the Pylance RunCodeSnippet tool for Python-based discovery, file search helpers, and one-off scripts")
fi

reason=$(IFS='; '; printf '%s' "${reason_parts[*]}")
context=$(IFS=' '; printf '%s' "${context_parts[*]}")

json_compact -n \
  --arg reason "$reason" \
  --arg context "$context" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason,
      additionalContext: $context
    },
    systemMessage: $reason
  }'
