#!/usr/bin/env bash
# vbw-cache-key.sh — shared helpers for workspace-scoped /tmp cache paths.

vbw_hash_path() {
  local root="$1"
  if command -v md5sum &>/dev/null; then
    printf '%s' "$root" | md5sum | cut -c1-8
  elif command -v md5 &>/dev/null; then
    printf '%s' "$root" | md5 -q | cut -c1-8
  else
    printf '%s' "$root" | cksum | cut -d' ' -f1
  fi
}

vbw_cache_prefix() {
  local version="$1" uid="$2" root="$3"
  local hash
  hash=$(vbw_hash_path "$root")
  printf '/tmp/vbw-%s-%s-%s' "${version:-0}" "$uid" "$hash"
}
