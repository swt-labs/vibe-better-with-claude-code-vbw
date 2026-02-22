#!/usr/bin/env bats

# Tests for write-verification.sh and extract-verified-items.sh deterministic format

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# =============================================================================
# write-verification.sh: valid JSON with checks_detail
# =============================================================================

@test "write-verification: produces correct frontmatter from checks_detail" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Test","status":"PASS","evidence":"ok"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '^tier: standard' "$TEST_TEMP_DIR/out.md"
  grep -q '^result: PASS' "$TEST_TEMP_DIR/out.md"
  grep -q '^passed: 1' "$TEST_TEMP_DIR/out.md"
  grep -q '^failed: 0' "$TEST_TEMP_DIR/out.md"
  grep -q '^total: 1' "$TEST_TEMP_DIR/out.md"
  grep -q '^date: ' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: generates Must-Have Checks table" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"quick","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Feature exists","status":"PASS","evidence":"Found it"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Must-Have Checks' "$TEST_TEMP_DIR/out.md"
  grep -q 'MH-01' "$TEST_TEMP_DIR/out.md"
  grep -q 'Feature exists' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: generates Artifact Checks table" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"quick","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"ART-01","category":"artifact","description":"README present","status":"PASS","evidence":"exists"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Artifact Checks' "$TEST_TEMP_DIR/out.md"
  grep -q 'ART-01' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: generates Key Link Checks table" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"KL-01","category":"key_link","description":"Config refs module","status":"PASS","evidence":"import found"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Key Link Checks' "$TEST_TEMP_DIR/out.md"
  grep -q 'KL-01' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: generates Anti-Pattern Scan table" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"AP-01","category":"anti_pattern","description":"No TODOs","status":"PASS","evidence":"clean"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Anti-Pattern Scan' "$TEST_TEMP_DIR/out.md"
  grep -q 'AP-01' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: generates Convention Compliance table" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"CC-01","category":"convention","description":"Naming OK","status":"PASS","evidence":"follows pattern"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Convention Compliance' "$TEST_TEMP_DIR/out.md"
  grep -q 'CC-01' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: generates Requirement Mapping table" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"deep","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"RM-01","category":"requirement","description":"REQ-01 mapped","status":"PASS","evidence":"found in plan"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Requirement Mapping' "$TEST_TEMP_DIR/out.md"
  grep -q 'RM-01' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: omits empty category sections" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"quick","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Test","status":"PASS","evidence":"ok"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  ! grep -q '## Anti-Pattern Scan' "$TEST_TEMP_DIR/out.md"
  ! grep -q '## Convention Compliance' "$TEST_TEMP_DIR/out.md"
  ! grep -q '## Requirement Mapping' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: generates Summary section" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PARTIAL","checks":{"passed":1,"failed":1,"total":2},"checks_detail":[{"id":"MH-01","category":"must_have","description":"A","status":"PASS","evidence":"ok"},{"id":"MH-02","category":"must_have","description":"B","status":"FAIL","evidence":"missing"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Summary' "$TEST_TEMP_DIR/out.md"
  grep -q 'Tier.*standard' "$TEST_TEMP_DIR/out.md"
  grep -q 'Result.*PARTIAL' "$TEST_TEMP_DIR/out.md"
  grep -q 'Passed.*1/2' "$TEST_TEMP_DIR/out.md"
  grep -q 'Failed.*MH-02' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: includes Pre-existing Issues table" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"A","status":"PASS","evidence":"ok"}],"pre_existing_issues":[{"test":"testFoo","file":"src/foo.js","error":"undefined var"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Pre-existing Issues' "$TEST_TEMP_DIR/out.md"
  grep -q 'testFoo' "$TEST_TEMP_DIR/out.md"
  grep -q 'src/foo.js' "$TEST_TEMP_DIR/out.md"
}

# =============================================================================
# write-verification.sh: fallback without checks_detail
# =============================================================================

@test "write-verification: falls back to body when no checks_detail" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"quick","result":"PASS","checks":{"passed":3,"failed":0,"total":3},"body":"## Custom Content\nSome free-form text"}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '^tier: quick' "$TEST_TEMP_DIR/out.md"
  grep -q 'Custom Content' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: minimal summary when no checks_detail and no body" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"FAIL","checks":{"passed":1,"failed":1,"total":2},"failures":[{"check":"Link check"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Summary' "$TEST_TEMP_DIR/out.md"
  grep -q 'Failed.*Link check' "$TEST_TEMP_DIR/out.md"
}

