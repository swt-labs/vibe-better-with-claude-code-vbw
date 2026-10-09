---
name: triage
description: Sort every new idea the user brings as now, next or later, with a reason and a size, before any requirement, planning or file change. Used by the vibe router for each new request.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
effort: low
---

# Triage

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" triage 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Above: the active milestone, its requirements, the open backlog and the user's answers. Write to the user's level, explanation depth and involvement ("-": plain words).

Router calls this for each new idea, before any requirement, planning or file change. At every autonomy setting (guided, balanced, hands-off) the idea is sorted and the user confirms or overrules it.

## When it applies

New idea: a feature, change, fix or wish not yet in the spec. Not a new idea, so no triage: an answer to a question VBW asked, "continue" or "go on", an approval, a question about the project.

Idea already matches a requirement or open backlog item: name it, no new entry. For a backlog item, offer to move it to now (`vbw spec add`, then `vbw todo done`).

## The sorting menu

One line per idea, then one AskUserQuestion with all of them. Each line: the sort, the reason in one sentence, the size (small, medium or large).

- **now**: joins the active milestone.
- **next**, **later**: go into the backlog; next is the following milestone, later is someday.

VBW's sort is the first option, marked (Recommended); the two other sorts are the other options. Never ask the user to type a command. Up to four ideas per menu; more than four are sorted four at a time. During a run, sort without interrupting it; a "now" idea waits for the run to end.

## Outcomes

- **now**: `vbw spec add auto|human "<idea>"`, then the normal flow (planning again, the approval menu). No active milestone: `vbw milestone start "<title>"` with the idea as its first requirement.
- **next** or **later**: `vbw todo add --sort <sort> --size <size> "<idea>"`.

## Overrule

The user picked a sort other than VBW's: exactly one follow-up question (AskUserQuestion) that says plainly what the choice displaces and its risk.

- **now** displaces planned work: it grows the milestone, sends the plan back for a new approval and delays planned work.
- **later** instead of **now** displaces nothing, but a problem VBW judged urgent stays unfixed.

Options: one or two ready reasons, the user's own words, keep VBW's sort.

A reason chosen: follow the user's sort, then `vbw decide "Triage overrule: <idea>: VBW sorted <VBW's sort>, the user chose <user's sort>" "<the user's reason>"`. Keep VBW's sort: apply VBW's sort, record no overrule.

Say the warning once per idea. Never repeat or argue it; never ask again.
