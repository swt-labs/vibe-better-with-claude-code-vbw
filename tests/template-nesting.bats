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

@test "vibe.md has 5 guarded symlink template expressions" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/vibe.md")
  [ "$count" -eq 5 ]
}

@test "qa.md has 2 guarded symlink template expressions" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/qa.md")
  [ "$count" -eq 2 ]
}

@test "verify.md has 4 guarded symlink template expressions" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/verify.md")
  [ "$count" -eq 4 ]
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

@test "resume.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/resume.md" || true)
  [ "${count:-0}" -eq 1 ]
}

@test "status.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/status.md" || true)
  [ "${count:-0}" -eq 1 ]
}

@test "total guarded symlink template expressions across commands is 17" {
  local count
  count=$(grep -rcF "$(_guard_pattern)" "$PROJECT_ROOT/commands/" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [ "$count" -eq 17 ]
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
  local S="$3"
  local PD=""

  [ -f "$P" ] && PD=$(cat "$P")

  if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ -L "$L" ]; then
    i=0
    while [ ! -L "$L" ] && [ $i -lt 20 ]; do
      sleep 0.1
      i=$((i+1))
    done

    S_M=0
    P_M=0
    [ -f "$S" ] && S_M=$(stat -c %Y "$S" 2>/dev/null || stat -f %m "$S" 2>/dev/null || echo 0)
    [ -f "$P" ] && P_M=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo 0)

    if [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ] && { [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ "$P_M" -lt "$S_M" ]; }; then
      PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
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

@test "commands with phase-detect preamble write stamp file" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_stamp_file_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing phase-detect stamp file path"; return 1; }
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

@test "commands with phase-detect refresh stale cache via mtime guard" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_stale_cache_mtime_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing stale-cache mtime guard"; return 1; }
  done
}

@test "commands with phase-detect wait conditionally (not always)" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_conditional_wait_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing conditional wait guard"; return 1; }
  done
}

@test "vibe/verify secondary readers no longer use legacy empty-only fallback" {
  run bash -c "grep -nF '[ -z \"\$PD\" ] && [ -L \"\$L\" ] && [ -f \"\$L/scripts/phase-detect.sh\" ]' \"$PROJECT_ROOT/commands/vibe.md\" \"$PROJECT_ROOT/commands/verify.md\""
  [ "$status" -eq 1 ]
}

@test "reader bypasses error cache when live script is available" {
  local td root link cache stamp out
  td=$(_new_tmp_test_dir)

  root="$td/root"
  link="$td/link"
  cache="$td/pd.txt"
  stamp="$td/stamp.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
echo "next_phase_state=fresh_live"
EOF
  chmod +x "$root/scripts/phase-detect.sh"

  ln -s "$root" "$link"
  : > "$stamp"
  echo "phase_detect_error=true" > "$cache"

  out=$(_simulate_phase_detect_reader "$link" "$cache" "$stamp")
  [[ "$out" == *"next_phase_state=fresh_live"* ]]
  [[ "$out" != *"phase_detect_error=true"* ]]
}

@test "reader refreshes stale cache older than stamp" {
  local td root link cache stamp out
  td=$(_new_tmp_test_dir)

  root="$td/root"
  link="$td/link"
  cache="$td/pd.txt"
  stamp="$td/stamp.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
echo "next_phase_state=fresh_live"
EOF
  chmod +x "$root/scripts/phase-detect.sh"

  echo "next_phase_state=stale_cache" > "$cache"
  : > "$stamp"
  touch -t 202402020101 "$cache"
  touch -t 202402020102 "$stamp"
  ln -s "$root" "$link"

  out=$(_simulate_phase_detect_reader "$link" "$cache" "$stamp")
  [[ "$out" == *"next_phase_state=fresh_live"* ]]
  [[ "$out" != *"next_phase_state=stale_cache"* ]]
}

@test "reader skips wait when cache is valid and symlink is absent" {
  local td cache stamp out
  td=$(_new_tmp_test_dir)

  cache="$td/pd.txt"
  stamp="$td/stamp.txt"
  echo "next_phase_state=cached_ok" > "$cache"

  _simulate_phase_detect_reader "$td/no-link" "$cache" "$stamp" > "$td/out.txt"
  out=$(cat "$td/out.txt")

  [[ "$out" == *"next_phase_state=cached_ok"* ]]
}

@test "reader treats whitespace-only output as error" {
  local td root link cache stamp out
  td=$(_new_tmp_test_dir)

  root="$td/root"
  link="$td/link"
  cache="$td/pd.txt"
  stamp="$td/stamp.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
printf '   \n\n'
EOF
  chmod +x "$root/scripts/phase-detect.sh"

  ln -s "$root" "$link"
  : > "$stamp"
  : > "$cache"

  out=$(_simulate_phase_detect_reader "$link" "$cache" "$stamp")
  [[ "$out" == "phase_detect_error=true" ]]
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
