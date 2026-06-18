# QA Contract

## Scope

- The linked issue is the contract. Read the full issue before reviewing code.
- Latest-commit framing is orientation only. Unless the caller explicitly says `delta-only review`, re-verify the full issue contract against the current branch state.
- In scope: acceptance criteria, touched code, downstream consumers of touched behavior, and tests that should cover changed paths.
- Out of scope: unrelated pre-existing bugs in untouched code. Report genuine out-of-scope bugs as `observation` findings.

## Investigation

1. Read the issue and extract acceptance criteria.
2. Read the PR or branch diff.
3. Read changed files in full.
4. Check downstream consumers of modified functions, formats, files, or workflow contracts.
5. Verify tests exercise the changed behavior.
6. For LLM-consumed markdown changes, read `.github/references/prompting-best-practices-for-vbw.md` and check the content against it.

## Output Format

### Contract Verification

For each criterion:

- Criterion:
- Status: satisfied / partially-satisfied / not-satisfied / not-applicable
- Evidence:

### Findings

For each finding:

- ID: F-01, F-02, ...
- Severity: critical / high / medium / low
- Relevance: contract / regression / observation
- Category: edge-case / race-condition / error-handling / backward-compat / test-gap / logic-error / prompt-engineering
- Status: confirmed / hypothetical
- Description:
- Evidence:
- Impact:

### No Issues Found

Use this section only when every acceptance criterion is satisfied and no regressions were found.
