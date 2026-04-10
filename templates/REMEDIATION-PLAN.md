---
phase: {NN} # bare integer, no quotes
round: {RR} # remediation round number, bare integer
plan: {round-plan-id} # stable plan ID, e.g. R01 or R01-02
title: {plan-title}
type: remediation
autonomous: {true|false}
effort_override: {thorough|balanced|fast|turbo}
skills_used: [{skill}]
files_modified: [{path}]
forbidden_commands: []
fail_classifications:
  - {id: "FAIL-ID", type: "code-fix|process-exception", rationale: "why this classification applies"}
  - {id: "FAIL-ID", type: "plan-amendment", rationale: "why this classification applies", source_plan: "01-01-PLAN.md"}
known_issues_input:
  - '{"test":"{test-name}","file":"{file-path}","error":"{error-message}"}'
known_issue_resolutions:
  - '{"test":"{test-name}","file":"{file-path}","error":"{error-message}","disposition":"resolved|accepted-process-exception|unresolved","rationale":"why this round resolves or carries the issue"}'
must_haves:
  truths: ["{invariant}"]
  artifacts: [{path: "{file}", provides: "{what}", contains: "{string}"}]
  key_links: [{from: "{src}", to: "{tgt}", via: "{rel}"}]
---
<objective>
{objective-description}
</objective>
<context>
@{context-file}
</context>
<tasks>
<!-- Tasks are executed sequentially — task N+1 sees the results of task N.
     Order matters: place foundational fixes before dependent ones. -->
<task type="auto">
  <name>{task-name}</name>
  <files>
    {file-1}
  </files>
  <action>
{what-to-do}
  </action>
  <verify>
{how-to-verify}
  </verify>
  <done>
{completion-criteria}
  </done>
</task>
</tasks>
<verification>
1. {check}
</verification>
<success_criteria>
- {criterion}
</success_criteria>
<known_issue_workflow>
- Copy every carried known issue from the remediation input backlog into `known_issues_input` using the canonical `{test,file,error}` shape.
- Add a matching `known_issue_resolutions` entry for every carried known issue. Use `resolved` when this round fixes it, `accepted-process-exception` when QA should treat it as a verified non-blocking carryover for this phase, and `unresolved` only when the issue is intentionally carried into the next round.
- Do not omit a carried known issue from these arrays. The deterministic gate treats missing coverage as a failed remediation round.
</known_issue_workflow>
<output>
R{RR}-SUMMARY.md
</output>
