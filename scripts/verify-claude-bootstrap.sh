#!/usr/bin/env bash
set -euo pipefail

# verify-claude-bootstrap.sh — Regression checks for bootstrap-claude.sh
#
# Usage: bash scripts/verify-claude-bootstrap.sh
# Exit: 0 if all pass, 1 if any fail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="$ROOT/scripts/bootstrap/bootstrap-claude.sh"

PASS=0
FAIL=0

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $label"
    FAIL=$((FAIL + 1))
  fi
}

check_absent() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  FAIL  $label"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS  $label"
    PASS=$((PASS + 1))
  fi
}

echo "=== verify-claude-bootstrap ==="

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT="$TMP_DIR/CLAUDE.md"

# 1) Greenfield generation
bash "$BOOTSTRAP" "$OUT" "Demo Project" "Demo core value"
check "greenfield creates output" test -f "$OUT"
check "greenfield has project title" grep -q '^# Demo Project$' "$OUT"
check "greenfield has core value" grep -q '^\*\*Core value:\*\* Demo core value$' "$OUT"
check "greenfield has Active Context" grep -q '^## Active Context$' "$OUT"
check "greenfield has Code Intelligence" grep -q '^## Code Intelligence$' "$OUT"
check "greenfield has Plugin Isolation" grep -q '^## Plugin Isolation$' "$OUT"
check_absent "greenfield omits Key Decisions (tracked in .vbw-planning/)" grep -q '^## Key Decisions$' "$OUT"

# 2) Brownfield preservation + managed section replacement
mkdir -p "$TMP_DIR/.vbw-planning"
cat > "$TMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| _(No decisions yet)_ | | |

## Todos
EOF

cat > "$TMP_DIR/existing.md" <<'EOF'
# Legacy Project

**Core value:** Legacy value

## Custom Notes
Keep this section.

## VBW Rules
OLD MANAGED CONTENT SHOULD BE REPLACED

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| Use widgets | 2025-01-01 | They work |

## Codebase Intelligence
OLD GSD CONTENT SHOULD BE STRIPPED

## Project Reference
OLD GSD PROJECT REFERENCE

## GSD Rules
OLD GSD RULES

## GSD Context
OLD GSD CONTEXT

## What This Is
OLD GSD WHAT THIS IS

## Core Value
OLD GSD CORE VALUE HEADER

## Context
OLD GSD CONTEXT HEADER

## Constraints
OLD GSD CONSTRAINTS HEADER

## Team Notes
Keep this too.
EOF

bash "$BOOTSTRAP" "$TMP_DIR/CLAUDE.md" "Demo Project" "Demo core value" "$TMP_DIR/existing.md"
OUT="$TMP_DIR/CLAUDE.md"
check "brownfield preserves custom title" grep -q '^# Legacy Project$' "$OUT"
check "brownfield preserves custom core value" grep -q '^\*\*Core value:\*\* Legacy value$' "$OUT"
check "brownfield preserves custom section" grep -q '^## Custom Notes$' "$OUT"
check "brownfield preserves team section" grep -q '^## Team Notes$' "$OUT"
check_absent "brownfield strips old managed VBW content" grep -q 'OLD MANAGED CONTENT SHOULD BE REPLACED' "$OUT"
check_absent "brownfield strips deprecated Key Decisions section" grep -q '^## Key Decisions$' "$OUT"
check_absent "brownfield strips deprecated Key Decisions content" grep -q 'Use widgets' "$OUT"
check "brownfield migrates Key Decisions data to STATE.md" grep -q 'Use widgets' "$TMP_DIR/.vbw-planning/STATE.md"
check_absent "brownfield strips old managed GSD section" grep -q '^## Codebase Intelligence$' "$OUT"

for header in \
  "## Codebase Intelligence" \
  "## Project Reference" \
  "## GSD Rules" \
  "## GSD Context" \
  "## What This Is" \
  "## Core Value" \
  "## Context" \
  "## Constraints"; do
  check_absent "brownfield strips fingerprinted $header" grep -q "^${header}$" "$OUT"
done

VBW_RULES_COUNT="$(grep -c '^## VBW Rules$' "$OUT")"
if [ "$VBW_RULES_COUNT" -eq 1 ]; then
  echo "  PASS  brownfield has one VBW Rules section"
  PASS=$((PASS + 1))
else
  echo "  FAIL  brownfield has one VBW Rules section (found $VBW_RULES_COUNT)"
  FAIL=$((FAIL + 1))
fi

