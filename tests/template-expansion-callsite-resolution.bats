#!/usr/bin/env bats

load test_helper

extract_plugin_root_refs() {
  local file="$1"
  grep -oE '\{plugin-root\}/[A-Za-z0-9._/{}-]+' "$file" | sort -u
}

assert_plugin_root_refs_resolve() {
  local rel="$1"
  local file="$PROJECT_ROOT/$rel"
  local refs
  refs=$(extract_plugin_root_refs "$file")
  [ -n "$refs" ] || { echo "$rel: no {plugin-root} references found"; return 1; }

  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    local path="${ref#\{plugin-root\}/}"
    if [[ "$path" == *'{'*'}'* ]]; then
      local glob="$path"
      glob="${glob//\{profile\}/*}"
      glob="${glob//\{name\}/*}"
      glob="${glob//\{phase-dir\}/*}"
      glob="${glob//\{phase\}/*}"
      compgen -G "$PROJECT_ROOT/$glob" >/dev/null || {
        echo "$rel: templated path does not resolve -> $path"
        return 1
      }
    else
      [ -e "$PROJECT_ROOT/$path" ] || {
        echo "$rel: resolved path does not exist -> $path"
        return 1
      }
    fi
  done <<< "$refs"
}

assert_header_followed_by_fenced_text() {
  local rel="$1"
  local header="$2"
  awk -v header="$header" '
    $0 == header { getline; if ($0 == "```text") found=1 }
    END { exit(found ? 0 : 1) }
  ' "$PROJECT_ROOT/$rel"
}

@test "primary migrated commands resolve plugin-root references to real repo files" {
  local file
  for file in \
    commands/config.md \
    commands/debug.md \
    commands/fix.md \
    commands/init.md \
    commands/map.md \
    commands/qa.md \
    commands/research.md \
    commands/verify.md; do
    assert_plugin_root_refs_resolve "$file"
  done
}

@test "supporting migrated commands resolve plugin-root references to real repo files" {
  local file
  for file in \
    commands/discuss.md \
    commands/help.md \
    commands/update.md \
    commands/whats-new.md; do
    assert_plugin_root_refs_resolve "$file"
  done
}

@test "doctor, teach, uninstall, and release moved context probes into fenced blocks" {
  assert_header_followed_by_fenced_text "commands/doctor.md" "Version:"
  assert_header_followed_by_fenced_text "commands/teach.md" "Codebase map:"
  assert_header_followed_by_fenced_text "commands/uninstall.md" "Planning dir:"
  assert_header_followed_by_fenced_text "commands/uninstall.md" "CLAUDE.md:"
  assert_header_followed_by_fenced_text "internal/release.md" "Version:"
  assert_header_followed_by_fenced_text "internal/release.md" "Current branch:"
}
