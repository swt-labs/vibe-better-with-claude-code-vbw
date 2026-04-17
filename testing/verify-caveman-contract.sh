#!/usr/bin/env bash
# Contract test: verify caveman integration structural invariants
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

fail() {
  echo "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

# --- references/caveman-language.md ---
LANG_FILE="$REPO_ROOT/references/caveman-language.md"
[ -f "$LANG_FILE" ] || fail "references/caveman-language.md missing"
if [ -f "$LANG_FILE" ]; then
  grep -q "## Lite" "$LANG_FILE" || fail "caveman-language.md missing Lite section"
  grep -q "## Full" "$LANG_FILE" || fail "caveman-language.md missing Full section"
  grep -q "## Ultra" "$LANG_FILE" || fail "caveman-language.md missing Ultra section"
  grep -q "Auto-Clarity" "$LANG_FILE" || fail "caveman-language.md missing Auto-Clarity section"
  grep -q "MIT" "$LANG_FILE" || fail "caveman-language.md missing MIT attribution"
fi

# --- references/caveman-commit.md ---
COMMIT_FILE="$REPO_ROOT/references/caveman-commit.md"
[ -f "$COMMIT_FILE" ] || fail "references/caveman-commit.md missing"
if [ -f "$COMMIT_FILE" ]; then
  grep -q "Conventional Commits" "$COMMIT_FILE" || fail "caveman-commit.md missing Conventional Commits reference"
  grep -q "MIT" "$COMMIT_FILE" || fail "caveman-commit.md missing MIT attribution"
fi

# --- references/caveman-review.md ---
REVIEW_FILE="$REPO_ROOT/references/caveman-review.md"
[ -f "$REVIEW_FILE" ] || fail "references/caveman-review.md missing"
if [ -f "$REVIEW_FILE" ]; then
  grep -q "L<line>" "$REVIEW_FILE" || grep -q 'L[0-9]' "$REVIEW_FILE" || fail "caveman-review.md missing L<line> format"
  grep -q "MIT" "$REVIEW_FILE" || fail "caveman-review.md missing MIT attribution"
fi

# --- commands/compress.md ---
COMPRESS_FILE="$REPO_ROOT/commands/compress.md"
[ -f "$COMPRESS_FILE" ] || fail "commands/compress.md missing"
if [ -f "$COMPRESS_FILE" ]; then
  head -5 "$COMPRESS_FILE" | grep -q "name: vbw:compress" || fail "compress.md missing name: vbw:compress frontmatter"
  head -10 "$COMPRESS_FILE" | grep -q "description:" || fail "compress.md missing description frontmatter"
fi

# --- scripts/lib/resolve-caveman-level.sh ---
RESOLVE_FILE="$REPO_ROOT/scripts/lib/resolve-caveman-level.sh"
[ -f "$RESOLVE_FILE" ] || fail "scripts/lib/resolve-caveman-level.sh missing"
if [ -f "$RESOLVE_FILE" ]; then
  grep -q "resolve_caveman_level" "$RESOLVE_FILE" || fail "resolve-caveman-level.sh missing resolve_caveman_level function"
  grep -q "RESOLVED_CAVEMAN_LEVEL" "$RESOLVE_FILE" || fail "resolve-caveman-level.sh missing RESOLVED_CAVEMAN_LEVEL variable"
fi

# --- config/defaults.json has caveman flags ---
DEFAULTS="$REPO_ROOT/config/defaults.json"
if [ -f "$DEFAULTS" ]; then
  jq -e '.caveman_style' "$DEFAULTS" >/dev/null 2>&1 || fail "defaults.json missing caveman_style"
  jq -e 'has("caveman_commit")' "$DEFAULTS" >/dev/null 2>&1 || fail "defaults.json missing caveman_commit"
  jq -e 'has("caveman_review")' "$DEFAULTS" >/dev/null 2>&1 || fail "defaults.json missing caveman_review"
fi

# --- Summary ---
if [ "$FAILURES" -gt 0 ]; then
  echo ""
  echo "Caveman contract: $FAILURES failure(s)"
  exit 1
else
  echo "Caveman contract: all checks passed"
  exit 0
fi
