#!/usr/bin/env bash
# dev-test-env.sh — Create an isolated Claude test environment with local VBW
#
# Copies your current Claude config to /tmp (preserving auth, settings, hooks),
# then overwrites the VBW plugin in that copy with files from this repo.
# The resulting environment is fully isolated — your real config is untouched.
#
# Usage:
#   bash scripts/dev-test-env.sh [target-dir]
#
# Default target: /tmp/vbw-dev-config
#
# Then in a new window:
#   CLAUDE_CONFIG_DIR=/tmp/vbw-dev-config claude
#
# To refresh after making more local changes, just re-run this script.
# The target dir is always wiped and rebuilt from scratch.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET_CONFIG="${1:-/tmp/vbw-dev-config}"

# Plugin directories to sync from repo into the installed cache
PLUGIN_DIRS=(commands agents references scripts config)

echo "VBW local test environment"
echo "=========================="
echo "Source config : $SOURCE_CONFIG"
echo "Target config : $TARGET_CONFIG"
echo "Repo root     : $REPO_ROOT"
echo ""

# Validate source config exists
if [ ! -d "$SOURCE_CONFIG" ]; then
  echo "Error: Claude config dir not found: $SOURCE_CONFIG" >&2
  echo "Set CLAUDE_CONFIG_DIR if your config is in a non-default location." >&2
  exit 1
fi

# Find installed VBW version
VBW_CACHE=$(ls -1d "$SOURCE_CONFIG/plugins/cache/vbw-marketplace/vbw/"* 2>/dev/null \
  | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)

if [ -z "$VBW_CACHE" ]; then
  echo "Error: VBW not installed in $SOURCE_CONFIG/plugins/cache/vbw-marketplace/vbw/" >&2
  echo "Install VBW first, then re-run this script." >&2
  exit 1
fi

VBW_VERSION=$(basename "$VBW_CACHE")
echo "VBW version   : $VBW_VERSION"
echo ""

# Wipe and rebuild target
echo "Copying Claude config to $TARGET_CONFIG ..."
rm -rf "$TARGET_CONFIG"
cp -r "$SOURCE_CONFIG" "$TARGET_CONFIG"

# Overwrite VBW plugin dirs with local repo files
VBW_TARGET="$TARGET_CONFIG/plugins/cache/vbw-marketplace/vbw/$VBW_VERSION"

echo "Installing local VBW files into test config..."
for dir in "${PLUGIN_DIRS[@]}"; do
  if [ -d "$REPO_ROOT/$dir" ]; then
    cp -r "$REPO_ROOT/$dir/." "$VBW_TARGET/$dir/"
    echo "  ✓ $dir/"
  fi
done

echo ""
echo "Done. Test environment ready."
echo ""
echo "Open a new Claude window with:"
echo ""
echo "  CLAUDE_CONFIG_DIR=$TARGET_CONFIG claude"
echo ""
echo "To refresh after more local changes, re-run this script."
