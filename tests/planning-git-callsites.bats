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

@test "planning-git callsites use deterministic echo path where expected" {
  local count
  count=$(grep -R -c 'echo /tmp/.vbw-plugin-root-link-.*planning-git' "$PROJECT_ROOT/commands" "$PROJECT_ROOT/references" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
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

  c=$(grep -c 'PG_SCRIPT="`!`SESSION_BASE="${CLAUDE_SESSION_ID:-}"; \[ -z "\$SESSION_BASE" \] && SESSION_BASE=\$(pwd); echo /tmp/.vbw-plugin-root-link-\$(printf '\''%s'\'' "\$SESSION_BASE" | shasum | awk '\''{print \$1}'\'' | cut -c1-16)`/scripts/planning-git.sh"' "$PROJECT_ROOT/commands/config.md")
  [ "$c" -eq 1 ]

  c=$(grep -c 'PG_SCRIPT="`!`SESSION_BASE="${CLAUDE_SESSION_ID:-}"; \[ -z "\$SESSION_BASE" \] && SESSION_BASE=\$(pwd); echo /tmp/.vbw-plugin-root-link-\$(printf '\''%s'\'' "\$SESSION_BASE" | shasum | awk '\''{print \$1}'\'' | cut -c1-16)`/scripts/planning-git.sh"' "$PROJECT_ROOT/commands/init.md")
  [ "$c" -eq 2 ]

  c=$(grep -c 'PG_SCRIPT="`!`SESSION_BASE="${CLAUDE_SESSION_ID:-}"; \[ -z "\$SESSION_BASE" \] && SESSION_BASE=\$(pwd); echo /tmp/.vbw-plugin-root-link-\$(printf '\''%s'\'' "\$SESSION_BASE" | shasum | awk '\''{print \$1}'\'' | cut -c1-16)`/scripts/planning-git.sh"' "$PROJECT_ROOT/commands/vibe.md")
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
  fallback_count=$(grep -R -cE 'PG_SCRIPT="`!`SESSION_BASE="\$\{CLAUDE_SESSION_ID:-\}"; \[ -z "\$SESSION_BASE" \] && SESSION_BASE=\$\(pwd\); echo /tmp/.vbw-plugin-root-link-\$\(printf '\''%s'\'' "\$SESSION_BASE" \| shasum \| awk '\''\{print \$1\}'\'' \| cut -c1-16\)`/scripts/planning-git.sh"|PG_SCRIPT="\$\{VBW_PLUGIN_ROOT\}/scripts/planning-git.sh"' "$PROJECT_ROOT/commands" "$PROJECT_ROOT/references" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [ "$fallback_count" -eq 8 ] || { echo "Unexpected planning-git callsite count: $fallback_count"; false; }
}

@test "planning-git callsites do not use sort -V fallback resolver" {
  run bash -c "grep -R -n 'sort -V 2>/dev/null \\\|\\\| sort -t\\.' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "plugin-root callsites avoid runtime command substitution" {
  run bash -c "grep -R -n '\\\$\\(cat /tmp/.vbw-plugin-root\\)' \"$PROJECT_ROOT/commands\" \"$PROJECT_ROOT/references\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "no legacy cat /tmp/.vbw-plugin-root readers in commands" {
  run bash -c "grep -R -n 'cat /tmp/.vbw-plugin-root' \"$PROJECT_ROOT/commands\" 2>/dev/null | grep -v 'vbw-plugin-root-link-'"
  [ "$status" -eq 1 ]
}

@test "no legacy temp file writes in commands" {
  run bash -c "grep -R -n 'printf.*> /tmp/.vbw-plugin-root' \"$PROJECT_ROOT/commands\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "all commands with readers have a preamble" {
  for file in "$PROJECT_ROOT/commands"/*.md; do
    local reader_count
    reader_count=$(grep -c 'echo /tmp/.vbw-plugin-root-link-' "$file" 2>/dev/null || true)
    if [ "$reader_count" -gt 0 ]; then
      grep -q 'LINK="/tmp/.vbw-plugin-root-link-' "$file" || { echo "$(basename "$file"): $reader_count readers but no preamble"; return 1; }
    fi
  done
}

@test "preamble and readers use supported session key expansion" {
  for file in "$PROJECT_ROOT/commands"/*.md; do
    local reader_count
    reader_count=$(grep -c 'echo /tmp/.vbw-plugin-root-link-' "$file" 2>/dev/null || true)
    [ "$reader_count" -gt 0 ] || continue
    # Preamble must use either deterministic SESSION_BASE hash fallback or legacy default fallback
    grep -Eq 'SESSION_BASE="\$\{CLAUDE_SESSION_ID:-\}"|CLAUDE_SESSION_ID:-default' "$file" || \
      { echo "$(basename "$file"): preamble missing supported session key fallback"; return 1; }
    # Reader references must use either deterministic hashed fallback or legacy default fallback
    local mismatched
    mismatched=$(grep 'echo /tmp/.vbw-plugin-root-link-' "$file" | grep -Ev 'CLAUDE_SESSION_ID:-default|SESSION_BASE="\$\{CLAUDE_SESSION_ID:-\}"' || true)
    [ -z "$mismatched" ] || { echo "$(basename "$file"): reader with unsupported session key fallback: $mismatched"; return 1; }
  done
}

@test "plugin-root resolver emits canonical link path" {
  local count
  count=$(grep -R -c 'LINK="/tmp/.vbw-plugin-root-link-' "$PROJECT_ROOT/commands" "$PROJECT_ROOT/references" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [[ "$count" =~ ^[0-9]+$ ]]
  [ "$count" -ge 1 ]
}
