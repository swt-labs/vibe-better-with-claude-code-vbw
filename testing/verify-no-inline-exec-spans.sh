#!/usr/bin/env bash
set -euo pipefail

# verify-no-inline-exec-spans.sh — Contract test for issue #157
#
# CC template processor executes fenced `!` blocks but NOT inline `!`cmd`
# spans. Inline spans are dead syntax — the model simulates them rather
# than executing them. This test ensures no command or reference file
# contains inline `!` spans outside fenced code blocks.
#
# What's allowed:
#   - Fenced blocks: ```\n!`command`\n``` (these execute via CC template processor)
#   - Literal paths: /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/...
#
# What's NOT allowed:
#   - Inline spans: `!`echo /tmp/...` in body text (dead syntax, never executes)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
KNOWN_UNFIXED="config debug discuss doctor fix help init list-todos map qa release research resume status teach todo uninstall update verify whats-new"

is_known_unfixed() {
  local name="$1"
  for k in $KNOWN_UNFIXED; do
    [ "$k" = "$name" ] && return 0
  done
  return 1
}

echo "=== Inline Execution Span Verification (Issue #157) ==="

# Scan all command, reference, and internal files
for dir in "$ROOT/commands" "$ROOT/references" "$ROOT/internal"; do
  [ -d "$dir" ] || continue
  dir_label="$(basename "$dir")"

  for file in "$dir"/*.md; do
    [ -f "$file" ] || continue
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
        warn "$dir_label/$base: $hit_count inline \`!\` span(s) — known unfixed (#157)"
      else
        fail "$dir_label/$base: $hit_count inline \`!\` span(s) found (dead syntax — CC does not execute inline spans)"
        printf '%s\n' "$inline_hits" | head -5 | sed 's/^/     /'
        if [ "$hit_count" -gt 5 ]; then
          echo "     ... and $((hit_count - 5)) more"
        fi
      fi
    else
      pass "$dir_label/$base: no inline \`!\` spans"
    fi
  done
done

echo ""
echo "=== Fenced Precompute Block Integrity ==="

# Verify that command files with fenced !` blocks have them intact.
# These are the blocks that CC template processor actually executes.
for file in "$ROOT/commands"/*.md; do
  [ -f "$file" ] || continue
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
