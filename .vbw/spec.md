# v2

## Goals

## Non-goals

## Constraints

## Requirements

- R1 [auto] Two consent grants made at the same time from different worktrees of one clone are both kept
- R2 [auto] A vbw command interrupted mid-commit leaves no stray index files in .vbw/runtime and keeps the caller's own exit cleanup
- R3 [auto] vbw report and vbw rtk do what their help says
- R4 [auto] In a real session, a documentation requirement is built by the Docs agent and proved
- R5 [auto] In a real session, QA fails a phase whose build deviates from its plan, and the fix loop closes it
- R6 [auto] In a real session, /vbw:debug finds the root cause of a seeded bug and fixes it with a regression test
- R7 [auto] In a real session, /vbw:research returns a sourced answer
- R8 [auto] In balanced autonomy, a background QA run causes no Stop-hook errors and the session reaches the accept stop
- R9 [human] A visual accept check asks the user for a screenshot of the page and keeps it with their verdict
- R10 [auto] Blocking or resetting a plan (its note or status) never withdraws the user's approval of an unchanged contract
- R11 [auto] Accepting a [human] requirement closes only the fixes opened by the user's own rejections; a fix QA opened stays open until QA passes the phase again
- R12 [auto] QA cannot record a verdict on a proof older than the current code: vbw qa record refuses and asks for vbw prove first

<!-- One requirement per line: an id, how it is proved, and a user-observable
     statement. [auto] = a check can prove it; [human] = only a person can judge it.
- R1 [auto] A visitor can sign up with an email address
- R2 [human] The landing page feels trustworthy
-->
