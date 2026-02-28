## Linked Issue

<!-- REQUIRED: Every PR must reference a tracking issue. CI will fail without one. -->
<!-- Accepted: Fixes/Closes/Resolves #N, full GitHub issue URL, bare #N, or sidebar link -->

Fixes #

## What

Brief description of the change.

## Why

What problem does this solve?

## How

Summary of the approach. Mention affected commands, agents, hooks, or scripts.

## Testing

- [ ] Loaded plugin locally with `claude --plugin-dir "<path-to-vbw-clone>"`
- [ ] Tested affected commands against a real project (not the VBW repo)
- [ ] No errors on plugin load
- [ ] Existing commands still work
- [ ] Ran QA review (2–4 separate AI sessions acting as devil's advocate on the diff)

## QA Review Evidence

Paste each QA round's report as a separate comment on this PR. Each round should have a corresponding fix commit (e.g., `fix(scope): address QA round 1`). Reviewers will verify the commit history matches the reported rounds.

QA must be run on a top-tier model: **Claude Opus 4.6**, **GPT-5.3 Codex high/xhigh**, or **Gemini 3.1 Pro**.

- **Rounds completed:** (number)
- **Model used:** (e.g., Claude Opus 4.6)
- **Fix commits:** (list commit SHAs or titles)

## Notes

Anything reviewers should know -- trade-offs, open questions, follow-up work.
