---
phase: {NN} # bare integer, no quotes
round: {RR} # remediation round number, bare integer
title: {round-title}
type: remediation
status: {in-progress|complete|partial|failed}
completed: {YYYY-MM-DD}
tasks_completed: {N}
tasks_total: {N}
commit_hashes:
  - {hash}
files_modified:
  - {path}
deviations:
  - "{deviation-description}"
---

{one-line-summary-of-what-this-remediation-round-accomplished}

## Task {N}: {task-name}

### What Was Built
- {deliverable-1}
- {deliverable-2}

### Files Modified
- `{file-path}` -- {action}: {purpose}

### Deviations
- {deviation-description}

<!-- Or write `None` / `No deviations` as plain text when there were no deviations.
  If there are multiple deviations, use one bullet per deviation. -->

<!-- Repeat "## Task {N}" section for each task in the plan.
     Keep task sections in execution order.
     Do NOT leave trailing blank lines between or after sections. -->