# 3) Idempotency: regenerate from generated file should be stable
cp "$OUT" "$TMP_DIR/before.md"
bash "$BOOTSTRAP" "$OUT" "Demo Project" "Demo core value" "$OUT"
if cmp -s "$TMP_DIR/before.md" "$OUT"; then
  echo "  PASS  idempotent regeneration"
  PASS=$((PASS + 1))
else
  echo "  FAIL  idempotent regeneration"
  FAIL=$((FAIL + 1))
fi

# 4) Preserve generic custom Context/Constraints without strong GSD fingerprint
cat > "$TMP_DIR/custom-generic.md" <<'EOF'
# Team Project

**Core value:** Team core value

## Context
This is team-specific context and should be preserved.

## Constraints
These are team-specific constraints and should be preserved.
EOF

bash "$BOOTSTRAP" "$OUT" "Team Project" "Team core value" "$TMP_DIR/custom-generic.md"
check "preserve custom generic Context section" grep -q '^## Context$' "$OUT"
check "preserve custom generic Constraints section" grep -q '^## Constraints$' "$OUT"
check "preserve custom generic Context content" grep -q 'team-specific context' "$OUT"
check "preserve custom generic Constraints content" grep -q 'team-specific constraints' "$OUT"

# 5) Edge case: empty PROJECT_NAME and CORE_VALUE should be rejected
check_absent "rejects empty PROJECT_NAME" bash "$BOOTSTRAP" "$OUT" "" "Some value"
check_absent "rejects empty CORE_VALUE" bash "$BOOTSTRAP" "$OUT" "Some Name" ""

# 6) Deprecated section migration: data rows migrate to STATE.md
mkdir -p "$TMP_DIR/.vbw-planning"
cat > "$TMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| _(No decisions yet)_ | | |

## Todos
EOF

cat > "$TMP_DIR/with-decisions.md" <<'EOF'
# Test Project

**Core value:** Test value

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| Use widgets | 2025-01-01 | They work |

## Custom Section
Keep this.
EOF

MIGRATE_OUTPUT="$(bash "$BOOTSTRAP" "$TMP_DIR/CLAUDE.md" "Test Project" "Test value" "$TMP_DIR/with-decisions.md" 2>&1 >/dev/null)"
if echo "$MIGRATE_OUTPUT" | grep -q 'Migrated 1 Key Decisions row(s).*STATE.md'; then
  echo "  PASS  deprecated section with data emits migration notice"
  PASS=$((PASS + 1))
else
  echo "  FAIL  deprecated section with data emits migration notice (got: $MIGRATE_OUTPUT)"
  FAIL=$((FAIL + 1))
fi

check_absent "migrated Key Decisions stripped from CLAUDE.md" grep -q '^## Key Decisions$' "$TMP_DIR/CLAUDE.md"
check "migrated data row appears in STATE.md" grep -q 'Use widgets' "$TMP_DIR/.vbw-planning/STATE.md"
check_absent "placeholder row removed from STATE.md" grep -q 'No decisions yet' "$TMP_DIR/.vbw-planning/STATE.md"

# F1/F5: Validate migrated table is contiguous (no blank line between separator and data)
SEPARATOR_LINE=$(grep -n '^|[-|[:space:]]*|$' "$TMP_DIR/.vbw-planning/STATE.md" | head -1 | cut -d: -f1)
DATA_LINE=$(grep -n 'Use widgets' "$TMP_DIR/.vbw-planning/STATE.md" | head -1 | cut -d: -f1)
EXPECTED_DATA_LINE=$((SEPARATOR_LINE + 1))
if [[ "$DATA_LINE" -eq "$EXPECTED_DATA_LINE" ]]; then
  echo "  PASS  migrated table rows are contiguous (no blank line gap)"
  PASS=$((PASS + 1))
else
  echo "  FAIL  migrated table rows are contiguous (separator L$SEPARATOR_LINE, data L$DATA_LINE, expected L$EXPECTED_DATA_LINE)"
  FAIL=$((FAIL + 1))
fi

# F2: Validate blank line before ## Todos after migrated rows
TODOS_LINE=$(grep -n '^## Todos$' "$TMP_DIR/.vbw-planning/STATE.md" | head -1 | cut -d: -f1)
BEFORE_TODOS_LINE=$((TODOS_LINE - 1))
BEFORE_TODOS_CONTENT=$(sed -n "${BEFORE_TODOS_LINE}p" "$TMP_DIR/.vbw-planning/STATE.md")
if [[ -z "$BEFORE_TODOS_CONTENT" ]]; then
  echo "  PASS  blank line before ## Todos after migration"
  PASS=$((PASS + 1))