# =============================================================================
# write-verification.sh: error handling
# =============================================================================

@test "write-verification: exits 1 on invalid JSON" {
  echo "not json" > "$TEST_TEMP_DIR/input.txt"
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "write-verification: exits 1 on missing required fields" {
  echo '{"payload":{"tier":"quick"}}' > "$TEST_TEMP_DIR/input.json"
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required fields"* ]]
}

@test "write-verification: exits 1 with no output path" {
  run bash -c "echo '{}' | bash '$SCRIPTS_DIR/write-verification.sh'"
  [ "$status" -eq 1 ]
}

@test "write-verification: accepts full envelope JSON" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"id":"q1","type":"qa_verdict","phase":2,"author_role":"qa","payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Test","status":"PASS","evidence":"ok"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '^phase: 2' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: accepts bare payload JSON" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Test","status":"PASS","evidence":"ok"}]}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '^result: PASS' "$TEST_TEMP_DIR/out.md"
}

# =============================================================================
# extract-verified-items.sh: deterministic format parsing
# =============================================================================

@test "extract-verified-items: parses deterministic VERIFICATION.md" {
  local pdir="$TEST_TEMP_DIR/phases/01-setup"
  mkdir -p "$pdir"
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":3,"failed":0,"total":3},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Feature A","status":"PASS","evidence":"ok"},{"id":"MH-02","category":"must_have","description":"Feature B","status":"PASS","evidence":"ok"},{"id":"ART-01","category":"artifact","description":"README","status":"PASS","evidence":"found"}]}}
JSON
  bash "$SCRIPTS_DIR/write-verification.sh" "$pdir/01-VERIFICATION.md" < "$TEST_TEMP_DIR/input.json"
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$pdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS MH-01: Feature A"* ]]
  [[ "$output" == *"PASS MH-02: Feature B"* ]]
  [[ "$output" == *"PASS ART-01: README"* ]]
  [[ "$output" == *"QA: PASS (3/3 passed"* ]]
}

@test "extract-verified-items: shows FAIL checks in deterministic format" {
  local pdir="$TEST_TEMP_DIR/phases/01-setup"
  mkdir -p "$pdir"
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"FAIL","checks":{"passed":1,"failed":1,"total":2},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Exists","status":"PASS","evidence":"ok"},{"id":"MH-02","category":"must_have","description":"Tests pass","status":"FAIL","evidence":"2 failures"}]}}
JSON
  bash "$SCRIPTS_DIR/write-verification.sh" "$pdir/01-VERIFICATION.md" < "$TEST_TEMP_DIR/input.json"
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$pdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS MH-01: Exists"* ]]
  [[ "$output" == *"FAIL MH-02: Tests pass"* ]]
  [[ "$output" == *"QA: FAIL (1/2 passed"* ]]
}

@test "extract-verified-items: handles frontmatter-only brownfield file" {
  local pdir="$TEST_TEMP_DIR/phases/01-setup"
  mkdir -p "$pdir"
  cat > "$pdir/01-VERIFICATION.md" << 'EOF'
---
phase: 1
tier: standard
result: PASS
passed: 5
failed: 0
total: 5
date: 2026-01-01
---

Some random content without tables.
EOF
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$pdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"QA: PASS (5/5 passed"* ]]
}

@test "extract-verified-items: no crash on empty phase dir" {
  local pdir="$TEST_TEMP_DIR/phases/01-setup"
  mkdir -p "$pdir"
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$pdir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract-verified-items: no crash on nonexistent dir" {
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$TEST_TEMP_DIR/nonexistent"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================================
# write-verification.sh: frontmatter field order
# =============================================================================

@test "write-verification: frontmatter fields in canonical order" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"deep","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"A","status":"PASS","evidence":"ok"}]}}
JSON
  bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  # Extract frontmatter field names in order
  local fields
  fields=$(sed -n '/^---$/,/^---$/{ /^---$/d; s/:.*//; p; }' "$TEST_TEMP_DIR/out.md" | tr '\n' ',')
  [[ "$fields" == "phase,tier,result,passed,failed,total,date," ]]
}

