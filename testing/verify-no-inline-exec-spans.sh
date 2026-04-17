#!/usr/bin/env bash
set -euo pipefail

# verify-no-inline-exec-spans.sh — Contract test for issue #157
#
# CC template processor executes standalone one-line `!` directives and
# fenced `!` blocks, but it does NOT execute `!` spans when they are
# embedded inside prose, paths, assignments, or larger strings. This test
# ensures no command or reference file contains embedded inline `!` spans
# outside fenced code blocks.
#
# What's allowed:
#   - Fenced blocks: ```\n!`command`\n``` (these execute via CC template processor)
#   - Literal paths: /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/...
#
# What's NOT allowed:
#   - Embedded inline spans: `!`echo /tmp/...` in body text or path construction
#   - Prose/path patterns like ``bash `!`echo /tmp/...`` that rely on embedded `!`

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

tracked_markdown_files() {
  local rel
  git -C "$ROOT" ls-files -- 'commands/*.md' 'references/*.md' 'internal/*.md' | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s\n' "$ROOT/$rel"
  done
}

tracked_command_markdown_files() {
  local rel
  git -C "$ROOT" ls-files -- 'commands/*.md' | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s\n' "$ROOT/$rel"
  done
}

TRACKED_MARKDOWN_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  TRACKED_MARKDOWN_FILES+=("$file")
done < <(tracked_markdown_files)

TRACKED_COMMAND_MARKDOWN_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  TRACKED_COMMAND_MARKDOWN_FILES+=("$file")
done < <(tracked_command_markdown_files)

PASS=0
FAIL=0
WARN=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

warn() {
  echo "WARN  $1"
  WARN=$((WARN + 1))
}

# Files not yet fixed for #157. These produce WARN (not FAIL) to avoid
# blocking CI. Remove entries as files are fixed. When this list is empty,
# issue #157 is fully resolved.
KNOWN_UNFIXED=""

is_known_unfixed() {
  local name="$1"
  for k in $KNOWN_UNFIXED; do
    [ "$k" = "$name" ] && return 0
  done
  return 1
}

echo "=== Inline Execution Span Verification (Issue #157) ==="

# Scan all tracked command, reference, and internal files
for file in "${TRACKED_MARKDOWN_FILES[@]}"; do
  rel_file="${file#$ROOT/}"
  dir_label="${rel_file%%/*}"
  base="$(basename "$file" .md)"

  # Use awk to find `!`<command> execution spans NOT inside fenced code blocks.
  # Pattern: backtick-bang-backtick immediately followed by a command (echo, cat, ls, etc.)
  # Excludes documentation mentions like "fenced `!` blocks" (no command follows).
  # Fenced blocks start/end with ``` at line start.
  inline_hits=$(awk '
    BEGIN { in_fence = 0 }
    /^```/ {
      in_fence = !in_fence
      next
    }
    !in_fence && /`!`[a-zA-Z$]/ {
      print NR": "$0
    }
  ' "$file")

  if [ -n "$inline_hits" ]; then
    hit_count=$(printf '%s\n' "$inline_hits" | wc -l | tr -d ' ')
    if is_known_unfixed "$base"; then
      warn "$dir_label/$base: $hit_count embedded \`!\` span(s) — known unfixed (#157)"
    else
      fail "$dir_label/$base: $hit_count embedded \`!\` span(s) found (unsupported inline/path/prose syntax in Claude Code)"
      printf '%s\n' "$inline_hits" | head -5 | sed 's/^/     /'
      if [ "$hit_count" -gt 5 ]; then
        echo "     ... and $((hit_count - 5)) more"
      fi
    fi
  else
    pass "$dir_label/$base: no inline \`!\` spans"
  fi
done

echo ""
echo "=== Fenced Precompute Block Integrity ==="

# Verify that tracked command files with fenced !` blocks have them intact.
# These are the blocks that CC template processor actually executes.
for file in "${TRACKED_COMMAND_MARKDOWN_FILES[@]}"; do
  base="$(basename "$file" .md)"

  fenced_exec_count=$(awk '
    BEGIN { in_fence = 0; count = 0 }
    /^```/ {
      in_fence = !in_fence
      next
    }
    in_fence && /^!`/ { count++ }
    END { print count }
  ' "$file")

  if [ "$fenced_exec_count" -gt 0 ]; then
    pass "$base: $fenced_exec_count fenced \`!\` block(s) intact"
  fi
done

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL, $WARN WARN (known unfixed)"
echo "==============================="

[ "$FAIL" -eq 0 ] || exit 1
