#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/.vbw-planning/phases/03-test"
  mkdir -p "$PHASE_DIR/remediation/uat/round-03"
  SCRIPT="$SCRIPTS_DIR/track-uat-deviations.sh"
}

teardown() {
  teardown_temp_dir
}

make_no_jq_path() {
  local shim_dir="$TEST_TEMP_DIR/no-jq-bin"
  local cmd
  mkdir -p "$shim_dir"
  for cmd in awk shasum sha256sum openssl; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ln -sf "$(command -v "$cmd")" "$shim_dir/$cmd"
    fi
  done
  printf '%s' "$shim_dir"
}

write_state_with_empty_todos() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# Test Project

## Current

Phase 03

## Todos

None.

## Done
EOF
}

write_legacy_state_with_pending_and_completed_todos() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# Test Project

## Current

Phase 03

## Todos

### Pending Todos

- Existing pending todo (added 2026-04-01) (ref:11111111)

### Completed Todos

- Completed todo that must stay separate (added 2026-04-01) (ref:22222222)

## Done
EOF
}

write_state_with_existing_flat_todos() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# Test Project

## Current

Phase 03

## Todos

- Existing manual todo (added 2026-04-01) (ref:11111111)

## Done
EOF
}

write_accepted_uat() {
  local sig="$1"
  local result="${2:-pass}"
  local disposition="${3:-accepted-process-exception}"
  local include_metadata="${4:-yes}"
  local uat_path="$PHASE_DIR/remediation/uat/round-03/R03-UAT.md"

  {
    printf '%s\n' '---'
    printf '%s\n' 'status: in_progress'
    printf '%s\n' '---'
    printf '\n%s\n\n' '## Tests'
    printf '%s\n\n' '### D01: Review summary deviation'
    printf '%s\n' '- **Source:** Summary deviation review'
    if [ "$include_metadata" = yes ]; then
      printf -- '- **Deviation Signature:** %s\n' "$sig"
      printf '%s\n' '- **Source Plan:** R03'
      printf '%s\n' '- **Source Summary:** remediation/uat/round-03/R03-SUMMARY.md'
      printf '%s\n' '- **Deviation:** Full-project SwiftLint unavailable'
    fi
    printf -- '- **Result:** %s\n' "$result"
    printf -- '- **Disposition:** %s\n' "$disposition"
  } > "$uat_path"
}

extract_output_value() {
  local key="$1"
  printf '%s\n' "$output" | awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2); exit}'
}

@test "shared todo section assertion fails closed for malformed STATE fixtures" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# Test Project

## Current
Phase 03

## Done
EOF
  run assert_no_blank_lines_in_state_section '^## Todos$' '^## '
  [ "$status" -ne 0 ]

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# Test Project

## Todos
- Existing todo
EOF
  run assert_no_blank_lines_in_state_section '^## Todos$' '^## '
  [ "$status" -ne 0 ]

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# Test Project

## Todos
- Existing todo

- Another todo
## Done
EOF
  run assert_no_blank_lines_in_state_section '^## Todos$' '^## '
  [ "$status" -ne 0 ]
}

@test "track-uat-deviations: signature is stable for source identity and text" {
  run bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable"
  [ "$status" -eq 0 ]
  first="$output"

  run bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "track-uat-deviations: record-from-uat stores accepted process-exception D entries" {
  local sig
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  cat > "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" <<EOF
---
status: complete
---

## Tests

### D01: Review summary deviation

- **Source:** Summary deviation review
- **Deviation Signature:** $sig
- **Source Plan:** R03
- **Source Summary:** remediation/uat/round-03/R03-SUMMARY.md
- **Deviation:** Full-project SwiftLint unavailable
- **Result:** pass
- **Disposition:** accepted-process-exception

### D02: Actual issue

- **Deviation Signature:** ignored
- **Source Plan:** R03
- **Source Summary:** remediation/uat/round-03/R03-SUMMARY.md
- **Deviation:** Actual bug
- **Result:** issue
- **Disposition:** blocking
EOF

  run bash "$SCRIPT" record-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md"
  [ "$status" -eq 0 ]

  local registry="$PHASE_DIR/remediation/uat/accepted-deviations.json"
  [ -f "$registry" ]
  [ "$(jq -r '.accepted | length' "$registry")" = "1" ]
  [ "$(jq -r '.accepted[0].signature' "$registry")" = "$sig" ]
  [ "$(jq -r '.accepted[0].disposition' "$registry")" = "accepted-process-exception" ]

  run bash "$SCRIPT" accepted-signatures "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$sig" ]
}

