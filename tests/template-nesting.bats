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

@test "qa.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/qa.md")
  [ "$count" -eq 1 ]
}

@test "verify.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/verify.md")
  [ "$count" -eq 1 ]
}

@test "discuss.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/discuss.md")
  [ "$count" -eq 1 ]
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

@test "resume.md has 0 guarded symlink template expressions (uses atomic cat)" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/resume.md" || true)
  [ "${count:-0}" -eq 0 ]
}

@test "total guarded symlink template expressions across commands is 7" {
  local count
  count=$(grep -rcF "$(_guard_pattern)" "$PROJECT_ROOT/commands/" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [ "$count" -eq 7 ]
}

@test "guarded expressions use symlink path variable not direct path" {
  # All guarded expressions should reference scripts via $L variable, not direct path
  run bash -c "grep -F '$(_guard_pattern)' \"$PROJECT_ROOT/commands/\"*.md | grep -v 'bash \"\$L/scripts/'"
  [ "$status" -eq 1 ]
}

# ── Atomic phase-detect via preamble temp file ──────────────────────────────
# Phase-detect.sh runs atomically inside the preamble (same !` backtick) to
# avoid race conditions between separate template expressions.
#
# Most commands read the preamble output from a temp file. vibe.md now reads
# phase-detect live (guarded) to avoid stale/shared temp-file collisions.

_atomic_pd_preamble_pattern() {
  printf 'phase-detect.sh" > "/tmp/.vbw-phase-detect-'
}

_atomic_pd_cat_pattern() {
  printf 'cat "/tmp/.vbw-phase-detect-'
}

@test "commands with phase-detect run it atomically in preamble" {
  for cmd in resume vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_atomic_pd_preamble_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -eq 1 ] || { echo "FAIL: ${cmd}.md missing atomic phase-detect in preamble"; return 1; }
  done
}

@test "commands with phase-detect use cat for temp file read" {
  for cmd in resume vibe discuss qa verify; do
    if [ "$cmd" = "vibe" ]; then
      grep -qF 'cat "$P"' "$PROJECT_ROOT/commands/${cmd}.md" || { echo "FAIL: ${cmd}.md missing cat for phase-detect temp file"; return 1; }
    else
      local count
      count=$(grep -cF "$(_atomic_pd_cat_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
      [ "$count" -eq 1 ] || { echo "FAIL: ${cmd}.md missing cat for phase-detect temp file"; return 1; }
    fi
  done
}

@test "vibe.md reads phase-detect live with temp-file fallback" {
  local cat_count
  cat_count=$(grep -cF 'cat "$P"' "$PROJECT_ROOT/commands/vibe.md" || true)
  [ "${cat_count:-0}" -ge 1 ] || { echo "FAIL: vibe.md missing phase-detect temp-file fallback"; return 1; }

  local live_count
  live_count=$(grep -cF 'bash "$L/scripts/phase-detect.sh"' "$PROJECT_ROOT/commands/vibe.md")
  [ "$live_count" -ge 1 ] || { echo "FAIL: vibe.md missing live phase-detect read"; return 1; }
}

# ── UAT protocol safeguards ─────────────────────────────────────────────────
# verify.md must explicitly ban automated test scenarios from UAT checkpoints.

@test "verify.md bans automated test commands in UAT scenarios" {
  grep -q 'NEVER generate tests that ask the user to run automated checks' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify.md lists automated test tools as excluded from UAT" {
  grep -q 'xcodebuild test, pytest, bats, jest' "$PROJECT_ROOT/commands/verify.md"
}

# ── Content validation in plugin root resolution ────────────────────────────
# The preamble must validate directories have scripts (hook-wrapper.sh) before
# accepting them, to guard against empty stub directories from --plugin-dir mode.

_content_validation_pattern() {
  printf 'scripts/hook-wrapper.sh'
}

@test "all 6 preamble commands use content validation for local/ check" {
  for cmd in vibe verify discuss help qa skills; do
    local count
    count=$(grep -c "$(_content_validation_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing content validation"; return 1; }
  done
}

@test "preamble does NOT use bare [ -d ] for local/ acceptance" {
  # The old pattern [ -d "${VBW_CACHE_ROOT}/local" ] accepts empty stubs
  for cmd in vibe verify discuss help qa skills; do
    run bash -c "grep 'elif \\[ -d.*VBW_CACHE_ROOT.*local' \"$PROJECT_ROOT/commands/${cmd}.md\" 2>/dev/null"
    [ "$status" -eq 1 ] || { echo "FAIL: ${cmd}.md still has bare [ -d ] local/ check"; return 1; }
  done
}

# ── Process-tree fallback for --plugin-dir mode ─────────────────────────────
# When cache resolution fails, the preamble falls back to detecting the plugin
# directory from the process tree (ps axww).

_process_tree_pattern() {
  printf 'ps axww -o args='
}

@test "all 6 preamble commands have process-tree fallback" {
  for cmd in vibe verify discuss help qa skills; do
    grep -q "$(_process_tree_pattern)" "$PROJECT_ROOT/commands/${cmd}.md" || \
      { echo "FAIL: ${cmd}.md missing process-tree fallback"; return 1; }
  done
}

# ── Canonical symlink resolution via pwd -P ─────────────────────────────────
# Preambles must canonicalize $R via (cd "$R" && pwd -P) before creating the
# /tmp symlink. This survives cache "local" symlink deletion mid-session by
# pointing the /tmp link directly at the real directory, not via the cache chain.

_canonical_pwd_pattern() {
  printf 'cd "$R" 2>/dev/null && pwd -P'
}

@test "all 18 preamble commands use pwd -P for canonical symlink resolution" {
  for cmd in config debug discuss fix help init list-todos map qa research resume skills status todo update verify vibe whats-new; do
    grep -q "$(_canonical_pwd_pattern)" "$PROJECT_ROOT/commands/${cmd}.md" || \
      { echo "FAIL: ${cmd}.md missing canonical pwd -P resolution"; return 1; }
  done
}

@test "all 18 preamble commands link REAL_R not raw R" {
  for cmd in config debug discuss fix help init list-todos map qa research resume skills status todo update verify vibe whats-new; do
    grep -q 'ln -s "$REAL_R" "$LINK"' "$PROJECT_ROOT/commands/${cmd}.md" || \
      { echo "FAIL: ${cmd}.md still links raw \$R instead of \$REAL_R"; return 1; }
  done
}
