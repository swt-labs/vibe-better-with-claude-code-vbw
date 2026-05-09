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
- `P{plan}-T{NN}` — full-scope plan checkpoint (example: `P01-T01`)
- `PR{round}-T{NN}` — remediation re-verification checkpoint (example: `PR03-T01`)
- `D{NN}` — prefilled summary-deviation review or discovered issue (example: `D01`)

Prefilled summary-deviation reviews are not blocking issues until the human rejects them. They start with an empty `Result`, include deterministic identity metadata, and are written before generated plan checkpoints.
Only entries whose final `Result` is `issue` are blocking UAT issues; empty, `pass`, and `skip` `DNN` review entries are non-blocking.
Accepted summary deviations may include an optional `Tracking:` line when the human accepts the deviation as non-blocking and asks VBW to add a follow-up todo. `Result: pass` plus `Disposition: accepted-process-exception` plus `Tracking: accepted deviation added to todos (ref:{8hex})` is non-blocking; only final `Result: issue` entries block UAT.

Issue `Description` values are synthesized, remediation-ready text, not raw user responses. Fold any visible attachment/image evidence into the description while it is available. Do not persist `image attached`, `(Image attached)`, `screenshot attached`, raw screenshots, raw attachment blobs, or base64 data in this artifact.

Tracked non-blocking example: `D01` with `Result: pass`, `Disposition: accepted-process-exception`, and `Tracking: accepted deviation added to todos (ref:1a2b3c4d)`.

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
- **Tracking:** {accepted deviation added to todos (ref:{8hex})|accepted deviation already tracked in todos (ref:{8hex})|accepted deviation todo tracking unavailable ({status})} # optional for accepted tracked deviations
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
