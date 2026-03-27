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

# ── Guarded symlink template expressions exist only where still needed ───────
# After the phase-detect self-healing refactor, the heavyweight state readers no
# longer wait on another prompt block to create the symlink/cache. The remaining
# guarded wait-patterns are lightweight readers that only need the link path.

_guard_pattern() {
  # No backticks needed — this substring is inside the template expression
  printf 'while [ ! -L "$L" ] && [ $i -lt 20 ]'
}

@test "vibe.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/vibe.md")
  [ "$count" -eq 1 ]
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

@test "resume.md has 0 guarded symlink template expressions" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/resume.md" || true)
  [ "${count:-0}" -eq 0 ]
}

@test "status.md has 0 guarded symlink template expressions" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/status.md" || true)
  [ "${count:-0}" -eq 0 ]
}

@test "total guarded symlink template expressions across commands is 6" {
  local count
  count=$(grep -rcF "$(_guard_pattern)" "$PROJECT_ROOT/commands/" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [ "$count" -eq 6 ]
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

_atomic_pd_temp_read_pattern() {
  printf '[ -f "$P" ] && PD=$(cat "$P")'
}

_error_cache_bypass_pattern() {
  printf '[ "$PD" = "phase_detect_error=true" ]'
}

_stale_cache_mtime_pattern() {
  printf '[ "$P_M" -lt "$S_M" ]'
}

_stamp_file_pattern() {
  printf '/tmp/.vbw-phase-detect-stamp-'
}

setup() {
  TMP_TEST_DIRS=()
}

_new_tmp_test_dir() {
  local d
  d=$(mktemp -d)
  TMP_TEST_DIRS+=("$d")
  printf '%s' "$d"
}

teardown() {
  local d
  for d in "${TMP_TEST_DIRS[@]}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
}

_conditional_wait_pattern() {
  printf 'if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ -L "$L" ]; then i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do'
}

_simulate_phase_detect_reader() {
  local L="$1"
  local P="$2"
  local PD=""

  _refresh_phase_detect() {
    local R="" REAL_R=""
    if [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]; then
      R="$L"
    fi
    [ -n "$R" ] || return 1

    REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"
    PD=$(bash "$REAL_R/scripts/phase-detect.sh" 2>/dev/null) || PD=""

    if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
      return 1
    fi

    printf '%s' "$PD" > "$P"
    return 0
  }

  [ -f "$P" ] && PD=$(cat "$P")
  _PD_CACHE="$PD"

  if ! _refresh_phase_detect; then
    PD="$_PD_CACHE"
    if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ]; then
      PD="phase_detect_error=true"
      printf '%s\n' "$PD" > "$P"
    fi
  fi

  if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
    printf '%s' "$PD"
  else
    echo "phase_detect_error=true"
  fi
}

@test "commands with phase-detect run it atomically in preamble" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_atomic_pd_preamble_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing atomic phase-detect in preamble"; return 1; }
  done
}

@test "commands with phase-detect preamble no longer use stamp file" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_stamp_file_pattern)" "$PROJECT_ROOT/commands/${cmd}.md") || true
    [ "$count" -eq 0 ] || { echo "FAIL: ${cmd}.md still references phase-detect stamp file"; return 1; }
  done
}

@test "commands with phase-detect use guarded temp-file read fallback" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_atomic_pd_temp_read_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing guarded phase-detect temp-file read"; return 1; }
  done
}

@test "commands with phase-detect treat error cache as cache miss" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_error_cache_bypass_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing error-cache bypass"; return 1; }
  done
}

@test "commands with phase-detect always re-run when plugin link exists" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_stale_cache_mtime_pattern)" "$PROJECT_ROOT/commands/${cmd}.md") || true
    [ "$count" -eq 0 ] || { echo "FAIL: ${cmd}.md still uses stale-cache mtime guard"; return 1; }
  done
}

@test "commands with phase-detect define self-healing refresh helpers" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF '_refresh_phase_detect()' "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing self-healing refresh helper"; return 1; }
  done
}

