---
phase: {NN} # bare integer, no quotes
plan: {plan-number}
title: {plan-title}
type: execute
wave: {wave-number}
depends_on: [{deps}]
cross_phase_deps: [{phase: {NN}, plan: "{NN-MM}", artifact: "{path}", reason: "{why}"}]
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
{plan-number}-SUMMARY.md
</output>
