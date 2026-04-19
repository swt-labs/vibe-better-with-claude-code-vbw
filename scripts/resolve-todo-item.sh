#!/usr/bin/env bash
# resolve-todo-item.sh — resolve a todo number to its text and ref
# Usage: bash resolve-todo-item.sh <N>
# Output: JSON object with status, text, ref, line fields
# Requires: jq, list-todos.sh in same scripts/ directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N="${1:-}"

if [ -z "$N" ]; then
  printf '{"status":"error","message":"Usage: resolve-todo-item.sh <N>"}\n'
  exit 1
fi

if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  printf '{"status":"error","message":"Not a number: %s"}\n' "$N"
  exit 1
fi

# Run list-todos.sh to get current items
OUTPUT=$(bash "$SCRIPT_DIR/list-todos.sh" 2>/dev/null) || {
  printf '{"status":"error","message":"list-todos.sh failed"}\n'
  exit 1
}

STATUS=$(printf '%s' "$OUTPUT" | jq -r '.status // "error"')
if [ "$STATUS" != "ok" ]; then
  MSG=$(printf '%s' "$OUTPUT" | jq -r '.message // "Unknown error"')
  printf '{"status":"error","message":"%s"}\n' "$MSG"
  exit 1
fi

COUNT=$(printf '%s' "$OUTPUT" | jq '.items | length')
if [ "$N" -lt 1 ] || [ "$N" -gt "$COUNT" ]; then
  printf '{"status":"error","message":"Invalid selection — only items 1-%d exist."}\n' "$COUNT"
  exit 1
fi

# Extract the Nth item (0-indexed in jq)
IDX=$((N - 1))
ITEM=$(printf '%s' "$OUTPUT" | jq -c ".items[$IDX]")
TEXT=$(printf '%s' "$ITEM" | jq -r '.text')
REF=$(printf '%s' "$ITEM" | jq -r '.ref // empty')
LINE=$(printf '%s' "$ITEM" | jq -r '.line')

# Build output — include ref suffix if present
if [ -n "$REF" ]; then
  DESC="${TEXT} (ref:${REF})"
else
  DESC="$TEXT"
fi

printf '{"status":"ok","num":%d,"text":"%s","ref":"%s","line":"%s","description":"%s"}\n' \
  "$N" \
  "$(printf '%s' "$TEXT" | sed 's/"/\\"/g')" \
  "$REF" \
  "$(printf '%s' "$LINE" | sed 's/"/\\"/g')" \
  "$(printf '%s' "$DESC" | sed 's/"/\\"/g')"