@test "vibe/verify secondary readers no longer use legacy empty-only fallback" {
  run bash -c "grep -nF '[ -z \"\$PD\" ] && [ -L \"\$L\" ] && [ -f \"\$L/scripts/phase-detect.sh\" ]' \"$PROJECT_ROOT/commands/vibe.md\" \"$PROJECT_ROOT/commands/verify.md\""
  [ "$status" -eq 1 ]
}

@test "reader bypasses error cache when live script is available" {
  local td root link cache out
  td=$(_new_tmp_test_dir)

  root="$td/root"
  link="$td/link"
  cache="$td/pd.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
echo "next_phase_state=fresh_live"
EOF
  chmod +x "$root/scripts/phase-detect.sh"

  ln -s "$root" "$link"
  echo "phase_detect_error=true" > "$cache"

  out=$(_simulate_phase_detect_reader "$link" "$cache")
  [[ "$out" == *"next_phase_state=fresh_live"* ]]
  [[ "$out" != *"phase_detect_error=true"* ]]
}

@test "reader refreshes stale valid cache when live script is available" {
  local td root link cache out
  td=$(_new_tmp_test_dir)

  root="$td/root"
  link="$td/link"
  cache="$td/pd.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
echo "next_phase_state=fresh_live"
EOF
  chmod +x "$root/scripts/phase-detect.sh"

  echo "next_phase_state=stale_cache" > "$cache"
  ln -s "$root" "$link"

  out=$(_simulate_phase_detect_reader "$link" "$cache")
  [[ "$out" == *"next_phase_state=fresh_live"* ]]
}

@test "reader skips wait when cache is valid and symlink is absent" {
  local td cache out
  td=$(_new_tmp_test_dir)

  cache="$td/pd.txt"
  echo "next_phase_state=cached_ok" > "$cache"

  _simulate_phase_detect_reader "$td/no-link" "$cache" > "$td/out.txt"
  out=$(cat "$td/out.txt")

  [[ "$out" == *"next_phase_state=cached_ok"* ]]
}

@test "reader treats whitespace-only output as error" {
  local td root link cache out
  td=$(_new_tmp_test_dir)

  root="$td/root"
  link="$td/link"
  cache="$td/pd.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
printf '   \n\n'
EOF
  chmod +x "$root/scripts/phase-detect.sh"

  ln -s "$root" "$link"
  : > "$cache"

  out=$(_simulate_phase_detect_reader "$link" "$cache")
  [[ "$out" == "phase_detect_error=true" ]]
}

@test "vibe.md uses self-healing live read with temp-file fallback" {
  local cat_count
  cat_count=$(grep -cF 'cat "$P"' "$PROJECT_ROOT/commands/vibe.md" || true)
  [ "${cat_count:-0}" -ge 1 ] || { echo "FAIL: vibe.md missing phase-detect temp-file fallback"; return 1; }

  local live_count
  live_count=$(grep -cF 'bash "$REAL_R/scripts/phase-detect.sh"' "$PROJECT_ROOT/commands/vibe.md")
  [ "$live_count" -ge 1 ] || { echo "FAIL: vibe.md missing live phase-detect read"; return 1; }

  local helper_count
  helper_count=$(grep -cF '_refresh_phase_detect()' "$PROJECT_ROOT/commands/vibe.md")
  [ "$helper_count" -ge 1 ] || { echo "FAIL: vibe.md missing self-healing refresh helper"; return 1; }
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

@test "all 16 preamble commands use pwd -P for canonical symlink resolution" {
  # todo and list-todos intentionally have no shell preamble (fix for #201)
  for cmd in config debug discuss fix help init map qa research resume skills status update verify vibe whats-new; do
    grep -q "$(_canonical_pwd_pattern)" "$PROJECT_ROOT/commands/${cmd}.md" || \
      { echo "FAIL: ${cmd}.md missing canonical pwd -P resolution"; return 1; }
  done
}

@test "all 16 preamble commands link REAL_R not raw R" {
  # todo and list-todos intentionally have no shell preamble (fix for #201)
  for cmd in config debug discuss fix help init map qa research resume skills status update verify vibe whats-new; do
    grep -q 'ln -s "$REAL_R" "$LINK"' "$PROJECT_ROOT/commands/${cmd}.md" || \
      { echo "FAIL: ${cmd}.md still links raw \$R instead of \$REAL_R"; return 1; }
  done
}
