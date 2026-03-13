---
phase: {NN} # bare integer, no quotes
tier: {quick|standard|deep}
result: {PASS|FAIL|PARTIAL}
passed: {N}
failed: {N}
total: {N}
date: {YYYY-MM-DD}
---

## Must-Have Checks

| # | ID | Truth/Condition | Status | Evidence |
|---|-----|-----------------|--------|----------|
| 1 | MH-01 | {invariant} | {PASS/FAIL/WARN} | {how-verified} |

## Artifact Checks

| # | ID | Artifact | Exists | Contains | Status |
|---|-----|----------|--------|----------|--------|
| 1 | ART-01 | {file-path} | {Yes/No} | {expected-content} | {PASS/FAIL/WARN} |

_Falls back to 5-col (# \| ID \| Artifact \| Status \| Evidence) when category fields absent._

## Key Link Checks

| # | ID | From | To | Via | Status |
|---|-----|------|-----|-----|--------|
| 1 | KL-01 | {source-file} | {target-file} | {match-pattern} | {PASS/FAIL/WARN} |

_Falls back to 5-col (# \| ID \| Link \| Status \| Evidence) when category fields absent._

## Anti-Pattern Scan

| # | ID | Pattern | Status | Evidence |
|---|-----|---------|--------|----------|
| 1 | AP-01 | {pattern} | {PASS/FAIL/WARN} | {location or "not found"} |

_Include for standard+ tier. Omit if no anti-patterns checked._

## Convention Compliance

| # | ID | Convention | File | Status | Detail |
|---|-----|------------|------|--------|--------|
| 1 | CC-01 | {convention} | {file-checked} | {PASS/FAIL/WARN} | {detail} |

_Falls back to 5-col (# \| ID \| Convention \| Status \| Evidence) when category fields absent._

_Include for standard+ tier when CONVENTIONS.md exists. Omit otherwise._

## Requirement Mapping

| # | ID | Requirement | Plan Ref | Evidence | Status |
|---|-----|-------------|----------|----------|--------|
| 1 | RM-01 | {requirement} | {plan-ref} | {artifact evidence} | {PASS/FAIL/WARN} |

_Falls back to 5-col (# \| ID \| Requirement \| Status \| Evidence) when category fields absent._

_Include for deep tier only. Omit otherwise._

## Skill-Augmented Checks

| # | ID    | Skill Check         | Status           | Evidence       |
|---|-------|---------------------|------------------|----------------|
| 1 | SA-01 | {skill-based-check} | {PASS/FAIL/WARN} | {how-verified} |

_Include when quality skills are active. Omit otherwise._

## Pre-existing Issues

| Test        | File        | Error             |
|-------------|-------------|-------------------|
| {test-name} | {file-path} | {error-message}   |

_Omit this section if no pre-existing issues were found._

## Summary

**Tier:** {quick|standard|deep}
**Result:** {PASS|FAIL|PARTIAL}
**Passed:** {N}/{total}
**Failed:** {list or "None"}