else
  echo "  FAIL  blank line before ## Todos after migration (line $BEFORE_TODOS_LINE: '$BEFORE_TODOS_CONTENT')"
  FAIL=$((FAIL + 1))
fi

# 7) Deprecated section migration: no migration for empty table
cat > "$TMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| _(No decisions yet)_ | | |
EOF

cat > "$TMP_DIR/empty-decisions.md" <<'EOF'
# Test Project

**Core value:** Test value

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|

## Custom Section
Keep this.
EOF

NOWARN_OUTPUT="$(bash "$BOOTSTRAP" "$TMP_DIR/CLAUDE.md" "Test Project" "Test value" "$TMP_DIR/empty-decisions.md" 2>&1 >/dev/null)"
if echo "$NOWARN_OUTPUT" | grep -q 'Key Decisions'; then
  echo "  FAIL  empty deprecated section should not trigger migration (got: $NOWARN_OUTPUT)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS  empty deprecated section does not trigger migration"
  PASS=$((PASS + 1))
fi
check "placeholder row preserved in STATE.md for empty table" grep -q 'No decisions yet' "$TMP_DIR/.vbw-planning/STATE.md"

# 7b) Migration preserves section when STATE.md Key Decisions has no table
cat > "$TMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State

## Key Decisions

## Todos
EOF

NOTABLE_OUTPUT="$(bash "$BOOTSTRAP" "$TMP_DIR/CLAUDE.md" "Test Project" "Test value" "$TMP_DIR/with-decisions.md" 2>&1 >/dev/null)"
if echo "$NOTABLE_OUTPUT" | grep -q 'Warning.*no table'; then
  echo "  PASS  migration warns when STATE.md Key Decisions has no table"
  PASS=$((PASS + 1))
else
  echo "  FAIL  migration warns when STATE.md Key Decisions has no table (got: $NOTABLE_OUTPUT)"
  FAIL=$((FAIL + 1))
fi
check "section preserved when STATE.md has no table" grep -q '^## Key Decisions$' "$TMP_DIR/CLAUDE.md"
check "data preserved when STATE.md has no table" grep -q 'Use widgets' "$TMP_DIR/CLAUDE.md"

# 8) Deprecated section migration: preserves section when STATE.md missing
rm -rf "$TMP_DIR/.vbw-planning"
NOSTATE_OUTPUT="$(bash "$BOOTSTRAP" "$TMP_DIR/CLAUDE.md" "Test Project" "Test value" "$TMP_DIR/with-decisions.md" 2>&1 >/dev/null)"
if echo "$NOSTATE_OUTPUT" | grep -q 'Warning.*Cannot migrate.*STATE.md not found'; then
  echo "  PASS  migration warns when STATE.md missing"
  PASS=$((PASS + 1))
else
  echo "  FAIL  migration warns when STATE.md missing (got: $NOSTATE_OUTPUT)"
  FAIL=$((FAIL + 1))
fi
check "Key Decisions preserved when STATE.md missing" grep -q '^## Key Decisions$' "$TMP_DIR/CLAUDE.md"
check "data rows preserved when STATE.md missing" grep -q 'Use widgets' "$TMP_DIR/CLAUDE.md"

# 9) Deprecated section migration: deduplicates rows already in STATE.md
mkdir -p "$TMP_DIR/.vbw-planning"
cat > "$TMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| Use widgets | 2025-01-01 | They work |

## Todos
EOF

cat > "$TMP_DIR/dup-decisions.md" <<'EOF'
# Test Project

**Core value:** Test value

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| Use widgets | 2025-01-01 | They work |
| New decision | 2025-02-01 | Fresh |

## Custom Section
Keep this.
EOF

DUP_OUTPUT="$(bash "$BOOTSTRAP" "$TMP_DIR/CLAUDE.md" "Test Project" "Test value" "$TMP_DIR/dup-decisions.md" 2>&1 >/dev/null)"
if echo "$DUP_OUTPUT" | grep -q 'Migrated 1 Key Decisions row(s)'; then
  echo "  PASS  deduplication: only new row migrated"
  PASS=$((PASS + 1))
else
  echo "  FAIL  deduplication: only new row migrated (got: $DUP_OUTPUT)"
  FAIL=$((FAIL + 1))
