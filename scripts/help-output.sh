#!/usr/bin/env bash
# help-output.sh — Generate formatted help output from command frontmatter
# Zero tokens: runs as shell, output injected into help.md via bash substitution
# Compatible with bash 3.2+ (macOS default)
set -euo pipefail

# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh" 2>/dev/null || true

PLUGIN_ROOT="${1:-${CLAUDE_PLUGIN_ROOT:-}}"
if [ -z "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT=$(find "${CLAUDE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/plugins/cache/vbw-marketplace/vbw" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1 || true)
fi
if [ -z "$PLUGIN_ROOT" ] || [ ! -d "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

COMMANDS_DIR="$PLUGIN_ROOT/commands"

if [ ! -d "$COMMANDS_DIR" ]; then
  echo "⚠ Commands directory not found: $COMMANDS_DIR"
  exit 1
fi

# Temp files for category grouping (bash 3.2 compatible, no associative arrays)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

for cat in lifecycle monitoring supporting advanced other; do
  : > "$TMP_DIR/$cat"
done

for file in "$COMMANDS_DIR"/*.md; do
  [ -f "$file" ] || continue

  name=""
  description=""
  category=""
  hint=""
  in_frontmatter=0

  while IFS= read -r line; do
    if [ "$in_frontmatter" -eq 0 ] && [ "$line" = "---" ]; then
      in_frontmatter=1
      continue
    fi
    if [ "$in_frontmatter" -eq 1 ] && [ "$line" = "---" ]; then
      break
    fi
    if [ "$in_frontmatter" -eq 1 ]; then
      case "$line" in
        name:*) name="${line#name: }" ; name="${name#name:}" ; name="${name# }" ;;
        description:*) description="${line#description: }" ; description="${description#description:}" ; description="${description# }" ; description="${description#\"}" ; description="${description%\"}" ;;
        category:*) category="${line#category: }" ; category="${category#category:}" ; category="${category# }" ;;
        argument-hint:*) hint="${line#argument-hint: }" ; hint="${hint#argument-hint:}" ; hint="${hint# }" ; hint="${hint#\"}" ; hint="${hint%\"}" ;;
      esac
    fi
  done < "$file"

  [ -z "$name" ] && continue

  # Build display line: command padded to 42 chars + description
  if [ -n "$hint" ]; then
    entry="  /$name $hint"
  else
    entry="  /$name"
  fi
  padded=$(printf "%-42s" "$entry")
  display_line="$padded $description"

  # Append to category file (sorted later)
  case "$category" in
    lifecycle)   echo "$display_line" >> "$TMP_DIR/lifecycle" ;;
    monitoring)  echo "$display_line" >> "$TMP_DIR/monitoring" ;;
    supporting)  echo "$display_line" >> "$TMP_DIR/supporting" ;;
    advanced)    echo "$display_line" >> "$TMP_DIR/advanced" ;;
    *)           echo "$display_line" >> "$TMP_DIR/other" ;;
  esac
done

# Version
VERSION=""
if [ -f "$PLUGIN_ROOT/VERSION" ]; then
  VERSION=$(cat "$PLUGIN_ROOT/VERSION")
fi

# Header
echo "╔══════════════════════════════════════════════════════════════════════════╗"
if [ -n "$VERSION" ]; then
  header="VBW Help — v$VERSION"
else
  header="VBW Help"
fi
padding=$((72 - ${#header}))
printf "║ %s%${padding}s║\n" "$header" ""
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

print_section() {
  local title="$1"
  local subtitle="$2"
  local file="$3"

  [ -s "$file" ] || return 0

  echo "  $title — $subtitle"
  echo "  ──────────────────────────────────────────────────────────────────────"
  sort < "$file"
  echo ""
}

print_section "Lifecycle"  "The Main Loop"                  "$TMP_DIR/lifecycle"
print_section "Monitoring" "Trust But Verify"               "$TMP_DIR/monitoring"
print_section "Supporting" "The Safety Net"                  "$TMP_DIR/supporting"
print_section "Advanced"   "For When You're Feeling Ambitious" "$TMP_DIR/advanced"
print_section "Other"      "Uncategorized"                  "$TMP_DIR/other"

echo "  /vbw:help <command>                      Details on a specific command"
echo "  /vbw:config                              View and change settings"
echo ""
echo "  Getting Started: /vbw:init → /vbw:vibe → /vbw:vibe --archive"
