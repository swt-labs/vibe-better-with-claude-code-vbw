---
session_id: {YYYYMMDD-HHMMSS}-{slug}
title: {one-line bug description}
status: investigating
created: {YYYY-MM-DD HH:MM:SS}
updated: {YYYY-MM-DD HH:MM:SS}
qa_round: 0
qa_last_result: pending
uat_round: 0
uat_last_result: pending
---

# Debug Session: {title}

## Issue

{Bug description as reported by the user. Include error messages, affected commands, reproduction steps.}

## Investigation

### Hypotheses

{Each hypothesis tested during investigation. For each:}

#### Hypothesis 1: {description}

- **Status:** confirmed | rejected | investigating
- **Evidence for:** {what supports this hypothesis}
- **Evidence against:** {what contradicts this hypothesis}
- **Conclusion:** {why this was chosen or rejected}

### Root Cause

{The confirmed root cause with supporting evidence. Reference specific files and line numbers.}

## Plan

{The chosen fix approach. What will be changed and why.}

## Implementation

{Summary of changes made. List each modified file and what changed.}

### Changed Files

{Bulleted list of files modified with one-line descriptions.}

### Commit

{Commit hash and message, or "No commit yet."}

## QA

{QA rounds are appended here by the QA workflow.}

## UAT

{UAT rounds are appended here by the UAT workflow.}

## Remediation History

{Previous investigation/plan/implementation rounds are archived here when the session re-enters investigation after QA or UAT failure.}
