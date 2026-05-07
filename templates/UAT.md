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

Supported checkpoint IDs:
- `P{plan}-T{NN}` — full-scope plan checkpoint
- `PR{round}-T{NN}` — remediation re-verification checkpoint
- `D{NN}` — prefilled summary-deviation review or discovered issue

Prefilled summary-deviation reviews are not blocking issues until the human rejects them. They start with an empty `Result`, include deterministic identity metadata, and are written before generated plan checkpoints.

### D{NN}: Review summary deviation

- **Source:** Summary deviation review
- **Deviation Signature:** {signature}
- **Source Plan:** {plan-id}
- **Source Summary:** {summary-path}
- **Deviation:** {documented deviation text}
- **Plan:** {plan-id} -- {plan-title}
- **Scenario:** Review a documented implementation deviation from SUMMARY.md
- **Expected:** Human confirms whether this documented deviation is acceptable for this phase.
- **Result:** {pass|skip|issue}
- **Disposition:** {accepted-process-exception|skipped-by-user|rejected-by-user}
- **Issue:** {only when result=issue}
  - Description: {why the deviation is unacceptable or what bug it exposes}
  - Severity: {critical|major|minor}

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
