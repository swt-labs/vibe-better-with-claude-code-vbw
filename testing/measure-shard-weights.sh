#!/usr/bin/env bash
set -euo pipefail

# measure-shard-weights.sh — Measure per-file bats execution times for shard balancing.
#
# Runs every bats file individually and writes testing/shard-weights.txt with
# actual execution times (seconds). Used by run-bats-shard.sh for greedy
# bin-packing shard assignment.
#
# Usage:
#   bash testing/measure-shard-weights.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEIGHTS_FILE="$ROOT/testing/shard-weights.txt"

if ! command -v bats &>/dev/null; then
  echo "ERROR: bats not found. Install bats-core first." >&2
  exit 1
fi

bats_files=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  bats_files+=("$f")
done < <(find "$ROOT/tests" -maxdepth 1 -type f -name '*.bats' | LC_ALL=C sort)

if [ "${#bats_files[@]}" -eq 0 ]; then
  echo "No .bats files found in tests/"
  exit 0
fi

echo "Measuring ${#bats_files[@]} bats files..."
results=""
for f in "${bats_files[@]}"; do
  name="$(basename "$f")"
  SECONDS=0
  bats "$f" >/dev/null 2>&1 || true
  t="$SECONDS"
  results+="$t"$'\t'"$name"$'\n'
  printf "  %3ds  %s\n" "$t" "$name"
done

{
  echo "# Measured execution times (seconds) per bats file."
  echo "# Used by run-bats-shard.sh for greedy bin-packing shard assignment."
  echo "# Regenerate with: bash testing/measure-shard-weights.sh"
  echo "#"
  echo "# Format: <seconds>\t<basename>"
  printf '%s' "$results" | sort -t$'\t' -k1,1rn -k2
} > "$WEIGHTS_FILE"

echo ""
echo "Wrote $WEIGHTS_FILE (${#bats_files[@]} files)"
