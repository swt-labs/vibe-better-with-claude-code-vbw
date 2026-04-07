---
phase: {NN} # bare integer, no quotes
plan: {plan-number}
title: {plan-title}
status: {complete|partial|failed}
completed: {YYYY-MM-DD}
tasks_completed: {N}
tasks_total: {N}
commit_hashes:
  - {hash}
deviations:
  - "{deviation-description}"
# Authoritative no-known-issues signal. When present, consumers must not fall back to a legacy body section.
pre_existing_issues: []
---

{one-line-substantive-summary}

## What Was Built

- {deliverable-1}
- {deliverable-2}

## Files Modified

- `{file-path}` -- {action}: {purpose}

## Deviations

{deviations-or-none}
