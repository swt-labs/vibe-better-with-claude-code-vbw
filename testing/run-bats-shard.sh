#!/usr/bin/env bash
set -euo pipefail

# run-bats-shard.sh — Shared BATS shard selector/runner for CI and local parity.
#
# Usage:
#   bash testing/run-bats-shard.sh <shard> <total-shards> [--print-files] <files...>
#
# With --print-files, prints the selected files (one per line) and exits 0.
# Without it, runs bats on the selected files and exits with the bats status.

SHARD="${1:-}"
TOTAL_SHARDS="${2:-}"
PRINT_FILES=false

usage() {
  echo "usage: run-bats-shard.sh <shard> <total-shards> [--print-files] <files...>" >&2
  exit 1
}

[ -n "$SHARD" ] || usage
[ -n "$TOTAL_SHARDS" ] || usage
shift 2

if [ "${1:-}" = "--print-files" ]; then
  PRINT_FILES=true
  shift
fi

case "$SHARD" in
  ''|*[!0-9]*) usage ;;
esac
case "$TOTAL_SHARDS" in
  ''|*[!0-9]*) usage ;;
esac

if [ "$TOTAL_SHARDS" -le 0 ]; then
  usage
fi
if [ "$SHARD" -ge "$TOTAL_SHARDS" ]; then
  usage
fi

files=("$@")

if [ "${#files[@]}" -eq 0 ]; then
  if [ "$PRINT_FILES" = true ]; then
    exit 0
  fi
  echo "Shard $SHARD: no bats files provided, skipping"
  exit 0
fi

shard_files=()
for i in "${!files[@]}"; do
  if [ $((i % TOTAL_SHARDS)) -eq "$SHARD" ]; then
    shard_files+=("${files[$i]}")
  fi
done

if [ "$PRINT_FILES" = true ]; then
  if [ "${#shard_files[@]}" -gt 0 ]; then
    printf '%s\n' "${shard_files[@]}"
  fi
  exit 0
fi

echo "Shard $SHARD: running ${#shard_files[@]} of ${#files[@]} bats files"
if [ "${#shard_files[@]}" -eq 0 ]; then
  echo "Shard $SHARD: no bats files assigned, skipping"
  exit 0
fi

bats "${shard_files[@]}"