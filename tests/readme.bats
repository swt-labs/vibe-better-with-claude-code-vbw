#!/usr/bin/env bats
# README.md consistency (R20): commands, install steps, images, sections.
# Image files may be missing (D20): they are reported, never failed.
# Badges are the one remote image kind: shields.io and contrib.rocks only.

load helper

README="$REPO_ROOT/README.md"

@test "every /vbw: command in README.md has a skill" {
  names="$(grep -o '/vbw:[a-z][a-z-]*' "$README" | sort -u | sed 's|/vbw:||')"
  [ -n "$names" ]
  for n in $names; do
    [ -f "$PLUGIN_ROOT/skills/$n/SKILL.md" ] || { echo "no skill for /vbw:$n"; return 1; }
  done
}

@test "install steps name the marketplace source and plugin from the manifests" {
  mkt="$(jq -r '.name' "$REPO_ROOT/.claude-plugin/marketplace.json")"
  src="$(jq -r '.plugins[0].source' "$REPO_ROOT/.claude-plugin/marketplace.json")"
  plug="$(jq -r '.name' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  [ "$(jq -r '.plugins[0].name' "$REPO_ROOT/.claude-plugin/marketplace.json")" = "$plug" ]
  [ -d "$REPO_ROOT/$src/.claude-plugin" ]
  grep -qE '^/plugin install '"$plug@$mkt"'$' "$README"
  grep -qE '^/plugin marketplace add [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' "$README"
}

@test "image references point under assets/ or are badges; presence is reported" {
  refs="$(grep -oE '!\[[^]]*\]\([^)]+\)|<img[^>]*src="[^"]+"' "$README" \
    | sed -E 's/.*\(([^)]+)\)$/\1/; s/.*src="([^"]+)"/\1/' || true)"
  for r in $refs; do
    case "$r" in
      assets/*) ;;
      https://img.shields.io/*|https://contrib.rocks/*) continue ;;
      *) echo "image outside assets/: $r"; return 1 ;;
    esac
    if [ -f "$REPO_ROOT/$r" ]; then echo "present: $r"; else echo "missing: $r"; fi
  done
}

@test "README has the required sections" {
  for h in 'Install' 'Start' 'Commands'; do
    grep -qE "^## $h\$" "$README" || { echo "missing section: $h"; return 1; }
  done
  grep -q '/vbw:vibe' "$README"
}
