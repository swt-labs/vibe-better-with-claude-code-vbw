#!/usr/bin/env bash
set -euo pipefail

# verify-claude-md-staleness.sh — Tests for CLAUDE.md VBW section staleness detection
#
# Tests:
#   1. No .vbw-planning → exit 0, not stale
#   2. No CLAUDE.md → detected as stale
#   3. Missing Code Intelligence detected
#   4. Version mismatch detected
#   5. Fresh state → not stale
#   6. --fix preserves custom heading/core/introduction
#   7. --fix refreshes exact canonical VBW sections in place
#   8. --fix writes version marker
#   9. --json output is valid JSON
#  10. session-start.sh does NOT auto-fix CLAUDE.md
#  11. doctor.md references staleness check
#  12. brownfield bootstrap preserves custom heading and code-block comments
#  13. greenfield omits Project Conventions / Commands
#  14. ### Code Intelligence prevents duplicate canonical section
#  15. # Code Intelligence prevents duplicate canonical section
#  16. #### Code Intelligence prevents duplicate canonical section
#  17. LSP guidance text without heading prevents duplicate canonical section

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-claude-md-staleness.sh"
BOOTSTRAP="$ROOT/scripts/bootstrap/bootstrap-claude.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "PASS $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "FAIL $1"
}

current_version() {
  local ver=""
  if [ -f "$ROOT/.claude-plugin/plugin.json" ]; then
    ver=$(jq -r '.version // ""' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null) || ver=""
  elif [ -f "$ROOT/VERSION" ]; then
    ver=$(tr -d '[:space:]' < "$ROOT/VERSION")
  fi
  printf '%s' "$ver"
}

make_project() {
  mkdir -p .vbw-planning
  cat > .vbw-planning/PROJECT.md <<'EOF'
# TestProject

Test description

**Core value:** Test value
EOF
}

with_tmpdir() {
  local tmp="$1"
  shift
  pushd "$tmp" >/dev/null
  "$@"
  local rc=$?
  popd >/dev/null
  rm -rf "$tmp"
  return "$rc"
}

test_no_project_not_stale() {
  echo "test" > CLAUDE.md
  if bash "$SCRIPT" --json >/tmp/claude-stale-test-1.json 2>/dev/null; then
    if grep -q '"stale":false' /tmp/claude-stale-test-1.json; then
      pass "1: no .vbw-planning → not stale"
    else
      fail "1: expected stale=false, got: $(cat /tmp/claude-stale-test-1.json)"
    fi
  else
    fail "1: no .vbw-planning should exit 0"
  fi
}

test_missing_claude_detected() {
  make_project
  if bash "$SCRIPT" --json >/tmp/claude-stale-test-2.json 2>/dev/null; then
    fail "2: missing CLAUDE.md should exit 1"
  else
    if grep -q '"reason":"no_claude_md"' /tmp/claude-stale-test-2.json; then
      pass "2: no CLAUDE.md → detected as stale"
    else
      fail "2: expected no_claude_md reason, got: $(cat /tmp/claude-stale-test-2.json)"
    fi
  fi
}

test_missing_code_intelligence_detected() {
  make_project
  cat > CLAUDE.md <<'EOF'
# TestProject

**Core value:** Test value

## Active Context

test

## VBW Rules

test

## Plugin Isolation

test
EOF

  bash "$SCRIPT" --json >/tmp/claude-stale-test-3.json 2>/dev/null || true
  if jq -e '.missing_sections | index("## Code Intelligence")' /tmp/claude-stale-test-3.json >/dev/null 2>&1; then
    pass "3: missing Code Intelligence detected"
  else
    fail "3: expected missing ## Code Intelligence, got: $(cat /tmp/claude-stale-test-3.json)"
  fi
}

test_version_mismatch_detected() {
  make_project
  bash "$BOOTSTRAP" CLAUDE.md "TestProject" "Test value" >/dev/null 2>&1
  echo "0.0.1" > .vbw-planning/.claude-md-version

  bash "$SCRIPT" --json >/tmp/claude-stale-test-4.json 2>/dev/null || true
  if jq -e '.version_mismatch == true' /tmp/claude-stale-test-4.json >/dev/null 2>&1; then
    pass "4: version mismatch detected"
  else
    fail "4: expected version_mismatch=true, got: $(cat /tmp/claude-stale-test-4.json)"
  fi
}

test_fresh_state() {
  local ver
  ver=$(current_version)

  make_project
  bash "$BOOTSTRAP" CLAUDE.md "TestProject" "Test value" >/dev/null 2>&1
  echo "$ver" > .vbw-planning/.claude-md-version

  if bash "$SCRIPT" --json >/tmp/claude-stale-test-5.json 2>/dev/null; then
    if jq -e '.stale == false' /tmp/claude-stale-test-5.json >/dev/null 2>&1; then
      pass "5: all sections + current version → not stale"
    else
      fail "5: expected stale=false, got: $(cat /tmp/claude-stale-test-5.json)"
    fi
  else
    fail "5: fresh state should exit 0"
  fi
}

