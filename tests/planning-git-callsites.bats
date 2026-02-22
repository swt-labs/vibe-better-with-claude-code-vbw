#!/usr/bin/env bats

load test_helper

@test "planning-git callsites avoid raw CLAUDE_PLUGIN_ROOT path" {
  run bash -c "grep -R -n 'bash \\\${CLAUDE_PLUGIN_ROOT}/scripts/planning-git\\.sh' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "planning-git callsites use ls glob for cache lookup (DXP-01 pattern)" {
  local count
  count=$(grep -R -c 'ls -1.*plugins/cache/vbw-marketplace/vbw.*planning-git.sh' "$PROJECT_ROOT/commands" "$PROJECT_ROOT/references" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [[ "$count" =~ ^[0-9]+$ ]]
  [ "$count" -ge 8 ]
}

@test "planning-git callsites use CLAUDE_PLUGIN_ROOT colon-plus fallback" {
  local count
  count=$(grep -R -c 'CLAUDE_PLUGIN_ROOT:+' "$PROJECT_ROOT/commands" "$PROJECT_ROOT/references" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [[ "$count" =~ ^[0-9]+$ ]]
  [ "$count" -ge 8 ]
}

@test "planning-git callsites do not use find with mindepth" {
  run bash -c "grep -R -n 'find.*plugins/cache/vbw-marketplace.*mindepth.*planning-git' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "planning-git callsites do not reference phantom marketplaces path" {
  run bash -c "grep -R -n 'plugins/marketplaces/vbw-marketplace/scripts/planning-git' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "planning-git resolver checks cache before PLUGIN_ROOT (DXP-01 order)" {
  # In each resolver block, the ls cache line must appear BEFORE the PLUGIN_ROOT line.
  local files=("$PROJECT_ROOT/commands/config.md" "$PROJECT_ROOT/commands/init.md" "$PROJECT_ROOT/commands/vibe.md" "$PROJECT_ROOT/references/execute-protocol.md")
  for f in "${files[@]}"; do
    local cache_line plugin_line
    cache_line=$(grep -n 'ls -1.*plugins/cache/vbw-marketplace' "$f" | head -1 | cut -d: -f1)
    plugin_line=$(grep -n 'CLAUDE_PLUGIN_ROOT:+' "$f" | head -1 | cut -d: -f1)
    [ -n "$cache_line" ] || { echo "Missing cache line in $f"; false; }
    [ -n "$plugin_line" ] || { echo "Missing PLUGIN_ROOT line in $f"; false; }
    [ "$cache_line" -lt "$plugin_line" ] || { echo "Wrong order in $f: cache=$cache_line plugin=$plugin_line"; false; }
  done
}