@test "track-uat-deviations: record-from-uat preserves JSON control characters in accepted D fields" {
  local sig source_plan source_path deviation registry
  source_plan=$'R03\tmanual'
  source_path=$'remediation/uat/round-03/R03-SUMMARY.md\tartifact'
  deviation=$'Full-project\tSwiftLint unavailable'
  sig=$(bash "$SCRIPT" signature "$source_plan" "$source_path" "$deviation")
  registry="$PHASE_DIR/remediation/uat/accepted-deviations.json"

  {
    printf '%s\n' '---'
    printf '%s\n' 'status: complete'
    printf '%s\n' '---'
    printf '\n%s\n\n' '## Tests'
    printf '%s\n\n' '### D01: Review summary deviation'
    printf '%s\n' '- **Source:** Summary deviation review'
    printf -- '- **Deviation Signature:** %s\n' "$sig"
    printf -- '- **Source Plan:** %s\n' "$source_plan"
    printf -- '- **Source Summary:** %s\n' "$source_path"
    printf -- '- **Deviation:** %s\n' "$deviation"
    printf '%s\n' '- **Result:** pass'
    printf '%s\n' '- **Disposition:** accepted-process-exception'
  } > "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md"

  run bash "$SCRIPT" record-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md"
  [ "$status" -eq 0 ]

  [ -f "$registry" ]
  [ "$(jq -r '.accepted | length' "$registry")" = "1" ]
  [ "$(jq -r '.accepted[0].signature' "$registry")" = "$sig" ]
  [ "$(jq -r '.accepted[0].source_plan' "$registry")" = "$source_plan" ]
  [ "$(jq -r '.accepted[0].source_path' "$registry")" = "$source_path" ]
  [ "$(jq -r '.accepted[0].text' "$registry")" = "$deviation" ]

  run bash "$SCRIPT" accepted-signatures "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$sig" ]
}