test_fix_preserves_custom_heading_and_intro() {
  make_project
  cat > CLAUDE.md <<'EOF'
# Derek's Custom Claude Guide

**Core value:** My own custom value line

This intro is hand-written and must survive untouched.

## Notes

This section is mine.

## VBW Rules

old rules that should be replaced
EOF

  bash "$SCRIPT" --fix >/dev/null 2>&1 || true

  if ! grep -q '^# Derek'\''s Custom Claude Guide$' CLAUDE.md; then
    fail "6: custom top heading was rewritten"
    return
  fi

  if ! grep -q '^\*\*Core value:\*\* My own custom value line$' CLAUDE.md; then
    fail "6: custom core value line was rewritten"
    return
  fi

  if ! grep -q 'This intro is hand-written and must survive untouched.' CLAUDE.md; then
    fail "6: custom intro text was lost"
    return
  fi

  if ! grep -q '^## VBW Rules$' CLAUDE.md; then
    fail "6: refreshed VBW Rules section missing"
    return
  fi

  pass "6: --fix preserves custom heading/core/introduction"
}

test_fix_refreshes_exact_canonical_sections() {
  make_project
  cat > CLAUDE.md <<'EOF'
# Custom File

## Active Context

OLD ACTIVE CONTEXT

## VBW Rules

OLD MANAGED RULES

## Plugin Isolation

OLD ISOLATION
EOF

  bash "$SCRIPT" --fix >/dev/null 2>&1 || true

  if grep -q 'OLD MANAGED RULES\|OLD ACTIVE CONTEXT\|OLD ISOLATION' CLAUDE.md; then
    fail "7: old canonical VBW content should be replaced in place"
    return
  fi

  if ! grep -q '\*\*Work:\*\* No active milestone' CLAUDE.md; then
    fail "7: refreshed Active Context content missing"
    return
  fi

  if ! grep -q 'Always use VBW commands' CLAUDE.md; then
    fail "7: refreshed VBW Rules content missing"
    return
  fi

  if ! grep -q '^## Plugin Isolation$' CLAUDE.md; then
    fail "7: refreshed Plugin Isolation section missing"
    return
  fi

  pass "7: --fix refreshes exact canonical VBW sections in place"
}

test_fix_writes_version_marker() {
  make_project
  bash "$BOOTSTRAP" CLAUDE.md "TestProject" "Test value" >/dev/null 2>&1
  rm -f .vbw-planning/.claude-md-version

  bash "$SCRIPT" --fix >/dev/null 2>&1 || true

  if [ ! -f .vbw-planning/.claude-md-version ]; then
    fail "8: version marker not written"
    return
  fi

  if [ -z "$(tr -d '[:space:]' < .vbw-planning/.claude-md-version)" ]; then
    fail "8: version marker is empty"
    return
  fi

  pass "8: --fix writes version marker"
}

test_json_output_valid() {
  make_project
  bash "$BOOTSTRAP" CLAUDE.md "TestProject" "Test value" >/dev/null 2>&1
  echo "0.0.1" > .vbw-planning/.claude-md-version

  bash "$SCRIPT" --json >/tmp/claude-stale-test-9.json 2>/dev/null || true
  if jq empty /tmp/claude-stale-test-9.json >/dev/null 2>&1; then
    pass "9: --json output is valid JSON"
  else
    fail "9: invalid JSON output: $(cat /tmp/claude-stale-test-9.json)"
  fi
}

test_session_start_has_no_autofix() {
  if grep -q 'check-claude-md-staleness.sh --fix' "$ROOT/scripts/session-start.sh"; then
    fail "10: session-start.sh should not auto-fix CLAUDE.md"
  else
    pass "10: session-start.sh does not auto-fix CLAUDE.md"
  fi
}

test_doctor_references_staleness_check() {
  if grep -q 'CLAUDE.md sections' "$ROOT/commands/doctor.md" && grep -q 'check-claude-md-staleness' "$ROOT/commands/doctor.md"; then
    pass "11: doctor.md references CLAUDE.md staleness check"
  else
    fail "11: doctor.md missing CLAUDE.md staleness check reference"
  fi
}

