#!/usr/bin/env bash
set -euo pipefail

# ensure-plugin-root-link.sh — Idempotently create/update a per-session plugin root symlink.
#
# Problem: command template !` blocks may resolve the plugin root in parallel. A simple
# `rm -f "$LINK"; ln -s "$REAL_R" "$LINK"` sequence is race-prone: one block can create
# the symlink between another block's rm and ln, causing ln to fail with EEXIST. Older or
# corrupted sessions may also leave a directory at the link path, which rm -f will not
# remove. This helper restores the invariant that the session link exists and points at the
# canonical plugin root regardless of those stale/racy states.

link_path="${1:-}"
target_dir="${2:-}"

if [ -z "$link_path" ] || [ -z "$target_dir" ]; then
  echo "Usage: ensure-plugin-root-link.sh <link-path> <target-dir>" >&2
  exit 1
fi

case "$(basename "$link_path")" in
  .vbw-plugin-root-link-*) ;;
  *)
    echo "Error: unexpected link path basename: $link_path" >&2
    exit 1
    ;;
esac

if [ ! -d "$target_dir" ]; then
  echo "Error: target directory does not exist: $target_dir" >&2
  exit 1
fi

cleanup_existing() {
  if [ -L "$link_path" ] || [ -f "$link_path" ]; then
    rm -f "$link_path"
  elif [ -d "$link_path" ] || [ -e "$link_path" ]; then
    rm -rf "$link_path"
  fi
}

current_target="$(readlink "$link_path" 2>/dev/null || true)"
if [ -L "$link_path" ] && [ "$current_target" = "$target_dir" ]; then
  exit 0
fi

cleanup_existing

if ln -s "$target_dir" "$link_path" 2>/dev/null; then
  exit 0
fi

# Another concurrent resolver may have won the race. Accept that outcome if it points to the
# same canonical target.
current_target="$(readlink "$link_path" 2>/dev/null || true)"
if [ -L "$link_path" ] && [ "$current_target" = "$target_dir" ]; then
  exit 0
fi

# One final cleanup+retry covers stale directories or wrong-target leftovers that appeared
# between cleanup and creation.
cleanup_existing
ln -s "$target_dir" "$link_path"
