#!/usr/bin/env bash
# resolve-todo-item.sh — resolve a todo number to its item details
# Usage: bash resolve-todo-item.sh <N>
# Output: JSON object with status, num, text, ref, line, description fields
# Requires: jq, list-todos.sh in same scripts/ directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N="${1:-}"

if [ -z "$N" ]; then
  printf '{"status":"error","message":"Usage: resolve-todo-item.sh <N>"}\n'
  exit 1
fi

if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  jq -n --arg message "Not a number: $N" '{status: "error", message: $message}'
  exit 1
fi

N=$((10#$N))

# Run list-todos.sh to get current items
OUTPUT=$(bash "$SCRIPT_DIR/list-todos.sh" 2>/dev/null) || {
  printf '{"status":"error","message":"list-todos.sh failed"}\n'
  exit 1
}

STATUS=$(printf '%s' "$OUTPUT" | jq -r '.status // "error"')
if [ "$STATUS" != "ok" ]; then
  MSG=$(printf '%s' "$OUTPUT" | jq -r '.message // .display // "Unknown error"')
  jq -n --arg message "$MSG" '{status: "error", message: $message}'
  exit 1
fi

COUNT=$(printf '%s' "$OUTPUT" | jq '.items | length')
if [ "$N" -lt 1 ] || [ "$N" -gt "$COUNT" ]; then
  jq -n --arg message "Invalid selection — only items 1-${COUNT} exist." '{status: "error", message: $message}'
  exit 1
fi

# Extract the Nth item (0-indexed in jq)
IDX=$((N - 1))
printf '%s' "$OUTPUT" | jq -c --argjson num "$N" \
  '.items['"$IDX"'] | {status: "ok", num: $num, text: .text, ref: .ref, line: .line, description: (if .ref then (.text + " (ref:" + .ref + ")") else .text end)}'
