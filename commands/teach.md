---
name: vbw:teach
category: supporting
disable-model-invocation: true
description: View, add, or manage project conventions. Shows what VBW already knows and warns about conflicts.
argument-hint: "[\"convention text\" | remove <id> | refresh]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# VBW Teach $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root: `${CLAUDE_PLUGIN_ROOT}`
Conventions:
```
!`cat .vbw-planning/conventions.json 2>/dev/null || echo "No conventions found"`
```
Codebase map: `!`ls .vbw-planning/codebase/INDEX.md 2>/dev/null && echo "EXISTS" || echo "NONE"``

## Guard

If no .vbw-planning/ dir: STOP "Run /vbw:init first." (check `.vbw-planning/config.json`)

## Convention Structure

Stored in `.vbw-planning/conventions.json`:
```json
{
  "conventions": [{
    "id": "CONV-001", "rule": "API routes go in src/routes/{resource}.ts",
    "source": "auto-detected", "category": "file-structure",
    "confidence": "high", "detected_from": "PATTERNS.md", "added": "2026-02-10"
  }]
}
```

**Sources:** `auto-detected` (from codebase map) | `user-defined` (manual via /vbw:teach)
**Categories:** file-structure | naming | testing | style | tooling | patterns | other
**Confidence** (auto-detected only): high (80%+) | medium (50-80%) | low (<50%)

## Behavior

### No arguments: Display known conventions

1. Read `.vbw-planning/conventions.json`. If missing, show empty state with examples (`/vbw:teach refresh` and `/vbw:teach "convention text"`).
2. Display conventions grouped by category. Tag: `[auto . {confidence}]` or `[user]`. Show totals.
3. AskUserQuestion: "What would you like to do?" Options: "Add a convention" | "Refresh from codebase" (if map exists) | "Done"

### Text argument: Add a convention

**A1. Parse:** Extract rule text. Infer category:
- File paths/dirs → file-structure
- Casing/naming/prefixes → naming
- Test/coverage/vitest/jest/pytest → testing
- Style/formatting/imports → style
- Tool names (eslint, prettier, pnpm) → tooling
- Patterns/architecture/state/API → patterns
- Otherwise → other

**A2. Conflict check:** Compare against ALL existing conventions:
- **Semantic conflict** (contradicting rules): display ⚠, AskUserQuestion: "Replace existing" | "Keep both" | "Cancel"
- **Redundancy** (essentially same rule): display ○, AskUserQuestion: "Replace with new version" | "Add as separate" | "Cancel"

**A3. Confirm category:** AskUserQuestion with inferred category (recommended) + 2-3 alternatives.

**A4. Save:** Generate next CONV-{NNN} ID, add to conventions.json. Display: `✓ Added CONV-{NNN}: {rule} [{category}]`

**A5. Update CLAUDE.md:** Regenerate `## Project Conventions` section. Format: `- {rule} [{category}]` per convention. No IDs, no source tags, no confidence.

### `remove <id>`: Remove a convention

1. Parse ID, find in conventions.json. Not found: `⚠ Convention not found: {id}`
2. Display convention, ask confirmation
3. Remove from conventions.json, update CLAUDE.md
4. Display: `✓ Removed {id}: {rule}`

### `refresh`: Re-run auto-detection

**R1.** If no `.vbw-planning/codebase/`: `⚠ No codebase map found. Run /vbw:map first.`

**R2. Extract conventions from map:** Read PATTERNS.md, ARCHITECTURE.md, STACK.md, CONCERNS.md. Rules:
- Be specific, not generic ("Components use PascalCase" good; "Code should be clean" bad)
- Only extract patterns actually present in codebase
- Confidence from language: "consistently/always/all" → high, "most/commonly" → medium, "some/mixed" → low
- Skip low-confidence unless only pattern for that category
- Maximum 15 auto-detected conventions

**R3. Reconcile:** User-defined always win. Replace stale auto-detected if conflicts. Add new. Remove orphaned auto-detections.

**R4. Save and display:** Write conventions.json. Show added/updated/removed/kept counts + totals. Update CLAUDE.md.

## Convention Injection

Conventions injected via CLAUDE.md `## Project Conventions` (loaded every session). QA checks user-defined + high-confidence auto-detected conventions. Violations appear as deviations in SUMMARY.md.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — single-line box, ✓ success, ⚠ conflicts/warnings, ○ skipped/info, no ANSI.
