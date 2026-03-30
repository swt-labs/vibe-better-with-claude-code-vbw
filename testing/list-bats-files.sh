#!/usr/bin/env bash
set -euo pipefail

# list-bats-files.sh — Shared bats file discovery for CI/local parity.
#
# Usage:
#   bash testing/list-bats-files.sh --shardable
#   bash testing/list-bats-files.sh --serial

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-}"

case "$MODE" in
  --shardable|--serial) ;;
  *)
    echo "usage: list-bats-files.sh --shardable|--serial" >&2
    exit 1
    ;;
esac

serial_files=(
  "$ROOT/tests/statusline-cache-isolation.bats"
)

is_serial_file() {
  local candidate="$1" serial_file
  for serial_file in "${serial_files[@]}"; do
    [ "$candidate" = "$serial_file" ] && return 0
  done
  return 1
}

all_files=()
while IFS= read -r bats_file; do
  [ -n "$bats_file" ] || continue
  all_files+=("$bats_file")
done < <(find "$ROOT/tests" -maxdepth 1 -type f -name '*.bats' | LC_ALL=C sort)

case "$MODE" in
  --serial)
    for bats_file in "${all_files[@]}"; do
      if is_serial_file "$bats_file"; then
        printf '%s\n' "$bats_file"
      fi
    done
    ;;
  --shardable)
    for bats_file in "${all_files[@]}"; do
      if ! is_serial_file "$bats_file"; then
        printf '%s\n' "$bats_file"
      fi
    done
    ;;
esac