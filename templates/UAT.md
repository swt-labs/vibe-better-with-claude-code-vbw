---
phase: {NN} # bare integer, no quotes
plan_count: {N}
status: {in_progress|complete|issues_found}
started: {YYYY-MM-DD}
completed: {YYYY-MM-DD}
total_tests: {N}
passed: {N}
skipped: {N}
issues: {N}
---

{one-line-summary}

## Tests

### P{plan}-T{NN}: {test-title}

- **Plan:** {plan-id} -- {plan-title}
- **Scenario:** {what to do}
- **Expected:** {what should happen}
- **Result:** {pass|skip|issue}
- **Issue:** {if result=issue}
  - Description: {issue-description}
  - Severity: {critical|major|minor}

### D{NN}: {discovered-issue-title}

- **Plan:** (discovered during {test-id})
- **Scenario:** User observation during UAT
- **Expected:** (not applicable — discovered issue)
- **Result:** issue
- **Issue:**
  - Description: {observation text}
  - Severity: {critical|major|minor}

## Summary

- Passed: {N}
- Skipped: {N}
- Issues: {N}
- Total: {N}
