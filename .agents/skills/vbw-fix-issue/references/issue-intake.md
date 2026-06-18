# Issue Intake

1. Resolve the issue number from the user prompt. If no tracked issue exists and the user supplied a bug report, create or ask for a tracking issue before implementation.
2. Read the issue body in full. Extract acceptance criteria, scope boundaries, reproduction steps, affected commands/hooks/scripts, and any root-cause notes.
3. Search for open PRs that already reference the issue. If a contributor PR exists, stop independent implementation and route the user to `$vbw-review-contributor-pr` unless they explicitly choose to implement independently.
4. If the user supplied an execution plan, preserve it as the draft contract. Ask `vbw-fix-planner` to audit and refine that same plan instead of starting over.
5. For reports about VBW runtime behavior, resolve the local debug target first:

```bash
TARGET_REPO=$(bash scripts/resolve-debug-target.sh repo)
PLANNING_DIR=$(bash scripts/resolve-debug-target.sh planning-dir)
CLAUDE_PROJECT_DIR=$(bash scripts/resolve-debug-target.sh claude-project-dir)
```

If the resolver exits nonzero, ask the user to configure the debug target path before diagnosing session behavior.
