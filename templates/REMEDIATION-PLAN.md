---
phase: {NN} # bare integer, no quotes
round: {RR} # remediation round number, bare integer
title: {plan-title}
type: remediation
autonomous: {true|false}
effort_override: {thorough|balanced|fast|turbo}
skills_used: [{skill}]
files_modified: [{path}]
forbidden_commands: []
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
<output>
R{RR}-SUMMARY.md
</output>
