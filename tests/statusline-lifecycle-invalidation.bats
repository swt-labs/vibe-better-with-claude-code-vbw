#!/usr/bin/env bats
# Tests for lifecycle_artifacts_newer_than_cache() — the fast-cache invalidation
# gate that checks whether UAT/VERIFICATION/remediation state files are newer
# than the cached statusline output.

load test_helper

# Source only the functions we need from vbw-statusline.sh without executing
# the main script body. We extract the helper functions into a small shim.
setup() {
  setup_temp_dir
  export _OS=$(uname)

  # Build a minimal shim with just the functions under test
  cat > "$TEST_TEMP_DIR/lifecycle-funcs.sh" <<'SHIM'
file_mtime_epoch() {
  local path="$1"
  if [ "$_OS" = "Darwin" ]; then
    stat -f %m "$path" 2>/dev/null || echo 0
  else
    stat -c %Y "$path" 2>/dev/null || echo 0
  fi
}
SHIM
  # Append lifecycle_artifacts_newer_than_cache from the real script
  sed -n '/^lifecycle_artifacts_newer_than_cache()/,/^}/p' \
    "$SCRIPTS_DIR/vbw-statusline.sh" >> "$TEST_TEMP_DIR/lifecycle-funcs.sh"

  # shellcheck disable=SC1091
  . "$TEST_TEMP_DIR/lifecycle-funcs.sh"
}

teardown() {
  teardown_temp_dir
}

# --- Helper: create a minimal planning dir with a phase ---
create_planning_with_phase() {
  local base="$1"
  local phase_dir="$base/phases/01-test-phase"
  mkdir -p "$phase_dir"
  printf '%s\n' "$phase_dir"
}

# --- T-01: cache invalidated when artifact is strictly newer ---
@test "cache is invalidated when artifact mtime is strictly newer than cache" {
  local planning="$TEST_TEMP_DIR/planning"
  local phase_dir
  phase_dir=$(create_planning_with_phase "$planning")
  local cache_file="$TEST_TEMP_DIR/test-cache-fast"

  # Write cache first
  echo "stale-data" > "$cache_file"
  sleep 1

  # Write artifact after cache (guaranteed newer by 1s)
  echo "---" > "$phase_dir/01-VERIFICATION.md"
  echo "result: PASS" >> "$phase_dir/01-VERIFICATION.md"
  echo "---" >> "$phase_dir/01-VERIFICATION.md"

  run lifecycle_artifacts_newer_than_cache "$cache_file" "$planning"
  [ "$status" -eq 0 ]
}

# --- T-02: cache NOT invalidated when artifact is strictly older ---
@test "cache is NOT invalidated when artifact mtime is strictly older than cache" {
  local planning="$TEST_TEMP_DIR/planning"
  local phase_dir
  phase_dir=$(create_planning_with_phase "$planning")
  local cache_file="$TEST_TEMP_DIR/test-cache-fast"

  # Write artifact first
  echo "---" > "$phase_dir/01-VERIFICATION.md"
  echo "result: PASS" >> "$phase_dir/01-VERIFICATION.md"
  echo "---" >> "$phase_dir/01-VERIFICATION.md"
  sleep 1

  # Write cache after artifact (guaranteed newer by 1s)
  echo "fresh-data" > "$cache_file"

  run lifecycle_artifacts_newer_than_cache "$cache_file" "$planning"
  [ "$status" -eq 1 ]
}

# --- T-03: same-second write invalidates cache (the bug fix) ---
@test "cache is invalidated when artifact has same mtime as cache (same-second race)" {
  local planning="$TEST_TEMP_DIR/planning"
  local phase_dir
  phase_dir=$(create_planning_with_phase "$planning")
  local cache_file="$TEST_TEMP_DIR/test-cache-fast"

  # Write both in the same second — use touch with identical timestamps
  local now_epoch
  now_epoch=$(date +%s)

  echo "stale-data" > "$cache_file"
  mkdir -p "$phase_dir/remediation/uat"
  printf 'stage=execute\nround=01\nlayout=round-dir\n' > "$phase_dir/remediation/uat/.uat-remediation-stage"

  # Force identical mtimes using touch
  if [ "$_OS" = "Darwin" ]; then
    # macOS touch -t format: [[CC]YY]MMDDhhmm[.SS]
    local ts
    ts=$(date -r "$now_epoch" +%Y%m%d%H%M.%S)
    touch -t "$ts" "$cache_file"
    touch -t "$ts" "$phase_dir/remediation/uat/.uat-remediation-stage"
  else
    touch -d "@$now_epoch" "$cache_file"
    touch -d "@$now_epoch" "$phase_dir/remediation/uat/.uat-remediation-stage"
  fi

  # Verify mtimes are identical
  local cache_mt artifact_mt
  cache_mt=$(file_mtime_epoch "$cache_file")
  artifact_mt=$(file_mtime_epoch "$phase_dir/remediation/uat/.uat-remediation-stage")
  [ "$cache_mt" -eq "$artifact_mt" ]

  # With -ge fix, same-mtime should invalidate the cache
  run lifecycle_artifacts_newer_than_cache "$cache_file" "$planning"
  [ "$status" -eq 0 ]
}