fi
WIDGET_COUNT=$(grep -c 'Use widgets' "$TMP_DIR/.vbw-planning/STATE.md")
if [[ "$WIDGET_COUNT" -eq 1 ]]; then
  echo "  PASS  deduplication: existing row not duplicated"
  PASS=$((PASS + 1))
else
  echo "  FAIL  deduplication: existing row not duplicated (found $WIDGET_COUNT)"
  FAIL=$((FAIL + 1))
fi
check "deduplication: new row added to STATE.md" grep -q 'New decision' "$TMP_DIR/.vbw-planning/STATE.md"

# 10) Deprecated section: non-table text preserved as user content
mkdir -p "$TMP_DIR/.vbw-planning"
cat > "$TMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| _(No decisions yet)_ | | |
EOF

cat > "$TMP_DIR/mixed-decisions.md" <<'EOF'
# Test Project

**Core value:** Test value

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| Use widgets | 2025-01-01 | They work |

random text
- random text 2

## Custom Section
Keep this.
EOF

bash "$BOOTSTRAP" "$TMP_DIR/CLAUDE.md" "Test Project" "Test value" "$TMP_DIR/mixed-decisions.md" 2>/dev/null
check_absent "mixed: Key Decisions header stripped" grep -q '^## Key Decisions$' "$TMP_DIR/CLAUDE.md"
check_absent "mixed: table data row stripped from CLAUDE.md" grep -q 'Use widgets' "$TMP_DIR/CLAUDE.md"
check "mixed: non-table text preserved in CLAUDE.md" grep -q 'random text' "$TMP_DIR/CLAUDE.md"
check "mixed: non-table list preserved in CLAUDE.md" grep -q 'random text 2' "$TMP_DIR/CLAUDE.md"
check "mixed: archived heading wraps orphaned text" grep -q '^## Key Decisions (Archived Notes)$' "$TMP_DIR/CLAUDE.md"
check "mixed: table data migrated to STATE.md" grep -q 'Use widgets' "$TMP_DIR/.vbw-planning/STATE.md"

# 11) Whitespace-normalized deduplication (F5)
mkdir -p "$TMP_DIR/.vbw-planning"
cat > "$TMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| Use widgets | 2025-01-01 | They work |

## Todos
EOF

# CLAUDE.md has extra internal spacing in the same row
cat > "$TMP_DIR/ws-dup-decisions.md" <<'EOF'
# Test Project

**Core value:** Test value

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
|  Use widgets  |  2025-01-01  |  They work  |

## Custom Section
Keep this.
EOF

WS_DUP_OUTPUT="$(bash "$BOOTSTRAP" "$TMP_DIR/CLAUDE.md" "Test Project" "Test value" "$TMP_DIR/ws-dup-decisions.md" 2>&1 >/dev/null)"
if echo "$WS_DUP_OUTPUT" | grep -q 'Skipped migration.*already in STATE.md'; then
  echo "  PASS  whitespace-normalized dedup: extra spaces treated as duplicate"
  PASS=$((PASS + 1))
else
  echo "  FAIL  whitespace-normalized dedup: extra spaces treated as duplicate (got: $WS_DUP_OUTPUT)"
  FAIL=$((FAIL + 1))
fi

# 12) Trailing whitespace on headers still matched (F6)
mkdir -p "$TMP_DIR/.vbw-planning"
cat > "$TMP_DIR/.vbw-planning/STATE.md" <<'EOF'
# State

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| _(No decisions yet)_ | | |

## Todos
EOF

# Note: printf preserves trailing spaces; heredoc may strip them
printf '%s\n' \
  "# Test Project" "" \
  "**Core value:** Test value" "" \
  "## Key Decisions  " "" \
  "| Decision | Date | Rationale |" \
  "|----------|------|-----------|" \
  "| Use widgets | 2025-01-01 | They work |" "" \
  "## Custom Section" \
  "Keep this." > "$TMP_DIR/trailing-ws.md"

bash "$BOOTSTRAP" "$TMP_DIR/CLAUDE.md" "Test Project" "Test value" "$TMP_DIR/trailing-ws.md" 2>/dev/null
check_absent "trailing whitespace: Key Decisions header still recognized" grep -q '^## Key Decisions' "$TMP_DIR/CLAUDE.md"
check "trailing whitespace: data migrated to STATE.md" grep -q 'Use widgets' "$TMP_DIR/.vbw-planning/STATE.md"

echo ""
echo "TOTAL: $PASS PASS, $FAIL FAIL"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
fi

echo "Some checks failed."
exit 1
