# VBW 2 — Vibe Better With Claude Code

> **This branch (`v2`) is under active development.** The released plugin (1.x) lives on `main`.

VBW gives Claude Code an **executable definition of done**:

1. **Spec**: you and Claude agree on what to build. Every requirement is either provable by a check or marked for human judgement.
2. **Contract**: acceptance checks are written first, fail first, and are protected from being weakened.
3. **Build**: Claude Code workflows build plans in parallel, each until its own checks pass.
4. **Prove**: a small kernel runs the approved checks and scope rules mechanically, at zero model tokens.
5. **Accept**: you judge only what checks can't.
6. **Ship**: the milestone is tagged with its evidence.

Requirements (v2): Claude Code with **Dynamic workflows** enabled (`/config`), a Sonnet, Opus or Fable session model for autonomous runs, and `bash`, `jq`, `git`.

Development: `claude --plugin-dir ./plugin` · tests: `bash tools/test.sh` · design and plan: `a_non_prod_docs/` (local working documents).
