#!/usr/bin/env bats

load test_helper

# ── Ban nested template expressions ─────────────────────────────────────────
# Claude Code's template processor cannot parse nested !` backtick expressions.
# All template directives must be single-level: !`bash /path/to/script.sh`
# Nested forms like !`bash `!`echo /path`/script.sh` pass raw text to the LLM.

@test "no nested template expressions in command files" {
  run bash -c "grep -rn '!\`bash \`!\`' \"$PROJECT_ROOT/commands/\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "no nested template expressions in reference files" {
  run bash -c "grep -rn '!\`bash \`!\`' \"$PROJECT_ROOT/references/\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "no nested template expressions in agent files" {
  run bash -c "grep -rn '!\`bash \`!\`' \"$PROJECT_ROOT/agents/\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

# ── Ban legacy runtime substitution ─────────────────────────────────────────
# $(cat /tmp/.vbw-plugin-root) was the old pattern — replaced by symlink path.

@test "no legacy cat /tmp/.vbw-plugin-root runtime substitution in commands" {
  run bash -c "grep -R -n 'cat /tmp/.vbw-plugin-root' \"$PROJECT_ROOT/commands\" 2>/dev/null | grep -v 'vbw-plugin-root-link-'"
  [ "$status" -eq 1 ]
}

@test "no legacy cat /tmp/.vbw-plugin-root runtime substitution in references" {
  run bash -c "grep -R -n 'cat /tmp/.vbw-plugin-root' \"$PROJECT_ROOT/references\" 2>/dev/null | grep -v 'vbw-plugin-root-link-'"
  [ "$status" -eq 1 ]
}

# ── Guarded symlink template expressions exist where expected ────────────────
# Dependent template expressions must include a spin-wait guard that waits for
# the session-specific symlink to be created by the preamble expression.
# Pattern: L="/tmp/..."; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; ...

_guard_pattern() {
  # No backticks needed — this substring is inside the template expression
  printf 'while [ ! -L "$L" ] && [ $i -lt 20 ]'
}

@test "vibe.md has 2 guarded symlink template expressions" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/vibe.md")
  [ "$count" -eq 2 ]
}

@test "qa.md has 2 guarded symlink template expressions" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/qa.md")
  [ "$count" -eq 2 ]
}

@test "verify.md has 2 guarded symlink template expressions" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/verify.md")
  [ "$count" -eq 2 ]
}

@test "discuss.md has 2 guarded symlink template expressions" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/discuss.md")
  [ "$count" -eq 2 ]
}

@test "help.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/help.md")
  [ "$count" -eq 1 ]
}

@test "skills.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/skills.md")
  [ "$count" -eq 1 ]
}

@test "total guarded symlink template expressions across commands is 10" {
  local count
  count=$(grep -rcF "$(_guard_pattern)" "$PROJECT_ROOT/commands/" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [ "$count" -eq 10 ]
}

@test "guarded expressions use symlink path variable not direct path" {
  # All guarded expressions should reference scripts via $L variable, not direct path
  run bash -c "grep -F '$(_guard_pattern)' \"$PROJECT_ROOT/commands/\"*.md | grep -v 'bash \"\$L/scripts/'"
  [ "$status" -eq 1 ]
}

# ── UAT protocol safeguards ─────────────────────────────────────────────────
# verify.md must explicitly ban automated test scenarios from UAT checkpoints.

@test "verify.md bans automated test commands in UAT scenarios" {
  grep -q 'NEVER generate tests that ask the user to run automated checks' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify.md lists automated test tools as excluded from UAT" {
  grep -q 'xcodebuild test, pytest, bats, jest' "$PROJECT_ROOT/commands/verify.md"
}
