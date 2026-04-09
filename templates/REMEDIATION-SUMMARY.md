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
known_issue_outcomes:
  - '{"test":"{test-name}","file":"{file-path}","error":"{error-message}","disposition":"resolved|accepted-process-exception|unresolved","rationale":"why this round resolved or carried the issue"}'
---

{one-line-summary-of-what-this-remediation-round-accomplished}

## Task {N}: {task-name}

### What Was Built
- {deliverable-1}
- {deliverable-2}

### Files Modified
- `{file-path}` -- {action}: {purpose}

### Known Issue Outcomes
- `{test-name}` (`{file-path}`) — `{resolved|accepted-process-exception|unresolved}`: {rationale}

### Deviations
- {deviation-description}

<!-- Or write `None` / `No deviations` as plain text when there were no deviations.
  If there are multiple deviations, use one bullet per deviation. -->

<!-- Keep `known_issue_outcomes` aligned 1:1 with the carried issue backlog from R{RR}-PLAN.md.
  `accepted-process-exception` means QA verified the issue is real but non-blocking for this phase, so it must remain visible to the user without forcing another blocking round. -->

<!-- Repeat "## Task {N}" section for each task in the plan.
     Keep task sections in execution order.
     Do NOT leave trailing blank lines between or after sections. -->
