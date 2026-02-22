---
phase: {phase-id}
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

| # | ID | Artifact | Status | Evidence |
|---|-----|----------|--------|----------|
| 1 | ART-01 | {file-path} | {PASS/FAIL/WARN} | {exists, contains required-content} |

## Key Link Checks

| # | ID | Link | Status | Evidence |
|---|-----|------|--------|----------|
| 1 | KL-01 | {source → target} | {PASS/FAIL/WARN} | {mechanism} |

## Anti-Pattern Scan

| # | ID | Pattern | Status | Evidence |
|---|-----|---------|--------|----------|
| 1 | AP-01 | {pattern} | {PASS/FAIL/WARN} | {location or "not found"} |

_Include for standard+ tier. Omit if no anti-patterns checked._

## Convention Compliance

| # | ID | Convention | Status | Evidence |
|---|-----|------------|--------|----------|
| 1 | CC-01 | {convention} | {PASS/FAIL/WARN} | {file, detail} |

_Include for standard+ tier when CONVENTIONS.md exists. Omit otherwise._

## Requirement Mapping

| # | ID | Requirement | Status | Evidence |
|---|-----|-------------|--------|----------|
| 1 | RM-01 | {requirement} | {PASS/FAIL/WARN} | {plan-ref, artifact evidence} |

_Include for deep tier only. Omit otherwise._

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
