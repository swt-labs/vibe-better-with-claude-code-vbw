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

@test "planning-git resolver checks cache before PLUGIN_ROOT in all blocks" {
  # Checks ALL resolver pairs per file, not just the first (F2 fix)
  local files=("$PROJECT_ROOT/commands/config.md" "$PROJECT_ROOT/commands/init.md" "$PROJECT_ROOT/commands/vibe.md" "$PROJECT_ROOT/references/execute-protocol.md")
  for f in "${files[@]}"; do
    local cache_lines plugin_lines cache_count plugin_count
    cache_lines=$(grep -n 'ls -1.*plugins/cache/vbw-marketplace.*planning-git' "$f" | cut -d: -f1)
    plugin_lines=$(grep -n 'CLAUDE_PLUGIN_ROOT:+' "$f" | cut -d: -f1)
    cache_count=$(echo "$cache_lines" | wc -l | tr -d ' ')
    plugin_count=$(echo "$plugin_lines" | wc -l | tr -d ' ')
    [ "$cache_count" = "$plugin_count" ] || { echo "Unequal pair count in $f: cache=$cache_count plugin=$plugin_count"; false; }
    local i=0
    while IFS= read -r cl; do
      i=$((i+1))
      local pl
      pl=$(echo "$plugin_lines" | sed -n "${i}p")
      [ -n "$cl" ] || { echo "Missing cache line $i in $f"; false; }
      [ -n "$pl" ] || { echo "Missing plugin line $i in $f"; false; }
      [ "$cl" -lt "$pl" ] || { echo "Wrong order pair $i in $f: cache=$cl plugin=$pl"; false; }
    done <<< "$cache_lines"
  done
}

@test "planning-git callsites reject CLAUDE_PLUGIN_ROOT assignment form" {
  # Catches old PG_SCRIPT="${CLAUDE_PLUGIN_ROOT:-}/scripts/planning-git.sh" regression (F3)
  run bash -c "grep -R -n 'CLAUDE_PLUGIN_ROOT:-.*planning-git' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "planning-git cache and fallback counts match" {
  # Ensures no additive bad-form callsites — cache ls count must equal fallback count (F4)
  local cache_count fallback_count
  cache_count=$(grep -R -c 'ls -1.*plugins/cache/vbw-marketplace/vbw.*planning-git.sh' "$PROJECT_ROOT/commands" "$PROJECT_ROOT/references" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  fallback_count=$(grep -R -c 'CLAUDE_PLUGIN_ROOT:+' "$PROJECT_ROOT/commands" "$PROJECT_ROOT/references" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [ "$cache_count" = "$fallback_count" ] || { echo "Mismatched: cache=$cache_count fallback=$fallback_count"; false; }
}

@test "planning-git ls callsites suppress stderr" {
  # Every ls glob line must include 2>/dev/null (F5)
  local files=("$PROJECT_ROOT/commands/config.md" "$PROJECT_ROOT/commands/init.md" "$PROJECT_ROOT/commands/vibe.md" "$PROJECT_ROOT/references/execute-protocol.md")
  for f in "${files[@]}"; do
    while IFS= read -r line; do
      echo "$line" | grep -q '2>/dev/null' || { echo "Missing 2>/dev/null in $f: $line"; false; }
    done < <(grep 'ls -1.*plugins/cache/vbw-marketplace.*planning-git' "$f")
  done
}