# =============================================================================
# write-verification.sh: edge cases from QA round 1
# =============================================================================

@test "write-verification: rejects checks_detail as object instead of array" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":{"id":"MH-01","category":"must_have","description":"X","status":"PASS","evidence":"ok"}}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checks_detail must be an array"* ]]
  # No partial output file should exist
  [ ! -f "$TEST_TEMP_DIR/out.md" ]
}

@test "write-verification: rejects entries missing id field" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"category":"must_have","description":"X","status":"PASS","evidence":"ok"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must have id and status"* ]]
}

@test "write-verification: rejects entries missing status field" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"X","evidence":"ok"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must have id and status"* ]]
}

@test "write-verification: rejects non-string status values" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"X","status":false,"evidence":"ok"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PASS|FAIL|WARN"* ]]
}

@test "write-verification: rejects whitespace-only id and status" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"   ","category":"must_have","description":"X","status":"   ","evidence":"ok"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must have id and status"* ]]
}

@test "write-verification: rejects mismatched checks counters versus checks_detail" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":2,"failed":1,"total":2},"checks_detail":[{"id":"MH-01","category":"must_have","description":"A","status":"PASS","evidence":"ok"},{"id":"MH-02","category":"must_have","description":"B","status":"PASS","evidence":"ok"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checks counters must match checks_detail"* ]]
  [ ! -f "$TEST_TEMP_DIR/out.md" ]
}

@test "write-verification: escapes pipe characters in description and evidence" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"A | B","status":"PASS","evidence":"path|line"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  # Raw pipes should not appear in the MH-01 data row (only escaped &#124;)
  local row
  row=$(grep 'MH-01' "$TEST_TEMP_DIR/out.md")
  # The row should contain escaped pipes
  [[ "$row" == *"&#124;"* ]]
  # Count pipe chars — a valid 5-col row has exactly 6 pipe delimiters
  local pipe_count
  pipe_count=$(echo "$row" | tr -cd '|' | wc -c | tr -d ' ')
  [ "$pipe_count" -eq 6 ]
}

@test "write-verification: routes unknown category to Other Checks section" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"FAIL","checks":{"passed":0,"failed":1,"total":1},"checks_detail":[{"id":"X-01","category":"mystery","description":"Mystery check","status":"FAIL","evidence":"hmm"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Other Checks' "$TEST_TEMP_DIR/out.md"
  grep -q 'X-01' "$TEST_TEMP_DIR/out.md"
  grep -q 'Mystery check' "$TEST_TEMP_DIR/out.md"
  # Should also appear in Summary failed list
  grep -q 'Failed.*X-01' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: skill_augmented uses Skill Check column label" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"SA-01","category":"skill_augmented","description":"Domain check","status":"PASS","evidence":"verified"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Skill-Augmented Checks' "$TEST_TEMP_DIR/out.md"
  grep -q '| # | ID | Skill Check | Status | Evidence |' "$TEST_TEMP_DIR/out.md"
  grep -q 'SA-01' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: unknown category items not in known sections" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":2,"failed":0,"total":2},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Real","status":"PASS","evidence":"ok"},{"id":"X-01","category":"mystery","description":"Unknown","status":"PASS","evidence":"ok"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  # MH-01 should be under Must-Have, X-01 under Other
  grep -q '## Must-Have Checks' "$TEST_TEMP_DIR/out.md"
  grep -q '## Other Checks' "$TEST_TEMP_DIR/out.md"
}

