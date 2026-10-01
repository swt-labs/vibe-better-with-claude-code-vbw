#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_URL="https://raw.githubusercontent.com/swt-labs/vibe-better-with-claude-code-vbw/main/VERSION"

FILES=(
  "$ROOT/VERSION"
  "$ROOT/plugin/VERSION"
  "$ROOT/plugin/.claude-plugin/plugin.json"
  "$ROOT/.claude-plugin/marketplace.json"
  "$ROOT/marketplace.json"
)

# --verify: check all 5 version files are in sync without bumping
if [[ "${1:-}" == "--verify" ]]; then
  V_FILE=$(tr -d '[:space:]' < "$ROOT/VERSION")
  V_PLUGIN_FILE=$(tr -d "[:space:]" < "$ROOT/plugin/VERSION")
  V_PLUGIN=$(jq -r '.version' "$ROOT/plugin/.claude-plugin/plugin.json")
  V_MKT_PLUGIN=$(jq -r '.plugins[0].version' "$ROOT/.claude-plugin/marketplace.json")
  V_MKT_ROOT=$(jq -r '.plugins[0].version' "$ROOT/marketplace.json")

  echo "Version sync check:"
  echo "  VERSION                         $V_FILE"
  echo "  plugin/VERSION                  $V_PLUGIN_FILE"
  echo "  plugin/.claude-plugin/plugin.json $V_PLUGIN"
  echo "  .claude-plugin/marketplace.json $V_MKT_PLUGIN"
  echo "  marketplace.json                $V_MKT_ROOT"

  # intentional: detect if ANY file differs from VERSION
  # shellcheck disable=SC2055
  if [[ "$V_FILE" != "$V_PLUGIN_FILE" || "$V_FILE" != "$V_PLUGIN" || "$V_FILE" != "$V_MKT_PLUGIN" || "$V_FILE" != "$V_MKT_ROOT" ]]; then
    echo ""
    echo "MISMATCH DETECTED — the following files differ:" >&2
    [[ "$V_FILE" != "$V_PLUGIN_FILE" ]] && echo "  plugin/VERSION ($V_PLUGIN_FILE != $V_FILE)" >&2
    [[ "$V_FILE" != "$V_PLUGIN" ]]     && echo "  plugin/.claude-plugin/plugin.json ($V_PLUGIN != $V_FILE)" >&2
    [[ "$V_FILE" != "$V_MKT_PLUGIN" ]] && echo "  .claude-plugin/marketplace.json ($V_MKT_PLUGIN != $V_FILE)" >&2
    [[ "$V_FILE" != "$V_MKT_ROOT" ]]   && echo "  marketplace.json ($V_MKT_ROOT != $V_FILE)" >&2
    exit 1
  fi

  echo ""
  echo "All 5 version files are in sync ($V_FILE)."
  exit 0
fi

LOCAL=$(tr -d '[:space:]' < "$ROOT/VERSION")

# --offline: skip remote fetch entirely (useful in CI or air-gapped environments)
if [[ "${1:-}" == "--offline" || "${1:-}" == "--set" ]]; then
  REMOTE="$LOCAL"
  echo "Offline mode: skipping GitHub fetch."
else
  # Fetch the authoritative version from GitHub (graceful fallback on failure)
  REMOTE=$(curl -sf --max-time 5 "$REPO_URL" 2>/dev/null | tr -d '[:space:]' || true)
  if [[ -z "$REMOTE" ]]; then
    echo "Warning: Could not fetch version from GitHub. Using local VERSION as baseline." >&2
    REMOTE="$LOCAL"
  fi
fi

# Use whichever is higher as the base (protects against local being behind)
BASE="$REMOTE"
if [[ "$(printf '%s\n%s' "$LOCAL" "$REMOTE" | sort -V | tail -1)" == "$LOCAL" ]]; then
  BASE="$LOCAL"
fi

# Auto-increment patch version
MAJOR="${BASE%%.*}"
REST="${BASE#*.}"
MINOR="${REST%%.*}"
PATCH="${REST#*.}"
NEW="${MAJOR}.${MINOR}.$((PATCH + 1))"
# --set X.Y.Z: an explicit version (a major or minor release).
if [[ "${1:-}" == "--set" ]]; then
  [[ "${2:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: bump-version.sh --set X.Y.Z" >&2; exit 2; }
  NEW="$2"
fi

echo "GitHub version:  $REMOTE"
echo "Local version:   $LOCAL"
echo "Bumping to:      $NEW"
echo ""

# Update all files — bail on first failure
printf '%s\n' "$NEW" > "$ROOT/VERSION"
printf '%s\n' "$NEW" > "$ROOT/plugin/VERSION"

jq --arg v "$NEW" '.version = $v' "$ROOT/plugin/.claude-plugin/plugin.json" > "$ROOT/.claude-plugin/plugin.json.tmp" \
  && mv "$ROOT/.claude-plugin/plugin.json.tmp" "$ROOT/plugin/.claude-plugin/plugin.json"

jq --arg v "$NEW" '.plugins[0].version = $v' "$ROOT/.claude-plugin/marketplace.json" > "$ROOT/.claude-plugin/marketplace.json.tmp" \
  && mv "$ROOT/.claude-plugin/marketplace.json.tmp" "$ROOT/.claude-plugin/marketplace.json"

jq --arg v "$NEW" '.plugins[0].version = $v' "$ROOT/marketplace.json" > "$ROOT/marketplace.json.tmp" \
  && mv "$ROOT/marketplace.json.tmp" "$ROOT/marketplace.json"

echo "Updated 5 files:"
for f in "${FILES[@]}"; do
  echo "  ${f#$ROOT/}"
done
echo ""
echo "Version is now $NEW"
