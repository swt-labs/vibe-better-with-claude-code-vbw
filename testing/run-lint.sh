#!/usr/bin/env bash
set -euo pipefail

# run-lint.sh — Shared shell lint entrypoint for local runs and CI.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

declare -a SHELLCHECK_PATHS=()
declare -a SYNTAX_PATHS=()

[ -d "$ROOT/scripts" ] && SHELLCHECK_PATHS+=("$ROOT/scripts")
[ -d "$ROOT/hooks" ] && SHELLCHECK_PATHS+=("$ROOT/hooks")

[ -d "$ROOT/scripts" ] && SYNTAX_PATHS+=("$ROOT/scripts")
[ -d "$ROOT/testing" ] && SYNTAX_PATHS+=("$ROOT/testing")

lint_error() {
  local message="$1"
  if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    echo "::error::$message"
  else
    echo "ERROR: $message"
  fi
}

syntax_error() {
  local file="$1"
  if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    echo "::error file=$file::Syntax error in $file"
  else
    echo "ERROR: Syntax error in $file"
  fi
}

shellcheck_failed=0
if command -v shellcheck >/dev/null 2>&1; then
  if [ "${#SHELLCHECK_PATHS[@]}" -gt 0 ]; then
    while IFS= read -r -d '' file; do
      if ! shellcheck -S warning "$file"; then
        shellcheck_failed=1
      fi
    done < <(find "${SHELLCHECK_PATHS[@]}" -type f -name '*.sh' -print0)
  fi
  if [ "$shellcheck_failed" -ne 0 ]; then
    lint_error "ShellCheck found issues in one or more files (see above)"
  fi
else
  lint_error "shellcheck is required for CI-parity local verification (install with: brew install shellcheck)"
  shellcheck_failed=1
fi

syntax_failed=0
if [ "${#SYNTAX_PATHS[@]}" -gt 0 ]; then
  while IFS= read -r -d '' file; do
    if ! bash -n "$file"; then
      syntax_error "$file"
      syntax_failed=1
    fi
  done < <(find "${SYNTAX_PATHS[@]}" -type f -name '*.sh' -print0)
fi

if [ "$shellcheck_failed" -ne 0 ] || [ "$syntax_failed" -ne 0 ]; then
  exit 1
fi
