#!/usr/bin/env bats

# Tests that maintainer-only commands are excluded from the consumer-facing
# commands/ directory (which is auto-discovered by the plugin system).
# Internal commands live in internal/ instead.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
COMMANDS_DIR="$REPO_ROOT/commands"
INTERNAL_DIR="$REPO_ROOT/internal"

@test "internal commands directory exists" {
  [ -d "$INTERNAL_DIR" ]
}

@test "internal directory has at least one command" {
  local count
  count=$(find "$INTERNAL_DIR" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
  [ "$count" -ge 1 ] || {
    echo "internal/ must contain at least one .md command file"
    return 1
  }
}

@test "internal commands are NOT in commands/" {
  for file in "$INTERNAL_DIR"/*.md; do
    [ -f "$file" ] || continue
    local cmd
    cmd="$(basename "$file")"
    if [ -f "$COMMANDS_DIR/$cmd" ]; then
      echo "$cmd must not be in commands/ (move to internal/)"
      return 1
    fi
  done
}

@test "internal commands have valid frontmatter" {
  for file in "$INTERNAL_DIR"/*.md; do
    [ -f "$file" ] || continue
    local cmd
    cmd="$(basename "$file")"
    [ "$(head -1 "$file")" = "---" ] || {
      echo "$cmd: missing YAML frontmatter"
      return 1
    }
  done
}
