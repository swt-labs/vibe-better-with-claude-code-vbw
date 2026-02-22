#!/usr/bin/env bats

load test_helper

@test "planning-git callsites avoid raw CLAUDE_PLUGIN_ROOT path" {
  run bash -c "grep -R -n 'bash \\\${CLAUDE_PLUGIN_ROOT}/scripts/planning-git\\.sh' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "planning-git callsites do not use cache ls-glob resolver pattern" {
  run bash -c "grep -R -n 'ls -1.*plugins/cache/vbw-marketplace/vbw.*planning-git.sh' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "planning-git callsites use temp-file fallback where expected" {
  local count
  count=$(grep -R -c 'cat.*/tmp/.vbw-plugin-root.*planning-git' "$PROJECT_ROOT/commands" "$PROJECT_ROOT/references" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [[ "$count" =~ ^[0-9]+$ ]]
  [ "$count" -ge 6 ]
}

@test "planning-git callsites support VBW_PLUGIN_ROOT fallback" {
  local count
  count=$(grep -R -c 'VBW_PLUGIN_ROOT.*/scripts/planning-git.sh' "$PROJECT_ROOT/commands" "$PROJECT_ROOT/references" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [[ "$count" =~ ^[0-9]+$ ]]
  [ "$count" -ge 2 ]
}

@test "planning-git callsites do not use find with mindepth" {
  run bash -c "grep -R -n 'find.*plugins/cache/vbw-marketplace.*mindepth.*planning-git' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "planning-git callsites do not reference phantom marketplaces path" {
  run bash -c "grep -R -n 'plugins/marketplaces/vbw-marketplace/scripts/planning-git' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "planning-git callsites use deterministic pre-resolved root path counts" {
  local c

  c=$(grep -c 'PG_SCRIPT="`!`cat /tmp/.vbw-plugin-root`/scripts/planning-git.sh"' "$PROJECT_ROOT/commands/config.md")
  [ "$c" -eq 1 ]

  c=$(grep -c 'PG_SCRIPT="`!`cat /tmp/.vbw-plugin-root`/scripts/planning-git.sh"' "$PROJECT_ROOT/commands/init.md")
  [ "$c" -eq 2 ]

  c=$(grep -c 'PG_SCRIPT="`!`cat /tmp/.vbw-plugin-root`/scripts/planning-git.sh"' "$PROJECT_ROOT/commands/vibe.md")
  [ "$c" -eq 3 ]

  c=$(grep -c 'PG_SCRIPT="${VBW_PLUGIN_ROOT}/scripts/planning-git.sh"' "$PROJECT_ROOT/references/execute-protocol.md")
  [ "$c" -eq 2 ]
}

@test "planning-git callsites reject CLAUDE_PLUGIN_ROOT assignment form" {
  # Catches old PG_SCRIPT="${CLAUDE_PLUGIN_ROOT:-}/scripts/planning-git.sh" regression (F3)
  run bash -c "grep -R -n 'CLAUDE_PLUGIN_ROOT:-.*planning-git' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "planning-git callsite count is exact" {
  local fallback_count
  fallback_count=$(grep -R -cE 'PG_SCRIPT="`!`cat /tmp/.vbw-plugin-root`/scripts/planning-git.sh"|PG_SCRIPT="\$\{VBW_PLUGIN_ROOT\}/scripts/planning-git.sh"' "$PROJECT_ROOT/commands" "$PROJECT_ROOT/references" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [ "$fallback_count" -eq 8 ] || { echo "Unexpected planning-git callsite count: $fallback_count"; false; }
}

@test "planning-git callsites do not use sort -V fallback resolver" {
  run bash -c "grep -R -n 'sort -V 2>/dev/null \\\|\\\| sort -t\\.' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}
