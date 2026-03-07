#!/usr/bin/env bash
set -euo pipefail

# Launch Claude Code with the local VBW plugin.
# Resolves the absolute path to the repo automatically,
# regardless of the current working directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

exec claude --plugin-dir "$REPO_DIR" "$@"