@test "write-verification: newlines in description/evidence are replaced with spaces" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"line1\nline2","status":"PASS","evidence":"err\nmore"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  local row
  row=$(grep 'MH-01' "$TEST_TEMP_DIR/out.md")
  # No literal newlines inside the row — description and evidence on same line
  local line_count
  line_count=$(echo "$row" | wc -l | tr -d ' ')
  [ "$line_count" -eq 1 ]
  # Originals collapsed to spaces
  [[ "$row" == *"line1 line2"* ]]
  [[ "$row" == *"err more"* ]]
}

@test "write-verification: pre_existing_issues pipes are escaped" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"A","status":"PASS","evidence":"ok"}],"pre_existing_issues":[{"test":"a|b","file":"c|d","error":"e|f"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '## Pre-existing Issues' "$TEST_TEMP_DIR/out.md"
  # Pipe chars in data should be escaped
  local pe_row
  pe_row=$(grep '&#124;' "$TEST_TEMP_DIR/out.md" | grep -v 'MH-01')
  [ -n "$pe_row" ]
  # Row should have exactly 4 pipe delimiters (3-col table)
  local pipe_count
  pipe_count=$(echo "$pe_row" | tr -cd '|' | wc -c | tr -d ' ')
  [ "$pipe_count" -eq 4 ]
}

@test "write-verification: pre_existing_issues newlines are stripped" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"A","status":"PASS","evidence":"ok"}],"pre_existing_issues":[{"test":"mytest","file":"foo.js","error":"line1\nline2"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  local pe_row
  pe_row=$(grep 'mytest' "$TEST_TEMP_DIR/out.md")
  local line_count
  line_count=$(echo "$pe_row" | wc -l | tr -d ' ')
  [ "$line_count" -eq 1 ]
  [[ "$pe_row" == *"line1 line2"* ]]
}

@test "write-verification: explicit jq-missing error message" {
  # Create a wrapper that shadows jq to simulate it not being found
  mkdir -p "$TEST_TEMP_DIR/fake-bin"
  # Copy essential commands but NOT jq
  for cmd in bash cat date mktemp sed printf rm mv tr wc; do
    local cmd_path
    cmd_path=$(command -v "$cmd" 2>/dev/null || true)
    [ -n "$cmd_path" ] && ln -sf "$cmd_path" "$TEST_TEMP_DIR/fake-bin/$cmd" 2>/dev/null || true
  done
  run bash -c "echo '{}' | PATH='$TEST_TEMP_DIR/fake-bin' bash '$SCRIPTS_DIR/write-verification.sh' '$TEST_TEMP_DIR/out.md'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is required"* ]]
}

@test "write-verification: no partial file on validation failure" {
  # Entries missing required fields — should fail before writing
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"category":"must_have"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 1 ]
  [ ! -f "$TEST_TEMP_DIR/out.md" ]
}

# =============================================================================
# extract-verified-items.sh: wave file support
# =============================================================================

@test "extract-verified-items: finds wave verification files" {
  local pdir="$TEST_TEMP_DIR/phases/01-setup"
  mkdir -p "$pdir"
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"quick","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Wave check","status":"PASS","evidence":"ok"}]}}
JSON
  bash "$SCRIPTS_DIR/write-verification.sh" "$pdir/01-VERIFICATION-wave1.md" < "$TEST_TEMP_DIR/input.json"
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$pdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS MH-01: Wave check"* ]]
}

@test "extract-verified-items: handles escaped pipes in table rows" {
  local pdir="$TEST_TEMP_DIR/phases/01-setup"
  mkdir -p "$pdir"
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"MH-01","category":"must_have","description":"A | B","status":"PASS","evidence":"path|line"}]}}
JSON
  bash "$SCRIPTS_DIR/write-verification.sh" "$pdir/01-VERIFICATION.md" < "$TEST_TEMP_DIR/input.json"
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$pdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS MH-01:"* ]]
  # Description should contain the original pipe char restored
  [[ "$output" == *"A | B"* ]]
}

@test "extract-verified-items: parses Other Checks section" {
  local pdir="$TEST_TEMP_DIR/phases/01-setup"
  mkdir -p "$pdir"
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"X-01","category":"custom","description":"Custom check","status":"PASS","evidence":"ok"}]}}
JSON
  bash "$SCRIPTS_DIR/write-verification.sh" "$pdir/01-VERIFICATION.md" < "$TEST_TEMP_DIR/input.json"
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$pdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS X-01: Custom check"* ]]
}

