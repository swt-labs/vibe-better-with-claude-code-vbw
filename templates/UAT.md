---
phase: {phase-id}
plan_count: {NN}
status: {in_progress|complete|issues_found}
started: {YYYY-MM-DD}
completed: {YYYY-MM-DD}
total_tests: {NN}
passed: {NN}
skipped: {NN}
issues: {NN}
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

- Passed: {NN}
- Skipped: {NN}
- Issues: {NN}
- Total: {NN}
