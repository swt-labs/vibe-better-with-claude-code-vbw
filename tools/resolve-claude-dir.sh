#!/usr/bin/env bash
# resolve-claude-dir.sh — Canonical CLAUDE_DIR resolution
#
# Source this file from other scripts:
#   . "$(dirname "$0")/resolve-claude-dir.sh"
#
# After sourcing, CLAUDE_DIR is set to the user's Claude config directory.
# Resolution order:
#   1. CLAUDE_CONFIG_DIR env var (if set, even if directory does not yet exist)
#   2. $HOME/.config/claude-code (new default on many systems, existence-checked)
#   3. $HOME/.claude (legacy default)
#
# This is the single source of truth for config directory resolution.
# New scripts MUST source this file instead of inlining the fallback pattern.

if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  export CLAUDE_DIR="${CLAUDE_CONFIG_DIR}"
elif [ -d "$HOME/.config/claude-code" ]; then
  export CLAUDE_DIR="$HOME/.config/claude-code"
else
  export CLAUDE_DIR="$HOME/.claude"
fi