@test "track-uat-deviations: signature does not require jq" {
  local no_jq_path expected
  no_jq_path=$(make_no_jq_path)
  expected=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")

  run env PATH="$no_jq_path" /bin/bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "track-uat-deviations: accepted-signatures fails open when jq is unavailable" {
  local no_jq_path registry sig
  no_jq_path=$(make_no_jq_path)
  registry="$PHASE_DIR/remediation/uat/accepted-deviations.json"
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  cat > "$registry" <<EOF
{"schema_version":1,"phase":"03-test","accepted":[{"signature":"$sig"}]}
EOF

  run --separate-stderr env PATH="$no_jq_path" /bin/bash "$SCRIPT" accepted-signatures "$PHASE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [[ "$stderr" == *"jq not available"* ]]
  [[ "$stderr" == *"continuing without accepted signatures"* ]]
}

@test "track-uat-deviations: record-from-uat fails open without registry side effects when jq is unavailable" {
  local no_jq_path sig registry
  no_jq_path=$(make_no_jq_path)
  registry="$PHASE_DIR/remediation/uat/accepted-deviations.json"
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  cat > "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" <<EOF
---
status: complete
---

## Tests

### D01: Review summary deviation

- **Source:** Summary deviation review
- **Deviation Signature:** $sig
- **Source Plan:** R03
- **Source Summary:** remediation/uat/round-03/R03-SUMMARY.md
- **Deviation:** Full-project SwiftLint unavailable
- **Result:** pass
- **Disposition:** accepted-process-exception
EOF

  run --separate-stderr env PATH="$no_jq_path" /bin/bash "$SCRIPT" record-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [[ "$stderr" == *"jq not available"* ]]
  [[ "$stderr" == *"skipping accepted deviation registry sync"* ]]
  [ ! -e "$registry" ]
}

@test "track-uat-deviations: todo-from-uat adds UAT deviation todo and detail from phase root" {
  local sig today ref details unrelated_dir
  write_state_with_empty_todos
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  write_accepted_uat "$sig"
  today=$(date +%Y-%m-%d)
  unrelated_dir="$TEST_TEMP_DIR/unrelated-cwd"
  mkdir -p "$unrelated_dir"

  run env VBW_PLANNING_DIR="$TEST_TEMP_DIR/bogus-planning" bash -c 'cd "$1" && bash "$2" todo-from-uat "$3" "$4" D01' _ \
    "$unrelated_dir" \
    "$SCRIPT" \
    "$PHASE_DIR" \
    "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"todo_status=added"* ]]
  [[ "$output" == *"detail_status=ok"* ]]
  ref=$(extract_output_value todo_ref)
  [[ "$ref" =~ ^[a-f0-9]{8}$ ]]

  grep -Fq -- "- [UAT-DEVIATION] R03: Full-project SwiftLint unavailable" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  grep -Fq -- "(added $today) (ref:$ref)" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  ! grep -Fxq 'None.' "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  assert_no_blank_lines_in_state_section '^## Todos$' '^## '

  details="$TEST_TEMP_DIR/.vbw-planning/todo-details.json"
  [ -f "$details" ]
  [ "$(jq -r --arg ref "$ref" '.items[$ref].source' "$details")" = "uat-deviation" ]
  [ "$(jq -r --arg ref "$ref" '.items[$ref].uat_deviation.signature' "$details")" = "$sig" ]
  [ ! -e "$TEST_TEMP_DIR/bogus-planning/todo-details.json" ]
}

@test "track-uat-deviations: todo-from-uat keeps detail paths phase-relative with trailing slash phase dir" {
  local sig ref details
  write_state_with_empty_todos
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  write_accepted_uat "$sig"

  run bash "$SCRIPT" todo-from-uat "${PHASE_DIR}/" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" D01
  [ "$status" -eq 0 ]
  [[ "$output" == *"todo_status=added"* ]]
  [[ "$output" == *"detail_status=ok"* ]]
  ref=$(extract_output_value todo_ref)
  [[ "$ref" =~ ^[a-f0-9]{8}$ ]]

  details="$TEST_TEMP_DIR/.vbw-planning/todo-details.json"
  [ "$(jq -r --arg ref "$ref" '.items[$ref].context | contains("UAT checkpoint: remediation/uat/round-03/R03-UAT.md#D01.")' "$details")" = "true" ]
  [ "$(jq -r --arg ref "$ref" '.items[$ref].files | index("remediation/uat/round-03/R03-SUMMARY.md") != null' "$details")" = "true" ]
  [ "$(jq -r --arg ref "$ref" '.items[$ref].files | index("remediation/uat/round-03/R03-UAT.md") != null' "$details")" = "true" ]
  [ "$(jq -r --arg ref "$ref" '.items[$ref].files | index("R03-UAT.md") == null' "$details")" = "true" ]
}

@test "track-uat-deviations: todo-from-uat appends flat todo without blank separators" {
  local sig ref today todos_block expected_block
  write_state_with_existing_flat_todos
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  write_accepted_uat "$sig"
  today=$(date +%Y-%m-%d)

  run bash "$SCRIPT" todo-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" D01
  [ "$status" -eq 0 ]
  [[ "$output" == *"todo_status=added"* ]]
  ref=$(extract_output_value todo_ref)

  todos_block=$(awk '/^## Todos$/ { found=1; next } found && /^## / { exit } found { print }' "$TEST_TEMP_DIR/.vbw-planning/STATE.md")
  expected_block=$'- Existing manual todo (added 2026-04-01) (ref:11111111)\n'
  expected_block+="- [UAT-DEVIATION] R03: Full-project SwiftLint unavailable (phase 03, see remediation/uat/round-03/R03-SUMMARY.md) (added ${today}) (ref:${ref})"
  [ "$todos_block" = "$expected_block" ]
  assert_no_blank_lines_in_state_section '^## Todos$' '^## '
}

@test "track-uat-deviations: todo-from-uat dedupes repeated accepted deviation by ref" {
  local sig ref
  write_state_with_empty_todos
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  write_accepted_uat "$sig"

  run bash "$SCRIPT" todo-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" D01
  [ "$status" -eq 0 ]
  ref=$(extract_output_value todo_ref)

  run bash "$SCRIPT" todo-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" D01
  [ "$status" -eq 0 ]
  [[ "$output" == *"todo_status=already_tracked"* ]]
  [ "$(grep -cF "(ref:$ref)" "$TEST_TEMP_DIR/.vbw-planning/STATE.md")" = "1" ]
}

@test "track-uat-deviations: todo-from-uat inserts legacy todos before completed section" {
  local sig ref pending_block completed_block list_output
  write_legacy_state_with_pending_and_completed_todos
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  write_accepted_uat "$sig"

  run bash "$SCRIPT" todo-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" D01
  [ "$status" -eq 0 ]
  [[ "$output" == *"todo_status=added"* ]]
  ref=$(extract_output_value todo_ref)

  pending_block=$(awk '/^### Pending Todos$/ { found=1; next } found && /^### Completed Todos$/ { exit } found { print }' "$TEST_TEMP_DIR/.vbw-planning/STATE.md")
  completed_block=$(awk '/^### Completed Todos$/ { found=1; next } found && /^## / { exit } found { print }' "$TEST_TEMP_DIR/.vbw-planning/STATE.md")
  [[ "$pending_block" == *"[UAT-DEVIATION]"* ]]
  [[ "$pending_block" == *"(ref:$ref)"* ]]
  [[ "$completed_block" != *"[UAT-DEVIATION]"* ]]
  assert_no_blank_lines_in_state_section '^### Pending Todos$' '(^### Completed Todos$)|(^## )'

  list_output=$(cd "$TEST_TEMP_DIR" && bash "$SCRIPTS_DIR/list-todos.sh")
  [ "$(printf '%s' "$list_output" | jq -r '.section')" = "### Pending Todos" ]
  [ "$(printf '%s' "$list_output" | jq --arg ref "$ref" '[.items[] | select(.ref == $ref and (.line | contains("[UAT-DEVIATION]")))] | length')" = "1" ]
}

@test "track-uat-deviations: todo-from-uat does not promote non-accepted D entries" {
  local sig
  write_state_with_empty_todos
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  write_accepted_uat "$sig" "issue" "rejected-by-user"

  run bash "$SCRIPT" todo-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" D01
  [ "$status" -eq 0 ]
  [[ "$output" == *"todo_status=not_accepted"* ]]
  ! grep -Fq '[UAT-DEVIATION]' "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-uat-deviations: todo-from-uat reports missing metadata for absent D entry" {
  local sig
  write_state_with_empty_todos
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  write_accepted_uat "$sig"

  run bash "$SCRIPT" todo-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" D02
  [ "$status" -eq 0 ]
  [[ "$output" == *"todo_status=missing_metadata"* ]]
  ! grep -Fq '[UAT-DEVIATION]' "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  [ ! -e "$TEST_TEMP_DIR/.vbw-planning/todo-details.json" ]
}

@test "track-uat-deviations: todo-from-uat fails open when STATE update fails" {
  local sig shim_dir tmp_leftovers
  write_state_with_empty_todos
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  write_accepted_uat "$sig"
  shim_dir="$TEST_TEMP_DIR/mv-fail-bin"
  mkdir -p "$shim_dir"
  cat > "$shim_dir/mv" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$shim_dir/mv"

  run env PATH="$shim_dir:$PATH" bash "$SCRIPT" todo-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" D01
  [ "$status" -eq 0 ]
  [[ "$output" == *"todo_status=state_update_failed"* ]]
  [[ "$output" != *"todo_status=already_tracked"* ]]
  [[ "$output" != *"todo_status=added"* ]]
  [[ "$output" == *"detail_status=skipped"* ]]
  [[ "$output" == *"todo_warning=STATE.md todo update failed; todo not persisted"* ]]
  ! grep -Fq '[UAT-DEVIATION]' "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  [ ! -e "$TEST_TEMP_DIR/.vbw-planning/todo-details.json" ]
  tmp_leftovers=$(find "$TEST_TEMP_DIR/.vbw-planning" -name 'STATE.md.tmp.*' -print -quit)
  [ -z "$tmp_leftovers" ]
}

@test "track-uat-deviations: insert_todo_line guards quiet grep status checks" {
  run awk '
    /^insert_todo_line\(\) \{/ { in_function=1 }
    in_function && /^[[:space:]]*(grep -qF|grep -Eq)/ {
      pending_standalone_grep = NR
      next
    }
    in_function && pending_standalone_grep && /grep_status=\$\?/ {
      printf "standalone quiet grep before grep_status at line %d\n", pending_standalone_grep
      exit 1
    }
    in_function { pending_standalone_grep = 0 }
    in_function && /^}/ { exit 0 }
  ' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "track-uat-deviations: todo-from-uat reports missing metadata for malformed D entries" {
  local sig
  write_state_with_empty_todos
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  write_accepted_uat "$sig" "pass" "accepted-process-exception" "no"

  run bash "$SCRIPT" todo-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" D01
  [ "$status" -eq 0 ]
  [[ "$output" == *"todo_status=missing_metadata"* ]]
  ! grep -Fq '[UAT-DEVIATION]' "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}

@test "track-uat-deviations: todo-from-uat fails open when STATE.md is missing" {
  local sig
  rm -f "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  write_accepted_uat "$sig"

  run bash "$SCRIPT" todo-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" D01
  [ "$status" -eq 0 ]
  [[ "$output" == *"todo_status=no_state_file"* ]]
  [ ! -e "$TEST_TEMP_DIR/.vbw-planning/todo-details.json" ]
}

@test "track-uat-deviations: todo-from-uat keeps STATE todo when detail registry update fails" {
  local sig ref
  write_state_with_empty_todos
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/todo-details.json"
  sig=$(bash "$SCRIPT" signature "R03" "remediation/uat/round-03/R03-SUMMARY.md" "Full-project SwiftLint unavailable")
  write_accepted_uat "$sig"

  run bash "$SCRIPT" todo-from-uat "$PHASE_DIR" "$PHASE_DIR/remediation/uat/round-03/R03-UAT.md" D01
  [ "$status" -eq 0 ]
  [[ "$output" == *"todo_status=added"* ]]
  [[ "$output" == *"detail_status=warning"* ]]
  ref=$(extract_output_value todo_ref)
  grep -Fq -- "(ref:$ref)" "$TEST_TEMP_DIR/.vbw-planning/STATE.md"
}