test_brownfield_bootstrap_preserves_custom_heading_and_comments() {
  make_project
  cat > CLAUDE.md <<'EOF'
# My Existing Custom Guide

**Core value:** My existing custom value

Intro paragraph.

## My Scripts

```bash
#!/usr/bin/env bash
# this comment must survive
echo "hello"
```

## VBW Rules

OLD RULES
EOF

  bash "$BOOTSTRAP" CLAUDE.md "TestProject" "Test value" CLAUDE.md >/dev/null 2>&1

  if ! grep -q '^# My Existing Custom Guide$' CLAUDE.md; then
    fail "12: brownfield bootstrap rewrote custom top heading"
    return
  fi

  if ! grep -q '^\*\*Core value:\*\* My existing custom value$' CLAUDE.md; then
    fail "12: brownfield bootstrap rewrote custom core value"
    return
  fi

  if ! grep -q '# this comment must survive' CLAUDE.md; then
    fail "12: brownfield bootstrap stripped code-block comment"
    return
  fi

  pass "12: brownfield bootstrap preserves custom heading and code-block comments"
}

test_greenfield_omits_removed_sections() {
  make_project
  bash "$BOOTSTRAP" CLAUDE.md "TestProject" "Test value" >/dev/null 2>&1

  if grep -q '^## Project Conventions$\|^## Commands$' CLAUDE.md; then
    fail "13: greenfield should not emit Project Conventions or Commands"
  else
    pass "13: greenfield omits Project Conventions / Commands"
  fi
}

assert_code_intelligence_variant_prevents_duplicate() {
  local label="$1"
  local body="$2"

  make_project
  cat > CLAUDE.md <<EOF
# Custom Guide

$body

## Active Context

test

## VBW Rules

test

## Plugin Isolation

test
EOF

  bash "$SCRIPT" --json >/tmp/claude-ci-variant.json 2>/dev/null || true
  if jq -e '.missing_sections | index("## Code Intelligence")' /tmp/claude-ci-variant.json >/dev/null 2>&1; then
    fail "$label: staleness check incorrectly reported missing Code Intelligence"
    return
  fi

  bash "$SCRIPT" --fix >/dev/null 2>&1 || true

  if [ "$(grep -c '^## Code Intelligence$' CLAUDE.md 2>/dev/null || true)" -ne 0 ]; then
    fail "$label: canonical ## Code Intelligence should not be duplicated"
    return
  fi

  pass "$label"
}

test_h3_code_intelligence_variant() {
  assert_code_intelligence_variant_prevents_duplicate "14: ### Code Intelligence prevents duplicate canonical section" $'## Rules\n\n### Code Intelligence\n\nPrefer LSP over Search/Grep/Glob for semantic code navigation.'
}

test_h1_code_intelligence_variant() {
  assert_code_intelligence_variant_prevents_duplicate "15: # Code Intelligence prevents duplicate canonical section" $'# Code Intelligence\n\nPrefer LSP over Search/Grep/Glob for semantic code navigation.'
}

test_h4_code_intelligence_variant() {
  assert_code_intelligence_variant_prevents_duplicate "16: #### Code Intelligence prevents duplicate canonical section" $'## Rules\n\n#### Code Intelligence\n\nPrefer LSP over Search/Grep/Glob for semantic code navigation.'
}

test_text_only_code_intelligence_guidance() {
  assert_code_intelligence_variant_prevents_duplicate "17: LSP guidance text without heading prevents duplicate canonical section" $'## Notes\n\nPrefer LSP over Search/Grep/Glob for semantic code navigation when possible.'
}

run_all_tests() {
  with_tmpdir "$(mktemp -d)" test_no_project_not_stale
  with_tmpdir "$(mktemp -d)" test_missing_claude_detected
  with_tmpdir "$(mktemp -d)" test_missing_code_intelligence_detected
  with_tmpdir "$(mktemp -d)" test_version_mismatch_detected
  with_tmpdir "$(mktemp -d)" test_fresh_state
  with_tmpdir "$(mktemp -d)" test_fix_preserves_custom_heading_and_intro
  with_tmpdir "$(mktemp -d)" test_fix_refreshes_exact_canonical_sections
  with_tmpdir "$(mktemp -d)" test_fix_writes_version_marker
  with_tmpdir "$(mktemp -d)" test_json_output_valid
  test_session_start_has_no_autofix
  test_doctor_references_staleness_check
  with_tmpdir "$(mktemp -d)" test_brownfield_bootstrap_preserves_custom_heading_and_comments
  with_tmpdir "$(mktemp -d)" test_greenfield_omits_removed_sections
  with_tmpdir "$(mktemp -d)" test_h3_code_intelligence_variant
  with_tmpdir "$(mktemp -d)" test_h1_code_intelligence_variant
  with_tmpdir "$(mktemp -d)" test_h4_code_intelligence_variant
  with_tmpdir "$(mktemp -d)" test_text_only_code_intelligence_guidance
}

run_all_tests

echo ""
echo "==============================="
echo "TOTAL: $PASS_COUNT PASS, $FAIL_COUNT FAIL"
echo "==============================="

[ "$FAIL_COUNT" -eq 0 ] || exit 1