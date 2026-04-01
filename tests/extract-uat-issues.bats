#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  # Create a phase directory with a UAT file
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/03-test-phase"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  rm -f /tmp/.vbw-test-stderr-$$.txt
  teardown_temp_dir
}

# Helper: create a UAT file with given content
create_uat_file() {
  local content="$1"
  printf '%s\n' "$content" > "$PHASE_DIR/03-UAT.md"
}

@test "extract-uat-issues: single major issue" {
  create_uat_file '---
phase: 03
plan_count: 3
status: issues_found
started: 2026-02-22
completed: 2026-02-22
total_tests: 6
passed: 5
skipped: 0
issues: 1
---

# Phase 03 UAT

## Tests

### P01-T1: Passing test

- **Plan:** 03-01 — Fix something
- **Scenario:** Do something
- **Expected:** It works
- **Result:** pass

### P01-T2: Failing test

- **Plan:** 03-01 — Fix something else
- **Scenario:** Do another thing
- **Expected:** It should work
- **Result:** issue
- **Issue:**
  - Description: Widget fails on edge case
  - Severity: major

## Summary

- Passed: 5
- Issues: 1
- Total: 6'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_phase=03"* ]]
  [[ "${lines[0]}" == *"uat_issues_total=1"* ]]
  [[ "${lines[1]}" == "P01-T2|major|Widget fails on edge case|1" ]]
}

@test "extract-uat-issues: multiple issues with mixed severity" {
  create_uat_file '---
phase: 03
status: issues_found
issues: 3
---

## Tests

### P01-T1: First issue

- **Result:** issue
- **Issue:**
  - Description: First problem
  - Severity: critical

### P02-T1: Passing

- **Result:** pass

### P02-T2: Second issue

- **Result:** issue
- **Issue:**
  - Description: Second problem
  - Severity: minor

### D1: Discovered issue

- **Result:** issue
- **Issue:**
  - Description: Found during testing
  - Severity: major

## Summary'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_issues_total=3"* ]]
  [[ "${lines[1]}" == "P01-T1|critical|First problem|1" ]]
  [[ "${lines[2]}" == "P02-T2|minor|Second problem|1" ]]
  [[ "${lines[3]}" == "D1|major|Found during testing|1" ]]
}

@test "extract-uat-issues: long description is preserved in full" {
  local long_desc
  long_desc=$(printf 'x%.0s' {1..250})
  create_uat_file "---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P01-T1: Long desc

- **Result:** issue
- **Issue:**
  - Description: ${long_desc}
  - Severity: major

## Summary"

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  # Description must NOT be truncated — full 250 chars preserved
  [[ "${lines[1]}" != *"..."* ]]
  [[ "${lines[1]}" == "P01-T1|major|${long_desc}|1" ]]
}

