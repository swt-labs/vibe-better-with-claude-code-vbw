#!/usr/bin/env bash
set -euo pipefail

# verify-askuserquestion-contract.sh — Contract checks for AskUserQuestion maxItems:4
#
# The Claude Code AskUserQuestion tool has a maxItems:4 constraint on its
# `options` array. Commands that need more than 4 choices must use a
# numbered-list-in-question-text workaround with explicit guard language.
#
# Checks:
# 1. No option lists with >4 items in AskUserQuestion context (pipe-delimited
#    or JSON array format)
# 2. Numbered-list AskUserQuestion workarounds include guard language

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMANDS_DIR="$ROOT/commands"

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

# Extract body after YAML frontmatter (everything after second ---)
extract_body() {
  local file="$1"
  awk '
    BEGIN { delim=0 }
    /^---$/ { delim++; next }
    delim >= 2 { print }
  ' "$file"
}

echo "=== AskUserQuestion maxItems Contract Verification ==="

# --------------------------------------------------------------------------
# Check 1: No pipe-delimited option lists exceeding 4 items
#
# Scans for lines matching: "something" | "something" | ... (quoted strings
# separated by pipes). If a single line has >4 pipe-separated quoted items,
# it violates the maxItems:4 constraint.
#
# Exclusions: fenced code blocks, markdown table rows (lines starting with |)
# --------------------------------------------------------------------------

echo ""
echo "--- Check 1: No >4 option lists ---"

for file in "$COMMANDS_DIR"/*.md; do
  [ -f "$file" ] || continue
  base="$(basename "$file" .md)"

  # Count lines with >4 options in either format (outside code fences):
  # - Pipe-delimited: "a" | "b" | "c" | "d" | "e"
  # - JSON array:     Options: ["a", "b", "c", "d", "e"]
  violations=$(extract_body "$file" | awk '
    /^```/ { in_fence = !in_fence; next }
    in_fence { next }
    /^\|/ { next }  # skip markdown table rows

    {
      # Check 1a: pipe-separated quoted segments: "..." | "..."
      n = split($0, parts, /\|/)
      quoted_count = 0
      for (i = 1; i <= n; i++) {
        if (parts[i] ~ /"[^"]*"/) {
          quoted_count++
        }
      }
      if (quoted_count > 4) {
        print NR ": " $0
        next
      }

      # Check 1b: JSON array options: Options: ["...", "...", ...]
      if ($0 ~ /Options:[[:space:]]*\[/) {
        # Extract content between [ and ]
        arr = $0
        sub(/.*Options:[[:space:]]*\[/, "", arr)
        sub(/\].*/, "", arr)
        # Count comma-separated quoted items
        m = split(arr, items, /,/)
        arr_count = 0
        for (j = 1; j <= m; j++) {
          if (items[j] ~ /"[^"]*"/) {
            arr_count++
          }
        }
        if (arr_count > 4) {
          print NR ": " $0
        }
      }
    }
  ')

  if [ -n "$violations" ]; then
    while IFS= read -r violation; do
      fail "$base: >4 options (line $violation)"
    done <<<"$violations"
  else
    pass "$base: no >4 option lists"
  fi
done

# --------------------------------------------------------------------------
# Check 2: Numbered-list AskUserQuestion workarounds include guard language
#
# When a command instructs the LLM to "present ... as a numbered list in the
# AskUserQuestion text", it should also include guard language like:
# "do NOT use `options` array" or "no `options` array"
#
# This prevents future editors from removing the guard while keeping the
# numbered-list pattern, which could lead to the LLM using an options array
# with >4 items.
# --------------------------------------------------------------------------

echo ""
echo "--- Check 2: Numbered-list workarounds include guard language ---"

for file in "$COMMANDS_DIR"/*.md; do
  [ -f "$file" ] || continue
  base="$(basename "$file" .md)"

  body=$(extract_body "$file")

  # Check if the command uses the numbered-list AskUserQuestion workaround pattern
  has_numbered_list_pattern=false
  if printf '%s\n' "$body" | grep -qi 'numbered list.*AskUserQuestion\|AskUserQuestion.*numbered list'; then
    # Only trigger on lines that say to present choices as a numbered list
    # in the AskUserQuestion text (the workaround pattern)
    if printf '%s\n' "$body" | grep -Eqi 'present.*(as a |as )numbered list.*(in|for).*AskUserQuestion|numbered list in the (AskUserQuestion|question) text'; then
      has_numbered_list_pattern=true
    fi
  fi

  if [ "$has_numbered_list_pattern" = true ]; then
    # Verify guard language exists somewhere in the body
    if printf '%s\n' "$body" | grep -qi 'do NOT use.*options.*array\|no.*options.*array'; then
      pass "$base: numbered-list workaround has guard language"
    else
      fail "$base: uses numbered-list AskUserQuestion workaround but missing guard language (e.g., 'do NOT use \`options\` array')"
    fi
  fi
done

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All AskUserQuestion contract checks passed."
exit 0