# =============================================================================
# write-verification.sh: per-category 6-column rich tables
# =============================================================================

@test "write-verification: artifact section uses 6-col when exists field present" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"ART-01","category":"artifact","description":"README.md","status":"PASS","exists":true,"contains":"## Setup"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '| # | ID | Artifact | Exists | Contains | Status |' "$TEST_TEMP_DIR/out.md"
  local row
  row=$(grep 'ART-01' "$TEST_TEMP_DIR/out.md")
  [[ "$row" == *"README.md"* ]]
  [[ "$row" == *"Yes"* ]]
  [[ "$row" == *"## Setup"* ]]
  # 6-col row has 7 pipe delimiters
  local pipe_count
  pipe_count=$(echo "$row" | tr -cd '|' | wc -c | tr -d ' ')
  [ "$pipe_count" -eq 7 ]
}

@test "write-verification: artifact exists=false renders No" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"FAIL","checks":{"passed":0,"failed":1,"total":1},"checks_detail":[{"id":"ART-01","category":"artifact","description":"CHANGELOG.md","status":"FAIL","exists":false,"contains":"## v1.0"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  local row
  row=$(grep 'ART-01' "$TEST_TEMP_DIR/out.md")
  [[ "$row" == *"No"* ]]
  [[ "$row" == *"FAIL"* ]]
}

@test "write-verification: key_link section uses 6-col when from field present" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"KL-01","category":"key_link","description":"Config refs module","status":"PASS","from":"config.js","to":"module.js","via":"import statement"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '| # | ID | From | To | Via | Status |' "$TEST_TEMP_DIR/out.md"
  local row
  row=$(grep 'KL-01' "$TEST_TEMP_DIR/out.md")
  [[ "$row" == *"config.js"* ]]
  [[ "$row" == *"module.js"* ]]
  [[ "$row" == *"import statement"* ]]
  local pipe_count
  pipe_count=$(echo "$row" | tr -cd '|' | wc -c | tr -d ' ')
  [ "$pipe_count" -eq 7 ]
}

@test "write-verification: requirement section uses 6-col when plan_ref present" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"deep","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"RM-01","category":"requirement","description":"REQ-01 implemented","status":"PASS","plan_ref":"PLAN.md T3","evidence":"function exists at line 42"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '| # | ID | Requirement | Plan Ref | Evidence | Status |' "$TEST_TEMP_DIR/out.md"
  local row
  row=$(grep 'RM-01' "$TEST_TEMP_DIR/out.md")
  [[ "$row" == *"REQ-01 implemented"* ]]
  [[ "$row" == *"PLAN.md T3"* ]]
  [[ "$row" == *"function exists at line 42"* ]]
  local pipe_count
  pipe_count=$(echo "$row" | tr -cd '|' | wc -c | tr -d ' ')
  [ "$pipe_count" -eq 7 ]
}

@test "write-verification: convention section uses 6-col when file field present" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"CC-01","category":"convention","description":"kebab-case naming","status":"PASS","file":"src/my-module.js","detail":"follows pattern"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '| # | ID | Convention | File | Status | Detail |' "$TEST_TEMP_DIR/out.md"
  local row
  row=$(grep 'CC-01' "$TEST_TEMP_DIR/out.md")
  [[ "$row" == *"kebab-case naming"* ]]
  [[ "$row" == *"src/my-module.js"* ]]
  [[ "$row" == *"follows pattern"* ]]
  local pipe_count
  pipe_count=$(echo "$row" | tr -cd '|' | wc -c | tr -d ' ')
  [ "$pipe_count" -eq 7 ]
}

@test "write-verification: key_link falls back to 5-col without from field" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"KL-01","category":"key_link","description":"Config refs module","status":"PASS","evidence":"import found"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  # Should use 5-col header with Link column
  grep -q '| # | ID | Link | Status | Evidence |' "$TEST_TEMP_DIR/out.md"
  local row
  row=$(grep 'KL-01' "$TEST_TEMP_DIR/out.md")
  local pipe_count
  pipe_count=$(echo "$row" | tr -cd '|' | wc -c | tr -d ' ')
  [ "$pipe_count" -eq 6 ]
}

