#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/repo/Sources/Services"
  cd "$TEST_TEMP_DIR/repo" || exit 1
  git init -q
  git config user.name "VBW Test"
  git config user.email "vbw-tests@example.com"
  cat > Sources/Services/SplitTransferService.swift <<'EOF'
import SwiftData

struct SplitTransferService {
  let context: ModelContext
  let schema: VersionedSchema.Type
}
EOF
  git add Sources/Services/SplitTransferService.swift
  git commit -qm "seed repo"
}

teardown() {
  teardown_temp_dir
}

@test "debug-skill-enrichment: concrete service cue surfaces likely file and markers" {
  run bash -c "cd '$TEST_TEMP_DIR/repo' && printf '%s' 'Reverse split issue in SplitTransferService' | bash '$SCRIPTS_DIR/debug-skill-enrichment.sh'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [ "$(echo "$output" | jq -r '.triggered')" = "true" ]
  [[ "$(echo "$output" | jq -r '.summary')" == *"SplitTransferService"* ]]
  [[ "$(echo "$output" | jq -r '.matched_files[0]')" == *"SplitTransferService.swift" ]]
  [[ "$(echo "$output" | jq -r '.markers[]')" == *"import SwiftData"* || "$(echo "$output" | jq -r '.markers[]')" == *"ModelContext"* ]]
  echo "$output" | jq -e '.markers | index("ModelContext")' >/dev/null
  echo "$output" | jq -e '.markers | index("VersionedSchema")' >/dev/null
}

@test "debug-skill-enrichment: vague bug text stays a no-op" {
  run bash -c "cd '$TEST_TEMP_DIR/repo' && printf '%s' 'App crashes sometimes when things happen' | bash '$SCRIPTS_DIR/debug-skill-enrichment.sh'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "no_signal" ]
  [ "$(echo "$output" | jq -r '.triggered')" = "false" ]
  [ "$(echo "$output" | jq '.matched_files | length')" -eq 0 ]
}

@test "debug-skill-enrichment: query tokens are treated as data, not shell code" {
  local sentinel="/tmp/vbw-524-enrichment-sentinel-$$"
  local query
  local query_file="$TEST_TEMP_DIR/query.txt"
  rm -f "$sentinel"
  query="Investigate \$(touch\${IFS}${sentinel}) SplitTransferService"
  printf '%s' "$query" > "$query_file"

  run bash -c "cd '$TEST_TEMP_DIR/repo' && cat '$query_file' | bash '$SCRIPTS_DIR/debug-skill-enrichment.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$sentinel" ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [[ "$(echo "$output" | jq -r '.matched_files[0]')" == *"SplitTransferService.swift" ]]
}

@test "debug-skill-enrichment: leading-dash filename cue is treated as a pattern, not an option" {
  mkdir -p "$TEST_TEMP_DIR/repo/Sources/Helpers"
  cat > "$TEST_TEMP_DIR/repo/Sources/Helpers/-ReverseSplitHelper.swift" <<'EOF'
import SwiftData
struct ReverseSplitHelper {}
EOF
  (
    cd "$TEST_TEMP_DIR/repo" || exit 1
    git add Sources/Helpers/-ReverseSplitHelper.swift
  )

  run bash -c "cd '$TEST_TEMP_DIR/repo' && printf '%s' '-ReverseSplitHelper.swift crash path' | bash '$SCRIPTS_DIR/debug-skill-enrichment.sh'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "ok" ]
  [[ "$(echo "$output" | jq -r '.matched_files[0]')" == *"-ReverseSplitHelper.swift" ]]
}