# --- T-04: UAT file triggers invalidation ---
@test "UAT file triggers cache invalidation" {
  local planning="$TEST_TEMP_DIR/planning"
  local phase_dir
  phase_dir=$(create_planning_with_phase "$planning")
  local cache_file="$TEST_TEMP_DIR/test-cache-fast"

  echo "stale-data" > "$cache_file"
  sleep 1
  printf -- '---\nstatus: issues_found\n---\n' > "$phase_dir/01-UAT.md"

  run lifecycle_artifacts_newer_than_cache "$cache_file" "$planning"
  [ "$status" -eq 0 ]
}

# --- T-05: SOURCE-UAT file does NOT trigger invalidation ---
@test "SOURCE-UAT file does not trigger cache invalidation" {
  local planning="$TEST_TEMP_DIR/planning"
  local phase_dir
  phase_dir=$(create_planning_with_phase "$planning")
  local cache_file="$TEST_TEMP_DIR/test-cache-fast"

  echo "stale-data" > "$cache_file"
  sleep 1
  printf -- '---\nstatus: complete\n---\n' > "$phase_dir/01-SOURCE-UAT.md"

  # SOURCE-UAT should be excluded by the find filter
  run lifecycle_artifacts_newer_than_cache "$cache_file" "$planning"
  [ "$status" -eq 1 ]
}

# --- T-06: .uat-remediation-stage triggers invalidation ---
@test ".uat-remediation-stage triggers cache invalidation" {
  local planning="$TEST_TEMP_DIR/planning"
  local phase_dir
  phase_dir=$(create_planning_with_phase "$planning")
  local cache_file="$TEST_TEMP_DIR/test-cache-fast"

  echo "stale-data" > "$cache_file"
  sleep 1
  mkdir -p "$phase_dir/remediation/uat"
  printf 'stage=execute\nround=01\nlayout=round-dir\n' > "$phase_dir/remediation/uat/.uat-remediation-stage"

  run lifecycle_artifacts_newer_than_cache "$cache_file" "$planning"
  [ "$status" -eq 0 ]
}

# --- T-07: .qa-remediation-stage triggers invalidation ---
@test ".qa-remediation-stage triggers cache invalidation" {
  local planning="$TEST_TEMP_DIR/planning"
  local phase_dir
  phase_dir=$(create_planning_with_phase "$planning")
  local cache_file="$TEST_TEMP_DIR/test-cache-fast"

  echo "stale-data" > "$cache_file"
  sleep 1
  mkdir -p "$phase_dir/remediation/qa"
  printf 'stage=done\n' > "$phase_dir/remediation/qa/.qa-remediation-stage"

  run lifecycle_artifacts_newer_than_cache "$cache_file" "$planning"
  [ "$status" -eq 0 ]
}

# --- T-08: no phases directory returns failure ---
@test "returns failure when phases directory does not exist" {
  local planning="$TEST_TEMP_DIR/planning-no-phases"
  mkdir -p "$planning"
  local cache_file="$TEST_TEMP_DIR/test-cache-fast"
  echo "data" > "$cache_file"

  run lifecycle_artifacts_newer_than_cache "$cache_file" "$planning"
  [ "$status" -eq 1 ]
}

# --- T-09: missing cache file returns failure ---
@test "returns failure when cache file does not exist" {
  local planning="$TEST_TEMP_DIR/planning"
  create_planning_with_phase "$planning" >/dev/null

  run lifecycle_artifacts_newer_than_cache "$TEST_TEMP_DIR/nonexistent-cache" "$planning"
  [ "$status" -eq 1 ]
}