@test "write-verification: convention falls back to 5-col without file field" {
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"CC-01","category":"convention","description":"Naming OK","status":"PASS","evidence":"follows pattern"}]}}
JSON
  run bash "$SCRIPTS_DIR/write-verification.sh" "$TEST_TEMP_DIR/out.md" < "$TEST_TEMP_DIR/input.json"
  [ "$status" -eq 0 ]
  grep -q '| # | ID | Convention | Status | Evidence |' "$TEST_TEMP_DIR/out.md"
  local row
  row=$(grep 'CC-01' "$TEST_TEMP_DIR/out.md")
  local pipe_count
  pipe_count=$(echo "$row" | tr -cd '|' | wc -c | tr -d ' ')
  [ "$pipe_count" -eq 6 ]
}

# =============================================================================
# extract-verified-items.sh: 6-column table parsing
# =============================================================================

@test "extract-verified-items: parses 6-col key_link table" {
  local pdir="$TEST_TEMP_DIR/phases/01-setup"
  mkdir -p "$pdir"
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"KL-01","category":"key_link","description":"Config refs module","status":"PASS","from":"config.js","to":"module.js","via":"import"}]}}
JSON
  bash "$SCRIPTS_DIR/write-verification.sh" "$pdir/01-VERIFICATION.md" < "$TEST_TEMP_DIR/input.json"
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$pdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS KL-01: config.js"* ]]
}

@test "extract-verified-items: parses 6-col artifact table" {
  local pdir="$TEST_TEMP_DIR/phases/01-setup"
  mkdir -p "$pdir"
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PASS","checks":{"passed":1,"failed":0,"total":1},"checks_detail":[{"id":"ART-01","category":"artifact","description":"README.md","status":"PASS","exists":true,"contains":"Setup section"}]}}
JSON
  bash "$SCRIPTS_DIR/write-verification.sh" "$pdir/01-VERIFICATION.md" < "$TEST_TEMP_DIR/input.json"
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$pdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS ART-01: README.md"* ]]
}

@test "extract-verified-items: parses 6-col convention table (status at col 6)" {
  local pdir="$TEST_TEMP_DIR/phases/01-setup"
  mkdir -p "$pdir"
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"FAIL","checks":{"passed":0,"failed":1,"total":1},"checks_detail":[{"id":"CC-01","category":"convention","description":"kebab-case","status":"FAIL","file":"src/BadName.js","detail":"uppercase not allowed"}]}}
JSON
  bash "$SCRIPTS_DIR/write-verification.sh" "$pdir/01-VERIFICATION.md" < "$TEST_TEMP_DIR/input.json"
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$pdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FAIL CC-01: kebab-case"* ]]
}

@test "extract-verified-items: parses mixed 5-col and 6-col sections" {
  local pdir="$TEST_TEMP_DIR/phases/01-setup"
  mkdir -p "$pdir"
  cat > "$TEST_TEMP_DIR/input.json" << 'JSON'
{"payload":{"tier":"standard","result":"PARTIAL","checks":{"passed":2,"failed":1,"total":3},"checks_detail":[{"id":"MH-01","category":"must_have","description":"Feature A","status":"PASS","evidence":"ok"},{"id":"KL-01","category":"key_link","description":"Link check","status":"PASS","from":"a.js","to":"b.js","via":"import"},{"id":"ART-01","category":"artifact","description":"README.md","status":"FAIL","exists":false,"contains":"Setup"}]}}
JSON
  bash "$SCRIPTS_DIR/write-verification.sh" "$pdir/01-VERIFICATION.md" < "$TEST_TEMP_DIR/input.json"
  run bash "$SCRIPTS_DIR/extract-verified-items.sh" "$pdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS MH-01: Feature A"* ]]
  [[ "$output" == *"PASS KL-01: a.js"* ]]
  [[ "$output" == *"FAIL ART-01: README.md"* ]]
}