@test "extract-uat-issues: no UAT file returns error marker" {
  rm -f "$PHASE_DIR"/*.md
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_extract_error=no_uat_file"* ]]
}

@test "extract-uat-issues: non-issues_found status returns status marker" {
  create_uat_file '---
phase: 03
status: complete
issues: 0
---

## Tests

### P01-T1: All good

- **Result:** pass

## Summary'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_extract_status=complete"* ]]
}

@test "extract-uat-issues: accepts a direct UAT file path" {
  create_uat_file '---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P01-T2: Direct file input

- **Result:** issue
- **Issue:**
  - Description: File-path input still works
  - Severity: major'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR/03-UAT.md"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_phase=03"* ]]
  [[ "${lines[0]}" == *"uat_issues_total=1"* ]]
  [[ "${lines[1]}" == "P01-T2|major|File-path input still works|1" ]]
}

@test "extract-uat-issues: direct round-dir UAT file preserves current round and recurrence" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01" "$PHASE_DIR/remediation/uat/round-02"
  printf 'stage=verify\nround=02\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  cat > "$PHASE_DIR/remediation/uat/round-01/R01-UAT.md" <<'EOF'
---
phase: 03
status: issues_found
---

## Tests

### P01-T2: recurring

- **Result:** issue
- **Issue:**
  - Description: Broke before
  - Severity: major
EOF
  cat > "$PHASE_DIR/remediation/uat/round-02/R02-UAT.md" <<'EOF'
---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P01-T2: recurring

- **Result:** issue
- **Issue:**
  - Description: Broke again
  - Severity: major
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR/remediation/uat/round-02/R02-UAT.md"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_round=2"* ]]
  [[ "${lines[1]}" == "P01-T2|major|Broke again|1,2" ]]
}

@test "extract-uat-issues: missing directory returns error" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$TEST_TEMP_DIR/nonexistent"

  [ "$status" -ne 0 ]
}

@test "extract-uat-issues: excludes SOURCE-UAT.md" {
  # Create a SOURCE-UAT.md (copied from milestone) and a real UAT
  create_uat_file '---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P01-T1: Real issue

- **Result:** issue
- **Issue:**
  - Description: Real issue from latest UAT
  - Severity: major

## Summary'

  # Also create a SOURCE-UAT.md with different content
  cat > "$PHASE_DIR/03-SOURCE-UAT.md" <<'EOF'
---
phase: 03
status: issues_found
issues: 1
---

### P01-T1: Old

- **Result:** issue
- **Issue:**
  - Description: Old milestone issue
  - Severity: critical
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[1]}" == *"Real issue from latest UAT"* ]]
  [[ "$output" != *"Old milestone issue"* ]]
}

@test "extract-uat-issues: all pass tests produce zero issues" {
  create_uat_file '---
phase: 03
status: issues_found
issues: 0
---

## Tests

### P01-T1: Everything works

- **Result:** pass

## Summary'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  # status: issues_found but no actual issue blocks — script still works
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_issues_total=0"* ]]
}

# ===========================================================================
# Recurrence tracking (FAILED_IN_ROUNDS 4th field)
# ===========================================================================

# Helper: create an archived round file with given issue IDs
create_round_file() {
  local round_num="$1"
  shift
  local file="$PHASE_DIR/03-UAT-round-${round_num}.md"
  {
    printf '%s\n' '---' 'status: issues_found' '---' '' '## Tests'
    for id in "$@"; do
      printf '\n### %s: Test\n\n- **Result:** issue\n- **Issue:**\n  - Description: Failed in round %s\n  - Severity: major\n' "$id" "$round_num"
    done
  } > "$file"
}

@test "extract-uat-issues: header includes uat_round for first round (no archives)" {
  create_uat_file '---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P01-T1: Test

- **Result:** issue
- **Issue:**
  - Description: First failure
  - Severity: major'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_round=1"* ]]
  # 4th field should be just "1" (current round only)
  [[ "${lines[1]}" == "P01-T1|major|First failure|1" ]]
}

@test "extract-uat-issues: recurrence from archived rounds" {
  # Create 2 archived rounds where P01-T1 failed in both
  create_round_file 1 "P01-T1"
  create_round_file 2 "P01-T1" "P02-T1"

  # Current UAT (round 3) has P01-T1 failing again
  create_uat_file '---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P01-T1: Recurring test

- **Result:** issue
- **Issue:**
  - Description: Still broken
  - Severity: major'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_round=3"* ]]
  # P01-T1 failed in rounds 1, 2, and current (3)
  [[ "${lines[1]}" == "P01-T1|major|Still broken|1,2,3" ]]
}

@test "extract-uat-issues: mixed recurring and first-time failures" {
  create_round_file 1 "P01-T1"

  create_uat_file '---
phase: 03
status: issues_found
issues: 2
---

## Tests

### P01-T1: Recurring

- **Result:** issue
- **Issue:**
  - Description: Old problem
  - Severity: major

### P02-T1: New failure

- **Result:** issue
- **Issue:**
  - Description: New problem
  - Severity: minor'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_round=2"* ]]
  # P01-T1 failed in round 1 and current (2)
  [[ "${lines[1]}" == "P01-T1|major|Old problem|1,2" ]]
  # P02-T1 is first-time (only current round)
  [[ "${lines[2]}" == "P02-T1|minor|New problem|2" ]]
}

@test "extract-uat-issues: output matches phase-detect marker payload for recurring issue" {
  touch "$PHASE_DIR/03-01-PLAN.md"
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > "$PHASE_DIR/03-01-SUMMARY.md"
  create_round_file 1 "P01-T1"
  create_round_file 2 "P01-T1"

  create_uat_file '---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P01-T1: Recurring test

- **Result:** issue
- **Issue:**
  - Description: Still broken
  - Severity: major'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  expected="$output"

  run bash "$SCRIPTS_DIR/phase-detect.sh"
  [ "$status" -eq 0 ]
  marker=$(printf '%s\n' "$output" | awk '/^---UAT_EXTRACT_START---$/{f=1; next} /^---UAT_EXTRACT_END---$/{exit} f{print}')
  [ "$marker" = "$expected" ]
}

@test "extract-uat-issues: discovered issue D-prefix tracked across rounds" {
  create_round_file 1 "D1"

  create_uat_file '---
phase: 03
status: issues_found
issues: 1
---

## Tests

### D1: Discovered issue

- **Result:** issue
- **Issue:**
  - Description: Keeps happening
  - Severity: major'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[1]}" == "D1|major|Keeps happening|1,2" ]]
}

# ===========================================================================
# UAT pre-seeding expansion logic (vibe.md Block 5)
# ===========================================================================

@test "uat-preseed: runs phase-detect live when cached file is missing (race fix)" {
  # Simulate the current vibe.md Block 5 reader logic.
  # When the symlink exists and the cached phase-detect file is absent,
  # the reader must consume the marker payload from a live phase-detect run.
  local session_key="test-race-$$"
  local link="/tmp/.vbw-plugin-root-link-${session_key}"
  local cache_file="/tmp/.vbw-phase-detect-${session_key}.txt"
  local fake_root="$TEST_TEMP_DIR/fake-plugin"

  mkdir -p "$fake_root/scripts"
  cat > "$fake_root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
next_phase_state=needs_uat_remediation
next_phase_slug=03-test-phase
---UAT_EXTRACT_START---
uat_phase=03 uat_issues_total=1 uat_round=1 uat_file=03-UAT.md
P01-T2|major|Race condition test issue|1
---UAT_EXTRACT_END---
OUT
EOF
  chmod +x "$fake_root/scripts/phase-detect.sh"

  # Create symlink pointing to fake plugin root
  ln -sf "$fake_root" "$link"
  # Ensure NO cached file exists (simulates race)
  rm -f "$cache_file"

  cd "$TEST_TEMP_DIR"

  # Run the expansion logic (extracted from vibe.md Block 5)
  run bash -c '
    SESSION_KEY="'"$session_key"'"
    L="'"$link"'"
    P="'"$cache_file"'"
    PD=""
    _PD_START_TS=$(date +%s 2>/dev/null || echo 0)
    _phase_detect_cache_fresh() {
      local m=""
      [ -f "$P" ] || return 1
      m=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo "")
      [ -n "$m" ] || return 1
      [ "$m" -ge "$_PD_START_TS" ] 2>/dev/null
    }
    i=0
    while [ $i -lt 100 ]; do
      if _phase_detect_cache_fresh; then
        PD=$(cat "$P")
        break
      fi
      sleep 0.1
      i=$((i+1))
    done
    if [ -z "$(printf "%s" "$PD" | tr -d "[:space:]")" ] && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]; then
      LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"
      i=0
      while [ $i -lt 100 ]; do
        if _phase_detect_cache_fresh; then
          PD=$(cat "$P")
          break
        fi
        if mkdir "$LOCK" 2>/dev/null; then
          PTMP="${P}.reader.$$.$RANDOM"
          PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
          if [ -n "$(printf "%s" "$PD" | tr -d "[:space:]")" ]; then
            printf "%s\n" "$PD" > "$PTMP" 2>/dev/null && mv "$PTMP" "$P" 2>/dev/null || true
          fi
          rmdir "$LOCK" 2>/dev/null || true
          break
        fi
        sleep 0.1
        i=$((i+1))
      done
    fi
    [ -z "$(printf "%s" "$PD" | tr -d "[:space:]")" ] && [ -f "$P" ] && PD=$(cat "$P")
    if [ -z "$(printf "%s" "$PD" | tr -d "[:space:]")" ] || [ "$PD" = "phase_detect_error=true" ]; then
      echo "uat_extract_error=true"
      exit 0
    fi
    if printf "%s" "$PD" | grep -q "^---UAT_EXTRACT_START---$"; then
      printf "%s\n" "$PD" | awk "/^---UAT_EXTRACT_START---$/{f=1; next} /^---UAT_EXTRACT_END---$/{exit} f{print}"
    else
      STATE=$(printf "%s" "$PD" | grep "^next_phase_state=" | head -1 | cut -d= -f2)
      if [ "$STATE" = "needs_uat_remediation" ]; then
        echo "uat_extract_error=true"
      else
        echo "not_in_remediation"
      fi
    fi
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_phase=03 uat_issues_total=1 uat_round=1 uat_file=03-UAT.md"* ]]
  [[ "$output" == *"P01-T2|major|Race condition test issue|1"* ]]

  # Cleanup
  rm -f "$link" "$cache_file"
}

@test "uat-preseed: falls back to cached file when symlink is missing" {
  local session_key="test-fallback-$$"
  local link="/tmp/.vbw-plugin-root-link-${session_key}"
  local cache_file="/tmp/.vbw-phase-detect-${session_key}.txt"

  # No symlink, but cached file exists with the marker payload already embedded.
  rm -f "$link"
  cat > "$cache_file" <<'EOF'
next_phase_state=needs_uat_remediation
next_phase_slug=03-test-phase
next_phase=3
---UAT_EXTRACT_START---
uat_phase=03 uat_issues_total=1 uat_round=1 uat_file=03-UAT.md
P01-T2|major|Fallback test issue|1
---UAT_EXTRACT_END---
EOF

  cd "$TEST_TEMP_DIR"

  # With no symlink, reader falls back to the cached phase-detect marker block.
  run bash -c '
    SESSION_KEY="'"$session_key"'"
    L="'"$link"'"
    P="'"$cache_file"'"
    PD=""
    _PD_START_TS=0
    _phase_detect_cache_fresh() {
      [ -f "$P" ]
    }
    i=0
    while [ $i -lt 100 ]; do
      if _phase_detect_cache_fresh; then
        PD=$(cat "$P")
        break
      fi
      sleep 0.1
      i=$((i+1))
    done
    if [ -z "$(printf "%s" "$PD" | tr -d "[:space:]")" ] && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]; then
      LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"
      i=0
      while [ $i -lt 100 ]; do
        if _phase_detect_cache_fresh; then
          PD=$(cat "$P")
          break
        fi
        if mkdir "$LOCK" 2>/dev/null; then
          PTMP="${P}.reader.$$.$RANDOM"
          PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
          if [ -n "$(printf "%s" "$PD" | tr -d "[:space:]")" ]; then
            printf "%s\n" "$PD" > "$PTMP" 2>/dev/null && mv "$PTMP" "$P" 2>/dev/null || true
          fi
          rmdir "$LOCK" 2>/dev/null || true
          break
        fi
        sleep 0.1
        i=$((i+1))
      done
    fi
    [ -z "$(printf "%s" "$PD" | tr -d "[:space:]")" ] && [ -f "$P" ] && PD=$(cat "$P")
    if [ -z "$(printf "%s" "$PD" | tr -d "[:space:]")" ] || [ "$PD" = "phase_detect_error=true" ]; then
      echo "uat_extract_error=true"
      exit 0
    fi
    if printf "%s" "$PD" | grep -q "^---UAT_EXTRACT_START---$"; then
      printf "%s\n" "$PD" | awk "/^---UAT_EXTRACT_START---$/{f=1; next} /^---UAT_EXTRACT_END---$/{exit} f{print}"
    else
      STATE=$(printf "%s" "$PD" | grep "^next_phase_state=" | head -1 | cut -d= -f2)
      if [ "$STATE" = "needs_uat_remediation" ]; then
        echo "uat_extract_error=true"
      else
        echo "not_in_remediation"
      fi
    fi
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_phase=03 uat_issues_total=1 uat_round=1 uat_file=03-UAT.md"* ]]
  [[ "$output" == *"P01-T2|major|Fallback test issue|1"* ]]

  rm -f "$cache_file"
}

@test "uat-preseed: prefers fresh cache over live phase-detect when symlink already exists" {
  local session_key="test-cache-first-$$"
  local link="/tmp/.vbw-plugin-root-link-${session_key}"
  local cache_file="/tmp/.vbw-phase-detect-${session_key}.txt"
  local fake_root="$TEST_TEMP_DIR/fake-plugin-cache-first"

  mkdir -p "$fake_root/scripts"
  cat > "$fake_root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
next_phase_state=needs_uat_remediation
next_phase_slug=03-test-phase
---UAT_EXTRACT_START---
uat_extract_error=true uat_file=03-UAT.md
---UAT_EXTRACT_END---
OUT
EOF
  chmod +x "$fake_root/scripts/phase-detect.sh"
  ln -sf "$fake_root" "$link"
  rm -f "$cache_file"

  # Publish a fresh cached payload shortly after the reader starts. The fixed
  # reader waits for the cache instead of immediately breaking on symlink
  # existence and consuming the stale live phase-detect output.
  (
    sleep 0.2
    cat > "$cache_file" <<'EOF'
next_phase_state=needs_uat_remediation
next_phase_slug=03-test-phase
---UAT_EXTRACT_START---
uat_phase=03 uat_issues_total=1 uat_round=1 uat_file=03-UAT.md
P01-T2|major|Fresh cached issue|1
---UAT_EXTRACT_END---
EOF
  ) &

  cd "$TEST_TEMP_DIR"
  run bash -c '
    SESSION_KEY="'"$session_key"'"
    L="'"$link"'"
    P="'"$cache_file"'"
    PD=""
    _PD_START_TS=$(date +%s 2>/dev/null || echo 0)
    _phase_detect_cache_fresh() {
      local m=""
      [ -f "$P" ] || return 1
      m=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo "")
      [ -n "$m" ] || return 1
      [ "$m" -ge "$_PD_START_TS" ] 2>/dev/null
    }
    i=0
    while [ $i -lt 100 ]; do
      if _phase_detect_cache_fresh; then
        PD=$(cat "$P")
        break
      fi
      sleep 0.1
      i=$((i+1))
    done
    [ -z "$(printf "%s" "$PD" | tr -d "[:space:]")" ] && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ] && \
      PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
    [ -z "$(printf "%s" "$PD" | tr -d "[:space:]")" ] && [ -f "$P" ] && PD=$(cat "$P")
    if printf "%s" "$PD" | grep -q "^---UAT_EXTRACT_START---$"; then
      printf "%s\n" "$PD" | awk "/^---UAT_EXTRACT_START---$/{f=1; next} /^---UAT_EXTRACT_END---$/{exit} f{print}"
    else
      echo "no-marker"
    fi
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_phase=03 uat_issues_total=1 uat_round=1 uat_file=03-UAT.md"* ]]
  [[ "$output" == *"P01-T2|major|Fresh cached issue|1"* ]]
  [[ "$output" != *"uat_extract_error=true uat_file=03-UAT.md"* ]]

  rm -f "$link" "$cache_file"
}

@test "uat-preseed: does not fall back to stale cache after lock timeout" {
  local session_key="test-stale-cache-$$"
  local link="/tmp/.vbw-plugin-root-link-${session_key}"
  local cache_file="/tmp/.vbw-phase-detect-${session_key}.txt"
  local lock_dir="/tmp/.vbw-phase-detect-live-${session_key}.lock"
  local fake_root="$TEST_TEMP_DIR/fake-plugin-stale-cache"

  mkdir -p "$fake_root/scripts"
  cat > "$fake_root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
next_phase_state=needs_uat_remediation
next_phase_slug=03-test-phase
---UAT_EXTRACT_START---
uat_phase=03 uat_issues_total=1 uat_round=1 uat_file=03-UAT.md
P01-T2|major|Fresh live issue|1
---UAT_EXTRACT_END---
OUT
EOF
  chmod +x "$fake_root/scripts/phase-detect.sh"
  ln -sf "$fake_root" "$link"

  # Pre-existing stale cache (older than the current invocation start)
  cat > "$cache_file" <<'EOF'
next_phase_state=needs_uat_remediation
next_phase_slug=03-test-phase
---UAT_EXTRACT_START---
uat_extract_error=true uat_file=03-UAT.md
---UAT_EXTRACT_END---
EOF
  # Hold the lock so the reader cannot acquire a live-fallback writer slot.
  mkdir "$lock_dir"

  cd "$TEST_TEMP_DIR"
  run bash -c '
    SESSION_KEY="'"$session_key"'"
    L="'"$link"'"
    P="'"$cache_file"'"
    PD=""
    _PD_START_TS=$(( (stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo 0) + 1 ))
    _phase_detect_cache_fresh() {
      local m=""
      [ -f "$P" ] || return 1
      m=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo "")
      [ -n "$m" ] || return 1
      [ "$m" -ge "$_PD_START_TS" ] 2>/dev/null
    }
    i=0
    while [ $i -lt 5 ]; do
      if _phase_detect_cache_fresh; then
        PD=$(cat "$P")
        break
      fi
      sleep 0.1
      i=$((i+1))
    done
    if [ -z "$(printf "%s" "$PD" | tr -d "[:space:]")" ] && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]; then
      LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"
      i=0
      while [ $i -lt 5 ]; do
        if _phase_detect_cache_fresh; then
          PD=$(cat "$P")
          break
        fi
        if mkdir "$LOCK" 2>/dev/null; then
          PTMP="${P}.reader.$$.$RANDOM"
          PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
          if [ -n "$(printf "%s" "$PD" | tr -d "[:space:]")" ]; then
            printf "%s\n" "$PD" > "$PTMP" 2>/dev/null && mv "$PTMP" "$P" 2>/dev/null || true
          fi
          rmdir "$LOCK" 2>/dev/null || true
          break
        fi
        sleep 0.1
        i=$((i+1))
      done
    fi
    [ -z "$(printf "%s" "$PD" | tr -d "[:space:]")" ] && _phase_detect_cache_fresh && PD=$(cat "$P")
    if [ -z "$(printf "%s" "$PD" | tr -d "[:space:]")" ] || [ "$PD" = "phase_detect_error=true" ]; then
      echo "uat_extract_error=true"
      exit 0
    fi
    printf "%s\n" "$PD" | awk "/^---UAT_EXTRACT_START---$/{f=1; next} /^---UAT_EXTRACT_END---$/{exit} f{print}"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_extract_error=true"* ]]
  [[ "$output" != *"Fresh live issue"* ]]

  rmdir "$lock_dir" 2>/dev/null || true
  rm -f "$link" "$cache_file"
}

# ===========================================================================
# Milestone-style path coverage (Phase A — pre-emit milestone UAT)
# ===========================================================================

@test "extract-uat-issues: works on milestone-style phase path" {
  # Milestone paths: .vbw-planning/milestones/<slug>/phases/<NN-slug>/
  local MS_PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/milestones/v1-initial/phases/03-test-phase"
  mkdir -p "$MS_PHASE_DIR"

  cat > "$MS_PHASE_DIR/03-UAT.md" <<'EOF'
---
phase: 03
status: issues_found
issues: 2
---

## Tests

### P01-T1: First issue

- **Result:** issue
- **Issue:**
  - Description: Milestone issue one
  - Severity: critical

### P02-T1: Second issue

- **Result:** issue
- **Issue:**
  - Description: Milestone issue two
  - Severity: minor

## Summary
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$MS_PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_phase=03"* ]]
  [[ "${lines[0]}" == *"uat_issues_total=2"* ]]
  [[ "${lines[1]}" == "P01-T1|critical|Milestone issue one|1" ]]
  [[ "${lines[2]}" == "P02-T1|minor|Milestone issue two|1" ]]
}

@test "extract-uat-issues: milestone path with no UAT file" {
  local MS_PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/milestones/v2-refactor/phases/01-cleanup"
  mkdir -p "$MS_PHASE_DIR"

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$MS_PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_extract_error=no_uat_file"* ]]
}

@test "extract-uat-issues: milestone path with complete UAT" {
  local MS_PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/milestones/v1-initial/phases/05-polish"
  mkdir -p "$MS_PHASE_DIR"

  cat > "$MS_PHASE_DIR/05-UAT.md" <<'EOF'
---
phase: 05
status: complete
issues: 0
---

## Tests

### P01-T1: All good

- **Result:** pass
EOF

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$MS_PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_extract_status=complete"* ]]
}

@test "extract-uat-issues: consistency guard triggers when frontmatter says issues but awk finds none" {
  # Simulate the bug: status=issues_found and issues=1 in frontmatter,
  # but the markdown body has no parseable issue entries (e.g., all tests pass
  # or the Result/Issue markup is missing/malformed)
  create_uat_file '---
phase: 03
status: issues_found
issues: 2
---

## Tests

### P01-T1: Test with pass result

- **Plan:** 03-01 — Fix something
- **Scenario:** Do something
- **Expected:** It works
- **Result:** pass

### P01-T2: Test with no result line

- **Plan:** 03-01 — Another test
- **Scenario:** Do another thing
- **Expected:** It should work'

  cd "$TEST_TEMP_DIR"
  # Capture stderr separately to verify diagnostic message
  run bash -c "bash '$SCRIPTS_DIR/extract-uat-issues.sh' '$PHASE_DIR' 2>/tmp/.vbw-test-stderr-$$.txt"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_extract_error=true"* ]]
  # Verify stderr diagnostic includes inconsistency details
  local stderr_content
  stderr_content=$(cat /tmp/.vbw-test-stderr-$$.txt 2>/dev/null)
  [[ "$stderr_content" == *"inconsistent_status"* ]]
  [[ "$stderr_content" == *"frontmatter_issues=2"* ]]
  rm -f /tmp/.vbw-test-stderr-$$.txt
}

@test "extract-uat-issues: consistency guard does not trigger when frontmatter issues=0" {
  # status=issues_found but issues=0 is an odd state but the guard should
  # only fire when the frontmatter explicitly says there ARE issues
  create_uat_file '---
phase: 03
status: issues_found
issues: 0
---

## Tests

### P01-T1: Test

- **Result:** pass'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_issues_total=0"* ]]
  # Should NOT show error since frontmatter says 0
  [[ "$output" != *"uat_extract_error"* ]]
}

@test "extract-uat-issues: consistency guard does not fire when awk correctly finds issues" {
  create_uat_file '---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P01-T1: Failing test

- **Result:** issue
- **Issue:**
  - Description: Something is broken
  - Severity: major'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_issues_total=1"* ]]
  [[ "${lines[1]}" == "P01-T1|major|Something is broken|1" ]]
  [[ "$output" != *"uat_extract_error"* ]]
}

@test "extract-uat-issues: shared parser accepts bold Description and Severity bullets" {
  create_uat_file '---
phase: 03
status: issues_found
issues: 1
---

## Tests

### P01-T1: Styled issue

- **Result:** issue
- **Issue:**
  - **Description:** Styled issue still parses
  - **Severity:** minor'

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/extract-uat-issues.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"uat_issues_total=1"* ]]
  [[ "${lines[1]}" == "P01-T1|minor|Styled issue still parses|1" ]]
}
